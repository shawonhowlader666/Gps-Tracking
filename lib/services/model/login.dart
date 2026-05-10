class UserLogin {
  int? status;
  String? userApiHash;
  Permissions? permissions;

  UserLogin({this.status, this.userApiHash, this.permissions});

  UserLogin.fromJson(Map<String, dynamic> json) {
    status = json['status'];
    userApiHash = json['user_api_hash'];
    permissions = json['permissions'] != null
        ? Permissions.fromJson(json['permissions'])
        : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = Map<String, dynamic>();
    data['status'] = status;
    data['user_api_hash'] = userApiHash;
    if (permissions != null) {
      data['permissions'] = permissions!.toJson();
    }
    return data;
  }
}

class Permissions {
  Devices? devices;
  Devices? beacons;
  Devices? alerts;
  Devices? geofences;
  Devices? routes;
  Devices? poi;
  Devices? reports;
  Devices? drivers;
  Devices? customEvents;
  Devices? userGprsTemplates;
  Devices? userSmsTemplates;
  Devices? smsGateway;
  Devices? sendCommand;
  Devices? history;
  Devices? maintenance;
  Devices? camera;
  Devices? deviceCamera;
  Devices? tasks;
  Devices? chat;
  Devices? mediaCategories;
  Devices? forwards;
  Devices? deviceImei;
  Devices? deviceSimNumber;
  Devices? deviceForward;
  Devices? deviceProtocol;
  Devices? deviceExpirationDate;
  Devices? deviceInstallationDate;
  Devices? deviceSimActivationDate;
  Devices? deviceSimExpirationDate;
  Devices? deviceMsisdn;
  Devices? deviceCustomFields;
  Devices? deviceDeviceTypeId;
  Devices? sharing;
  Devices? checklistTemplate;
  Devices? checklist;
  Devices? checklistActivity;
  Devices? checklistQrCode;
  Devices? checklistQrPreStartOnly;
  Devices? checklistOptionalImage;
  Devices? deviceConfiguration;
  Devices? deviceRouteTypes;
  Devices? callActions;
  Devices? widgetTemplateWebhook;
  Devices? customDeviceAdd;
  Devices? externalUrl;
  Devices? userLoginToken;
  Devices? userClientId;

  Permissions(
      {this.devices,
        this.beacons,
        this.alerts,
        this.geofences,
        this.routes,
        this.poi,
        this.reports,
        this.drivers,
        this.customEvents,
        this.userGprsTemplates,
        this.userSmsTemplates,
        this.smsGateway,
        this.sendCommand,
        this.history,
        this.maintenance,
        this.camera,
        this.deviceCamera,
        this.tasks,
        this.chat,
        this.mediaCategories,
        this.forwards,
        this.deviceImei,
        this.deviceSimNumber,
        this.deviceForward,
        this.deviceProtocol,
        this.deviceExpirationDate,
        this.deviceInstallationDate,
        this.deviceSimActivationDate,
        this.deviceSimExpirationDate,
        this.deviceMsisdn,
        this.deviceCustomFields,
        this.deviceDeviceTypeId,
        this.sharing,
        this.checklistTemplate,
        this.checklist,
        this.checklistActivity,
        this.checklistQrCode,
        this.checklistQrPreStartOnly,
        this.checklistOptionalImage,
        this.deviceConfiguration,
        this.deviceRouteTypes,
        this.callActions,
        this.widgetTemplateWebhook,
        this.customDeviceAdd,
        this.externalUrl,
        this.userLoginToken,
        this.userClientId});

  Permissions.fromJson(Map<String, dynamic> json) {
    devices =
    json['devices'] != null ? Devices.fromJson(json['devices']) : null;
    beacons =
    json['beacons'] != null ? Devices.fromJson(json['beacons']) : null;
    alerts =
    json['alerts'] != null ? Devices.fromJson(json['alerts']) : null;
    geofences = json['geofences'] != null
        ? Devices.fromJson(json['geofences'])
        : null;
    routes =
    json['routes'] != null ? Devices.fromJson(json['routes']) : null;
    poi = json['poi'] != null ? Devices.fromJson(json['poi']) : null;
    reports =
    json['reports'] != null ? Devices.fromJson(json['reports']) : null;
    drivers =
    json['drivers'] != null ? Devices.fromJson(json['drivers']) : null;
    customEvents = json['custom_events'] != null
        ? Devices.fromJson(json['custom_events'])
        : null;
    userGprsTemplates = json['user_gprs_templates'] != null
        ? Devices.fromJson(json['user_gprs_templates'])
        : null;
    userSmsTemplates = json['user_sms_templates'] != null
        ? Devices.fromJson(json['user_sms_templates'])
        : null;
    smsGateway = json['sms_gateway'] != null
        ? Devices.fromJson(json['sms_gateway'])
        : null;
    sendCommand = json['send_command'] != null
        ? Devices.fromJson(json['send_command'])
        : null;
    history =
    json['history'] != null ? Devices.fromJson(json['history']) : null;
    maintenance = json['maintenance'] != null
        ? Devices.fromJson(json['maintenance'])
        : null;
    camera =
    json['camera'] != null ? Devices.fromJson(json['camera']) : null;
    deviceCamera = json['device_camera'] != null
        ? Devices.fromJson(json['device_camera'])
        : null;
    tasks = json['tasks'] != null ? Devices.fromJson(json['tasks']) : null;
    chat = json['chat'] != null ? Devices.fromJson(json['chat']) : null;
    mediaCategories = json['media_categories'] != null
        ? Devices.fromJson(json['media_categories'])
        : null;
    forwards = json['forwards'] != null
        ? Devices.fromJson(json['forwards'])
        : null;
    deviceImei = json['device.imei'] != null
        ? Devices.fromJson(json['device.imei'])
        : null;
    deviceSimNumber = json['device.sim_number'] != null
        ? Devices.fromJson(json['device.sim_number'])
        : null;
    deviceForward = json['device.forward'] != null
        ? Devices.fromJson(json['device.forward'])
        : null;
    deviceProtocol = json['device.protocol'] != null
        ? Devices.fromJson(json['device.protocol'])
        : null;
    deviceExpirationDate = json['device.expiration_date'] != null
        ? Devices.fromJson(json['device.expiration_date'])
        : null;
    deviceInstallationDate = json['device.installation_date'] != null
        ? Devices.fromJson(json['device.installation_date'])
        : null;
    deviceSimActivationDate = json['device.sim_activation_date'] != null
        ? Devices.fromJson(json['device.sim_activation_date'])
        : null;
    deviceSimExpirationDate = json['device.sim_expiration_date'] != null
        ? Devices.fromJson(json['device.sim_expiration_date'])
        : null;
    deviceMsisdn = json['device.msisdn'] != null
        ? Devices.fromJson(json['device.msisdn'])
        : null;
    deviceCustomFields = json['device.custom_fields'] != null
        ? Devices.fromJson(json['device.custom_fields'])
        : null;
    deviceDeviceTypeId = json['device.device_type_id'] != null
        ? Devices.fromJson(json['device.device_type_id'])
        : null;
    sharing =
    json['sharing'] != null ? Devices.fromJson(json['sharing']) : null;
    checklistTemplate = json['checklist_template'] != null
        ? Devices.fromJson(json['checklist_template'])
        : null;
    checklist = json['checklist'] != null
        ? Devices.fromJson(json['checklist'])
        : null;
    checklistActivity = json['checklist_activity'] != null
        ? Devices.fromJson(json['checklist_activity'])
        : null;
    checklistQrCode = json['checklist_qr_code'] != null
        ? Devices.fromJson(json['checklist_qr_code'])
        : null;
    checklistQrPreStartOnly = json['checklist_qr_pre_start_only'] != null
        ? Devices.fromJson(json['checklist_qr_pre_start_only'])
        : null;
    checklistOptionalImage = json['checklist_optional_image'] != null
        ? Devices.fromJson(json['checklist_optional_image'])
        : null;
    deviceConfiguration = json['device_configuration'] != null
        ? Devices.fromJson(json['device_configuration'])
        : null;
    deviceRouteTypes = json['device_route_types'] != null
        ? Devices.fromJson(json['device_route_types'])
        : null;
    callActions = json['call_actions'] != null
        ? Devices.fromJson(json['call_actions'])
        : null;
    widgetTemplateWebhook = json['widget_template_webhook'] != null
        ? Devices.fromJson(json['widget_template_webhook'])
        : null;
    customDeviceAdd = json['custom_device_add'] != null
        ? Devices.fromJson(json['custom_device_add'])
        : null;
    externalUrl = json['external_url'] != null
        ? Devices.fromJson(json['external_url'])
        : null;
    userLoginToken = json['user.login_token'] != null
        ? Devices.fromJson(json['user.login_token'])
        : null;
    userClientId = json['user.client_id'] != null
        ? Devices.fromJson(json['user.client_id'])
        : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = Map<String, dynamic>();
    if (devices != null) {
      data['devices'] = devices!.toJson();
    }
    if (beacons != null) {
      data['beacons'] = beacons!.toJson();
    }
    if (alerts != null) {
      data['alerts'] = alerts!.toJson();
    }
    if (geofences != null) {
      data['geofences'] = geofences!.toJson();
    }
    if (routes != null) {
      data['routes'] = routes!.toJson();
    }
    if (poi != null) {
      data['poi'] = poi!.toJson();
    }
    if (reports != null) {
      data['reports'] = reports!.toJson();
    }
    if (drivers != null) {
      data['drivers'] = drivers!.toJson();
    }
    if (customEvents != null) {
      data['custom_events'] = customEvents!.toJson();
    }
    if (userGprsTemplates != null) {
      data['user_gprs_templates'] = userGprsTemplates!.toJson();
    }
    if (userSmsTemplates != null) {
      data['user_sms_templates'] = userSmsTemplates!.toJson();
    }
    if (smsGateway != null) {
      data['sms_gateway'] = smsGateway!.toJson();
    }
    if (sendCommand != null) {
      data['send_command'] = sendCommand!.toJson();
    }
    if (history != null) {
      data['history'] = history!.toJson();
    }
    if (maintenance != null) {
      data['maintenance'] = maintenance!.toJson();
    }
    if (camera != null) {
      data['camera'] = camera!.toJson();
    }
    if (deviceCamera != null) {
      data['device_camera'] = deviceCamera!.toJson();
    }
    if (tasks != null) {
      data['tasks'] = tasks!.toJson();
    }
    if (chat != null) {
      data['chat'] = chat!.toJson();
    }
    if (mediaCategories != null) {
      data['media_categories'] = mediaCategories!.toJson();
    }
    if (forwards != null) {
      data['forwards'] = forwards!.toJson();
    }
    if (deviceImei != null) {
      data['device.imei'] = deviceImei!.toJson();
    }
    if (deviceSimNumber != null) {
      data['device.sim_number'] = deviceSimNumber!.toJson();
    }
    if (deviceForward != null) {
      data['device.forward'] = deviceForward!.toJson();
    }
    if (deviceProtocol != null) {
      data['device.protocol'] = deviceProtocol!.toJson();
    }
    if (deviceExpirationDate != null) {
      data['device.expiration_date'] = deviceExpirationDate!.toJson();
    }
    if (deviceInstallationDate != null) {
      data['device.installation_date'] = deviceInstallationDate!.toJson();
    }
    if (deviceSimActivationDate != null) {
      data['device.sim_activation_date'] =
          deviceSimActivationDate!.toJson();
    }
    if (deviceSimExpirationDate != null) {
      data['device.sim_expiration_date'] =
          deviceSimExpirationDate!.toJson();
    }
    if (deviceMsisdn != null) {
      data['device.msisdn'] = deviceMsisdn!.toJson();
    }
    if (deviceCustomFields != null) {
      data['device.custom_fields'] = deviceCustomFields!.toJson();
    }
    if (deviceDeviceTypeId != null) {
      data['device.device_type_id'] = deviceDeviceTypeId!.toJson();
    }
    if (sharing != null) {
      data['sharing'] = sharing!.toJson();
    }
    if (checklistTemplate != null) {
      data['checklist_template'] = checklistTemplate!.toJson();
    }
    if (checklist != null) {
      data['checklist'] = checklist!.toJson();
    }
    if (checklistActivity != null) {
      data['checklist_activity'] = checklistActivity!.toJson();
    }
    if (checklistQrCode != null) {
      data['checklist_qr_code'] = checklistQrCode!.toJson();
    }
    if (checklistQrPreStartOnly != null) {
      data['checklist_qr_pre_start_only'] =
          checklistQrPreStartOnly!.toJson();
    }
    if (checklistOptionalImage != null) {
      data['checklist_optional_image'] = checklistOptionalImage!.toJson();
    }
    if (deviceConfiguration != null) {
      data['device_configuration'] = deviceConfiguration!.toJson();
    }
    if (deviceRouteTypes != null) {
      data['device_route_types'] = deviceRouteTypes!.toJson();
    }
    if (callActions != null) {
      data['call_actions'] = callActions!.toJson();
    }
    if (widgetTemplateWebhook != null) {
      data['widget_template_webhook'] = widgetTemplateWebhook!.toJson();
    }
    if (customDeviceAdd != null) {
      data['custom_device_add'] = customDeviceAdd!.toJson();
    }
    if (externalUrl != null) {
      data['external_url'] = externalUrl!.toJson();
    }
    if (userLoginToken != null) {
      data['user.login_token'] = userLoginToken!.toJson();
    }
    if (userClientId != null) {
      data['user.client_id'] = userClientId!.toJson();
    }
    return data;
  }
}

class Devices {
  bool? view;
  bool? edit;
  bool? remove;

  Devices({this.view, this.edit, this.remove});

  Devices.fromJson(Map<String, dynamic> json) {
    view = json['view'];
    edit = json['edit'];
    remove = json['remove'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = Map<String, dynamic>();
    data['view'] = view;
    data['edit'] = edit;
    data['remove'] = remove;
    return data;
  }
}