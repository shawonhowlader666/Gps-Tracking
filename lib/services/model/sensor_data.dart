class SensorData extends Object {
  String? dateTime;
  int? val;

  SensorData(
      {this.dateTime, this.val});

  SensorData.fromJson(Map<String, dynamic> json) {
    dateTime = json["dateTime"];
    val = json["val"];
  }
}
