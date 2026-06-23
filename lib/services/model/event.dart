class Event extends Object {
  dynamic id;
  String? message;
  dynamic latitude;
  dynamic longitude;
  String? device_name;
  String? time;
  dynamic speed;

  Event(
      {this.id, String? message, this.latitude, this.longitude, this.device_name}) {
    this.message = _cleanMessage(message);
  }

  Event.fromJson(Map<String, dynamic> json) {
    id = json["id"];
    message = _cleanMessage(json["message"]);
    latitude = json["latitude"];
    longitude = json["longitude"];
    device_name = json["device_name"];
    time = json["time"];
    speed = json["speed"];
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
