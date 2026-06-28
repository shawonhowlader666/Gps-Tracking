import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:smart_lock/services/model/bill.dart';
import 'package:smart_lock/services/model/payment_stats.dart';
import 'package:smart_lock/storage/user_repository.dart';
import 'package:http/http.dart' as http;

class PaymentService {
  static const String baseUrl = "https://billing.orbitgps.com.bd/api";
  static const Duration timeoutDuration = Duration(seconds: 30);
  static String? _token;
  static bool _isLoggingIn = false;

  /// Login to payment server
  static Future<bool> login() async {
    if (_isLoggingIn) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (_token == null) {
        throw const HttpException("Already logging in, but no token acquired yet.");
      }
      return true;
    }
    _isLoggingIn = true;
    try {
      final email = UserRepository.getEmail();
      final password = UserRepository.getPassword();
      if (email == null || password == null) {
        throw const HttpException("User email or password is not saved in preferences.");
      }

      final response = await http
          .post(
            Uri.parse("$baseUrl/auth/login"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "login": email,
              "password": password,
              "device_name": "mobile_app",
            }),
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        _token = jsonDecode(response.body)['token'];
        return true;
      }
      throw HttpException("Billing Auth Failed (Status: ${response.statusCode}, Response: ${response.body})");
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (e) {
      rethrow;
    } finally {
      _isLoggingIn = false;
    }
  }

  static void clearToken() => _token = null;
  static bool get hasToken => _token != null;

  static Map<String, String> get _headers => {
        "Content-Type": "application/json",
        "Accept": "application/json",
        if (_token != null) "Authorization": "Bearer $_token",
      };

  static Future<bool> _ensureLoggedIn() async {
    if (_token == null) return await login();
    return true;
  }

  /// Generic GET with auto-retry on 401
  static Future<Map<String, dynamic>?> _getJson(String path) async {
    await _ensureLoggedIn();

    var response = await http
        .get(
          Uri.parse("$baseUrl$path"),
          headers: _headers,
        )
        .timeout(timeoutDuration);

    if (response.statusCode == 401) {
      _token = null;
      await login();
      response = await http
          .get(
            Uri.parse("$baseUrl$path"),
            headers: _headers,
          )
          .timeout(timeoutDuration);
    }

    if (response.statusCode == 200) return jsonDecode(response.body);
    throw HttpException("Server Error (Status: ${response.statusCode}, Response: ${response.body})");
  }

  /// Generic POST with auto-retry on 401
  static Future<Map<String, dynamic>?> _postJson(String path,
      {Map<String, dynamic>? body}) async {
    await _ensureLoggedIn();

    var response = await http
        .post(
          Uri.parse("$baseUrl$path"),
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(timeoutDuration);

    if (response.statusCode == 401) {
      _token = null;
      await login();
      response = await http
          .post(
            Uri.parse("$baseUrl$path"),
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeoutDuration);
    }

    if (response.statusCode == 200) return jsonDecode(response.body);
    throw HttpException("Server Error (Status: ${response.statusCode}, Response: ${response.body})");
  }

  /// Get payment statistics
  static Future<PaymentStats?> getStats() async {
    try {
      final data = await _getJson('/stats');
      if (data != null) return PaymentStats.fromJson(data);
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (e) {
      rethrow;
    }
    return null;
  }

  /// Get bills with pagination
  static Future<List<Bill>?> getBills({int page = 1}) async {
    try {
      final data = await _getJson('/bills?per_page=15&page=$page');
      if (data != null) {
        final List list = data['data'];
        return list.map((e) => Bill.fromJson(e)).toList();
      }
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (e) {
      rethrow;
    }
    return null;
  }

  /// Initiate SSL payment and get gateway URL
  static Future<String?> initiateSslPayment() async {
    try {
      final data = await _postJson('/payments/ssl/initiate');
      return data?['gateway_url'];
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  /// Get user expiration info
  /// Returns: { expiration_date, is_expired, days_remaining, human_readable }
  static Future<Map<String, dynamic>?> getExpirationInfo() async {
    try {
      return await _getJson('/user/expiration');
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }
}
