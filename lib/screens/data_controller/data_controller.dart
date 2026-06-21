import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gpspro/services/model/device.dart';
import 'package:gpspro/services/model/device_item.dart';
import 'package:gpspro/services/model/event.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/services/tracksolid_repository.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

class DataController extends GetxController {
  // Device Lists
  RxList<Device> devices = <Device>[].obs;
  RxList<DeviceItem> onlyDevices = <DeviceItem>[].obs;
  RxList<DeviceItem> filteredDevices = <DeviceItem>[].obs;
  RxList<DeviceItem> searchedDevices = <DeviceItem>[].obs;

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

  // Other data
  RxList<Event> events = <Event>[].obs;
  RxList<Event> localEvents = <Event>[].obs;
  var counter = 0.obs;
  var markers = <Marker>{}.obs;

  // For tracking previous events
  final List<int> _previousEventIds = [];

  // Notification service
  final NotificationService _notificationService = NotificationService();

  // Maps to keep track of previous values for change detection
  final Map<int, bool> _prevEngineStatus = {};
  final Map<int, String> _prevOnlineStatus = {};
  final Map<int, DateTime> _lastOverspeedTime = {};
  final Map<int, bool> _prevSOSStatus = {};

  @override
  Future<void> onInit() async {
    super.onInit();
    _loadLocalEvents();
    updateDevices();
  }

  void updateDevices() {
    // Update based on whichever API mode is active (Traccar hash or Tracksolid token)
    if (UserRepository.getHash() != null || UserRepository.isTracksolidMode()) {
      getDevices();
      getEvents();
    }
  }

  @override
  Future<void> onReady() async {
    Timer.periodic(const Duration(seconds: 8), (timer) {
      // Periodic polling works for both API modes
      if (UserRepository.getHash() != null || UserRepository.isTracksolidMode()) {
        getDevices();
        getEvents();
      }
    });
    super.onReady();
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

  Future<void> getDevices() async {
    debugPrint("DATA_CONTROLLER getDevices START: this=${hashCode} onlyDevices=${onlyDevices.length}");
    try {
      // Choose API based on user preference
      if (UserRepository.isTracksolidMode()) {
        // Tracksolid path – repository handles token & mapping
        final tracksolidRepo = TracksolidRepository();
        final devicesResponse = await tracksolidRepo.getDevices();
        debugPrint("Tracksolid devicesResponse: ${devicesResponse?.length}");
        devices.value = devicesResponse ?? [];
        await _processDeviceItems(devicesResponse ?? []);
        debugPrint("Tracksolid onlyDevices: ${onlyDevices.length}");
      } else {
        // Existing Traccar / WOX server flow
        final devicesResponse = await APIService.getDevices();
        if (devicesResponse != null) {
          debugPrint("Traccar devicesResponse: ${devicesResponse.length}");
          devices.value = devicesResponse;
          await _processDeviceItems(devicesResponse);
          debugPrint("Traccar onlyDevices: ${onlyDevices.length}");
        } else {
          debugPrint("Traccar devicesResponse is NULL");
        }
      }
      isLoading.value = false;
      _updateStatusCounters();
      _reapplyCurrentFilter();
      _checkLocalAlerts(onlyDevices);
      debugPrint("DATA_CONTROLLER getDevices SUCCESS: this=${hashCode} onlyDevices=${onlyDevices.length}");
    } catch (e) {
      debugPrint("Error fetching devices: $e");
      isLoading.value = false;
    }
    update();
  }

  Future<void> _checkLocalAlerts(List<DeviceItem> deviceItems) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      for (var device in deviceItems) {
        if (device.id == null) continue;
        final devId = device.id!;

        // 1. Engine Status Alert (Ignition On/Off)
        final bool isEngineAlertEnabled = prefs.getBool('quick_alert_${devId}_ignition_duration') ?? 
                                           prefs.getBool('quick_alert_all_ignition_duration') ?? false;
        if (isEngineAlertEnabled) {
          bool currentEngine = device.engineStatus == true || 
                               device.engineStatus == 1 || 
                               device.engineStatus.toString().toLowerCase() == 'true' ||
                               device.engineStatus.toString() == '1';

          if (_prevEngineStatus.containsKey(devId)) {
            bool prevEngine = _prevEngineStatus[devId]!;
            if (currentEngine != prevEngine) {
              String statusStr = currentEngine ? "ON" : "OFF";
              final String body = "Engine has been turned $statusStr";
              _notificationService.showLocalNotification(
                id: devId * 10 + 1,
                title: "🔑 Engine status: ${device.name}",
                body: body,
                channelId: 'alert_channel_v1',
              );
              _createAndSaveLocalEvent(
                message: body,
                device: device,
              );
            }
          }
          _prevEngineStatus[devId] = currentEngine;
        }

        // 2. Over Speed Alert
        final bool isOverspeedEnabled = prefs.getBool('quick_alert_${devId}_overspeed') ?? 
                                        prefs.getBool('quick_alert_all_overspeed') ?? false;
        if (isOverspeedEnabled) {
          double currentSpeed = double.tryParse(device.speed.toString()) ?? 0.0;
          double speedLimit = prefs.getDouble('quick_alert_${devId}_overspeed_limit') ?? 
                              prefs.getDouble('quick_alert_all_overspeed_limit') ?? 80.0;
          if (currentSpeed > speedLimit) {
            final now = DateTime.now();
            final lastNotification = _lastOverspeedTime[devId];
            if (lastNotification == null || now.difference(lastNotification).inMinutes >= 10) {
              final String body = "Vehicle is moving at ${currentSpeed.toStringAsFixed(1)} km/h (Limit: ${speedLimit.toInt()} km/h)";
              _notificationService.showLocalNotification(
                id: devId * 10 + 2,
                title: "⚡ Over Speed: ${device.name}",
                body: body,
                channelId: 'alert_channel_v1',
              );
              _lastOverspeedTime[devId] = now;
              _createAndSaveLocalEvent(
                message: body,
                device: device,
              );
            }
          }
        }

        // 3. SOS Alarm Alert
        final bool isSosEnabled = prefs.getBool('quick_alert_${devId}_sos') ?? 
                                  prefs.getBool('quick_alert_all_sos') ?? false;
        if (isSosEnabled) {
          bool currentSOS = device.alarm == 1 || device.alarm.toString() == "sos";
          if (_prevSOSStatus.containsKey(devId)) {
            bool prevSOS = _prevSOSStatus[devId]!;
            if (currentSOS && !prevSOS) {
              final String body = "Emergency SOS button triggered!";
              _notificationService.showLocalNotification(
                id: devId * 10 + 3,
                title: "🆘 SOS Alarm: ${device.name}",
                body: body,
                channelId: 'sos_channel_v1',
                priority: Priority.max,
                importance: Importance.max,
              );
              _createAndSaveLocalEvent(
                message: body,
                device: device,
              );
            }
          }
          _prevSOSStatus[devId] = currentSOS;
        }

        // 4. Offline Alert
        final bool isOfflineEnabled = prefs.getBool('quick_alert_${devId}_offline_duration') ?? 
                                      prefs.getBool('quick_alert_all_offline_duration') ?? false;
        if (isOfflineEnabled) {
          String currentOnline = device.iconColor ?? 'green';
          if (_prevOnlineStatus.containsKey(devId)) {
            String prevOnline = _prevOnlineStatus[devId]!;
            if (currentOnline == 'red' && prevOnline != 'red') {
              final String body = "Vehicle went offline";
              _notificationService.showLocalNotification(
                id: devId * 10 + 4,
                title: "❌ Offline Alert: ${device.name}",
                body: body,
                channelId: 'alert_channel_v1',
              );
              _createAndSaveLocalEvent(
                message: body,
                device: device,
              );
            }
          }
          _prevOnlineStatus[devId] = currentOnline;
        }

        // 5. Movement Alert
        final bool isMovementEnabled = prefs.getBool('quick_alert_${devId}_start_of_movement') ?? 
                                       prefs.getBool('quick_alert_all_start_of_movement') ?? false;
        if (isMovementEnabled) {
          String currentOnline = device.iconColor ?? 'green';
          if (_prevOnlineStatus.containsKey(devId)) {
            String prevOnline = _prevOnlineStatus[devId]!;
            if (currentOnline == 'green' && prevOnline != 'green') {
              final String body = "Vehicle has started moving";
              _notificationService.showLocalNotification(
                id: devId * 10 + 5,
                title: "Directions Movement: ${device.name}",
                body: body,
                channelId: 'event_channel_v1',
              );
              _createAndSaveLocalEvent(
                message: body,
                device: device,
              );
            }
          }
          _prevOnlineStatus[devId] = currentOnline;
        }
      }
    } catch (e) {
      debugPrint("Error checking local alerts: $e");
    }
  }

  Future<void> _processDeviceItems(List<Device> deviceGroups) async {
    debugPrint("DATA_CONTROLLER _processDeviceItems: clearing onlyDevices (size was ${onlyDevices.length})");
    onlyDevices.clear();
    for (var group in deviceGroups) {
      if (group.items != null) {
        onlyDevices.addAll(group.items!);
      }
    }
    filteredDevices.assignAll(onlyDevices);
    debugPrint("DATA_CONTROLLER _processDeviceItems: cleared and added. New size is ${onlyDevices.length}");
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
    update();
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
      update();
      return;
    }

    final searchLower = text.toLowerCase();
    searchedDevices.assignAll(filteredDevices
        .where((device) =>
    device.name?.toLowerCase().contains(searchLower) ?? false)
        .toList());
    update();
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
    update();
  }

  void _loadLocalEvents() {
    try {
      final prefs = UserRepository.prefs;
      if (prefs != null) {
        final String? localEventsStr = prefs.getString('local_notifications_history');
        if (localEventsStr != null && localEventsStr.isNotEmpty) {
          final List<dynamic> decoded = json.decode(localEventsStr);
          final List<Event> loaded = decoded.map((e) => Event.fromJson(e)).toList();
          localEvents.value = loaded;
        }
      }
    } catch (e) {
      debugPrint("Error loading local events: $e");
    }
  }

  void _saveLocalEvent(Event event) {
    try {
      final prefs = UserRepository.prefs;
      if (prefs != null) {
        localEvents.insert(0, event);
        if (localEvents.length > 100) {
          localEvents.removeLast();
        }
        _saveAllLocalEvents();
      }
    } catch (e) {
      debugPrint("Error saving local event: $e");
    }
  }

  void _saveAllLocalEvents() {
    try {
      final prefs = UserRepository.prefs;
      if (prefs != null) {
        final List<Map<String, dynamic>> jsonList = localEvents.map((e) => {
          'id': e.id,
          'message': e.message,
          'latitude': e.latitude,
          'longitude': e.longitude,
          'device_name': e.device_name,
          'time': e.time,
          'speed': e.speed,
        }).toList();
        prefs.setString('local_notifications_history', json.encode(jsonList));
      }
    } catch (e) {
      debugPrint("Error saving all local events: $e");
    }
  }

  void deleteLocalEvent(dynamic id) {
    localEvents.removeWhere((e) => e.id == id);
    _saveAllLocalEvents();
    update();
  }

  void clearLocalEvents() {
    localEvents.clear();
    final prefs = UserRepository.prefs;
    prefs?.remove('local_notifications_history');
    update();
  }

  void _createAndSaveLocalEvent({required String message, required DeviceItem device}) {
    final event = Event(
      id: DateTime.now().millisecondsSinceEpoch,
      message: message,
      device_name: device.name,
      latitude: device.lat,
      longitude: device.lng,
      speed: device.speed,
    )..time = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    _saveLocalEvent(event);

    final merged = <Event>[];
    merged.addAll(localEvents);
    merged.addAll(events.where((e) {
      final idVal = e.id;
      if (idVal is int && idVal >= 1700000000000) return false;
      return true;
    }));

    merged.sort((a, b) => _parseEventTime(b.time).compareTo(_parseEventTime(a.time)));
    events.value = merged;
  }

  DateTime _parseEventTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
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

  void getEvents({bool showError = false}) async {
    try {
      isEventLoading.value = true;

      List<Event>? eventsResponse;

      if (UserRepository.isTracksolidMode()) {
        // Tracksolid mode – fetch alarms/events via repository
        final repo = TracksolidRepository();
        eventsResponse = await repo.getAlarms();
      } else {
        // Existing Traccar / WOX flow
        eventsResponse = await APIService.getEventList();
      }

      final List<Event> merged = [];
      merged.addAll(localEvents);

      if (eventsResponse != null && eventsResponse.isNotEmpty) {
        _checkForNewEvents(eventsResponse);
        merged.addAll(eventsResponse);
      }

      merged.sort((a, b) => _parseEventTime(b.time).compareTo(_parseEventTime(a.time)));
      events.value = merged;

    } catch (e) {
      // Periodic background polling should fail silently. We only show error popups if explicitly requested.
      if (showError) {
        String message = 'An unexpected error occurred';
        if (e is SocketException) {
          message = 'No internet connection. Please check your network.';
        } else if (e is TimeoutException) {
          message = 'Connection timeout. Please try again.';
        } else {
          message = e.toString().replaceAll('Exception: ', '');
        }
        _showError(message);
      }
    } finally {
      isEventLoading.value = false;
      update();
    }
  }

// Helper method to show errors
  void _showError(String message) {
    Get.snackbar(
      'Error',
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
  }

  // Check for new events and trigger notifications
  void _checkForNewEvents(List<Event> newEvents) {
    if (_previousEventIds.isEmpty) {
      // First time loading events - just populate the list
      _previousEventIds.addAll(
          newEvents.where((e) => e.id != null).map((e) => e.id as int)
      );
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
    _previousEventIds.addAll(
        newEvents.where((e) => e.id != null).map((e) => e.id as int)
    );
  }

  void setExpandedIndex(int index) {
    expandedIndex.value = expandedIndex.value == index ? -1 : index;
    update();
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