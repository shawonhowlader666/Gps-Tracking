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
      'https://bgd.tracksolidpro.com/route/rest';
  static const String _appKey =
      '8FB345B8693CCD00C6CEB12895C150CF339A22A4105B6558';
  static const String _appSecret = '3928b55300604564b98344c92f5d6a2b';
  static const String _version = '0.9';

  /// Helper to build the mandatory base parameters for every request.
  Map<String, String> _baseParams(String method) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    return {
      'method': method,
      'app_key': _appKey,
      'timestamp': timestamp,
      'sign_method': 'hmac',
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
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Public API – each method mirrors a Tracksolid endpoint.
  // ---------------------------------------------------------------------

  Future<String?> login({required String account, required String password}) async {
    final params = _baseParams('jimi.user.login');
    params['account'] = account;
    params['password'] = password;
    final resp = await _post(params);
    if (resp == null) return null;
    if (resp['code'] == 0 || resp['code'] == '0') {
      final result = resp['result'];
      if (result is Map && result['accessToken'] != null) {
        return result['accessToken'].toString();
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> deviceList(String token) async {
    final params = _baseParams('jimi.device.list');
    params['access_token'] = token;
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
    const batchSize = 50;
    final List<Map<String, dynamic>> aggregated = [];
    for (int i = 0; i < imeis.length; i += batchSize) {
      final batch = imeis.skip(i).take(batchSize).toList();
      final params = _baseParams('jimi.device.currentinfo.get');
      params['access_token'] = token;
      params['imeis'] = batch.join(',');
      final resp = await _post(params);
      if (resp == null) continue;
      if (resp['code'] != 0 && resp['code'] != '0') continue;
      final result = resp['result'];
      if (result is List) {
        aggregated.addAll(List<Map<String, dynamic>>.from(result));
      }
    }
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
        '\${from.year}-\${_pad(from.month)}-\${_pad(from.day)} 00:00:00';
    params['endtime'] =
        '\${to.year}-\${_pad(to.month)}-\${_pad(to.day)} 23:59:59';
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
