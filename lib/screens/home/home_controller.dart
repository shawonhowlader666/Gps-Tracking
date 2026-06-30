
import 'dart:async';
import 'dart:developer';
import 'package:get/get.dart';
import 'package:gpspro/screens/common_method.dart';
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

    // Set loading state
    isLoadingReport.value = true;
    reportError.value = '';

    try {
      final now = DateTime.now();
      DateTime from, to;
      final period = selectedPeriod.value;
      
      if (period == ReportPeriod.today) {
        from = DateTime(now.year, now.month, now.day);
        to = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (period == ReportPeriod.yesterday) {
        final yesterday = now.subtract(const Duration(days: 1));
        from = DateTime(yesterday.year, yesterday.month, yesterday.day);
        to = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
      } else if (period == ReportPeriod.thisWeek) {
        final monday = now.subtract(Duration(days: now.weekday - 1));
        from = DateTime(monday.year, monday.month, monday.day);
        to = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (period == ReportPeriod.thisMonth) {
        from = DateTime(now.year, now.month, 1);
        to = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else {
        from = customStart.value ?? DateTime(now.year, now.month, now.day);
        to = customEnd.value ?? DateTime(now.year, now.month, now.day, 23, 59, 59);
      }

      final fromDateStr = formatDateReport(from.toString());
      final toDateStr = formatDateReport(to.toString());

      // Phase 1: Fast API Fetch (History JSON) - Instant load
      final history = await APIService.getHistory(
        deviceId.toString(),
        fromDateStr,
        "00:00",
        toDateStr,
        "23:59",
      );

      if (history != null) {
        double distanceVal = 0;
        double hoursVal = 0;
        String avgSpeedStr = '--';
        
        if (history.distance_sum != null) {
          try {
            distanceVal = double.parse(history.distance_sum!.replaceAll(RegExp(r'[^0-9.]'), ''));
          } catch (_) {}
        }
        if (history.move_duration != null) {
          hoursVal = _parseDurationToHours(history.move_duration!);
        }
        if (hoursVal > 0) {
          avgSpeedStr = "${(distanceVal / hoursVal).toStringAsFixed(1)} kph";
        }

        final initialData = TodayReportData(
          routeLength: history.distance_sum,
          topSpeed: history.top_speed != null ? "${history.top_speed} kph" : '--',
          moveDuration: history.move_duration,
          stopDuration: history.stop_duration,
          averageSpeed: avgSpeedStr,
          fuelConsumption: history.fuel_consumption,
          engineHours: selectedDevice?.engineHours ?? selectedDevice?.deviceData?.engineHours,
        );

        // Instantly display Phase 1 data and stop the spinner
        todayReport.value = initialData;
        isLoadingReport.value = false;
      }

      // Phase 2: PDF generation & parse in background to get extra details
      ReportService.getReportForPeriod(
        deviceId: deviceId,
        period: period,
        customStart: customStart.value,
        customEnd: customEnd.value,
        forceRefresh: forceRefresh,
      ).then((pdfReport) {
        if (!pdfReport.isEmpty) {
          // Merge PDF report fields with history data
          final mergedData = TodayReportData(
            device: pdfReport.device ?? todayReport.value?.device,
            routeStart: pdfReport.routeStart ?? todayReport.value?.routeStart,
            routeEnd: pdfReport.routeEnd ?? todayReport.value?.routeEnd,
            routeLength: pdfReport.routeLength ?? todayReport.value?.routeLength,
            moveDuration: pdfReport.moveDuration ?? todayReport.value?.moveDuration,
            stopDuration: pdfReport.stopDuration ?? todayReport.value?.stopDuration,
            topSpeed: pdfReport.topSpeed ?? todayReport.value?.topSpeed,
            averageSpeed: pdfReport.averageSpeed ?? todayReport.value?.averageSpeed,
            overspeedCount: pdfReport.overspeedCount ?? todayReport.value?.overspeedCount,
            engineHours: pdfReport.engineHours ?? todayReport.value?.engineHours,
            engineWork: pdfReport.engineWork ?? todayReport.value?.engineWork,
            engineIdle: pdfReport.engineIdle ?? todayReport.value?.engineIdle,
            odometer: pdfReport.odometer ?? todayReport.value?.odometer,
            fuelConsumption: pdfReport.fuelConsumption ?? todayReport.value?.fuelConsumption,
          );
          todayReport.value = mergedData;
        }
      }).catchError((e) {
        log('⚠️ [HomeController] Background PDF load failed: $e');
      });

    } catch (e) {
      log('❌ [HomeController] Error: $e');
      if (todayReport.value == null) {
        todayReport.value = TodayReportData();
        reportError.value = 'Failed to load report';
      }
    } finally {
      isLoadingReport.value = false;
    }
  }

  double _parseDurationToHours(String duration) {
    try {
      double hours = 0;
      final RegExp hourReg = RegExp(r'(\d+)\s*h');
      final RegExp minReg = RegExp(r'(\d+)\s*m');
      final RegExp secReg = RegExp(r'(\d+)\s*s');

      final hMatch = hourReg.firstMatch(duration);
      if (hMatch != null) {
        hours += double.parse(hMatch.group(1)!);
      }
      final mMatch = minReg.firstMatch(duration);
      if (mMatch != null) {
        hours += double.parse(mMatch.group(1)!) / 60.0;
      }
      final sMatch = secReg.firstMatch(duration);
      if (sMatch != null) {
        hours += double.parse(sMatch.group(1)!) / 3600.0;
      }
      return hours;
    } catch (_) {
      return 0;
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