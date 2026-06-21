class ServerList extends Object {
  dynamic id;
  String? name;
  String? url;

  ServerList(
      {id,
        name,
        type});

  ServerList.fromJson(Map<String, dynamic> json) {
    id = json["id"];
    name = json["name"];
    url = json["url"];
  }
}
