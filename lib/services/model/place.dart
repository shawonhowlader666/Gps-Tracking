import 'package:google_maps_cluster_manager/google_maps_cluster_manager.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Place with ClusterItem {
  final String name;
  final bool isClosed;
  final LatLng latLng;
  final String course;
  final String icon;
  final String title;
  final String deviceId;
  final dynamic device;

  Place({
    required this.name,
    required this.latLng,
    this.isClosed = false,
    required this.course,
    required this.icon,
    required this.title,
    required this.deviceId,
    required this.device,
  });

  @override
  LatLng get location => latLng;
}
