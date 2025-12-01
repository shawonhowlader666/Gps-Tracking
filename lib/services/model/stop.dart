class Stop extends Object {
  int? deviceId;
  String? deviceName;
  double? distance;
  double? averageSpeed;
  double? maxSpeed;
  double? spentFuel;
  double? startOdometer;
  double? endOdometer;
  int? positionId;
  double? latitude;
  double? longitude;
  String? startTime;
  String? endTime;
  String? address;
  int? duration;
  int? engineHours;

  Stop(
      {this.deviceId,
      this.deviceName,
      this.distance,
      this.averageSpeed,
      this.maxSpeed,
      this.spentFuel,
      this.startOdometer,
      this.endOdometer,
      this.positionId,
      this.latitude,
      this.longitude,
      this.startTime,
      this.endTime,
      this.address,
      this.duration,
      this.engineHours});

  Stop.fromJson(Map<String, dynamic> json) {
    deviceId = json["deviceId"];
    deviceName = json["deviceName"];
    distance = json["distance"];
    averageSpeed = json["distance"];
    maxSpeed = json["maxSpeed"];
    spentFuel = json["spentFuel"];
    startOdometer = json["startOdometer"];
    endOdometer = json["endOdometer"];
    positionId = json["positionId"];
    latitude = json["latitude"];
    longitude = json["longitude"];
    startTime = json["startTime"];
    endTime = json["endTime"];
    address = json["address"];
    duration = json["duration"];
    engineHours = json["engineHours"];
  }
}
