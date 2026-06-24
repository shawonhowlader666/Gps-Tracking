// ignore_for_file: file_names, non_constant_identifier_names

class EventHistory extends Object {
  int? id;
  int? user_id;
  int? device_id;
  dynamic geofence_id;
  dynamic poi_id;
  dynamic position_id;
  dynamic alert_id;
  dynamic type;
  dynamic message;
  dynamic address;
  dynamic altitude;
  dynamic course;
  dynamic latitude;
  dynamic longitude;
  dynamic power;
  dynamic speed;
  dynamic time;
  dynamic deleted;
  dynamic created_at;
  dynamic updated_at;
  dynamic additional;
  dynamic silent;
  dynamic name;
  dynamic detail;
  dynamic geofence;
  dynamic device_name;

  EventHistory(
      {this.id,
      this.user_id,
      this.device_id,
      this.geofence_id,
      this.poi_id,
      this.position_id,
      this.alert_id,
      this.type,
      dynamic message,
      this.address,
      this.altitude,
      this.course,
      this.latitude,
      this.longitude,
      this.power,
      this.speed,
      this.time,
      this.deleted,
      this.created_at,
      this.updated_at,
      this.additional,
      this.silent,
      this.name,
      this.detail,
      this.geofence,
      this.device_name}) {
    this.message = _cleanMessage(message?.toString());
  }

  EventHistory.fromJson(Map<String, dynamic> json) {
    id = json["id"];
    user_id = json["user_id"];
    device_id = json["device_id"];
    geofence_id = json["geofence_id"];
    poi_id = json["poi_id"];
    position_id = json["position_id"];
    alert_id = json["alert_id"];
    type = json["type"];
    message = _cleanMessage(json["message"]?.toString());
    address = json["address"];
    altitude = json["altitude"];
    course = json["course"];
    latitude = json["latitude"];
    longitude = json["longitude"];
    power = json["power"];
    speed = json["speed"];
    time = json["time"];
    deleted = json["deleted"];
    created_at = json["created_at"];
    updated_at = json["updated_at"];
    additional = json["additional"];
    silent = json["silent"];
    name = json["name"];
    detail = json["detail"];
    geofence = json["geofence"];
    device_name = json["device_name"];
  }

  static String? _cleanMessage(String? rawMessage) {
    if (rawMessage == null) return null;
    final msg = rawMessage.toLowerCase();
    if (msg.contains('ignition') || msg.contains('engine')) {
      if (msg.contains('off') || msg.contains('stop')) {
        return 'Engine Off';
      } else {
        return 'Engine On';
      }
    }
    if (msg.contains('power') &&
        (msg.contains('cut') ||
            msg.contains('disconnect') ||
            msg.contains('fail') ||
            msg.contains('off') ||
            msg.contains('low'))) {
      return 'Power Disconnect';
    }
    return rawMessage;
  }
}
