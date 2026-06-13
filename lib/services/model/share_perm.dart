class SharePerm {
  int? statusCode;
  String? message;
  int? status;
  Errors? errors;
  int? perm;

  SharePerm(
      {this.statusCode, this.message, this.status, this.errors, this.perm});

  SharePerm.fromJson(Map<String, dynamic> json) {
    statusCode = json['statusCode'];
    message = json['message'];
    status = json['status'];
    errors =
    json['errors'] != null ? Errors.fromJson(json['errors']) : null;
    perm = json['perm'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['statusCode'] = statusCode;
    data['message'] = message;
    data['status'] = status;
    if (errors != null) {
      data['errors'] = errors!.toJson();
    }
    data['perm'] = perm;
    return data;
  }
}

class Errors {
  String? id;

  Errors({this.id});

  Errors.fromJson(Map<String, dynamic> json) {
    id = json['id'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    return data;
  }
}