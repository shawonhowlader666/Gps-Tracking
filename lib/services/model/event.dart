class Event extends Object {
  dynamic id;
  String? message;
  dynamic latitude;
  dynamic longitude;
  String? device_name;
  String? time;
  dynamic speed;

  Event(
      {this.id, this.message, this.latitude, this.longitude, this.device_name});

  Event.fromJson(Map<String, dynamic> json) {
    id = json["id"];
    message = json["message"];
    latitude = json["latitude"];
    longitude = json["longitude"];
    device_name = json["device_name"];
    time = json["time"];
    speed = json["speed"];
  }
}
