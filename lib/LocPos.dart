class LocPos {
  double latitude;
  double longitude;
  DateTime timestamp;
  int nearby;

  LocPos({required this.latitude, required this.longitude, required this.timestamp, required this.nearby});


}

extension LocPosCopyWith on LocPos {
  LocPos copyWith({
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    int? nearby,
  }) {
    return LocPos(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      nearby: nearby ?? this.nearby,
    );
  }
}