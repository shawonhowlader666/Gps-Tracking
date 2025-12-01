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
      {
        this.id,
        this.user_id,
        this.device_id,
        this.geofence_id,
        this.poi_id,
        this.position_id,
        this.alert_id,
        this.type,
        this.message,
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
        this.device_name
      });

  EventHistory.fromJson(Map<String, dynamic> json) {
    id = json["id"];
    user_id = json["user_id"];
    device_id = json["device_id"];
    geofence_id = json["geofence_id"];
    poi_id = json["poi_id"];
    position_id = json["position_id"];
    alert_id = json["alert_id"];
    type = json["type"];
    message = json["message"];
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
}
