import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_lock/services/model/device.dart';
import 'package:smart_lock/services/model/device_item.dart';
import 'package:smart_lock/services/model/event.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/storage/user_repository.dart';
import 'package:smart_lock/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DataController extends GetxController {
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
      print('Error loading overrides: $e');
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
      print('Error saving overrides: $e');
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
      print('Error refreshing DataController overrides: $e');
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
      print('Error refreshing DataController overrides: $e');
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
      if (['on', '1', 'true', 'ign on', 'engine on', 'acc on'].contains(s))
        return true;
      if (['off', '0', 'false', 'ign off', 'engine off', 'acc off'].contains(s))
        return false;
    }
    return null;
  }

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

  @override
  Future<void> onInit() async {
    super.onInit();
    await loadOverrides();
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
      }
    } catch (e) {
      isLoading.value = false;
    }
  }

  Future<void> _processDeviceItems(List<Device> deviceGroups) async {
    onlyDevices.clear();
    for (var group in deviceGroups) {
      if (group.items != null) {
        for (var element in group.items!) {
          final devId = element.id;
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

  void getEvents() async {
    try {
      isEventLoading.value = true;

      final eventsResponse = await APIService.getEventList();

      debugPrint('[Events] API returned: ${eventsResponse?.length ?? 'null'} events');

      if (eventsResponse != null && eventsResponse.isNotEmpty) {
        _checkForNewEvents(eventsResponse);
        events.assignAll(eventsResponse);
      } else {
        events.clear();
      }
    } catch (e, stack) {
      debugPrint('[Events] Error fetching events: $e');
      debugPrint('[Events] Stack: $stack');
      events.clear();
    } finally {
      isEventLoading.value = false;
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
