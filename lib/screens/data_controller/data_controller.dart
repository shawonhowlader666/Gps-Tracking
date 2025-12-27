import 'dart:async';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gpspro/services/model/device.dart';
import 'package:gpspro/services/model/device_item.dart';
import 'package:gpspro/services/model/event.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/services/notification_service.dart';

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
      }
    } catch (e) {
      print("Error getting devices: $e");
      isLoading.value = false;
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

  void getEvents() async {
    try {
      final eventsResponse = await APIService.getEventList();
      if (eventsResponse != null) {
        // Check for new events and show notifications
        _checkForNewEvents(eventsResponse);

        events.value = eventsResponse;
      }
    } catch (e) {
      print("Error getting events: $e");
    } finally {
      isEventLoading.value = false;
    }
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
        print("🔔 New event notification: ${event.message}");
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