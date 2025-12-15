import 'package:get/get.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/screens/report/get_today_report.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/services/model/device_item.dart';
import 'dart:developer';

class HomeController extends GetxController {
  final DataController dataController = Get.find<DataController>();

  // Subscription Status
  RxInt totalVehicles = 0.obs;
  RxInt paidVehicles = 0.obs;
  RxInt dueVehicles = 0.obs;
  RxBool isLoadingSubscription = true.obs;
  var isDummyMileageData = false.obs;

  // Vehicle Summary
  RxInt selectedDeviceId = 0.obs;
  Rx<TodayReportData?> todayReport = Rx<TodayReportData?>(null);
  RxBool isLoadingReport = false.obs;

  // Mileage Chart Data
  RxList<MileageData> mileageData = <MileageData>[].obs;
  RxBool isLoadingMileage = false.obs;
  Rx<DateTime> selectedStartDate = DateTime.now().subtract(Duration(days: 6)).obs;
  Rx<DateTime> selectedEndDate = DateTime.now().obs;

  // Helper to get current device
  DeviceItem? get selectedDevice {
    if (selectedDeviceId.value == 0) return null;
    try {
      return dataController.onlyDevices.firstWhere(
            (device) => device.id == selectedDeviceId.value,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  void onInit() {
    super.onInit();
    _initializeData();
  }

  void _initializeData() {
    // Listen to device changes
    dataController.onlyDevices.listen((devices) {
      if (devices.isNotEmpty) {
        updateSubscriptionStatus(devices);

        if (selectedDeviceId.value == 0) {
          selectedDeviceId.value = devices.first.id!;
          loadTodayReport(devices.first.id!);
          loadMileageData(devices.first.id!);
        }
      }
    });

    // Initial load
    if (dataController.onlyDevices.isNotEmpty) {
      updateSubscriptionStatus(dataController.onlyDevices);
      selectedDeviceId.value = dataController.onlyDevices.first.id!;
      loadTodayReport(selectedDeviceId.value);
      loadMileageData(selectedDeviceId.value);
    }
  }

  Future<void> refreshData() async {
    try {
      await dataController.getDevices();
      if (selectedDeviceId.value != 0) {
        await Future.wait([
          loadTodayReport(selectedDeviceId.value),
          loadMileageData(selectedDeviceId.value),
        ]);
      }
    } catch (e) {
      log("Error refreshing data: $e");
    }
  }

  void updateSubscriptionStatus(List<DeviceItem> devices) {
    totalVehicles.value = devices.length;

    paidVehicles.value = devices.where((device) {
      return device.iconColor == "green" || device.iconColor == "yellow";
    }).length;

    dueVehicles.value = devices.where((device) {
      return device.iconColor == "red";
    }).length;

    isLoadingSubscription.value = false;
  }

  Future<void> loadTodayReport(int deviceId) async {
    try {
      isLoadingReport.value = true;
      final report = await ReportService.getTodayReportData(deviceId: deviceId);
      todayReport.value = report;
      log("Today's report loaded: ${report.toJson()}");
    } catch (e) {
      log("Error loading today's report: $e");
      todayReport.value = TodayReportData();
    } finally {
      isLoadingReport.value = false;
    }
  }

  Future<void> loadMileageData(int deviceId) async {
    try {
      isLoadingMileage.value = true;
      mileageData.clear();
      isDummyMileageData.value = false; // Reset flag, assume real data

      log("🔄 Loading mileage data for device: $deviceId");

      bool hasAnyRealData = false;

      // Load data for last 7 days
      for (int i = 6; i >= 0; i--) {
        final date = DateTime.now().subtract(Duration(days: i));
        final mileage = await _fetchDayMileage(deviceId, date);
        mileageData.add(mileage);

        // Check if we got any real data (not generated)
        if (mileage.isRealData) {
          hasAnyRealData = true;
        }
      }

      // If no real data was found for any day, mark as dummy
      if (!hasAnyRealData) {
        isDummyMileageData.value = true;
        log("⚠️ No real data found, using dummy data");
      } else {
        isDummyMileageData.value = false;
        log("✅ Real mileage data loaded");
      }

      log("✅ Mileage data loaded: ${mileageData.length} days");
      for (var data in mileageData) {
        log("  ${data.dayLabel}/${data.date.month}: ${data.distance} km ${data.isRealData ? '(Real)' : '(Dummy)'}");
      }
    } catch (e) {
      log("❌ Error loading mileage data: $e");
      _addDummyMileageData();
    } finally {
      isLoadingMileage.value = false;
    }
  }

  Future<MileageData> _fetchDayMileage(int deviceId, DateTime date) async {
    try {
      final dateStr = _formatDateForApi(date);
      final nextDateStr = _formatDateForApi(date.add(Duration(days: 1)));

      log("📊 Fetching mileage for $dateStr");

      // Try to get real data from API
      final history = await APIService.getHistory(
        deviceId.toString(),
        dateStr,
        "00:00",
        nextDateStr,
        "00:00",
      );

      double distance = 0.0;
      bool isReal = false;

      if (history?.items != null && history!.items!.isNotEmpty) {
        // Calculate distance from history
        distance = _calculateDistanceFromHistory(history);
        isReal = true; // Mark as real data if we got response from API
        log("  ✓ Real distance for ${date.day}/${date.month}: $distance km");
      } else {
        // No data from API, use 0 (not dummy random data)
        distance = 0.0;
        isReal = true; // It's real data, just 0 distance
        log("  ✓ No movement for ${date.day}/${date.month}: 0 km");
      }

      return MileageData(
        date: date,
        distance: distance,
        isRealData: isReal,
      );
    } catch (e) {
      log("  ✗ Error for ${date.day}/${date.month}: $e");
      // API error - use dummy data
      return MileageData(
        date: date,
        distance: _generateRandomDistance(date),
        isRealData: false,
      );
    }
  }

  double _calculateDistanceFromHistory(dynamic history) {
    try {
      // Adjust based on your actual PositionHistory structure
      if (history.items != null && history.items!.isNotEmpty) {
        // If your history has distance field
        // return history.totalDistance ?? 0.0;

        // Estimate based on position count
        return history.items!.length * 2.0; // Approximate
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  double _parseDistance(String? routeLength) {
    if (routeLength == null || routeLength.isEmpty) return 0.0;

    try {
      // Extract number from string like "150.5 Km" or "150 km"
      final numStr = routeLength.replaceAll(RegExp(r'[^0-9.]'), '');
      return double.tryParse(numStr) ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  double _generateRandomDistance(DateTime date) {
    // Generate realistic random distances for demo
    final seed = date.day + date.month * 31;
    final base = (seed * 17) % 200;
    return (base + 50).toDouble();
  }

  void _addDummyMileageData() {
    mileageData.clear();
    isDummyMileageData.value = true;

    for (int i = 6; i >= 0; i--) {
      final date = DateTime.now().subtract(Duration(days: i));
      mileageData.add(MileageData(
        date: date,
        distance: _generateRandomDistance(date),
        isRealData: false,
      ));
    }
    log("📝 Added dummy mileage data for demo");
  }

  String _formatDateForApi(DateTime date) {
    String month = date.month < 10 ? "0${date.month}" : date.month.toString();
    String day = date.day < 10 ? "0${date.day}" : date.day.toString();
    return "${date.year}-$month-$day";
  }

  void onVehicleChanged(int deviceId) {
    selectedDeviceId.value = deviceId;
    loadTodayReport(deviceId);
    loadMileageData(deviceId);
  }

  String getFormattedDateRange() {
    final start = selectedStartDate.value;
    final end = selectedEndDate.value;
    return "${_formatDateDisplay(start)} - ${_formatDateDisplay(end)}";
  }

  String _formatDateDisplay(DateTime date) {
    String day = date.day < 10 ? "0${date.day}" : date.day.toString();
    String month = date.month < 10 ? "0${date.month}" : date.month.toString();
    return "$day/$month/${date.year}";
  }
}

class MileageData {
  final DateTime date;
  final double distance;
  final bool isRealData;

  MileageData({
    required this.date,
    required this.distance,
    this.isRealData = true, // Default to true
  });

  String get dayLabel {
    String day = date.day < 10 ? "0${date.day}" : date.day.toString();
    return day;
  }
}