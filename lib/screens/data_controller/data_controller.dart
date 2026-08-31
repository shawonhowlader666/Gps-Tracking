import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:smart_lock/services/model/device.dart';
import 'package:smart_lock/services/model/device_item.dart';
import 'package:smart_lock/services/model/event.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/storage/user_repository.dart';
import 'package:smart_lock/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_lock/util/util.dart';
import 'package:smart_lock/services/payment_service.dart';

class DataController extends GetxController with WidgetsBindingObserver {
  Timer? _pollingTimer;
  int _currentPollingIntervalSeconds = 8;
  // Overrides to prevent UI bouncing after sending lock/unlock commands
  static final Map<int, String> _localEngineStatusOverrides =
      {}; // deviceId -> engineStatus
  static final Map<int, String> _localLockStatusOverrides =
      {}; // deviceId -> lockStatus


  static Future<void> loadOverrides() async {
    try {
      final prefs =
          UserRepository.prefs ?? await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('local_status_overrides');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> decoded = json.decode(jsonStr);
        decoded.forEach((key, value) {
          final int? deviceId = int.tryParse(key);
          if (deviceId != null && value is Map) {
            if (value.containsKey('engineStatus')) {
              _localEngineStatusOverrides[deviceId] =
                  value['engineStatus'] as String;
            }
            if (value.containsKey('lockStatus')) {
              _localLockStatusOverrides[deviceId] =
                  value['lockStatus'] as String;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading overrides: $e');
    }
  }

  static Future<void> saveOverrides() async {
    try {
      final prefs =
          UserRepository.prefs ?? await SharedPreferences.getInstance();
      final Map<String, dynamic> dataToSave = {};

      final allDeviceIds = <int>{
        ..._localEngineStatusOverrides.keys,
        ..._localLockStatusOverrides.keys
      };

      for (final deviceId in allDeviceIds) {
        dataToSave[deviceId.toString()] = {
          if (_localEngineStatusOverrides.containsKey(deviceId))
            'engineStatus': _localEngineStatusOverrides[deviceId],
          if (_localLockStatusOverrides.containsKey(deviceId))
            'lockStatus': _localLockStatusOverrides[deviceId],
        };
      }

      await prefs.setString('local_status_overrides', json.encode(dataToSave));
    } catch (e) {
      debugPrint('Error saving overrides: $e');
    }
  }

  static String? getLocalEngineOverride(int deviceId) {
    return _localEngineStatusOverrides[deviceId];
  }

  static String? getLocalLockOverride(int deviceId) {
    return _localLockStatusOverrides[deviceId];
  }

  static Future<void> setLocalStatusOverride(int deviceId,
      {required String engineStatus, required String lockStatus}) async {
    _localEngineStatusOverrides[deviceId] = engineStatus;
    _localLockStatusOverrides[deviceId] = lockStatus;
    await saveOverrides();

    // Find instance and refresh
    try {
      if (Get.isRegistered<DataController>()) {
        final controller = Get.find<DataController>();
        controller.applyOverridesAndRefresh();
      }
    } catch (e) {
      debugPrint('Error refreshing DataController overrides: $e');
    }
  }

  static Future<void> clearLocalStatusOverride(int deviceId) async {
    _localEngineStatusOverrides.remove(deviceId);
    _localLockStatusOverrides.remove(deviceId);
    await saveOverrides();

    // Find instance and refresh
    try {
      if (Get.isRegistered<DataController>()) {
        final controller = Get.find<DataController>();
        controller.applyOverridesAndRefresh();
      }
    } catch (e) {
      debugPrint('Error refreshing DataController overrides: $e');
    }
  }

  static void clearAllOverridesInMemory() {
    _localEngineStatusOverrides.clear();
    _localLockStatusOverrides.clear();
  }

  void applyOverridesAndRefresh() {
    for (var element in onlyDevices) {
      final devId = element.id;
      if (devId != null) {
        if (_localEngineStatusOverrides.containsKey(devId)) {
          element.engineStatus = _localEngineStatusOverrides[devId];
        }
        if (element.deviceData != null &&
            _localLockStatusOverrides.containsKey(devId)) {
          element.deviceData!.lockStatus = _localLockStatusOverrides[devId];
        }
      }
    }
    onlyDevices.refresh();
    devices.refresh();
    filteredDevices.assignAll(onlyDevices);
    _updateStatusCounters();
    _reapplyCurrentFilter();
  }

  static bool? _parseRawEngineStatus(dynamic status) {
    if (status == null) return null;
    if (status is bool) return status;
    if (status is int) return status == 1;
    if (status is String) {
      final s = status.toLowerCase().trim();
      if (['on', '1', 'true', 'ign on', 'engine on', 'acc on'].contains(s)) {
        return true;
      }
      if (['off', '0', 'false', 'ign off', 'engine off', 'acc off'].contains(s)) {
        return false;
      }
    }
    return null;
  }

  // Device Lists
  RxList<Device> devices = <Device>[].obs;
  RxList<DeviceItem> onlyDevices = <DeviceItem>[].obs;
  RxList<DeviceItem> filteredDevices = <DeviceItem>[].obs;
  RxList<DeviceItem> searchedDevices = <DeviceItem>[].obs;
  final RxMap<String, double> vehicleDueMap = <String, double>{}.obs;

  double getVehicleDue(DeviceItem device) {
    if (vehicleDueMap.isEmpty) return 0.0;
    final id = device.id?.toString();
    final name = device.name?.toLowerCase().trim();
    final imei = (device.imei ?? device.deviceData?.imei)?.toString().trim();

    if (id != null && vehicleDueMap.containsKey(id)) return vehicleDueMap[id]!;
    if (imei != null && vehicleDueMap.containsKey(imei)) return vehicleDueMap[imei]!;
    if (name != null && vehicleDueMap.containsKey(name)) return vehicleDueMap[name]!;
    return 0.0;
  }

  // Status Counters
  RxInt allCount = 0.obs;
  RxInt movingCount = 0.obs;
  RxInt idleCount = 0.obs;
  RxInt offlineCount = 0.obs;

  // UI State
  RxBool isLoading = true.obs;
  RxBool isEventLoading = true.obs;
  RxInt selectedFilterIndex = 0.obs;
  RxString searchText = ''.obs;
  RxBool isSearchVisible = false.obs;
  RxInt expandedIndex = (-1).obs;

  // ── Events: দুটো source — local (app-generated) + server (WOX API) ────────
  // localEvents: engine on/off, overspeed, offline, geofence — locally detect করা
  // events: merged final list (local + server, deduplicated, newest first)
  RxList<Event> localEvents = <Event>[].obs;
  RxList<Event> events = <Event>[].obs;
  var counter = 0.obs;
  var markers = <Marker>{}.obs;

  // ── Change-detection state (for local alert triggers) ─────────────────────
  final Map<int, bool> _prevEngineStatus = {};
  final Map<int, bool> _prevOnlineStatus = {};
  final Map<int, bool> _prevIdleStatus = {};     // true = idle (engine on, speed=0)
  final Map<int, bool> _prevMovingStatus = {};   // true = moving (speed > 0)
  final Map<int, bool> _prevSpeedStatus = {};    // true = overspeeding
  final Map<int, DateTime> _lastOverspeedTime = {};
  final Map<int, bool> _prevSOSStatus = {};

  // Server event ID tracking (for new-event notifications)
  final List<int> _previousEventIds = [];

  // Notification service
  final NotificationService _notificationService = NotificationService();

  @override
  Future<void> onInit() async {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    await loadOverrides();
    await _loadLocalEvents();
    // Only fetch immediately if already authenticated (returning user via splash auto-login)
    // New logins should call startPolling() after successful authentication
    if (UserRepository.getHash() != null) {
      updateDevices();
    }
  }

  void updateDevices() {
    if (UserRepository.getHash() != null) {
      getDevices();
      getEvents();
    }
  }

  /// Call this after successful login — or on home screen mount — to begin data polling.
  /// Safe to call multiple times: _startPollingTimer() always cancels the old timer first.
  void startPolling() {
    if (UserRepository.getHash() == null) return;
    updateDevices();  // Immediate fetch
    _startPollingTimer(); // Restarts the periodic timer (cancels old one first)
  }

  @override
  Future<void> onReady() async {
    super.onReady();
    // NOTE: Polling is started explicitly by home_screen.dart via startPolling().
    // We do NOT auto-start the timer here to avoid double-polling.
  }

  void _startPollingTimer() {
    _pollingTimer?.cancel();
    if (UserRepository.getHash() == null) return; // Guard: never poll without auth
    _pollingTimer = Timer.periodic(Duration(seconds: _currentPollingIntervalSeconds), (timer) {
      if (UserRepository.getHash() != null) {
        getDevices();
        getEvents();
      } else {
        // Hash was cleared (logout), stop polling immediately
        _stopPollingTimer();
      }
    });
  }

  void _stopPollingTimer() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      debugPrint('[DataController] App backgrounded -> Stopping polling timer to protect server.');
      _stopPollingTimer();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('[DataController] App resumed -> Restarting polling timer.');
      updateDevices();
      _startPollingTimer();
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPollingTimer();
    super.onClose();
  }

  void _reapplyCurrentFilter() {
    switch (selectedFilterIndex.value) {
      case 0:
        filterDevicesByStatus("all");
        break;
      case 1:
        filterDevicesByStatus("green");
        break;
      case 2:
        filterDevicesByStatus("yellow");
        break;
      case 3:
        filterDevicesByStatus("red");
        break;
    }
  }

  Future<void> getDevices({bool forceBillingRefresh = false}) async {
    try {
      // Fetch devices from GPSWOX API, and update billing expiration in parallel (throttled by TTL in PaymentService)
      final results = await Future.wait([
        PaymentService.updateBillingExpirationStatus(force: forceBillingRefresh).catchError((_) {}),
        APIService.getDevices(),
      ]);
      final devicesResponse = results[1] as List<Device>?;
      if (devicesResponse != null) {
        // Reset error backoff interval on successful fetch
        if (_currentPollingIntervalSeconds != 8) {
          _currentPollingIntervalSeconds = 8;
          _startPollingTimer();
        }

        devices.value = devicesResponse;
        await _processDeviceItems(devicesResponse);
        isLoading.value = false;
        _updateStatusCounters();
        _reapplyCurrentFilter();
        // ← device data update হলে local alerts check করো
        await _checkLocalAlerts(onlyDevices);

        // ── Billing API: per-vehicle is_expired status update (throttled & gated) ──
        final vehicleIds = onlyDevices
            .map((d) => d.id)
            .whereType<int>()
            .toList();
        PaymentService.updateAllVehicleExpirations(vehicleIds, force: forceBillingRefresh).then((_) async {
          // Fetch invoices and build vehicle due map (only if logged in)
          try {
            if (PaymentService.hasToken) {
              final rawInvoices = await PaymentService.getInvoicesRaw();
              if (rawInvoices != null && rawInvoices['bills'] != null) {
                final List bills = rawInvoices['bills'];
                final Map<String, double> tempDueMap = {};
                for (var b in bills) {
                  if (b['status'] == 'unpaid') {
                    final double amt = ((b['amount'] ?? b['total_bill'] ?? 0.0) as num).toDouble();
                    final bVehicleId = b['vehicle_id']?.toString() ?? b['device_id']?.toString();
                    final bVehicleName = b['vehicle']?['name']?.toString().toLowerCase().trim();
                    final bVehicleImei = b['vehicle']?['imei']?.toString().trim();
                    
                    if (bVehicleId != null) tempDueMap[bVehicleId] = (tempDueMap[bVehicleId] ?? 0.0) + amt;
                    if (bVehicleName != null) tempDueMap[bVehicleName] = (tempDueMap[bVehicleName] ?? 0.0) + amt;
                    if (bVehicleImei != null) tempDueMap[bVehicleImei] = (tempDueMap[bVehicleImei] ?? 0.0) + amt;
                  }
                }
                vehicleDueMap.assignAll(tempDueMap);
              }
            }
          } catch (_) {}

          _processDeviceItems(devicesResponse);
          _updateStatusCounters();
          _reapplyCurrentFilter();
        }).catchError((_) {});
      } else {
        // API response null/failed -> increase polling interval to 30s backoff to protect server
        if (_currentPollingIntervalSeconds != 30) {
          _currentPollingIntervalSeconds = 30;
          _startPollingTimer();
        }
      }
    } catch (e) {
      isLoading.value = false;
      if (_currentPollingIntervalSeconds != 30) {
        _currentPollingIntervalSeconds = 30;
        _startPollingTimer();
      }
    }
  }

  bool _isDeviceExpired(DeviceItem device) {
    try {
      if (device.online == 'expired' || device.time == 'Disabled') return true;
      final expiry = device.deviceData?.expirationDate?.toString();
      if (expiry == null || expiry.isEmpty) return false;
      final date = DateTime.tryParse(expiry);
      if (date == null) return false;
      return date.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  bool _isVehicleExpiredInBilling(DeviceItem device) {
    final isGpswoxExpired = _isDeviceExpired(device);
    if (isGpswoxExpired) return true; // GPSWOX expired is ALWAYS blocked

    final id = device.id;
    if (id == null) return false;
    final isBillingExpired = PaymentService.isVehicleExpired(id);
    final days = PaymentService.vehicleDaysRemaining(id);
    return isBillingExpired || days <= 0;
  }

  Future<void> _processDeviceItems(List<Device> deviceGroups) async {
    onlyDevices.clear();
    for (var group in deviceGroups) {
      if (group.items != null) {
        for (var rawElement in group.items!) {
          var element = rawElement;
          final devId = element.id;
          if (devId != null && _isVehicleExpiredInBilling(element)) {
            // Expired vehicle: strip live data so no live updates occur on cards/map
            element.lat = null;
            element.lng = null;
            element.speed = 0;
            element.sensors = [];
            element.tail = [];
          }
          if (devId != null) {
            final hasEngineOverride =
                _localEngineStatusOverrides.containsKey(devId);
            final hasLockOverride =
                _localLockStatusOverrides.containsKey(devId);

            if (hasEngineOverride || hasLockOverride) {
              final rawEngineStatus = element.engineStatus;
              final rawLockStatus = element.deviceData?.lockStatus;

              final bool? isRawEngineOn =
                  _parseRawEngineStatus(rawEngineStatus);
              final String? targetEngineOverride =
                  _localEngineStatusOverrides[devId];
              final bool? isTargetEngineOn = targetEngineOverride != null
                  ? _parseRawEngineStatus(targetEngineOverride)
                  : null;

              final String? targetLockOverride =
                  _localLockStatusOverrides[devId];
              final bool isLockMatch = (rawLockStatus?.toLowerCase().trim() ==
                  targetLockOverride?.toLowerCase().trim());
              final bool isEngineMatch = (isRawEngineOn == isTargetEngineOn);

              bool shouldClear = true;
              if (hasEngineOverride && !isEngineMatch) shouldClear = false;
              if (hasLockOverride && !isLockMatch) shouldClear = false;

              if (shouldClear) {
                _localEngineStatusOverrides.remove(devId);
                _localLockStatusOverrides.remove(devId);
                saveOverrides();
              } else {
                if (hasEngineOverride) {
                  element.engineStatus = _localEngineStatusOverrides[devId];
                }
                if (hasLockOverride && element.deviceData != null) {
                  element.deviceData!.lockStatus =
                      _localLockStatusOverrides[devId];
                }
              }
            }
          }
          onlyDevices.add(element);
        }
      }
    }
    filteredDevices.assignAll(onlyDevices);
  }

  void _updateStatusCounters() {
    movingCount.value = onlyDevices.where((d) => d.iconColor == "green").length;
    idleCount.value = onlyDevices.where((d) => d.iconColor == "yellow").length;
    offlineCount.value = onlyDevices.where((d) => d.iconColor == "red").length;
    allCount.value = onlyDevices.length;
  }

  void filterDevicesByStatus(String status) {
    selectedFilterIndex.value = _getFilterIndex(status);

    if (status == "all") {
      filteredDevices.assignAll(onlyDevices);
    } else {
      filteredDevices.assignAll(
          onlyDevices.where((device) => device.iconColor == status).toList());
    }

    if (searchText.isNotEmpty) {
      searchDevices(searchText.value);
    }
  }

  int _getFilterIndex(String status) {
    switch (status) {
      case "all":
        return 0;
      case "green":
        return 1;
      case "yellow":
        return 2;
      case "red":
        return 3;
      default:
        return 0;
    }
  }

  void searchDevices(String text) {
    searchText.value = text;

    if (text.isEmpty) {
      searchedDevices.clear();
      _applyFilters();
      return;
    }

    final searchLower = text.toLowerCase();
    searchedDevices.assignAll(filteredDevices
        .where((device) =>
            device.name?.toLowerCase().contains(searchLower) ?? false)
        .toList());
  }

  void _applyFilters() {
    if (searchText.isEmpty) {
      if (selectedFilterIndex.value == 0) {
        filteredDevices.assignAll(onlyDevices);
      }
    } else {
      searchDevices(searchText.value);
    }
  }

  void toggleSearchVisibility() {
    isSearchVisible.toggle();
    if (!isSearchVisible.value) {
      searchText.value = '';
      searchedDevices.clear();
    }
  }

  // ── Local Events Persistence ──────────────────────────────────────────────

  Future<void> _loadLocalEvents() async {
    try {
      final prefs = UserRepository.prefs ?? await SharedPreferences.getInstance();
      final String? stored = prefs.getString('smart_lock_local_events');
      if (stored != null && stored.isNotEmpty) {
        final List<dynamic> decoded = json.decode(stored);
        final List<Event> loaded = decoded
            .map((e) => Event.fromJson(e as Map<String, dynamic>))
            .toList();
        localEvents.value = loaded;
        debugPrint('[LocalEvents] Loaded ${loaded.length} local events from storage');
      }
    } catch (e) {
      debugPrint('[LocalEvents] Error loading: $e');
    }
  }

  void _saveAllLocalEvents() {
    try {
      final prefs = UserRepository.prefs;
      if (prefs == null) return;
      final List<Map<String, dynamic>> jsonList = localEvents.map((e) => {
        'id': e.id,
        'message': e.message,
        'latitude': e.latitude,
        'longitude': e.longitude,
        'device_name': e.device_name,
        'time': e.time,
        'speed': e.speed,
      }).toList();
      prefs.setString('smart_lock_local_events', json.encode(jsonList));
    } catch (e) {
      debugPrint('[LocalEvents] Error saving: $e');
    }
  }

  void _createAndSaveLocalEvent({required String message, required DeviceItem device}) {
    final event = Event(
      id: DateTime.now().millisecondsSinceEpoch, // large timestamp → never collides with server IDs
      message: message,
      device_name: device.name,
      latitude: device.lat,
      longitude: device.lng,
    )
      ..speed = device.speed
      ..time = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    localEvents.insert(0, event);
    if (localEvents.length > 200) localEvents.removeLast(); // max 200 local events
    _saveAllLocalEvents();
    _mergeAndUpdateEvents(null); // events list refresh
  }

  void deleteLocalEvent(dynamic id) {
    localEvents.removeWhere((e) => e.id == id);
    _saveAllLocalEvents();
    _mergeAndUpdateEvents(null);
  }

  void clearLocalEvents() {
    localEvents.clear();
    _saveAllLocalEvents();
    _mergeAndUpdateEvents(null);
  }

  // ── Local Alert Detection: always-on auto-tracking ──────────────────────────
  Future<void> _checkLocalAlerts(List<DeviceItem> deviceItems) async {
    try {
      final prefs = UserRepository.prefs ?? await SharedPreferences.getInstance();
      final bool engineEnabled = prefs.getBool('auto_alert_engine') ?? true;
      final bool idleEnabled = prefs.getBool('auto_alert_idle') ?? true;
      final bool offlineEnabled = prefs.getBool('auto_alert_offline') ?? true;

      for (var device in deviceItems) {
        if (device.id == null) continue;
        final devId = device.id!;
        final double speed = double.tryParse(device.speed?.toString() ?? '0') ?? 0.0;
        final String currentColor = device.iconColor ?? 'green';

        // ─ 1. Engine On/Off ──────────────────────────────────────────────────
        final bool currentEngine =
            device.engineStatus == true ||
            device.engineStatus == 1 ||
            device.engineStatus.toString().toLowerCase() == 'true' ||
            device.engineStatus.toString() == '1';

        if (!_prevEngineStatus.containsKey(devId)) {
          // First-load: just initialize the state to prevent startup lag and event flooding
          _prevEngineStatus[devId] = currentEngine;
        } else if (currentEngine != _prevEngineStatus[devId]!) {
          if (engineEnabled) {
            final String msg =
                currentEngine ? 'Engine turned ON' : 'Engine turned OFF';
            _notificationService.showLocalNotification(
              id: devId * 10 + 1,
              title: '🔑 Engine: ${device.name}',
              body: msg,
              channelId: 'alert_channel_v1',
            );
            _createAndSaveLocalEvent(message: msg, device: device);
          }
          _prevEngineStatus[devId] = currentEngine;
        }

        // ─ 3. Over Speed detection ───────────────────────────────────────────
        final bool speedEnabled = prefs.getBool('auto_alert_speed') ?? false;
        final int userSpeedLimit = prefs.getInt('auto_alert_speed_limit') ?? 80;
        final bool isCurrentlyOverSpeed = speed > userSpeedLimit;

        if (_prevSpeedStatus.containsKey(devId)) {
          final wasOverSpeed = _prevSpeedStatus[devId]!;
          if (isCurrentlyOverSpeed && !wasOverSpeed) {
            if (speedEnabled) {
              const String msg = 'Over Speed';
              _notificationService.showLocalNotification(
                id: devId * 10 + 7,
                title: '⚡ Over Speed: ${device.name}',
                body: 'Vehicle speed exceeded $userSpeedLimit km/h (Current: ${speed.toInt()} km/h)',
                channelId: 'alert_channel_v1',
              );
              _createAndSaveLocalEvent(message: msg, device: device);
            }
          }
        }
        _prevSpeedStatus[devId] = isCurrentlyOverSpeed;

        // ─ 4. Offline / Back Online ───────────────────────────────────────────
        final bool isOnline = Util.isDeviceOnline(device);
        if (_prevOnlineStatus.containsKey(devId)) {
          final bool prevOnline = _prevOnlineStatus[devId]!;
          if (!isOnline && prevOnline) {
            if (offlineEnabled) {
              const String msg = 'Vehicle went offline';
              _notificationService.showLocalNotification(
                id: devId * 10 + 4,
                title: '❌ Offline: ${device.name}',
                body: msg,
                channelId: 'alert_channel_v1',
              );
              _createAndSaveLocalEvent(message: msg, device: device);
            }
          } else if (isOnline && !prevOnline) {
            if (offlineEnabled) {
              const String msg = 'Vehicle is back online';
              _notificationService.showLocalNotification(
                id: devId * 10 + 5,
                title: '✅ Online: ${device.name}',
                body: msg,
                channelId: 'alert_channel_v1',
              );
              _createAndSaveLocalEvent(message: msg, device: device);
            }
          }
        }
        _prevOnlineStatus[devId] = isOnline;
      }
    } catch (e) {
      debugPrint('[LocalAlerts] Error: $e');
    }
  }


  // ── getEvents: server events fetch + merge with local ─────────────────────

  Future<void> getEvents() async {
    try {
      isEventLoading.value = true;
      final eventsResponse = await APIService.getEventList();
      debugPrint('[Events] Server returned: ${eventsResponse?.length ?? 0} events');

      if (eventsResponse != null) {
        _checkForNewEvents(eventsResponse); // push notification for new ones
      }
      // merge করো — null হলেও local events দেখাবে
      _mergeAndUpdateEvents(eventsResponse);
    } catch (e, stack) {
      debugPrint('[Events] Error fetching: $e\n$stack');
      // ❌ events.clear() করা যাবে না — existing list রাখো
      _mergeAndUpdateEvents(null); // শুধু local events দেখাও
    } finally {
      isEventLoading.value = false;
    }
  }

  // ── Merge: local + server, deduplicate by ID, sort newest first ───────────

  void _mergeAndUpdateEvents(List<Event>? serverEvents) {
    final merged = <Event>[];

    // ─ local events (app-generated alerts) — সবচেয়ে high priority ─────────
    merged.addAll(localEvents);

    // ─ server events — duplicate বাদ দাও ────────────────────────────────────
    if (serverEvents != null) {
      // local event এর IDs collect করো (timestamp-based, > 1.7 trillion)
      final localIds = Set<dynamic>.from(
          localEvents.where((e) => e.id != null).map((e) => e.id));

      for (final serverEvent in serverEvents) {
        // ID দিয়ে duplicate check
        if (serverEvent.id != null && localIds.contains(serverEvent.id)) {
          continue; // same ID → skip
        }
        // Message + DeviceName + same minute → duplicate check
        final isDuplicate = localEvents.any((local) =>
            local.message == serverEvent.message &&
            local.device_name == serverEvent.device_name &&
            _isSameMinute(local.time, serverEvent.time));
        if (!isDuplicate) {
          merged.add(serverEvent);
        }
      }
    }

    // ─ newest first sort ─────────────────────────────────────────────────────
    merged.sort(
        (a, b) => _parseEventTime(b.time).compareTo(_parseEventTime(a.time)));

    events.value = merged;
  }

  bool _isSameMinute(String? t1, String? t2) {
    if (t1 == null || t2 == null) return false;
    try {
      final d1 = _parseEventTime(t1);
      final d2 = _parseEventTime(t2);
      return d1.year == d2.year &&
          d1.month == d2.month &&
          d1.day == d2.day &&
          d1.hour == d2.hour &&
          d1.minute == d2.minute;
    } catch (_) {
      return false;
    }
  }

  DateTime _parseEventTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    try {
      return DateTime.parse(timeStr);
    } catch (_) {
      try {
        return DateFormat('yyyy-MM-dd HH:mm:ss').parse(timeStr);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
  }

// Helper method to show errors
//   void _showError(String message) {
//     Get.snackbar(
//       'Error',
//       message,
//       snackPosition: SnackPosition.BOTTOM,
//       backgroundColor: Colors.red,
//       colorText: Colors.white,
//       duration: const Duration(seconds: 3),
//     );
//   }

  // Check for new events and trigger notifications
  void _checkForNewEvents(List<Event> newEvents) {
    if (_previousEventIds.isEmpty) {
      // First time loading events - just populate the list
      _previousEventIds
          .addAll(newEvents.where((e) => e.id != null).map((e) => e.id as int));
      return;
    }

    // Find new events
    for (var event in newEvents) {
      if (event.id != null && !_previousEventIds.contains(event.id)) {
        // New event detected - show notification
        _notificationService.showEventNotification(event);
      }
    }

    // Update previous event IDs
    _previousEventIds.clear();
    _previousEventIds
        .addAll(newEvents.where((e) => e.id != null).map((e) => e.id as int));
  }

  void setExpandedIndex(int index) {
    expandedIndex.value = expandedIndex.value == index ? -1 : index;
  }

  // Manual notification trigger (for testing)
  void sendTestNotification() {
    _notificationService.showLocalNotification(
      title: "🧪 Test Notification",
      body: "This is a test notification from GPS Pro",
      payload: "test",
    );
  }
}
