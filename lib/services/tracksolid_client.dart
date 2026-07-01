import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Low‑level HTTP client for Tracksolid Pro API.
///
/// It is deliberately pure (no Flutter dependencies) so it can be unit‑tested
/// easily and reused from other layers (repository, service, etc.).
class TracksolidClient {
  static const String _baseUrl =
      'https://hk-open.tracksolidpro.com/route/rest';
  static const String _appKey =
      '8FB345B8693CCD00C6CEB12895C150CF339A22A4105B6558';
  static const String _appSecret = '3928b55300604564b98344c92f5d6a2b';
  static const String _version = '1.0';

  /// Helper to build the mandatory base parameters for every request.
  Map<String, String> _baseParams(String method) {
    final now = DateTime.now().toUtc();
    final timestamp =
        '${now.year}-${_pad(now.month)}-${_pad(now.day)} '
        '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}';
    return {
      'method': method,
      'app_key': _appKey,
      'timestamp': timestamp,
      'sign_method': 'md5',
      'v': _version,
      'format': 'json',
    };
  }

  /// Calculates the MD5‑based signature as required by Tracksolid.
  ///
  /// The algorithm defined by Tracksolid is:
  ///   sign = MD5(appSecret + "key1" + "value1" + "key2" + "value2" + ... + appSecret)
  /// where keys are sorted alphabetically.
  String _calcSign(Map<String, String> params) {
    final sortedKeys = params.keys.toList()..sort();
    final buffer = StringBuffer(_appSecret);
    for (final key in sortedKeys) {
      buffer.write(key);
      buffer.write(params[key]);
    }
    buffer.write(_appSecret);
    final bytes = utf8.encode(buffer.toString());
    final digest = md5.convert(bytes);
    return digest.toString().toUpperCase();
  }

  /// Executes a POST request and returns the decoded JSON map.
  Future<Map<String, dynamic>?> _post(Map<String, String> params) async {
    final sign = _calcSign(params);
    params['sign'] = sign;
    try {
      final response = await http
          .post(Uri.parse(_baseUrl),
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: params)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
      } else {
        print("[Tracksolid API] HTTP Error: ${response.statusCode} - ${response.body}");
      }
      return null;
    } catch (e) {
      print("[Tracksolid API] Connection Exception: $e");
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Public API – each method mirrors a Tracksolid endpoint.
  // ---------------------------------------------------------------------

  Future<String?> login({required String account, required String password}) async {
    // API requires: user_id (account name) and user_pwd_md5 (lowercase MD5 of password)
    final cleanAccount = account.trim();
    final cleanPassword = password.trim();
    String pwdMd5;
    final hexRegExp = RegExp(r'^[a-fA-F0-9]{32}$');
    if (hexRegExp.hasMatch(cleanPassword)) {
      pwdMd5 = cleanPassword.toLowerCase();
    } else {
      pwdMd5 = md5.convert(utf8.encode(cleanPassword)).toString(); // lowercase MD5
    }
    final params = _baseParams('jimi.oauth.token.get');
    params['user_id'] = cleanAccount;
    params['user_pwd_md5'] = pwdMd5;
    params['expires_in'] = '7200';
    final resp = await _post(params);
    if (resp == null) {
      print("[Tracksolid API] Login response is null");
      return null;
    }
    print("[Tracksolid API] Login response: $resp");
    if (resp['code'] == 0 || resp['code'] == '0') {
      final result = resp['result'];
      if (result is Map && result['accessToken'] != null) {
        return result['accessToken'].toString();
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> deviceList(String token, String target) async {
    final params = _baseParams('jimi.user.device.list');
    params['access_token'] = token;
    params['target'] = target;
    params['page'] = '1';
    params['page_size'] = '1000';
    final resp = await _post(params);
    if (resp == null) return [];
    if (resp['code'] != 0 && resp['code'] != '0') return [];
    final result = resp['result'];
    if (result is List) return List<Map<String, dynamic>>.from(result);
    if (result is Map && result['list'] is List) {
      return List<Map<String, dynamic>>.from(result['list']);
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> currentInfo(String token, List<String> imeis) async {
    if (imeis.isEmpty) return [];
    
    const batchSize = 100;
    final List<Map<String, dynamic>> aggregated = [];
    
    // Prepare all request parameter sets
    final List<Map<String, String>> requestBatches = [];
    for (int i = 0; i < imeis.length; i += batchSize) {
      final batch = imeis.skip(i).take(batchSize).toList();
      final params = _baseParams('jimi.device.location.get');
      params['access_token'] = token;
      params['imeis'] = batch.join(',');
      requestBatches.add(params);
    }
    
    // Process requests in concurrent groups of 10
    const concurrency = 10;
    for (int i = 0; i < requestBatches.length; i += concurrency) {
      final group = requestBatches.skip(i).take(concurrency);
      final futures = group.map((params) => _post(params)).toList();
      final results = await Future.wait(futures);
      
      for (final resp in results) {
        if (resp == null) {
          print("[Tracksolid API] currentInfo batch response is null");
          continue;
        }
        if (resp['code'] != 0 && resp['code'] != '0') {
          print("[Tracksolid API] currentInfo error code: ${resp['code']} - message: ${resp['message']}");
          continue;
        }
        final result = resp['result'];
        if (result is List) {
          aggregated.addAll(List<Map<String, dynamic>>.from(result));
        } else {
          print("[Tracksolid API] currentInfo unexpected result format: $result");
        }
      }
    }
    
    print("[Tracksolid API] currentInfo: Fetched ${aggregated.length} records for ${imeis.length} devices.");
    return aggregated;
  }

  Future<List<Map<String, dynamic>>> history(
      String token, String imei, String beginTime, String endTime,
      {int limit = 1000}) async {
    final params = _baseParams('jimi.device.track.get');
    params['access_token'] = token;
    params['imei'] = imei;
    params['begintime'] = beginTime;
    params['endtime'] = endTime;
    params['limit'] = limit.toString();
    final resp = await _post(params);
    if (resp == null) return [];
    if (resp['code'] != 0 && resp['code'] != '0') return [];
    final result = resp['result'];
    if (result is List) return List<Map<String, dynamic>>.from(result);
    if (result is Map && result['list'] is List) {
      return List<Map<String, dynamic>>.from(result['list']);
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> alarms(
      String token, {
        String? imei,
        required DateTime from,
        required DateTime to,
        int page = 1,
        int limit = 50,
      }) async {
    final params = _baseParams('jimi.alarm.list');
    params['access_token'] = token;
    params['begintime'] =
        '${from.year}-${_pad(from.month)}-${_pad(from.day)} 00:00:00';
    params['endtime'] =
        '${to.year}-${_pad(to.month)}-${_pad(to.day)} 23:59:59';
    params['page'] = page.toString();
    params['limit'] = limit.toString();
    if (imei != null && imei.isNotEmpty) params['imei'] = imei;
    final resp = await _post(params);
    if (resp == null) return [];
    if (resp['code'] != 0 && resp['code'] != '0') return [];
    final result = resp['result'];
    if (result is List) return List<Map<String, dynamic>>.from(result);
    if (result is Map && result['list'] is List) {
      return List<Map<String, dynamic>>.from(result['list']);
    }
    return [];
  }

  Future<bool> control(String token, String imei, String command) async {
    final params = _baseParams('jimi.device.control');
    params['access_token'] = token;
    params['imei'] = imei;
    params['command'] = command;
    final resp = await _post(params);
    if (resp == null) return false;
    return resp['code'] == 0 || resp['code'] == '0';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
