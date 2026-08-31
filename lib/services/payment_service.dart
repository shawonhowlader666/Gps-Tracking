import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:smart_lock/services/model/bill.dart';
import 'package:smart_lock/services/model/payment_stats.dart';
import 'package:smart_lock/storage/user_repository.dart';
import 'package:http/http.dart' as http;

class PaymentService {
  static const String baseUrl = "https://billing.smartlockbd.com/api";
  static const Duration timeoutDuration = Duration(seconds: 30);
  static String? _token;
  static Future<bool>? _loginFuture;
  static DateTime? _lastLoginFailure;
  static int _consecutiveFailures = 0;

  static bool _isUserExpired = false;
  static DateTime? _userExpirationDate;
  static int _daysRemaining = 999;
  static bool _enableBillAlert = true;

  static DateTime? _lastBillingStatusUpdate;
  static const Duration _billingStatusTtl = Duration(minutes: 10);

  static DateTime? _lastAllVehiclesFetch;
  static const Duration _vehicleCacheTtl = Duration(hours: 1);
  static Future<void>? _allVehiclesFuture;

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
  static final Map<int, Map<String, dynamic>> _vehicleExpirationCache = {};

  /// Returns true if billing API says this vehicle is expired.
  static bool isVehicleExpired(int vehicleId) {
    final cached = _vehicleExpirationCache[vehicleId];
    if (cached == null) return false;
    final bool isExpiredBool = cached['is_expired'] == true || cached['is_expired'] == 'true' || cached['is_expired'] == 1;
    final int days = (cached['days_remaining'] as int?) ?? 999;
    return isExpiredBool || days <= 0;
  }

  /// Returns days_remaining for this vehicle. 999 if not fetched.
  static int vehicleDaysRemaining(int vehicleId) {
    final cached = _vehicleExpirationCache[vehicleId];
    return (cached?['days_remaining'] as int?) ?? 999;
  }

  /// Fetch expiration info for a single vehicle and cache it.
  static Future<void> updateVehicleExpiration(int vehicleId) async {
    final cached = _vehicleExpirationCache[vehicleId];
    if (cached != null) {
      final fetchedAt = cached['fetched_at'] as DateTime?;
      // Cache both valid hits and 404/error hits for 1 hour to prevent 404 HTTP flood on server
      if (fetchedAt != null && DateTime.now().difference(fetchedAt) < _vehicleCacheTtl) {
        return; // Valid cache hit
      }
    }

    try {
      final data = await _getJson('/vehicle/$vehicleId/expiration');
      if (data != null) {
        _vehicleExpirationCache[vehicleId] = {
          'is_expired': data['is_expired'] == true || data['is_expired'] == 'true' || data['is_expired'] == 1,
          'days_remaining': (data['days_remaining'] as int?) ?? 999,
          'expiration_date': data['expiration_date'],
          'human_readable': data['human_readable'],
          'fetched_at': DateTime.now(),
          'is_error': false,
        };
      } else {
        // Error cache: retry after 15 seconds instead of 30 minutes
        _vehicleExpirationCache[vehicleId] = {
          'is_expired': false,
          'days_remaining': 999,
          'expiration_date': null,
          'human_readable': null,
          'fetched_at': DateTime.now(),
          'is_error': true,
        };
      }
    } catch (_) {
      _vehicleExpirationCache[vehicleId] = {
        'is_expired': false,
        'days_remaining': 999,
        'fetched_at': DateTime.now(),
        'is_error': true,
      };
    }
  }

  /// Get raw vehicle expiration details from server
  static Future<Map<String, dynamic>?> getVehicleExpiration(int vehicleId) async {
    try {
      await updateVehicleExpiration(vehicleId);
      final cached = _vehicleExpirationCache[vehicleId];
      if (cached != null && cached['is_error'] != true) {
        return cached;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetch expiration info for ALL vehicles in throttled batches of 5.
  /// Cached for 30 minutes unless forced.
  static Future<void> updateAllVehicleExpirations(List<int> vehicleIds, {bool force = false}) async {
    if (vehicleIds.isEmpty) return;
    if (!force && _lastAllVehiclesFetch != null) {
      if (DateTime.now().difference(_lastAllVehiclesFetch!) < _vehicleCacheTtl) {
        return;
      }
    }
    if (_allVehiclesFuture != null) {
      return _allVehiclesFuture!;
    }

    _allVehiclesFuture = _performUpdateAllVehicleExpirations(vehicleIds);
    try {
      await _allVehiclesFuture;
    } finally {
      _allVehiclesFuture = null;
    }
  }

  static Future<void> _performUpdateAllVehicleExpirations(List<int> vehicleIds) async {
    await login(); // Ensure authentication token is active before running batch requests
    _lastAllVehiclesFetch = DateTime.now();

    // Process in batches of 5 concurrent requests to prevent server connection overload
    const int batchSize = 5;
    for (int i = 0; i < vehicleIds.length; i += batchSize) {
      final end = (i + batchSize < vehicleIds.length) ? i + batchSize : vehicleIds.length;
      final batch = vehicleIds.sublist(i, end);
      await Future.wait(batch.map((id) => updateVehicleExpiration(id)));
    }
  }

  /// Dynamic exponential backoff duration based on consecutive failures
  static Duration get _backoffDuration {
    switch (_consecutiveFailures) {
      case 0:
        return Duration.zero;
      case 1:
        return const Duration(seconds: 30);
      case 2:
        return const Duration(minutes: 1);
      case 3:
        return const Duration(minutes: 3);
      default:
        return const Duration(minutes: 10);
    }
  }

  /// Login to payment server with exponential backoff & mutex
  static Future<bool> login({bool force = false}) async {
    // 1. Check in-memory token
    if (_token != null && !force) return true;

    // 2. Check persistent token from UserRepository
    if (_token == null && !force) {
      final savedToken = UserRepository.getBillingToken();
      if (savedToken != null && savedToken.isNotEmpty) {
        _token = savedToken;
        return true;
      }
    }

    // 3. Exponential backoff check on failed login attempts
    if (!force && _lastLoginFailure != null) {
      final elapsed = DateTime.now().difference(_lastLoginFailure!);
      if (elapsed < _backoffDuration) {
        debugPrint("[PaymentService] Login suppressed by exponential backoff (${_backoffDuration.inSeconds - elapsed.inSeconds}s remaining).");
        return false;
      }
    }

    // 4. Mutex: single shared Future for concurrent login callers
    if (_loginFuture != null) {
      return (await _loginFuture) ?? false;
    }

    _loginFuture = _performLogin();
    try {
      final result = await _loginFuture!;
      return result;
    } finally {
      _loginFuture = null;
    }
  }

  static Future<bool> _performLogin() async {
    try {
      final email = UserRepository.getEmail();
      final password = UserRepository.getPassword();
      if (email == null || password == null) {
        _recordFailure();
        return false;
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
        final body = jsonDecode(response.body);
        if (body is Map && body.containsKey('token')) {
          _token = body['token']?.toString();
          UserRepository.setBillingToken(_token);
          _consecutiveFailures = 0;
          _lastLoginFailure = null;
          return true;
        }
      }
      _recordFailure();
      return false;
    } catch (_) {
      _recordFailure();
      return false;
    }
  }

  static void _recordFailure() {
    _consecutiveFailures++;
    _lastLoginFailure = DateTime.now();
    _token = null;
    UserRepository.setBillingToken(null);
  }

  static void clearToken() {
    _token = null;
    UserRepository.setBillingToken(null);
  }

  static bool get hasToken => _token != null || UserRepository.getBillingToken() != null;

  static Map<String, String> get _headers => {
        "Content-Type": "application/json",
        "Accept": "application/json",
        if (_token != null) "Authorization": "Bearer $_token",
      };

  static Future<bool> _ensureLoggedIn() async {
    if (_token != null) return true;
    return await login();
  }

  /// Generic GET with auto-retry on 401
  static Future<Map<String, dynamic>?> _getJson(String path) async {
    final loggedIn = await _ensureLoggedIn();
    if (!loggedIn) return null;

    try {
      var response = await http
          .get(
            Uri.parse("$baseUrl$path"),
            headers: _headers,
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 401) {
        _token = null;
        final relinkSuccess = await login(force: true);
        if (!relinkSuccess) return null;

        response = await http
            .get(
              Uri.parse("$baseUrl$path"),
              headers: _headers,
            )
            .timeout(timeoutDuration);
      }

      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Generic POST with auto-retry on 401
  static Future<Map<String, dynamic>?> _postJson(String path,
      {Map<String, dynamic>? body}) async {
    final loggedIn = await _ensureLoggedIn();
    if (!loggedIn) return null;

    try {
      var response = await http
          .post(
            Uri.parse("$baseUrl$path"),
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 401) {
        _token = null;
        final relinkSuccess = await login(force: true);
        if (!relinkSuccess) return null;

        response = await http
            .post(
              Uri.parse("$baseUrl$path"),
              headers: _headers,
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(timeoutDuration);
      }

      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (_) {
      return null;
    }
  }

  static PaymentStats? _cachedStats;
  static DateTime? _lastStatsFetch;
  static const Duration _statsTtl = Duration(minutes: 5);

  /// Get payment statistics with 5-minute TTL caching
  static Future<PaymentStats?> getStats({bool force = false}) async {
    if (!force && _cachedStats != null && _lastStatsFetch != null) {
      if (DateTime.now().difference(_lastStatsFetch!) < _statsTtl) {
        return _cachedStats;
      }
    }
    try {
      final data = await _getJson('/stats');
      if (data != null) {
        final stats = PaymentStats.fromJson(data);
        _enableBillAlert = stats.enableBillAlert;
        _cachedStats = stats;
        _lastStatsFetch = DateTime.now();
        return stats;
      }
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (e) {
      rethrow;
    }
    return _cachedStats;
  }

  /// Get bills with pagination (resolved from invoices)
  static Future<List<Bill>?> getBills({int page = 1}) async {
    try {
      if (page > 1) return [];
      final data = await _getJson('/invoices');
      if (data != null) {
        final List list = data['bills'] ?? [];
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

  /// Get bills for a specific vehicle
  static Future<List<dynamic>?> getVehicleBills(int vehicleId) async {
    try {
      final data = await _getJson('/vehicle/$vehicleId/bills');
      if (data != null) {
        return data['data'] as List?;
      }
    } catch (_) {}
    return null;
  }

  /// Get raw bills data from server
  static Future<Map<String, dynamic>?> getBillsRaw() async {
    try {
      return await _getJson('/bills?per_page=15');
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _cachedInvoicesRaw;
  static DateTime? _lastInvoicesRawFetch;
  static const Duration _invoicesTtl = Duration(minutes: 5);

  /// Get raw invoices data from server with 5-minute TTL caching
  static Future<Map<String, dynamic>?> getInvoicesRaw({bool force = false}) async {
    if (!force && _cachedInvoicesRaw != null && _lastInvoicesRawFetch != null) {
      if (DateTime.now().difference(_lastInvoicesRawFetch!) < _invoicesTtl) {
        return _cachedInvoicesRaw;
      }
    }
    try {
      final res = await _getJson('/invoices');
      if (res != null) {
        _cachedInvoicesRaw = res;
        _lastInvoicesRawFetch = DateTime.now();
      }
      return res ?? _cachedInvoicesRaw;
    } catch (_) {
      return _cachedInvoicesRaw;
    }
  }

  /// Get raw singular invoice data from server
  static Future<Map<String, dynamic>?> getInvoiceSingularRaw() async {
    try {
      return await _getJson('/invoice');
    } catch (_) {
      return null;
    }
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
  static Future<void> updateBillingExpirationStatus({bool force = false}) async {
    if (!force && _lastBillingStatusUpdate != null) {
      if (DateTime.now().difference(_lastBillingStatusUpdate!) < _billingStatusTtl) {
        return;
      }
    }
    _lastBillingStatusUpdate = DateTime.now();
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
      }
    } catch (_) {}
  }

  /// Get all billing packages from the server
  static Future<List<Map<String, dynamic>>?> getBillingPackages() async {
    try {
      final data = await _getJson('/subscription-packages');
      if (data != null && data['data'] != null) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
    } catch (e) {
      rethrow;
    }
    return null;
  }

  /// Calculate custom discount and payable total from billing API for user's vehicles.
  /// Pass durationMonths: null to let server decide the best duration automatically.
  static Future<Map<String, dynamic>?> calculateManualCustomDiscount({
    int? durationMonths,
    num? discountPercent,
    String? startMonth,
    bool willCreate = false,
  }) async {
    try {
      final Map<String, dynamic> body = {
        'will_create': willCreate,
      };
      if (durationMonths != null && durationMonths > 0) {
        body['duration_months'] = durationMonths;
      }
      if (discountPercent != null) {
        body['discount_percent'] = discountPercent;
      }
      if (startMonth != null) {
        body['start_month'] = startMonth;
      }
      debugPrint("[BILLING API] Sending POST /users/manual-custom-discount with body: $body");
      final res = await _postJson('/users/manual-custom-discount', body: body);
      debugPrint("[BILLING API] Received response: $res");
      return res;
    } catch (e) {
      debugPrint("[BILLING API] ERROR IN calculateManualCustomDiscount: $e");
      return null;
    }
  }
}
