class GeocoderModel extends Object {
  dynamic place_id;
  String? licence;
  String? osm_type;
  dynamic osm_id;
  String? lat;
  String? lon;
  String? display_name;

  GeocoderModel(
      {this.place_id,
      this.licence,
      this.osm_type,
      this.osm_id,
      this.lat,
      this.lon,
      this.display_name});

  GeocoderModel.fromJson(Map<String, dynamic> json) {
    place_id = json["place_id"];
    licence = json["licence"];
    osm_type = json["osm_type"];
    osm_id = json["osm_id"];
    lat = json["lat"];
    lon = json["lon"];
    display_name = json["display_name"];
  }
}
