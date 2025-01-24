import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:ariamaps/LocPos.dart';
import 'package:ariamaps/constant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icon_decoration/icon_decoration.dart';
import 'package:latlong2/latlong.dart';
import 'package:mysql1/mysql1.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

final String bgTaskName = "background_loc_task";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  runApp(MyApp());
}

void backgroundStartLocTask() {
  final uniqueName = bgTaskName;
  Workmanager().registerPeriodicTask(
    uniqueName,
    bgTaskName,
    frequency: Duration(minutes: 15),
  );
}

void backgroundStopLocTask() {
  Workmanager().cancelAll();
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    DartPluginRegistrant.ensureInitialized();
    final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        forceAndroidLocationManager: true);
    await savePositionToDatabase(pos);
    return Future.value(true);
  });
}

Future<void> savePositionToDatabase(Position position) async {
  try {
    final conn = await MySqlConnection.connect(ConnectionSettings(
      host: DB_HOST,
      port: DB_PORT,
      user: DB_USER,
      password: DB_PASSWORD,
      db: DB_NAME,
    ));
    await conn.query(
      'INSERT INTO positions (latitude, longitude, timestamp) VALUES (?, ?, ?)',
      [position.latitude, position.longitude, DateTime.now().toUtc()],
    );
    await conn.close();
  } catch (e) {
    print("Erreur lors de l'enregistrement dans la base de données : $e");
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS Logger',
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.purpleAccent)),
      home: GpsLoggerScreen(),
    );
  }
}

class GpsLoggerScreen extends StatefulWidget {
  const GpsLoggerScreen({super.key});

  @override
  _GpsLoggerScreenState createState() => _GpsLoggerScreenState();
}

class _GpsLoggerScreenState extends State<GpsLoggerScreen> {
  List<LocPos> _positions = [];
  bool switchValue = false;

  @override
  void initState() {
    super.initState();
    _fetchPositionsFromDatabase();
    _initDefaultPositionSlider();
    _askLocationPermission();
  }

  Future<void> _initDefaultPositionSlider() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey("switchValue")) {
      prefs.setBool("switchValue", false);
    }
    setState(() {
      switchValue = prefs.getBool("switchValue")!;
    });
  }

  Future<void> _sliderChange() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      switchValue = !switchValue;
    });
    switchValue ? backgroundStartLocTask() : backgroundStopLocTask();
    prefs.setBool("switchValue", switchValue);
  }

  Future<void> _askLocationPermission() async {
    var status = await Permission.location.request();

    if (status.isPermanentlyDenied) {
      openAppSettings();
    }
    if (!status.isGranted) {
      print("Permission location refusée");
    } else {
      print("Permission location accordée");
    }

    status = await Permission.locationAlways.request();

    if (status.isPermanentlyDenied) {
      openAppSettings();
    }
    if (!status.isGranted) {
      print("Permission locationAlways refusée");
    } else {
      print("Permission locationAlways accordée");
    }

    status = await Permission.notification.request();

    if (status.isPermanentlyDenied) {
      openAppSettings();
    }
    if (!status.isGranted) {
      print("Permission notification refusée");
    } else {
      print("Permission notification accordée");
    }
  }

  // Fonction pour calculer la distance entre deux coordonnées (en mètres)
  double haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000; // Rayon de la Terre en mètres
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  List<LocPos> filterAndCountNeighbors(
      List<LocPos> results, double minDistance) {
    List<LocPos> filteredPositions = [];

    for (var i = 0; i < results.length; i++) {
      final currentPosition = results[i];

      // Vérifier si la position est trop proche des positions déjà filtrées
      bool isFarEnough = filteredPositions.every((existingPosition) {
        final distance = haversine(
          currentPosition.latitude,
          currentPosition.longitude,
          existingPosition.latitude,
          existingPosition.longitude,
        );
        return distance > minDistance;
      });

      if (isFarEnough) {
        // Compter les voisins proches (non filtrés) pour cette position
        int nearbyCount = 0;
        for (var j = 0; j < results.length; j++) {
          if (i == j) continue; // Ignore la position elle-même

          final other = results[j];
          final distance = haversine(
            currentPosition.latitude,
            currentPosition.longitude,
            other.latitude,
            other.longitude,
          );

          if (distance <= minDistance) {
            nearbyCount++;
          }
        }

        // Ajouter le compteur de voisins ignorés
        currentPosition.nearby = nearbyCount;
        filteredPositions.add(currentPosition);
      }
    }

    return filteredPositions;
  }

  Future<void> _fetchPositionsFromDatabase() async {
    try {
      final conn = await _connectToDatabase();
      final results = await conn
          .query('SELECT latitude, longitude, timestamp FROM positions');

      final liste = results.map((row) {
        return LocPos(
            longitude: row['longitude'],
            latitude: row['latitude'],
            timestamp: DateTime.timestamp(),
            nearby: 0);
      }).toList();
      setState(() {
        _positions = filterAndCountNeighbors(liste, 10);
      });

      await conn.close();
    } catch (e) {
      print('Erreur lors de la récupération des données : $e');
    }
  }

  Future<MySqlConnection> _connectToDatabase() async {
    final settings = ConnectionSettings(
      host: DB_HOST,
      port: DB_PORT,
      user: DB_USER,
      password: DB_PASSWORD,
      db: DB_NAME,
    );
    return await MySqlConnection.connect(settings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Ariamaps',
          style: GoogleFonts.outfit(),
        ),
        backgroundColor: Theme.of(context).colorScheme.primaryFixed,
        actions: [
          Switch(
            value: switchValue,
            inactiveThumbColor: Colors.white,
            activeColor: Theme.of(context).colorScheme.primaryFixed,
            onChanged: (bool value) {
              _sliderChange();
            },
          )
        ],
      ),
      body: Center(
          child: _positions.isEmpty
              ? const Text('Aucune position enregistrée.')
              : Column(
                  children: [
                    Expanded(
                      child: FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(48.685, 6.184),
                            interactionOptions: InteractionOptions(
                              flags:
                                  InteractiveFlag.all & ~InteractiveFlag.rotate,
                            ),
                            initialZoom: 11.5,
                          ),
                          children: [
                            TileLayer(
                              retinaMode: true,
                              urlTemplate:
                                  'https://tile.jawg.io/jawg-lagoon/{z}/{x}/{y}{r}.png?access-token=$JAWG_TOKEN',
                            ),
                            MarkerLayer(
                              markers: _positions.map((point) {
                                return Marker(
                                  point:
                                      LatLng(point.latitude, point.longitude),
                                  width: 100.0,
                                  height: 100.0,
                                  child: DecoratedIcon(
                                    icon: Icon(Icons.location_on,
                                        color: point.nearby < 10
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primaryFixed
                                            : point.nearby < 20
                                                ? Colors.indigo
                                                : point.nearby < 30
                                                    ? Colors.blue
                                                    : point.nearby < 40
                                                        ? Colors.greenAccent
                                                        : point.nearby < 50
                                                            ? Colors.green
                                                            : point.nearby < 60
                                                                ? Colors.yellow
                                                                : Colors.red),
                                    decoration: IconDecoration(
                                        border: IconBorder(
                                            color: Colors.black, width: 3)),
                                  ),
                                );
                              }).toList(),
                            ),
                          ]),
                    ),
                  ],
                )),
    );
  }
}
