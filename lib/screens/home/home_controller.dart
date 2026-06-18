
import 'dart:async';
import 'dart:developer';
import 'package:get/get.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/screens/report/get_today_report.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/services/model/device_item.dart';

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
  Rx<ReportPeriod> selectedPeriod = ReportPeriod.today.obs;
  Rx<DateTime?> customStart = Rx<DateTime?>(null);
  Rx<DateTime?> customEnd   = Rx<DateTime?>(null);

  void onPeriodChanged(ReportPeriod period) {
    if (period == selectedPeriod.value) return;
    selectedPeriod.value = period;
    if (selectedDeviceId.value != 0) {
      loadTodayReport(selectedDeviceId.value, forceRefresh: true);
    }
  }

  void onCustomRangePicked(DateTime start, DateTime end) {
    customStart.value = start;
    customEnd.value   = end;
    selectedPeriod.value = ReportPeriod.custom;
    if (selectedDeviceId.value != 0) {
      loadTodayReport(selectedDeviceId.value, forceRefresh: true);
    }
  }

  // Mileage Chart Data
  RxList<MileageData> mileageData = <MileageData>[].obs;
  RxBool isLoadingMileage = false.obs;
  Rx<DateTime> selectedStartDate = DateTime.now().subtract(const Duration(days: 6)).obs;
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
    ever(dataController.onlyDevices, (List<DeviceItem> devices) {
      if (devices.isNotEmpty) {
        updateSubscriptionStatus(devices);
        if (selectedDeviceId.value == 0) {
          final first = devices.first;
          if (first.id != null) {
            selectedDeviceId.value = first.id!;
            // Parallel — both load simultaneously on first device selection
            Future.wait([
              loadTodayReport(first.id!),
              loadMileageData(first.id!),
            ]);
          }
        }
      }
    });

    if (dataController.onlyDevices.isNotEmpty) {
      updateSubscriptionStatus(dataController.onlyDevices);
      final first = dataController.onlyDevices.first;
      if (first.id != null) {
        selectedDeviceId.value = first.id!;
        Future.wait([
          loadTodayReport(first.id!),
          loadMileageData(first.id!),
        ]);
      }
    }
  }

  Future<void> refreshData() async {
    ReportService.clearCache();
    await dataController.getDevices();
    if (selectedDeviceId.value != 0) {
      // Parallel — both start at the same time
      await Future.wait([
        loadTodayReport(selectedDeviceId.value, forceRefresh: true),
        loadMileageData(selectedDeviceId.value),
      ]);
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
  Future<void> loadTodayReport(int deviceId, {bool forceRefresh = false}) async {
    if (deviceId == 0) {
      log('⚠️ [HomeController] loadTodayReport: deviceId is 0');
      return;
    }

   // log('📊 [HomeController] loadTodayReport for device: $deviceId');

    // Set loading state
    isLoadingReport.value = true;
    reportError.value = '';

    try {
      // Call ReportService with the selected period
      final report = await ReportService.getReportForPeriod(
        deviceId: deviceId,
        period: selectedPeriod.value,
        customStart: selectedPeriod.value == ReportPeriod.custom ? customStart.value : null,
        customEnd:   selectedPeriod.value == ReportPeriod.custom ? customEnd.value   : null,
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

      if (report.isEmpty) {
        reportError.value = 'No data for ${selectedPeriod.value.name}';
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
    selectedDeviceId.value = deviceId;
    todayReport.value = null;
    reportError.value = '';
    // Parallel — report and mileage load simultaneously
    Future.wait([
      loadTodayReport(deviceId),
      loadMileageData(deviceId),
    ]);
  }

  Future<void> loadMileageData(int deviceId) async {
    if (deviceId == 0) return;
    isLoadingMileage.value = true;
    isDummyMileageData.value = false;

    try {
      // Parallel: fetch all 7 days at the same time instead of sequentially
      final futures = List.generate(7, (i) {
        final date = DateTime.now().subtract(Duration(days: 6 - i));
        return _fetchDayMileage(deviceId, date);
      });
      final results = await Future.wait(futures);
      mileageData.assignAll(results);
      if (results.any((m) => m.isRealData && m.distance > 0)) {
        isDummyMileageData.value = false;
      }
    } catch (e) {
      _addDummyMileageData();
    } finally {
      isLoadingMileage.value = false;
    }
  }

  Future<MileageData> _fetchDayMileage(int deviceId, DateTime date) async {
    try {
      final d = _formatDate(date);
      final d2 = _formatDate(date.add(const Duration(days: 1)));

      final h = await APIService.getHistory(deviceId.toString(), d, "00:00", d2, "00:00");

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

  MileageData({required this.date, required this.distance, this.isRealData = true});

  String get dayLabel {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }
}