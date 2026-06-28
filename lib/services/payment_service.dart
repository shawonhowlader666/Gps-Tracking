import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:gpspro/services/model/bill.dart';
import 'package:gpspro/services/model/payment_stats.dart';
import 'package:gpspro/services/model/billing_vehicle.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:http/http.dart' as http;

class PaymentService {
  static const String baseUrl = "https://billing.orbitgps.com.bd/api";
  static const Duration timeoutDuration = Duration(seconds: 30);
  static String? _token;
  static bool _isLoggingIn = false;

  /// Login to payment server
  static Future<bool> login() async {
    // Prevent multiple simultaneous login attempts
    if (_isLoggingIn) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (_token == null) {
        throw Exception("Authentication in progress, please try again.");
      }
      return true;
    }

    _isLoggingIn = true;

    try {
      final email = UserRepository.getEmail();
      final password = UserRepository.getPassword();

      if (email == null || password == null) {
        throw Exception("Your password is not saved in this session. Please log out and sign in again with 'Keep me signed in' checked.");
      }

      debugPrint("Payment Login: Trying with email=$email to $baseUrl/auth/login");

      final response = await http.post(
        Uri.parse("$baseUrl/auth/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "login": email,
          "password": password,
          "device_name": "mobile_app"
        }),
      ).timeout(timeoutDuration);

      debugPrint("Payment Login: Status=${response.statusCode} Body=${response.body.length > 300 ? response.body.substring(0, 300) : response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        debugPrint("Payment Login: Success, token=${_token?.substring(0, 20)}...");
        return true;
      } else if (response.statusCode == 401 || response.statusCode == 404) {
        throw Exception("This account is not registered on the billing server (Status ${response.statusCode}). Please contact support.");
      } else {
        throw Exception("Billing server login failed (Status ${response.statusCode}).");
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
        throw Exception("Failed to authenticate with the billing server.");
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
        throw Exception("Session expired. Please reload.");
      } else {
        debugPrint("Get Stats Error: Status ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Get Stats Error: $e");
      if (e.toString().contains("not registered") || e.toString().contains("not saved")) {
        rethrow;
      }
    }

    // Fallback: calculate stats from the bills list if stats endpoint fails
    try {
      final bills = await getBills();
      if (bills != null && bills.isNotEmpty) {
        double due = 0.0;
        double totalBilled = 0.0;
        double totalPaid = 0.0;
        int unpaidBillsCount = 0;

        for (final bill in bills) {
          totalBilled += bill.amount;
          double paidForBill = 0.0;
          for (final payment in bill.payments) {
            paidForBill += payment.amount;
          }
          if (bill.status.toLowerCase() == 'paid' && paidForBill < bill.amount) {
            paidForBill = bill.amount;
          }
          totalPaid += paidForBill;

          if (bill.status.toLowerCase() != 'paid') {
            due += (bill.amount - paidForBill);
            unpaidBillsCount++;
          }
        }
        return PaymentStats(
          due: due,
          totalBilled: totalBilled,
          totalPaid: totalPaid,
          unpaidBillsCount: unpaidBillsCount,
        );
      }
    } catch (e) {
      debugPrint("Fallback Get Stats Error: $e");
      rethrow;
    }
    throw Exception("No data could be retrieved from the billing server.");
  }

  /// Get bills with pagination
  static Future<List<Bill>?> getBills({int page = 1}) async {
    try {
      if (!await _ensureLoggedIn()) {
        throw Exception("Failed to authenticate with the billing server.");
      }

      final List<Bill> bills = [];
      int consecutive404Count = 0;
      int currentId = 1;
      const int batchSize = 5;
      const int maxConsecutive404 = 3;

      while (consecutive404Count < maxConsecutive404 && currentId <= 100) {
        final List<int> batchIds = [];
        for (int i = 0; i < batchSize; i++) {
          batchIds.add(currentId + i);
        }

        final List<Future<http.Response>> requests = batchIds.map((id) =>
          http.get(
            Uri.parse("$baseUrl/invoices/$id"),
            headers: _headers,
          ).timeout(const Duration(seconds: 10)),
        ).toList();

        var responses = await Future.wait(requests);

        // Check for 401 token expiration
        bool has401 = responses.any((res) => res.statusCode == 401);
        if (has401) {
          _token = null;
          if (await login()) {
            // Retry batch
            final retryRequests = batchIds.map((id) =>
              http.get(
                Uri.parse("$baseUrl/invoices/$id"),
                headers: _headers,
              ).timeout(const Duration(seconds: 10)),
            ).toList();
            responses = await Future.wait(retryRequests);
          } else {
            break; // Login failed, stop fetching
          }
        }

        for (int i = 0; i < responses.length; i++) {
          final res = responses[i];
          final id = batchIds[i];

          if (res.statusCode == 200) {
            consecutive404Count = 0; // Reset count
            try {
              final data = jsonDecode(res.body);
              if (data['data'] != null && data['data']['bill'] != null) {
                bills.add(Bill.fromJson(data['data']['bill']));
              }
            } catch (e) {
              debugPrint("Error parsing bill $id: $e");
            }
          } else if (res.statusCode == 404) {
            consecutive404Count++;
            if (consecutive404Count >= maxConsecutive404) {
              break;
            }
          }
        }

        currentId += batchSize;
      }

      // Sort bills by ID descending
      bills.sort((a, b) => b.id.compareTo(a.id));
      return bills;
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
  }

  /// Get vehicles from billing server
  static Future<List<BillingVehicle>?> getBillingVehicles() async {
    try {
      if (!await _ensureLoggedIn()) {
        return null;
      }

      final response = await http.get(
        Uri.parse("$baseUrl/vehicles?per_page=100"),
        headers: _headers,
      ).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List list = data['data'];
        return list.map((e) => BillingVehicle.fromJson(e)).toList();
      } else if (response.statusCode == 401) {
        _token = null;
        if (await login()) {
          final retryResponse = await http.get(
            Uri.parse("$baseUrl/vehicles?per_page=100"),
            headers: _headers,
          ).timeout(timeoutDuration);

          if (retryResponse.statusCode == 200) {
            final data = jsonDecode(retryResponse.body);
            final List list = data['data'];
            return list.map((e) => BillingVehicle.fromJson(e)).toList();
          }
        }
      } else {
        debugPrint("Get Billing Vehicles Error: Status ${response.statusCode}");
      }
    } on TimeoutException {
      debugPrint("Get Billing Vehicles Error: Connection timed out");
      rethrow;
    } on SocketException catch (e) {
      debugPrint("Get Billing Vehicles Error: Network error - $e");
      rethrow;
    } catch (e) {
      debugPrint("Get Billing Vehicles Error: $e");
      rethrow;
    }
    return null;
  }

  static Future<void> testEndpoints() async {
    try {
      await _ensureLoggedIn();
      final urls = [
        "$baseUrl/invoices",
        "$baseUrl/invoice",
        "$baseUrl/bills",
        "$baseUrl/bill",
        "$baseUrl/user/invoices",
        "$baseUrl/user/bills",
        "$baseUrl/my-invoices",
        "$baseUrl/my-bills",
        "$baseUrl/me/invoices",
        "$baseUrl/me/bills",
        "$baseUrl/invoices/2", // Specific bill ID from screenshot
      ];

      for (final url in urls) {
        final res = await http.get(Uri.parse(url), headers: _headers);
        debugPrint("PROBE $url -> STATUS: ${res.statusCode} | BODY: ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}");
      }
    } catch(e) {
      debugPrint("testEndpoints error: $e");
    }
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