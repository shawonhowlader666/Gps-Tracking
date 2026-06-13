class User extends Object {
  int? id;
  String? email;
  String? username;
  String? expiration_date;
  dynamic days_left;
  String? plan;
  int? devices_limit;
  int? group_id;

  User(
      {this.id,
      this.email,
      this.username,
      this.expiration_date,
      this.days_left,
      this.plan,
      this.devices_limit,
      this.group_id});

  User.fromJson(Map<String, dynamic> json) {
    id = json["id"];
    email = json["email"];
    username = json["username"] ?? json["name"];
    expiration_date = json["expiration_date"];
    days_left = json["days_left"];
    plan = json["plan"];
    devices_limit = json["devices_limit"];
    group_id = json["group_id"];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'username': username,
        'expiration_date': expiration_date,
        'days_left': days_left,
        'plan': plan,
        'devices_limit': devices_limit,
        'group_id': group_id
      };
}
