class ShareModel extends Object {
  int? id;
  int? user_id;
  String? name;
  String? hash;
  String? expiration_date;
  String? active;
  String? delete_after_expiration;

  ShareModel(
      {this.id, this.user_id, this.name, this.hash, this.expiration_date, this.active, this.delete_after_expiration});

  ShareModel.fromJson(Map<String, dynamic> json) {
    id = json["id"];
    user_id = json["user_id"];
    name = json["name"];
    hash = json["hash"];
    expiration_date = json["expiration_date"];
    active = json["active"];
    delete_after_expiration = json["delete_after_expiration"];
  }

  Map<String, dynamic> toJson() =>
      {
        'id': id,
        'user_id': user_id,
        'name': name,
        'hash': hash,
        'expiration_date': expiration_date,
        'active': active,
        'delete_after_expiration': delete_after_expiration
      };
}
