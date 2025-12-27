import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:gpspro/services/model/bill.dart';
import 'package:gpspro/services/model/payment_stats.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:http/http.dart' as http;

class PaymentService {
  static const String baseUrl = "http://93.127.143.78:8000/api";
  static const Duration timeoutDuration = Duration(seconds: 30);
  static String? _token;
  static bool _isLoggingIn = false;

  /// Login to payment server
  static Future<bool> login() async {
    // Prevent multiple simultaneous login attempts
    if (_isLoggingIn) {
      // Wait for ongoing login to complete
      await Future.delayed(const Duration(milliseconds: 500));
      return _token != null;
    }

    _isLoggingIn = true;

    try {
      final email = UserRepository.getEmail();
      final password = UserRepository.getPassword();

      if (email == null || password == null) {
        debugPrint("Payment Login Error: Email or password is null");
        return false;
      }

      final response = await http.post(
        Uri.parse("$baseUrl/auth/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "login": email,
          "password": password,
          "device_name": "mobile_app"
        }),
      ).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        debugPrint("Payment Login: Success");
        return true;
      } else {
        debugPrint("Payment Login Error: Status ${response.statusCode}");
        return false;
      }
    } on TimeoutException {
      debugPrint("Payment Login Error: Connection timed out");
      rethrow;
    } on SocketException catch (e) {
      debugPrint("Payment Login Error: Network error - $e");
      rethrow;
    } catch (e) {
      debugPrint("Payment Login Error: $e");
      rethrow;
    } finally {
      _isLoggingIn = false;
    }
  }

  /// Clear stored token (call when user logs out)
  static void clearToken() {
    _token = null;
  }

  /// Check if token exists
  static bool get hasToken => _token != null;

  /// Get authorization headers
  static Map<String, String> get _headers => {
    "Content-Type": "application/json",
    "Accept": "application/json",
    if (_token != null) "Authorization": "Bearer $_token",
  };

  /// Ensure user is logged in before making API calls
  static Future<bool> _ensureLoggedIn() async {
    if (_token == null) {
      return await login();
    }
    return true;
  }

  /// Get payment statistics
  static Future<PaymentStats?> getStats() async {
    try {
      if (!await _ensureLoggedIn()) {
        return null;
      }

      final response = await http.get(
        Uri.parse("$baseUrl/stats"),
        headers: _headers,
      ).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        return PaymentStats.fromJson(jsonDecode(response.body));
      } else if (response.statusCode == 401) {
        // Token expired, clear and try login again
        _token = null;
        if (await login()) {
          // Retry once after re-login
          final retryResponse = await http.get(
            Uri.parse("$baseUrl/stats"),
            headers: _headers,
          ).timeout(timeoutDuration);

          if (retryResponse.statusCode == 200) {
            return PaymentStats.fromJson(jsonDecode(retryResponse.body));
          }
        }
      } else {
        debugPrint("Get Stats Error: Status ${response.statusCode}");
      }
    } on TimeoutException {
      debugPrint("Get Stats Error: Connection timed out");
      rethrow;
    } on SocketException catch (e) {
      debugPrint("Get Stats Error: Network error - $e");
      rethrow;
    } catch (e) {
      debugPrint("Get Stats Error: $e");
      rethrow;
    }
    return null;
  }

  /// Get bills with pagination
  static Future<List<Bill>?> getBills({int page = 1}) async {
    try {
      if (!await _ensureLoggedIn()) {
        return null;
      }

      final response = await http.get(
        Uri.parse("$baseUrl/bills?per_page=15&page=$page"),
        headers: _headers,
      ).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List list = data['data'];
        return list.map((e) => Bill.fromJson(e)).toList();
      } else if (response.statusCode == 401) {
        // Token expired, clear and try login again
        _token = null;
        if (await login()) {
          // Retry once after re-login
          final retryResponse = await http.get(
            Uri.parse("$baseUrl/bills?per_page=15&page=$page"),
            headers: _headers,
          ).timeout(timeoutDuration);

          if (retryResponse.statusCode == 200) {
            final data = jsonDecode(retryResponse.body);
            final List list = data['data'];
            return list.map((e) => Bill.fromJson(e)).toList();
          }
        }
      } else {
        debugPrint("Get Bills Error: Status ${response.statusCode}");
      }
    } on TimeoutException {
      debugPrint("Get Bills Error: Connection timed out");
      rethrow;
    } on SocketException catch (e) {
      debugPrint("Get Bills Error: Network error - $e");
      rethrow;
    } catch (e) {
      debugPrint("Get Bills Error: $e");
      rethrow;
    }
    return null;
  }

  /// Initiate SSL payment and get gateway URL
  static Future<String?> initiateSslPayment() async {
    try {
      if (!await _ensureLoggedIn()) {
        return null;
      }

      final response = await http.post(
        Uri.parse("$baseUrl/payments/ssl/initiate"),
        headers: _headers,
      ).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['gateway_url'];
      } else if (response.statusCode == 401) {
        // Token expired, clear and try login again
        _token = null;
        if (await login()) {
          // Retry once after re-login
          final retryResponse = await http.post(
            Uri.parse("$baseUrl/payments/ssl/initiate"),
            headers: _headers,
          ).timeout(timeoutDuration);

          if (retryResponse.statusCode == 200) {
            final data = jsonDecode(retryResponse.body);
            return data['gateway_url'];
          }
        }
      } else {
        debugPrint("Initiate Payment Error: Status ${response.statusCode}");
      }
    } on TimeoutException {
      debugPrint("Initiate Payment Error: Connection timed out");
      rethrow;
    } on SocketException catch (e) {
      debugPrint("Initiate Payment Error: Network error - $e");
      rethrow;
    } catch (e) {
      debugPrint("Initiate Payment Error: $e");
      rethrow;
    }
    return null;
  }
}