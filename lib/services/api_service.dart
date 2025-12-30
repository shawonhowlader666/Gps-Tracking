
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gpspro/services/model/alert.dart';
import 'package:gpspro/services/model/device.dart';
import 'package:gpspro/services/model/event.dart';
import 'package:gpspro/services/model/event_history.dart';
import 'package:gpspro/services/model/geofence_model.dart';
import 'package:gpspro/services/model/position_history.dart';
import 'package:gpspro/services/model/route_report.dart';
import 'package:gpspro/services/model/share.dart';
import 'package:gpspro/services/model/share_perm.dart';
import 'package:gpspro/services/model/user.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:http/http.dart' as http;

class APIService {
  static String? serverURL;
  static String? socketURL;

  static Map<String, String> headers = {};

  static Future<http.Response?> login(url, email, password) async {
    headers['content-type'] = "application/json; charset=utf-8";
    try {
      serverURL = url;
      final response = await http.post(
          Uri.parse("${serverURL! + "/api/login?email=" + email}&password=" +
              password),
          headers: headers);
      updateCookie(response);
      if (response.statusCode == 200) {
        return response;
      } else {
        return response;
      }
    } catch (e) {
      return null;
    }
  }

  static updateCookie(http.Response response) {
    String rawCookie = response.headers['set-cookie'].toString();
    // ignore: unnecessary_null_comparison
    if (rawCookie != null) {
      int index = rawCookie.indexOf(';');
      headers['cookie'] =
          (index == -1) ? rawCookie : rawCookie.substring(0, index);
    }
  }

  static Future<RxList<Device>?> getDevices() async {
    final response = await http.get(Uri.parse(
        "$serverURL/api/get_devices?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"));
    print(response.body);
    if (response.statusCode == 200) {
      Iterable list = json.decode(response.body.replaceAll("ï»¿", ""));
      return list.map((model) => Device.fromJson(model)).toList().obs;
    } else {
      return null;
    }
  }

  static Future<PositionHistory?> getHistory(String deviceID, String fromDate,
      String fromTime, String toDate, String toTime) async {
    http.Response response = await http.get(Uri.parse(
        "$serverURL/api/get_history?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}&from_date=$fromDate&from_time=$fromTime&to_date=$toDate&to_time=$toTime&device_id=$deviceID"));
    if (response.statusCode == 200) {
      return PositionHistory.fromJson(
          json.decode(response.body.replaceAll("ï»¿", "")));
    } else {
      return null;
    }
  }

  static Future<RouteReport?> getReport(
      String deviceID, String fromDate, String toDate, int type) async {
    final response = await http.get(Uri.parse(
        "$serverURL/api/generate_report?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}&date_from=$fromDate&devices[]=$deviceID&date_to=$toDate&format=pdf&type=$type&daily=0&weekly=0&monthly=0&send_to_email=" +
            UserRepository.getEmail()!));
    if (response.statusCode == 200) {
      return RouteReport.fromJson(
          json.decode(response.body.replaceAll("ï»¿", "")));
    } else {
      return null;
    }
  }

  static Future<RouteReport?> getReportStop(
      String deviceID, String fromDate, String toDate, int type) async {
    final response = await http.get(Uri.parse(
        "$serverURL/api/generate_report?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}&date_from=$fromDate&devices[]=$deviceID&geofences[]=0&date_to=$toDate&format=pdf&type=$type&daily=0&weekly=0&monthly=0&send_to_email=" +
            UserRepository.getEmail()!));
    print("Response");
    print(response.body);
    if (response.statusCode == 200) {
      return RouteReport.fromJson(
          json.decode(response.body.replaceAll("ï»¿", "")));
    } else {
      return null;
    }
  }

  static Future<RouteReport?> getReportHtml(
      String deviceID, String fromDate, String toDate, int type) async {
    final response = await http.get(Uri.parse(
        "$serverURL/api/generate_report?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}&date_from=$fromDate&devices[]=$deviceID&date_to=$toDate&format=html&type=$type&daily=0&weekly=0&monthly=0"));
    if (response.statusCode == 200) {
      return RouteReport.fromJson(
          json.decode(response.body.replaceAll("ï»¿", "")));
    } else {
      return null;
    }
  }

  static Future<User?> getUserData() async {
    final response = await http.get(Uri.parse(
        "$serverURL/api/get_user_data?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"));
    if (response.statusCode == 200) {
      return User.fromJson(json.decode(response.body.replaceAll("ï»¿", "")));
    } else {
      return null;
    }
  }

  static Future<User?> getGeofences() async {
    final response = await http.get(Uri.parse(
        "$serverURL/api/get_user_data?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"));
    if (response.statusCode == 200) {
      return User.fromJson(json.decode(response.body.replaceAll("ï»¿", "")));
    } else {
      return null;
    }
  }

  static Future<http.Response> sessionLogout() async {
    headers['content-type'] = "application/x-www-form-urlencoded";
    final response = await http.delete(Uri.parse("$serverURL/api/session"),
        headers: headers);
    return response;
  }

  static Future<http.Response?> getSendCommands(String id) async {
    final response = await http.get(Uri.parse(
        "$serverURL/api/send_command_data?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"));
    if (response.statusCode == 200) {
      return response;
    } else {
      return null;
    }
  }

  static Future<http.Response> sendCommands(body) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    final response = await http.post(
        Uri.parse(
            "$serverURL/api/send_gprs_command?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"),
        body: body,
        headers: headers);
    print(response.body);
    return response;
  }
  //
  // static Future<List<Geofence>?> getGeoFences() async {
  //   headers['Accept'] = "application/json";
  //   final response = await http.get(
  //       Uri.parse(
  //           "$serverURL/api/get_geofences?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"),
  //       headers: headers);
  //   if (response.statusCode == 200) {
  //     Iterable list = json.decode(response.body.replaceAll("ï»¿", ""))['items']
  //         ['geofences'];
  //     if (list.isNotEmpty) {
  //       return list.map((model) => Geofence.fromJson(model)).toList();
  //     } else {
  //       return null;
  //     }
  //   } else {
  //     return null;
  //   }
  // }

  // static Future<http.Response?> addGeofence(fence) async {
  //   headers['content-type'] =
  //       "application/x-www-form-urlencoded; charset=UTF-8";
  //   final response = await http.post(
  //       Uri.parse(
  //           "$serverURL/api/add_geofence?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"),
  //       body: fence,
  //       headers: headers);
  //   return response;
  // }
  //
  // static Future<http.Response> destroyGeofence(id) async {
  //   headers['content-type'] =
  //       "application/x-www-form-urlencoded; charset=UTF-8";
  //   final response = await http.get(
  //       Uri.parse(
  //           "$serverURL/api/destroy_geofence?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"),
  //       headers: headers);
  //   return response;
  // }
  // Fix the destroyGeofence method in api_service.dart

  // In api_service.dart

  static Future<http.Response?> addGeofence(Map<String, dynamic> fence) async {
    headers['content-type'] = "application/x-www-form-urlencoded; charset=UTF-8";

    print('Creating geofence with data: $fence'); // Debug log

    final response = await http.post(
      Uri.parse(
          "$serverURL/api/add_geofence?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"
      ),
      body: fence,
      headers: headers,
    );

    print('Response: ${response.statusCode} - ${response.body}'); // Debug log
    return response;
  }

  static Future<List<Geofence>?> getGeoFences() async {
    headers['Accept'] = "application/json";
    final response = await http.get(
      Uri.parse(
          "$serverURL/api/get_geofences?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"
      ),
      headers: headers,
    );

    print('Geofences response: ${response.body}'); // Debug log

    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body.replaceAll("ï»¿", ""));
      Iterable list = jsonData['items']['geofences'];

      if (list.isNotEmpty) {
        return list.map((model) => Geofence.fromJson(model)).toList();
      } else {
        return null;
      }
    } else {
      return null;
    }
  }

  static Future<http.Response> destroyGeofence(id) async {
    headers['content-type'] = "application/x-www-form-urlencoded; charset=UTF-8";
    final response = await http.get(
        Uri.parse(
            "$serverURL/api/destroy_geofence?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}&geofence_id=$id"),
        headers: headers);
    return response;
  }

  // Add these methods to api_service.dart

// Get devices associated with a geofence
  static Future<List<dynamic>?> getGeofenceDevices(int? fenceId) async {
    if (fenceId == null) return null;

    try {
      final response = await http.get(
        Uri.parse(
            "$serverURL/api/get_geofence?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}&geofence_id=$fenceId"
        ),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body.replaceAll("ï»¿", ""));
        return data['items']?['devices'] ?? [];
      }
    } catch (e) {
      debugPrint('Error fetching geofence devices: $e');
    }
    return null;
  }

// Update geofence with devices
  static Future<http.Response?> updateGeofence(int fenceId, Map<String, dynamic> data) async {
    headers['content-type'] = "application/x-www-form-urlencoded; charset=UTF-8";

    final response = await http.post(
      Uri.parse(
          "$serverURL/api/edit_geofence?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"
      ),
      body: data,
      headers: headers,
    );
    return response;
  }

  static Future<List<Alert>?> getAlertList() async {
    headers['Accept'] = "application/json";
    final response = await http.get(
        Uri.parse(
            "$serverURL/api/get_alerts?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"),
        headers: headers);
    if (response.statusCode == 200) {
      Iterable list =
          json.decode(response.body.replaceAll("ï»¿", ""))['items']['alerts'];
      if (list.isNotEmpty) {
        return list.map((model) => Alert.fromJson(model)).toList();
      } else {
        return null;
      }
    } else {
      return null;
    }
  }

  static Future<http.Response?> getSavedCommands(String id) async {
    final response = await http.get(Uri.parse(
        "$serverURL/api/get_device_commands?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}&device_id=$id"));
    if (response.statusCode == 200) {
      return response;
    } else {
      return null;
    }
  }

  static Future<RxList<Event>?> getEventList() async {
    try {
      headers['Accept'] = "application/json";

      // Get language with fallback
      final language = UserRepository.getLanguage() ?? 'en';
      final hash = UserRepository.getHash() ?? '';

      final uri = Uri.parse(
          "$serverURL/api/get_events?user_api_hash=$hash&lang=$language"
      );

      // ✅ Add timeout
      final response = await http.get(
        uri,
        headers: headers,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Connection timeout - Please check your internet');
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body.replaceAll("ï»¿", ""));

        if (jsonData['items'] != null && jsonData['items']['data'] != null) {
          Iterable list = jsonData['items']['data'];

          if (list.isNotEmpty) {
            return list.map((model) => Event.fromJson(model)).toList().obs;
          }
        }
        return null;

      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized - Please login again');
      } else if (response.statusCode >= 500) {
        throw Exception('Server error - Please try again later');
      } else {
        throw Exception('Failed to load events: ${response.statusCode}');
      }

    } on SocketException {
      throw Exception('No internet connection');
    } on TimeoutException {
      throw Exception('Connection timeout - Please check your internet');
    } on FormatException {
      throw Exception('Invalid response format');
    } catch (e) {
      throw Exception('Error loading events: $e');
    }
  }

  static Future<http.Response> getGeocoder(lat, lng) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    final response = await http.get(
        Uri.parse(
            "$serverURL/api/geo_address?lat=$lat&lon=$lng&user_api_hash=${UserRepository.getHash()}"),
        headers: headers);
    return response;
  }

  static Future<String> getGeocoderAddress(lat, lng) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    final response = await http.get(
        Uri.parse(
            "$serverURL/api/geo_address?lat=$lat&lon=$lng&user_api_hash=${UserRepository.getHash()}"),
        headers: headers);
    if (response.statusCode == 200) {
      return response.body;
    } else {
      return "";
    }
  }

  static Future<http.Response> activateAlert(val) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    final response = await http.post(
        Uri.parse(
            "$serverURL/api/change_active_alert?user_api_hash=${UserRepository.getHash()}"),
        body: val,
        headers: headers);
    return response;
  }

  // static Future<http.Response> generateShare(email, deviceId, duration) async {
  //   SharedPreferences prefs = await SharedPreferences.getInstance();
  //   headers['content-type'] =
  //   "application/x-www-form-urlencoded; charset=UTF-8";
  //   final response = await http.post(
  //       Uri.parse(serverURL+"/sharing/send?_token="+prefs.getString("user_api_hash")+""
  //           "&expiration_by=duration&expiration_date=&duration="+duration+"&delete_after_expiration=0&devices%5B%5D="+deviceId+"&send_email=1&email="+email+""),
  //       headers: headers);
  //   print(response.request);
  //   return response;
  // }

  static Future<dynamic> generateShare(deviceId, expirationDate, name) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    final response = await http.post(
        Uri.parse(
            "${serverURL! + "/api/sharing?user_api_hash=${UserRepository.getHash()}&active=1&name=" + name + "&expiration_date=" + expirationDate}&delete_after_expiration=1&devices%5B%5D=" +
                deviceId),
        headers: headers);
    if (response.statusCode == 200) {
      return ShareModel.fromJson(
          json.decode(response.body.replaceAll("ï»¿", ""))['data']);
    } else {
      return SharePerm.fromJson(
          json.decode(response.body.replaceAll("ï»¿", "")));
    }
  }

  static Future<http.Response> changePassword(password) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    Map<String, String> requestBody = <String, String>{
      'password': password,
      "password_confirmation": password
    };
    final response = await http.post(
        Uri.parse(
            "$serverURL/api/change_password?user_api_hash=${UserRepository.getHash()}"),
        body: requestBody,
        headers: headers);
    return response;
  }

  static Future<http.Response> activateFCM(token) async {
    final response = await http.get(
        Uri.parse(
            "$serverURL/api/fcm_token?user_api_hash=${UserRepository.getHash()}&token=" +
                token),
        headers: headers);

    return response;
  }

  static Future<http.Response> activateDevice(val) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    final response = await http.post(
        Uri.parse(
            "$serverURL/api/change_active_device?user_api_hash=${UserRepository.getHash()}"),
        body: val,
        headers: headers);
    return response;
  }

  static Future<http.Response> editDeviceData(val) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    final response = await http.post(
        Uri.parse(
            "$serverURL/api/edit_device_data?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"),
        body: val,
        headers: headers);
    return response;
  }

  static Future<http.Response> getEditDeviceData(String deviceId) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    final response = await http.post(
        Uri.parse(
            "$serverURL/api/edit_device_data?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}&device_id=$deviceId"),
        headers: headers);
    return response;
  }

  static Future<http.Response> editDevice(val) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    final response = await http.post(
        Uri.parse(
            "$serverURL/api/edit_device?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"),
        body: val,
        headers: headers);
    return response;
  }

  static Future<http.Response> addDevice(val) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    final response = await http.post(
        Uri.parse(
            "$serverURL/api/add_device?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}"),
        body: val,
        headers: headers);
    return response;
  }

  static Future<List<EventHistory>?> getEventsByDevice(
      fromDate, toDate, deviceId) async {
    headers['Accept'] = "application/json";
    final response = await http.get(
        Uri.parse(
            "$serverURL/api/get_events?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}&from_date=" +
                fromDate +
                "&to_date=" +
                toDate +
                "&device_id=" +
                deviceId),
        headers: headers);
    if (response.statusCode == 200) {
      Iterable list =
          json.decode(response.body.replaceAll("ï»¿", ""))['items']['data'];
      if (list.isNotEmpty) {
        return list.map((model) => EventHistory.fromJson(model)).toList();
      } else {
        return null;
      }
    } else {
      return null;
    }
  }

  static Future<List<EventHistory>?> getTodayEvents(deviceId) async {
    headers['Accept'] = "application/json";
    final response = await http.get(
        Uri.parse(
            "$serverURL/api/get_events?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}&device_id=" +
                deviceId),
        headers: headers);
    if (response.statusCode == 200) {
      Iterable list =
          json.decode(response.body.replaceAll("ï»¿", ""))['items']['data'];
      if (list.isNotEmpty) {
        return list.map((model) => EventHistory.fromJson(model)).toList();
      } else {
        return null;
      }
    } else {
      return null;
    }
  }

  static Future<http.Response> addAlert(String request) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    final response = await http.post(
        Uri.parse(
            "$serverURL/api/add_alert?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}" +
                request),
        headers: headers);
    print(response.request);
    print(response.body);
    return response;
  }

  static Future<http.Response> destroyAlert(id) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    final response = await http.get(
        Uri.parse(serverURL! +
            "/api/destroy_alert?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}&alert_id=" +
            id.toString()),
        headers: headers);
    print(response.request);
    return response;
  }

  static Future<List<Event>?> getEventByID(String id, String fromDate,
      String fromTime, String toDate, String toTime) async {
    headers['Accept'] = "application/json";
    final response = await http.get(
        Uri.parse(serverURL! +
            "/api/get_events?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}&from_date=" +
            fromDate +
            "&from_time=" +
            fromTime +
            "&to_date=" +
            toDate +
            "&to_time=" +
            toTime +
            "&device_id=" +
            id),
        headers: headers);
    if (response.statusCode == 200) {
      Iterable list =
          json.decode(response.body.replaceAll("ï»¿", ""))['items']['data'];
      if (list.isNotEmpty) {
        return list.map((model) => Event.fromJson(model)).toList();
      } else {
        return null;
      }
    } else {
      return null;
    }
  }

  static Future<http.Response> activateFence(val) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    final response = await http.post(
        Uri.parse(serverURL! +
            "/api/change_active_geofence?user_api_hash=${UserRepository.getHash()}"),
        body: val,
        headers: headers);
    return response;
  }

  static Future<RouteReport?> getReportGeofence(
      String deviceID, String fromDate, String toDate, int type) async {
    final response = await http.get(Uri.parse(serverURL! +
        "/api/generate_report?user_api_hash=${UserRepository.getHash()}&lang=${UserRepository.getLanguage()}&date_from=" +
        fromDate +
        "&devices[]=" +
        deviceID +
        "&geofences[]=0" +
        "&date_to=" +
        toDate +
        "&format=pdf" +
        "&type=" +
        type.toString() +
        "&daily=0&weekly=0&monthly=0"));
    print(response.body);
    if (response.statusCode == 200) {
      return RouteReport.fromJson(
          json.decode(response.body.replaceAll("ï»¿", "")));
    } else {
      return null;
    }
  }

  static Future<http.Response> changePasswordByUser(password) async {
    headers['content-type'] =
        "application/x-www-form-urlencoded; charset=UTF-8";
    Map<String, String> requestBody = <String, String>{
      'password': password,
      "password_confirmation": password
    };
    final response = await http.post(
        Uri.parse(
            "$serverURL/api/change_password?user_api_hash=${UserRepository.getHash()}"),
        body: requestBody,
        headers: headers);
    return response;
  }

}
