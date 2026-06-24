// ignore_for_file: file_names

class CommandList {
  List<dynamic>? devicesSms;
  List<DevicesGprs>? devicesGprs;
  List<SmsTemplates>? smsTemplates;
  List<dynamic>? gprsTemplates;
  List<Commands>? commands;
  List<dynamic>? units;
  List<dynamic>? numberIndex;
  List<dynamic>? actions;
  dynamic deviceId;
  List<dynamic>? commandSchedules;
  int? status;

  CommandList(
      {this.devicesSms,
      this.devicesGprs,
      this.smsTemplates,
      this.gprsTemplates,
      this.commands,
      this.units,
      this.numberIndex,
      this.actions,
      this.deviceId,
      this.commandSchedules,
      this.status});

  CommandList.fromJson(Map<String, dynamic> json) {
    if (json['devices_sms'] != null) {
      devicesSms = json['devices_sms'];
    }
    if (json['devices_gprs'] != null) {
      devicesGprs = <DevicesGprs>[];
      json['devices_gprs'].forEach((v) {
        // ignore: unnecessary_new
        devicesGprs!.add(new DevicesGprs.fromJson(v));
      });
    }
    if (json['sms_templates'] != null) {
      smsTemplates = <SmsTemplates>[];
      json['sms_templates'].forEach((v) {
        smsTemplates!.add(SmsTemplates.fromJson(v));
      });
    }
    if (json['gprs_templates'] != null) {
      gprsTemplates = json['gprs_templates'];
    }
    if (json['commands'] != null) {
      commands = <Commands>[];
      json['commands'].forEach((v) {
        commands!.add(Commands.fromJson(v));
      });
    }
    if (json['units'] != null) {
      units = json['units'];
    }
    if (json['number_index'] != null) {
      numberIndex = json['number_index'];
    }
    if (json['actions'] != null) {
      actions = json['actions'];
    }
    deviceId = json['device_id'];
    if (json['command_schedules'] != null) {
      commandSchedules = json['command_schedules'];
    }
    status = json['status'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    if (devicesSms != null) {
      data['devices_sms'] = devicesSms!.map((v) => v.toJson()).toList();
    }
    if (devicesGprs != null) {
      data['devices_gprs'] = devicesGprs!.map((v) => v.toJson()).toList();
    }
    if (smsTemplates != null) {
      data['sms_templates'] = smsTemplates!.map((v) => v.toJson()).toList();
    }
    if (gprsTemplates != null) {
      data['gprs_templates'] = gprsTemplates!.map((v) => v.toJson()).toList();
    }
    if (commands != null) {
      data['commands'] = commands!.map((v) => v.toJson()).toList();
    }
    if (units != null) {
      data['units'] = units!.map((v) => v.toJson()).toList();
    }
    if (numberIndex != null) {
      data['number_index'] = numberIndex!.map((v) => v.toJson()).toList();
    }
    if (actions != null) {
      data['actions'] = actions!.map((v) => v.toJson()).toList();
    }
    data['device_id'] = deviceId;
    data['command_schedules'] = commandSchedules;
    data['status'] = status;
    return data;
  }
}

class DevicesGprs {
  int? id;
  String? value;

  DevicesGprs({this.id, this.value});

  DevicesGprs.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    value = json['value'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['value'] = value;
    return data;
  }
}

class SmsTemplates {
  String? id;
  String? title;
  String? message;

  SmsTemplates({this.id, this.title, this.message});

  SmsTemplates.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    title = json['title'];
    message = json['message'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['title'] = title;
    data['message'] = message;
    return data;
  }
}

class Commands {
  String? id;
  String? value;
  String? title;

  Commands({this.id, this.value, this.title});

  Commands.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    value = json['value'];
    title = json['title'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['value'] = value;
    data['title'] = title;
    return data;
  }
}

class NumberIndex {
  int? id;
  String? value;
  String? title;

  NumberIndex({this.id, this.value, this.title});

  NumberIndex.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    value = json['value'];
    title = json['title'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['value'] = value;
    data['title'] = title;
    return data;
  }
}
