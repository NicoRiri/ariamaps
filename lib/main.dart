import 'dart:async';

import 'package:ariamaps/constant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mysql1/mysql1.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';

final String bgTaskName = "background_loc_task";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
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
    print("Native called background task: $task");
    switch (task) {
      case "background_loc_task":
        await savePositionToDatabase(await Geolocator.getCurrentPosition());
        break;
    }
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

    print("Insert okay");

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
      theme: ThemeData(primarySwatch: Colors.blue),
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
  List<Position> _positions = [];
  bool switchValue = false;

  @override
  void initState() {
    super.initState();
    _fetchPositionsFromDatabase();
    _askLocationPermission();
    Future.delayed(Duration(seconds: 5), () async {
      await savePositionToDatabase(await Geolocator.getCurrentPosition());
    });
  }

  Future<void> _askLocationPermission() async {
    var status = await Permission.locationAlways.request();

    if (status.isPermanentlyDenied) {
      openAppSettings();
    }
    if (!status.isGranted) {
      print("Permission locationAlways refusée");
    } else {
      print("Permission locationAlways accordée");
    }

    status = await Permission.location.request();

    if (status.isPermanentlyDenied) {
      openAppSettings();
    }
    if (!status.isGranted) {
      print("Permission location refusée");
    } else {
      print("Permission location accordée");
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

  Future<void> _fetchPositionsFromDatabase() async {
    try {
      final conn = await _connectToDatabase();
      final results = await conn
          .query('SELECT latitude, longitude, timestamp FROM positions');

      setState(() {
        _positions = results.map((row) {
          return Position(
              longitude: row['longitude'],
              latitude: row['latitude'],
              timestamp: DateTime.timestamp(),
              accuracy: 0,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0);
        }).toList();
      });

      await conn.close();
    } catch (e) {
      print('Erreur lors de la récupération des données : $e');
    }
  }

  Future<MySqlConnection> _connectToDatabase() async {
    final settings = ConnectionSettings(
      host: 'www.nikollei.dev',
      port: 30069,
      user: 'root',
      password: 'psariamaps',
      db: 'ariamaps',
    );
    return await MySqlConnection.connect(settings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Positions Enregistrées'),
          actions: [
            Switch(
              value: switchValue,
              onChanged: (bool value) {
                setState(() {
                  switchValue = !switchValue;
                });
                switchValue
                    ? backgroundStartLocTask()
                    : backgroundStopLocTask();
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
                              // Position initiale de la carte
                              initialZoom: 11.5, // Niveau de zoom
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              ),
                              MarkerLayer(
                                markers: _positions.map((point) {
                                  return Marker(
                                    point:
                                        LatLng(point.latitude, point.longitude),
                                    width: 40.0,
                                    height: 40.0,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.green,
                                      size: 30.0,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ]),
                      ),
                    ],
                  )));
  }
}
