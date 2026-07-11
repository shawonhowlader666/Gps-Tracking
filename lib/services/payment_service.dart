import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:smart_lock/services/model/bill.dart';
import 'package:smart_lock/services/model/payment_stats.dart';
import 'package:smart_lock/storage/user_repository.dart';
import 'package:http/http.dart' as http;

class PaymentService {
  static const String baseUrl = "https://billing.smartlockbd.com/api";
  static const Duration timeoutDuration = Duration(seconds: 30);
  static String? _token;
  static bool _isLoggingIn = false;

  static bool _isUserExpired = false;
  static DateTime? _userExpirationDate;
  static int _daysRemaining = 999;
  static bool _enableBillAlert = true;

  static bool get isUserExpired => _isUserExpired;
  static set isUserExpired(bool val) => _isUserExpired = val;
  static DateTime? get userExpirationDate => _userExpirationDate;
  static int get daysRemaining => _daysRemaining;
  static set daysRemaining(int val) => _daysRemaining = val;

  static bool get enableBillAlert => _enableBillAlert;
  static set enableBillAlert(bool val) => _enableBillAlert = val;

  static bool _sessionSnoozed = false;
  static bool get sessionSnoozed => _sessionSnoozed;
  static set sessionSnoozed(bool val) => _sessionSnoozed = val;

  static bool get isForcedBlocked => _isUserExpired && _enableBillAlert;

  // ── Per-vehicle expiration cache (from billing API) ───────────────────────
  // Key: GPSWOX device ID (int)
  // Value: {is_expired: bool, days_remaining: int}
  static final Map<int, Map<String, dynamic>> _vehicleExpirationCache = {};

  /// Returns true if billing API says this vehicle is expired.
  /// Falls back to false if not yet fetched.
  static bool isVehicleExpired(int vehicleId) {
    if (!_enableBillAlert) return false;
    final cached = _vehicleExpirationCache[vehicleId];
    if (cached == null) return false;
    return cached['is_expired'] == true;
  }

  /// Returns days_remaining for this vehicle. 999 if not fetched.
  static int vehicleDaysRemaining(int vehicleId) {
    final cached = _vehicleExpirationCache[vehicleId];
    return (cached?['days_remaining'] as int?) ?? 999;
  }

  /// Fetch expiration info for a single vehicle and cache it.
  static Future<void> updateVehicleExpiration(int vehicleId) async {
    try {
      final data = await _getJson('/vehicle/$vehicleId/expiration');
      if (data != null) {
        _vehicleExpirationCache[vehicleId] = {
          'is_expired': data['is_expired'] == true || data['is_expired'] == 'true',
          'days_remaining': (data['days_remaining'] as int?) ?? 999,
          'expiration_date': data['expiration_date'],
          'human_readable': data['human_readable'],
        };
      }
    } catch (_) {
      // Keep previous cache entry on failure — do not clear
    }
  }

  /// Fetch expiration info for ALL vehicles concurrently.
  /// Called after device list loads — runs in background, does NOT block UI.
  static Future<void> updateAllVehicleExpirations(List<int> vehicleIds) async {
    if (vehicleIds.isEmpty) return;
    await Future.wait(
      vehicleIds.map((id) => updateVehicleExpiration(id)),
    );
  }

  /// Login to payment server
  static Future<bool> login() async {
    if (_isLoggingIn) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (_token == null) {
        throw const HttpException(
            "Already logging in, but no token acquired yet.");
      }
      return true;
    }
    _isLoggingIn = true;
    try {
      final email = UserRepository.getEmail();
      final password = UserRepository.getPassword();
      if (email == null || password == null) {
        throw const HttpException(
            "User email or password is not saved in preferences.");
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
      throw HttpException(
          "Billing Auth Failed (Status: ${response.statusCode}, Response: ${response.body})");
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
    throw HttpException(
        "Server Error (Status: ${response.statusCode}, Response: ${response.body})");
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
    throw HttpException(
        "Server Error (Status: ${response.statusCode}, Response: ${response.body})");
  }

  /// Get payment statistics
  static Future<PaymentStats?> getStats() async {
    try {
      final data = await _getJson('/stats');
      if (data != null) {
        final stats = PaymentStats.fromJson(data);
        _enableBillAlert = stats.enableBillAlert;
        return stats;
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
      final info = await _getJson('/user/expiration');
      if (info != null) {
        _isUserExpired =
            info['is_expired'] == true || info['is_expired'] == 'true';
        final rawDate = info['expiration_date']?.toString();
        if (rawDate != null) {
          _userExpirationDate = DateTime.tryParse(rawDate);
        }
        _daysRemaining = (info['days_remaining'] as int?) ?? 999;
      }
      return info;
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  /// Update cached billing expiration status of user
  static Future<void> updateBillingExpirationStatus() async {
    try {
      final info = await getExpirationInfo();
      if (info != null) {
        _isUserExpired =
            info['is_expired'] == true || info['is_expired'] == 'true';
        final rawDate = info['expiration_date']?.toString();
        if (rawDate != null) {
          _userExpirationDate = DateTime.tryParse(rawDate);
        }
        _daysRemaining = (info['days_remaining'] as int?) ?? 999;
      } else {
        _isUserExpired = false;
        _userExpirationDate = null;
        _daysRemaining = 999;
      }
    } catch (_) {
      _isUserExpired = false;
      _userExpirationDate = null;
      _daysRemaining = 999;
    }
  }

  /// Get all billing packages from the server
  static Future<List<Map<String, dynamic>>?> getBillingPackages() async {
    try {
      final data = await _getJson('/billing-packages');
      if (data != null && data['data'] != null) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
    } catch (e) {
      rethrow;
    }
    return null;
  }
}
