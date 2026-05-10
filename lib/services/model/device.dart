// ignore_for_file: file_names

import 'package:smart_lock/services/model/device_item.dart';

class Device extends Object {
  int? id;
  String? title;
  List<DeviceItem>? items;

  Device({this.id, this.title, this.items});

  Device.fromJson(Map<String, dynamic> json) {
    id = json["id"];
    title = json["title"];
    if (json['items'] != null) {
      items = <DeviceItem>[];
      json['items'].forEach((v) {
        items!.add(DeviceItem.fromJson(v));
      });
    }
  }
}
