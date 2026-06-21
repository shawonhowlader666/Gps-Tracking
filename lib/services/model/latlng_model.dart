class LatLngModel extends Object {
  double? lat;
  double? lng;

  LatLngModel(
    this.lat,
    this.lng,
  );

  LatLngModel.fromJson(Map<String, dynamic> json) {
    lat = json["lat"];
    lng = json["lng"];
  }

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
      };
}
