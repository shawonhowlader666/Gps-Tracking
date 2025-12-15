import 'dart:convert';
import 'package:gpspro/services/model/bill.dart';
import 'package:gpspro/services/model/payment_stats.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:http/http.dart' as http;

class PaymentService {
  static const String baseUrl = "http://93.127.143.78:8000/api";
  static String? _token;

  static Future<bool> login() async {
    final email = UserRepository.getEmail();
    final password = UserRepository.getPassword();

    if (email == null || password == null) return false;

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/auth/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "login": email,
          "password": password,
          "device_name": "mobile_app"
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        return true;
      }
      return false;
    } catch (e) {
      print("Payment Login Error: $e");
      return false;
    }
  }

  static Map<String, String> get _headers => {
    "Content-Type": "application/json",
    "Accept": "application/json",
    if (_token != null) "Authorization": "Bearer $_token",
  };

  static Future<PaymentStats?> getStats() async {
    if (_token == null) {
      bool loggedIn = await login();
      if (!loggedIn) return null;
    }
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/stats"),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return PaymentStats.fromJson(jsonDecode(response.body));
      } else if (response.statusCode == 401) {
        // Token expired, try login again
        if (await login()) {
          return getStats();
        }
      }
    } catch (e) {
      print("Get Stats Error: $e");
    }
    return null;
  }

  static Future<List<Bill>?> getBills({int page = 1}) async {
    if (_token == null) {
      bool loggedIn = await login();
      if (!loggedIn) return null;
    }
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/bills?per_page=15&page=$page"),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List list = data['data'];
        return list.map((e) => Bill.fromJson(e)).toList();
      } else if (response.statusCode == 401) {
        if (await login()) {
          return getBills(page: page);
        }
      }
    } catch (e) {
      print("Get Bills Error: $e");
    }
    return null;
  }

  static Future<String?> initiateSslPayment() async {
    if (_token == null) {
      bool loggedIn = await login();
      if (!loggedIn) return null;
    }
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/payments/ssl/initiate"),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['gateway_url'];
      }
    } catch (e) {
      print("Initiate Payment Error: $e");
    }
    return null;
  }
}
