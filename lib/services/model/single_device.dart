
class SingleDevice extends Object {
  dynamic device_id;
  Map<String, dynamic>? engine_hours;
  Map<String, dynamic>? detect_engine;
  Map<String, dynamic>? device_groups;
  Map<String, dynamic>? sensor_groups;
  Map<String, dynamic>? item;
  Map<String, dynamic>? device_fuel_measurements;
  List<Map<String, dynamic>>? device_icons; 
  Map<String, dynamic>? sensors;
  Map<String, dynamic>? services;
  Map<String, dynamic>? expiration_date_select;
  List<dynamic>? timezones;
  List<dynamic>? users;

  SingleDevice({this.device_id, this.item, this.device_icons});

  SingleDevice.fromJson(Map<String, dynamic> json) {
    device_id = json["id"];
    item = json["item"];
    device_icons = (json["device_icons"] as List?)
        ?.map((e) => e as Map<String, dynamic>)
        .toList();
  }
}
