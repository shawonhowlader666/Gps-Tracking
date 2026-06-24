import 'dart:async';
import 'dart:developer';
import 'package:get/get.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/screens/report/get_today_report.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/services/model/device_item.dart';

class HomeController extends GetxController {
  final DataController dataController = Get.find<DataController>();

  // Subscription Status
  RxInt totalVehicles = 0.obs;
  RxInt paidVehicles = 0.obs;
  RxInt dueVehicles = 0.obs;
  RxBool isLoadingSubscription = true.obs;
  var isDummyMileageData = false.obs;

  // Vehicle Summary - REACTIVE VARIABLES
  RxInt selectedDeviceId = 0.obs;
  Rx<TodayReportData?> todayReport = Rx<TodayReportData?>(null);
  RxBool isLoadingReport = false.obs;
  RxString reportError = ''.obs;

  // Mileage Chart Data
  RxList<MileageData> mileageData = <MileageData>[].obs;
  RxBool isLoadingMileage = false.obs;
  Rx<DateTime> selectedStartDate =
      DateTime.now().subtract(const Duration(days: 6)).obs;
  Rx<DateTime> selectedEndDate = DateTime.now().obs;

  Timer? _refreshTimer;

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
    //log('🏠 [HomeController] onInit');
    _initializeData();
    _startAutoRefresh();
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    super.onClose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (selectedDeviceId.value != 0) {
        // log('🔄 [HomeController] Auto refresh...');
        loadTodayReport(selectedDeviceId.value, forceRefresh: true);
      }
    });
  }

  void _initializeData() {
    // Listen for device list changes
    ever(dataController.onlyDevices, (List<DeviceItem> devices) {
      // log('🏠 [HomeController] Devices changed: ${devices.length}');

      if (devices.isNotEmpty) {
        updateSubscriptionStatus(devices);

        // Auto-select first device if none selected
        if (selectedDeviceId.value == 0) {
          final first = devices.first;
          if (first.id != null) {
            //  log('🏠 [HomeController] Auto-selecting device: ${first.id}');
            selectedDeviceId.value = first.id!;
            loadTodayReport(first.id!);
            loadMileageData(first.id!);
          }
        }
      }
    });

    // Initial load if devices already exist
    if (dataController.onlyDevices.isNotEmpty) {
      // log('🏠 [HomeController] Initial devices: ${dataController.onlyDevices.length}');
      updateSubscriptionStatus(dataController.onlyDevices);

      final first = dataController.onlyDevices.first;
      if (first.id != null) {
        selectedDeviceId.value = first.id!;
        loadTodayReport(first.id!);
        loadMileageData(first.id!);
      }
    }
  }

  Future<void> refreshData() async {
    //log('🔄 [HomeController] Manual refresh');
    ReportService.clearCache();

    await dataController.getDevices();

    if (selectedDeviceId.value != 0) {
      await loadTodayReport(selectedDeviceId.value, forceRefresh: true);
      await loadMileageData(selectedDeviceId.value);
    }
  }

  void updateSubscriptionStatus(List<DeviceItem> devices) {
    totalVehicles.value = devices.length;
    paidVehicles.value = devices.where((d) {
      final c = d.iconColor?.toLowerCase() ?? '';
      return c == "green" || c == "yellow";
    }).length;
    dueVehicles.value = devices.where((d) {
      final c = d.iconColor?.toLowerCase() ?? '';
      return c == "red";
    }).length;
    isLoadingSubscription.value = false;
  }

  /// MAIN METHOD: Load today's report
  Future<void> loadTodayReport(int deviceId,
      {bool forceRefresh = false}) async {
    if (deviceId == 0) {
      log('⚠️ [HomeController] loadTodayReport: deviceId is 0');
      return;
    }

    // log('📊 [HomeController] loadTodayReport for device: $deviceId');

    // Set loading state
    isLoadingReport.value = true;
    reportError.value = '';

    try {
      // Call ReportService
      final report = await ReportService.getTodayReportData(
        deviceId: deviceId,
        forceRefresh: forceRefresh,
      );
      //
      // log('📊 [HomeController] Report received:');
      // log('   isEmpty: ${report.isEmpty}');
      // log('   routeLength: ${report.routeLength}');
      // log('   moveDuration: ${report.moveDuration}');
      // log('   stopDuration: ${report.stopDuration}');
      // log('   topSpeed: ${report.topSpeed}');
      // log('   engineHours: ${report.engineHours}');

      // UPDATE THE REACTIVE VARIABLE - THIS IS KEY!
      todayReport.value = report;

      // Trigger update notification
      todayReport.refresh();

      if (report.isEmpty) {
        reportError.value = 'No data for today';
        //  log('⚠️ [HomeController] Report is empty');
      } else {
        // log('✅ [HomeController] Report loaded successfully');
      }
    } catch (e) {
      //  log('❌ [HomeController] Error: $e');
      todayReport.value = TodayReportData();
      reportError.value = 'Failed to load report';
    } finally {
      isLoadingReport.value = false;
      log('📊 [HomeController] isLoadingReport = false');
    }
  }

  void onVehicleChanged(int deviceId) {
    if (deviceId == selectedDeviceId.value) return;

    // log('🚗 [HomeController] Vehicle changed: $deviceId');
    selectedDeviceId.value = deviceId;

    // Clear previous data
    todayReport.value = null;
    reportError.value = '';

    // Load new data
    loadTodayReport(deviceId);
    loadMileageData(deviceId);
  }

  Future<void> loadMileageData(int deviceId) async {
    if (deviceId == 0) return;

    isLoadingMileage.value = true;
    mileageData.clear();
    isDummyMileageData.value = false;

    try {
      for (int i = 6; i >= 0; i--) {
        final date = DateTime.now().subtract(Duration(days: i));
        final m = await _fetchDayMileage(deviceId, date);
        mileageData.add(m);
        if (m.isRealData && m.distance > 0) isDummyMileageData.value = false;
      }
    } catch (e) {
      // log('❌ [HomeController] Mileage error: $e');
      _addDummyMileageData();
    } finally {
      isLoadingMileage.value = false;
    }
  }

  Future<MileageData> _fetchDayMileage(int deviceId, DateTime date) async {
    try {
      final d = _formatDate(date);
      final d2 = _formatDate(date.add(const Duration(days: 1)));

      final h = await APIService.getHistory(
          deviceId.toString(), d, "00:00", d2, "00:00");

      double dist = 0.0;
      bool real = false;

      if (h != null && h.distance_sum != null) {
        dist = _parseDistance(h.distance_sum);
        real = true;
      }

      return MileageData(date: date, distance: dist, isRealData: real);
    } catch (e) {
      return MileageData(date: date, distance: 0, isRealData: false);
    }
  }

  double _parseDistance(String? s) {
    if (s == null) return 0;
    final n = s.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(n) ?? 0;
  }

  void _addDummyMileageData() {
    mileageData.clear();
    isDummyMileageData.value = true;
    for (int i = 6; i >= 0; i--) {
      mileageData.add(MileageData(
        date: DateTime.now().subtract(Duration(days: i)),
        distance: 0,
        isRealData: false,
      ));
    }
  }

  String _formatDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return "${d.year}-$m-$day";
  }

  String getFormattedDateRange() {
    final s = selectedStartDate.value;
    final e = selectedEndDate.value;
    return "${s.day}/${s.month} - ${e.day}/${e.month}";
  }
}

class MileageData {
  final DateTime date;
  final double distance;
  final bool isRealData;

  MileageData(
      {required this.date, required this.distance, this.isRealData = true});

  String get dayLabel {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }
}
