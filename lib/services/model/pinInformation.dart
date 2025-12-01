import 'dart:ui';

import 'package:google_maps_flutter/google_maps_flutter.dart';

class PinInformation {
  String? pinPath;
  String? avatarPath;
  String? address;
  String? updatedTime;
  LatLng? location;
  String? status;
  String? name;
  String? speed;
  Color? labelColor;
  String? ignition;
  var batteryLevel;
  bool? charging;
  int? deviceId;
  bool? blocked;
  String? calcTotalDist;
  dynamic device;

  PinInformation(
      {this.pinPath,
      this.avatarPath,
      this.address,
      this.updatedTime,
      this.location,
      this.status,
      this.name,
      this.speed,
      this.labelColor,
      this.batteryLevel,
      this.ignition,
      this.charging,
      this.deviceId,
      this.blocked,
      this.calcTotalDist,
      this.device});
}
