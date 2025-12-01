class NotificationTypeModel extends Object {
  String? type;

  NotificationTypeModel(
    this.type,
  );

  NotificationTypeModel.fromJson(Map<String, dynamic> json) {
    type = json["type"];
  }

  Map<String, dynamic> toJson() => {
        'type': type,
      };
}
