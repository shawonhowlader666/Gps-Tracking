// ignore_for_file: file_names, non_constant_identifier_names

class PlayBackRoute extends Object {
  String? id;
  String? device_id;
  String? latitude;
  String? longitude;
  String? course;
  String? raw_time;
  dynamic speed;
  String? show;
  String? left;
  String? time;
  dynamic distance;
  int? fuel_consumption;
  int? top_speed;
  int? average_speed;
  int? engine_hours;
  String? speedType;
  int? status;
  dynamic all_data;

  PlayBackRoute({
    this.id,
    this.device_id,
    this.latitude,
    this.longitude,
    this.course,
    this.raw_time,
    this.speed,
    this.show,
    this.left,
    this.time,
    this.distance,
    this.fuel_consumption,
    this.top_speed,
    this.average_speed,
    this.engine_hours,
    this.speedType,
    this.status,
    this.all_data
  });

  PlayBackRoute.fromJson(Map<String, dynamic> json) {
    id = json["id"];
    device_id = json["device_id"];
    latitude = json["latitude"];
    longitude = json["longitude"];
    course = json["course"];
    raw_time = json["raw_time"];
    speed = json["speed"];
    show = json["show"];
    left = json["left"];
    time = json["time"];
    distance = json["distance"];
    fuel_consumption = json["fuel_consumption"];
    top_speed = json["top_speed"];
    average_speed = json["average_speed"];
    engine_hours = json["engine_hours"];
    speedType = json["speedType"];
    status = json["status"];
    all_data = json["all_data"];
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'device_id': device_id,
    'latitude': latitude,
    'longitude': longitude,
    'course': course,
    'raw_time': raw_time,
    'speed': speed,
    'show': show,
    'left': left,
    'time': time,
    'distance': distance,
    'fuel_consumption': fuel_consumption,
    'top_speed': top_speed,
    'average_speed': average_speed,
    'engine_hours': engine_hours,
    'speedType': speedType,
    'status': status,
    'all_data': all_data
  };
}
