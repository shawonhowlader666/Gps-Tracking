import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gpspro/services/model/device.dart';
import 'package:gpspro/services/model/device_item.dart';
import 'package:gpspro/services/model/event.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
    updateDevices();
  }

  void updateDevices() {
    if (UserRepository.getHash() != null) {
      getDevices();
      getEvents();
    }
  }

  @override
  Future<void> onReady() async {
    Timer.periodic(const Duration(seconds: 8), (timer) {
      if (UserRepository.getHash() != null) {
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
    try {
      final devicesResponse = await APIService.getDevices();
      if (devicesResponse != null) {
        devices.value = devicesResponse;
        await _processDeviceItems(devicesResponse);
        isLoading.value = false;
        _updateStatusCounters();
        _reapplyCurrentFilter();
        _checkLocalAlerts(onlyDevices);
      }
    } catch (e) {
      isLoading.value = false;
    }
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
              _notificationService.showLocalNotification(
                id: devId * 10 + 1,
                title: "🔑 Engine status: ${device.name}",
                body: "Engine has been turned $statusStr",
                channelId: 'alert_channel_v1',
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
              _notificationService.showLocalNotification(
                id: devId * 10 + 2,
                title: "⚡ Over Speed: ${device.name}",
                body: "Vehicle is moving at ${currentSpeed.toStringAsFixed(1)} km/h (Limit: ${speedLimit.toInt()} km/h)",
                channelId: 'alert_channel_v1',
              );
              _lastOverspeedTime[devId] = now;
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
              _notificationService.showLocalNotification(
                id: devId * 10 + 3,
                title: "🆘 SOS Alarm: ${device.name}",
                body: "Emergency SOS button triggered!",
                channelId: 'sos_channel_v1',
                priority: Priority.max,
                importance: Importance.max,
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
              _notificationService.showLocalNotification(
                id: devId * 10 + 4,
                title: "❌ Offline Alert: ${device.name}",
                body: "Vehicle went offline",
                channelId: 'alert_channel_v1',
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
              _notificationService.showLocalNotification(
                id: devId * 10 + 5,
                title: "Directions Movement: ${device.name}",
                body: "Vehicle has started moving",
                channelId: 'event_channel_v1',
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
    onlyDevices.clear();
    for (var group in deviceGroups) {
      if (group.items != null) {
        onlyDevices.addAll(group.items!);
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

  void getEvents({bool showError = false}) async {
    try {
      isEventLoading.value = true;

      final eventsResponse = await APIService.getEventList();

      if (eventsResponse != null && eventsResponse.isNotEmpty) {
        // Check for new events and show notifications
        _checkForNewEvents(eventsResponse);
        events.value = eventsResponse;
      } else {
        // Handle empty events
        events.value = <Event>[].obs;
      }

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