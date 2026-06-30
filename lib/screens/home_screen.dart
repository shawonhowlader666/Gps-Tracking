import 'dart:async';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import 'package:gpspro/screens/home/home_controller.dart';
import 'package:gpspro/screens/payment_list.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/util/util.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/payment_service.dart';
import '../services/model/billing_vehicle.dart';
import 'data_controller/data_controller.dart';
import 'quick_links/driving_instructor_screen.dart';
import 'quick_links/traffic_signs_screen.dart';
import 'quick_links/car_knowledge_screen.dart';
import 'report/get_today_report.dart' show ReportPeriod;

// Status enum for consistency
enum VehicleStatus { running, idle, stop, offline, noData, expired }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final HomeController homeController = Get.put(HomeController());
  late final DataController dataController;

  Timer? _countdownTimer;
  Timer? _statusRefreshTimer;
  bool _isVisible = true;

  // â”€â”€ Fully reactive â€” zero setState â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final RxDouble _dueAmount   = RxDouble(0.0);
  final RxBool   _hasDue      = false.obs;
  final RxInt    _runningCount = 0.obs;
  final RxInt    _idleCount    = 0.obs;
  final RxInt    _stopCount    = 0.obs;
  final RxInt    _offlineCount = 0.obs;
  final RxInt    _noDataCount  = 0.obs;
  final RxInt    _expiredCount = 0.obs;
  final RxString _timeLeftStr  = ''.obs;  // replaces _timeLeft Duration
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  // Simple color palette
  static const Color primaryColor  = Color(0xFFFF0000);
  static const Color successColor  = Color(0xFF00C853);
  static const Color warningColor  = Color(0xFFFF9100);
  static const Color dangerColor   = Color(0xFFFF0000);
  static const Color neutralColor  = Color(0xFF475569);

  int _currentBannerIndex = 0;
  final List<String> _localBanners = const [
    'images/banner_dashcam.png',
    'images/banner_discount.png',
    'images/banner_security.png',
  ];

  final RxMap<String, BillingVehicle> _billingMap = <String, BillingVehicle>{}.obs;
  bool _isLoadingBilling = false;

  Future<void> _loadBillingInfo() async {
    if (_isLoadingBilling) return;
    _isLoadingBilling = true;
    try {
      final billingList = await PaymentService.getBillingVehicles();
      if (billingList != null) {
        // RxMap update â€” no setState, only affected Obx rebuild
        _billingMap.assignAll({for (final v in billingList) v.imei: v});
        _calculateStatusCounts();
      }
    } catch (e) {
      debugPrint('Home billing error: $e');
    } finally {
      _isLoadingBilling = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    dataController = Get.put(DataController(), permanent: true);

    // Listen to onlyDevices changes reactively to update counts without triggering build loop
    ever(dataController.onlyDevices, (_) {
      _calculateStatusCounts();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBillingInfo();
      _calculateStatusCounts();
      _startStatusRefresh();
    });
  }

  void _startStatusRefresh() {
    _statusRefreshTimer?.cancel();
    // 60 s is enough â€” avoids janky rebuilds every 10 s
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (_isVisible) {
        _loadBillingInfo();
        _calculateStatusCounts();
      }
    });
  }

  void _calculateStatusCounts() {
    if (!mounted) return;

    final vehicles = dataController.onlyDevices;
    int running = 0;
    int idle = 0;
    int stop = 0;
    int offline = 0;
    int noData = 0;
    int expired = 0;

    for (final device in vehicles) {
      final status = _getVehicleStatus(device);
      switch (status) {
        case VehicleStatus.running:
          running++;
          break;
        case VehicleStatus.idle:
          idle++;
          break;
        case VehicleStatus.stop:
          stop++;
          break;
        case VehicleStatus.offline:
          offline++;
          break;
        case VehicleStatus.noData:
          noData++;
          break;
        case VehicleStatus.expired:
          expired++;
          break;
      }
    }

    _runningCount.value = running;
    _idleCount.value = idle;
    _stopCount.value = stop;
    _offlineCount.value = offline;
    _noDataCount.value = noData;
    _expiredCount.value = expired;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _isVisible = false;
        _countdownTimer?.cancel();
        _statusRefreshTimer?.cancel();
        break;
      case AppLifecycleState.resumed:
        _isVisible = true;
        if (_timeLeftStr.value.isNotEmpty || _dueAmount.value > 0) {
          _resumeCountdownIfNeeded();
        }
        _calculateStatusCounts();
        _startStatusRefresh();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  void _resumeCountdownIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final graceEnd = prefs.getInt('grace_end_time');
    if (graceEnd != null && mounted) {
      final endTime = DateTime.fromMillisecondsSinceEpoch(graceEnd);
      if (DateTime.now().isBefore(endTime)) {
        _startCountdown(endTime);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _statusRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPaymentStatus() async {
    if (!mounted) return;

    try {
      final stats = await PaymentService.getStats();
      if (!mounted) return;

      if (stats == null || stats.due <= 0) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('grace_end_time');
        _dueAmount.value = 0.0;
        _hasDue.value = false;
        return;
      }

      _dueAmount.value = stats.due;
      _hasDue.value = true;

      final prefs = await SharedPreferences.getInstance();
      final graceEnd = prefs.getInt('grace_end_time');

      if (!mounted) return;

      if (graceEnd != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now <= graceEnd) {
          _startCountdown(DateTime.fromMillisecondsSinceEpoch(graceEnd));
        }
      }
    } catch (e) {
      debugPrint('Error checking payment status: $e');
    }
  }

  void _startCountdown(DateTime endTime) {
    _countdownTimer?.cancel();
    _updateTimeLeft(endTime);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isVisible) {
        timer.cancel();
        return;
      }
      final now = DateTime.now();
      if (now.isAfter(endTime)) {
        timer.cancel();
        _timeLeftStr.value = '';
        _checkPaymentStatus();
      } else {
        _updateTimeLeft(endTime);
      }
    });
  }

  void _updateTimeLeft(DateTime endTime) {
    final now = DateTime.now();
    if (now.isBefore(endTime)) {
      final d = endTime.difference(now);
      _timeLeftStr.value = _formatDuration(d);
    }
  }

  // ==================== STATUS DETECTION METHODS ====================
  // SAME LOGIC AS DevicePage for consistency

  bool _isDeviceExpired(DeviceItem device) {
    // 1. Check from Billing Server Map first (same as devices.dart)
    final imei = device.imei ?? device.deviceData?.imei;
    if (imei != null) {
      final billingInfo = _billingMap[imei];
      if (billingInfo != null && billingInfo.expirationDate != null && billingInfo.expirationDate!.isNotEmpty) {
        try {
          final d = DateTime.parse(billingInfo.expirationDate!);
          if (d.isBefore(DateTime.now())) {
            return true;
          }
        } catch (_) {}
      }
    }

    // 2. Check general device expiration date
    final expStr = device.deviceData?.expirationDate;
    if (expStr != null && expStr.toString().isNotEmpty) {
      try {
        final d = DateTime.parse(expStr.toString());
        if (d.isBefore(DateTime.now())) {
          return true;
        }
      } catch (_) {}
    }

    // 3. Check SIM expiration date
    final simExpStr = device.simExpirationDate;
    if (simExpStr != null && simExpStr.toString().isNotEmpty) {
      try {
        final d = DateTime.parse(simExpStr.toString());
        if (d.isBefore(DateTime.now())) {
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  /// MASTER STATUS DETERMINATION - Same as DevicePage
  VehicleStatus _getVehicleStatus(DeviceItem device) {
    // STEP 0: Check if device is expired
    if (_isDeviceExpired(device)) {
      return VehicleStatus.expired;
    }

    // STEP 0.5: Check if device has no data
    final latVal = device.lat is double ? (device.lat as double) : double.tryParse(device.lat.toString());
    final lngVal = device.lng is double ? (device.lng as double) : double.tryParse(device.lng.toString());
    if (latVal == null || lngVal == null || latVal == 0.0 || lngVal == 0.0) {
      return VehicleStatus.noData;
    }

    // STEP 1: Check if device is online first
    final isOnline = _isDeviceOnline(device);

    if (!isOnline) {
      return VehicleStatus.offline;
    }

    // STEP 2: Device is online, check speed
    final speed = double.tryParse(device.speed.toString()) ?? 0;

    // STEP 3: Check engine status
    final isEngineOn = _isEngineOn(device);

    // STEP 4: Determine status based on online + speed + engine
    if (speed > 0) {
      // Moving = Running (engine must be on if moving)
      return VehicleStatus.running;
    } else {
      // Not moving (speed = 0)
      if (isEngineOn) {
        // Engine on but not moving = Idle
        return VehicleStatus.idle;
      } else {
        // Engine off and not moving = Stop/Parking
        return VehicleStatus.stop;
      }
    }
  }

  /// Check if device is online - SAME AS DevicePage (unchanged)
  bool _isDeviceOnline(DeviceItem device) {
    // Check the online field first
    final online = device.online?.toLowerCase().trim() ?? '';

    // Explicitly offline
    if (online.contains('offline')) {
      return false;
    }

    // Explicitly online
    if (online.contains('online')) {
      return true;
    }

    // Check by iconColor - if it's green or yellow, device is online
    final iconColor = device.iconColor?.toLowerCase().trim() ?? '';
    if (iconColor == 'green' || iconColor == 'yellow') {
      return true;
    }

    // Check by timestamp - if last update was within 5 minutes
    if (device.timestamp != null && device.timestamp! > 0) {
      try {
        final lastUpdate =
        DateTime.fromMillisecondsSinceEpoch(device.timestamp! * 1000);
        final difference = DateTime.now().difference(lastUpdate);
        return difference.inMinutes < 5;
      } catch (_) {
        return false;
      }
    }

    // Check if has speed > 0 (must be online if moving)
    final speed = double.tryParse(device.speed.toString()) ?? 0;
    if (speed > 0) {
      return true;
    }

    return false;
  }

  /// MASTER ENGINE CHECK - Same as DevicePage
  bool _isEngineOn(DeviceItem device) {
    if (device.engineStatus != null) {
      final status = device.engineStatus;
      if (status is bool) return status;
      if (status is int) return status == 1;
      if (status is String) {
        final s = status.toLowerCase().trim();
        return s == 'on' || s == '1' || s == 'true';
      }
    } else {
      final traccar = device.deviceData?.traccar;
      if (traccar != null) {
        final engineOnAt = traccar.engineOnAt;
        final engineOffAt = traccar.engineOffAt;
        if (engineOnAt != null && engineOffAt != null) {
          try {
            final onTime = DateTime.parse(engineOnAt);
            final offTime = DateTime.parse(engineOffAt);
            return onTime.isAfter(offTime);
          } catch (_) {}
        }
      }
    }
    return false;
  }



  /// Get the color for the current status
  Color _getStatusColor(DeviceItem device) {
    switch (_getVehicleStatus(device)) {
      case VehicleStatus.running:
        return successColor;
      case VehicleStatus.idle:
        return warningColor;
      case VehicleStatus.stop:
        return dangerColor; // Stopped is Red
      case VehicleStatus.offline:
        return neutralColor; // Offline is Grey
      case VehicleStatus.noData:
        return Colors.grey[500]!;
      case VehicleStatus.expired:
        return dangerColor; // Expired is Red
    }
  }

  /// Get the label text for the current status
  String _getStatusLabel(DeviceItem device) {
    switch (_getVehicleStatus(device)) {
      case VehicleStatus.running:
        return 'Moving';
      case VehicleStatus.idle:
        return 'idle';
      case VehicleStatus.stop:
        return 'Stopped';
      case VehicleStatus.offline:
        return 'Offline';
      case VehicleStatus.noData:
        return 'No Data';
      case VehicleStatus.expired:
        return 'Expired';
    }
  }

  /// Get the icon for the current status
  IconData _getStatusIcon(DeviceItem device) {
    switch (_getVehicleStatus(device)) {
      case VehicleStatus.running:
        return Icons.directions_car;
      case VehicleStatus.idle:
        return Icons.pause_circle;
      case VehicleStatus.stop:
        return Icons.local_parking;
      case VehicleStatus.offline:
        return Icons.signal_wifi_off;
      case VehicleStatus.noData:
        return Icons.error_outline;
      case VehicleStatus.expired:
        return Icons.timer_off_outlined;
    }
  }

  // ==================== PAYMENT DIALOG ====================

  void _showPaymentDialog(double due,
      {bool allowSnooze = true, bool isBlocking = false}) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: !isBlocking,
      barrierColor: Colors.black.withValues(alpha: isBlocking ? 0.7 : 0.5),
      builder: (dialogContext) => PopScope(
        canPop: !isBlocking,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 10,
          child: Container(
            padding: const EdgeInsets.all(0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isBlocking
                          ? [const Color(0xFFFF0000), const Color(0xFFB71C1C)]
                          : [const Color(0xFFFF9800), const Color(0xFFF57C00)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isBlocking
                              ? Icons.error_outline_rounded
                              : Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isBlocking ? 'à¦ªà§‡à¦®à§‡à¦¨à§à¦Ÿ à¦œà¦°à§à¦°à¦¿!' : 'à¦ªà§‡à¦®à§‡à¦¨à§à¦Ÿ à¦¬à¦•à§‡à¦¯à¦¼à¦¾',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text(
                        'à¦®à§‹à¦Ÿ à¦¬à¦•à§‡à¦¯à¦¼à¦¾',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'à§³',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD32F2F),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            due.toStringAsFixed(2),
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD32F2F),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isBlocking
                              ? const Color(0xFFFFEBEE)
                              : const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: isBlocking
                                  ? const Color(0xFFD32F2F)
                                  : const Color(0xFFF57C00),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isBlocking
                                    ? 'à¦†à¦ªà¦¨à¦¾à¦° à¦—à§à¦°à§‡à¦¸ à¦ªà¦¿à¦°à¦¿à¦¯à¦¼à¦¡ à¦¶à§‡à¦·à¥¤ à¦¸à§‡à¦¬à¦¾ à¦šà¦¾à¦²à§ à¦°à¦¾à¦–à¦¤à§‡ à¦à¦–à¦¨à¦‡ à¦ªà§‡à¦®à§‡à¦¨à§à¦Ÿ à¦•à¦°à§à¦¨à¥¤'
                                    : 'à¦¸à§‡à¦¬à¦¾ à¦…à¦¬à§à¦¯à¦¾à¦¹à¦¤ à¦°à¦¾à¦–à¦¤à§‡ à¦¬à¦•à§‡à¦¯à¦¼à¦¾ à¦ªà¦°à¦¿à¦¶à§‹à¦§ à¦•à¦°à§à¦¨à¥¤',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isBlocking
                                      ? const Color(0xFFD32F2F)
                                      : const Color(0xFFF57C00),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PaymentListScreen(),
                              ),
                            ).then((_) {
                              if (mounted) _checkPaymentStatus();
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.payment_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'à¦à¦–à¦¨à¦‡ à¦ªà§‡à¦®à§‡à¦¨à§à¦Ÿ à¦•à¦°à§à¦¨',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (allowSnooze && !isBlocking) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton(
                            onPressed: () async {
                              final prefs =
                              await SharedPreferences.getInstance();
                              final later =
                              DateTime.now().add(const Duration(days: 7));
                              await prefs.setInt(
                                'grace_end_time',
                                later.millisecondsSinceEpoch,
                              );
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop();
                                _startCountdown(later);
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey[700],
                              side: BorderSide(color: Colors.grey[300]!),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.schedule_rounded, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'à§­ à¦¦à¦¿à¦¨ à¦ªà¦°à§‡ à¦®à¦¨à§‡ à¦•à¦°à¦¿à¦¯à¦¼à§‡ à¦¦à¦¿à¦¨',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (isBlocking) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              _contactSupport();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey[700],
                              side: BorderSide(color: Colors.grey[300]!),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.support_agent, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'à¦¸à¦¾à¦ªà§‹à¦°à§à¦Ÿà§‡ à¦¯à§‹à¦—à¦¾à¦¯à§‹à¦— à¦•à¦°à§à¦¨',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _contactSupport() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.support_agent, color: primaryColor),
            SizedBox(width: 8),
            Text('à¦¸à¦¾à¦ªà§‹à¦°à§à¦Ÿ', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone, color: successColor),
              title: const Text('à¦«à§‹à¦¨ à¦•à¦°à§à¦¨'),
              subtitle: const Text('+8801960446666'),
              onTap: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse('tel:+8801960446666'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat, color: successColor),
              title: const Text('WhatsApp'),
              subtitle: const Text('+8801960446666'),
              onTap: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse('https://wa.me/+8801960446666'));
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('à¦¬à¦¨à§à¦§ à¦•à¦°à§à¦¨'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (days > 0) {
      return '${days}d ${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else {
      return '${minutes}m ${seconds}s';
    }
  }

  // ==================== BUILD METHODS ====================

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          await homeController.refreshData();
          _calculateStatusCounts();
        },
        color: primaryColor,
        child: ScrollConfiguration(
          // Remove Android overscroll glow â€” gives a clean fluid feel
          behavior: const _NoGlowScrollBehavior(),
          child: CustomScrollView(

          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: Obx(() {
                // Build item list reactively â€” only Obx rebuilds, not whole Scaffold
                final hasDue = _hasDue.value;
                final items = <Widget>[
                  if (hasDue) RepaintBoundary(child: _buildDueReminderContainer()),
                  if (hasDue) const SizedBox(height: 16),
                  RepaintBoundary(child: _buildBannerCarousel()),
                  const SizedBox(height: 16),
                  RepaintBoundary(child: _buildStatsRow()),
                  const SizedBox(height: 16),
                  RepaintBoundary(child: _buildVehicleSelector()),
                  const SizedBox(height: 16),
                  RepaintBoundary(child: _buildVehicleSummary()),
                  const SizedBox(height: 16),
                  RepaintBoundary(child: _buildNearByPlacesCard()),
                  const SizedBox(height: 16),
                  RepaintBoundary(child: _buildMileageChart()),
                  const SizedBox(height: 16),
                  RepaintBoundary(child: _buildQuickLinksCard()),
                  const SizedBox(height: 16),
                  RepaintBoundary(child: _buildSubscriptionCard()),
                  const SizedBox(height: 24),
                ];
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => items[i],
                    childCount: items.length,
                    // addRepaintBoundaries already handled per-item above
                    addRepaintBoundaries: false,
                    addAutomaticKeepAlives: true,
                  ),
                );
              }),
            ),
          ],
        ),        // CustomScrollView
        ),         // ScrollConfiguration
      ),           // RefreshIndicator
    );
  }

  Widget _buildDueReminderContainer() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            dangerColor.withValues(alpha: 0.8),
            dangerColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'à¦ªà§‡à¦®à§‡à¦¨à§à¦Ÿ à¦¬à¦•à§‡à¦¯à¦¼à¦¾ à¦°à¦¯à¦¼à§‡à¦›à§‡!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'à¦®à§‹à¦Ÿ à¦¬à¦•à§‡à¦¯à¦¼à¦¾: à§³ ${_dueAmount.value.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Obx(() => _timeLeftStr.value.isNotEmpty
            ? Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'à¦—à§à¦°à§‡à¦¸ à¦ªà¦¿à¦°à¦¿à¦¯à¦¼à¦¡ à¦¬à¦¾à¦•à¦¿: ${_timeLeftStr.value}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : const SizedBox.shrink()
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'à¦¸à§‡à¦¬à¦¾ à¦…à¦¬à§à¦¯à¦¾à¦¹à¦¤ à¦°à¦¾à¦–à¦¤à§‡ à¦…à¦¨à§à¦—à§à¦°à¦¹ à¦•à¦°à§‡ à¦¬à¦•à§‡à¦¯à¦¼à¦¾ à¦ªà¦°à¦¿à¦¶à§‹à¦§ à¦•à¦°à§à¦¨à¥¤',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PaymentListScreen()),
                  ).then((_) {
                    if (mounted) _checkPaymentStatus();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: dangerColor,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'à¦ªà§‡à¦®à§‡à¦¨à§à¦Ÿ à¦•à¦°à§à¦¨',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFFFF0000), // Pure red status bar
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(5),
        ),
      ),
      centerTitle: true,
      toolbarHeight: 50,
      automaticallyImplyLeading: false,
      title: const Text(
        'Home',
        style: TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildAppBarIcon(IconData icon, VoidCallback onTap, {int? badge}) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.grey[700], size: 20),
          ),
          if (badge != null && badge > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                decoration: const BoxDecoration(
                  color: dangerColor,
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(
                    BorderSide(color: Colors.white, width: 1.5),
                  ),
                ),
                child: Center(
                  child: Text(
                    badge > 99 ? '99+' : badge.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Obx(() {
      final allCount = dataController.onlyDevices.length;
      final running = _runningCount.value;
      final idle = _idleCount.value;
      final parking = _stopCount.value;
      final offline = _offlineCount.value;
      final noData = _noDataCount.value;
      final expired = _expiredCount.value;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Fleet Status',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ),
            Divider(color: Colors.grey[200], height: 1, thickness: 1),
            const SizedBox(height: 16),
            Row(
              children: [
                // Pie Chart
                SizedBox(
                  width: 180,
                  height: 180,
                  child: allCount == 0
                      ? _buildEmptyPieChart()
                      : Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2.0,
                          centerSpaceRadius: 44,
                          startDegreeOffset: -90,
                          sections: _buildPieSections(
                            running: running,
                            idle: idle,
                            parking: parking,
                            offline: offline,
                            noData: noData,
                            expired: expired,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            allCount.toString(),
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                          const Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 58),
                // Legend
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLegendItem(
                        color: successColor,
                        label: 'Moving:',
                        count: running,
                        total: allCount,
                      ),
                      const SizedBox(height: 10),
                      _buildLegendItem(
                        color: dangerColor,
                        label: 'Stopped:',
                        count: parking,
                        total: allCount,
                      ),
                      const SizedBox(height: 10),
                      _buildLegendItem(
                        color: warningColor,
                        label: 'idle:',
                        count: idle,
                        total: allCount,
                      ),
                      const SizedBox(height: 10),
                      _buildLegendItem(
                        color: neutralColor,
                        label: 'Offline:',
                        count: offline,
                        total: allCount,
                      ),
                      const SizedBox(height: 10),
                      _buildLegendItem(
                        color: dangerColor,
                        label: 'Expired:',
                        count: expired,
                        total: allCount,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  List<PieChartSectionData> _buildPieSections({
    required int running,
    required int idle,
    required int parking,
    required int offline,
    required int noData,
    required int expired,
  }) {
    final total = running + idle + parking + offline + noData + expired;
    if (total == 0) return [];

    final sections = <PieChartSectionData>[];

    if (running > 0) {
      sections.add(
        PieChartSectionData(
          color: successColor,
          value: running.toDouble(),
          title: '',
          radius: 42,
        ),
      );
    }

    if (idle > 0) {
      sections.add(
        PieChartSectionData(
          color: warningColor,
          value: idle.toDouble(),
          title: '',
          radius: 42,
        ),
      );
    }

    if (parking > 0) {
      sections.add(
        PieChartSectionData(
          color: dangerColor, // Red for Stopped
          value: parking.toDouble(),
          title: '',
          radius: 42,
        ),
      );
    }

    if (offline > 0) {
      sections.add(
        PieChartSectionData(
          color: neutralColor, // Grey for Offline
          value: offline.toDouble(),
          title: '',
          radius: 42,
        ),
      );
    }

    if (noData > 0) {
      sections.add(
        PieChartSectionData(
          color: Colors.grey[500]!,
          value: noData.toDouble(),
          title: '',
          radius: 42,
        ),
      );
    }

    if (expired > 0) {
      sections.add(
        PieChartSectionData(
          color: dangerColor, // Red for Expired
          value: expired.toDouble(),
          title: '',
          radius: 42,
        ),
      );
    }

    return sections;
  }

  Widget _buildEmptyPieChart() {
    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sectionsSpace: 0,
            centerSpaceRadius: 44,
            sections: [
              PieChartSectionData(
                color: Colors.grey[200],
                value: 1,
                title: '',
                radius: 42,
              ),
            ],
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '0',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.grey[400],
              ),
            ),
            Text(
              'Total',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required int count,
    required int total,
  }) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildBannerCarousel() {
    return Column(
      children: [
        CarouselSlider(
          options: CarouselOptions(
            height: 220,
            viewportFraction: 1.0,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 5),
            enlargeCenterPage: false,
            onPageChanged: (index, reason) {
              setState(() {
                _currentBannerIndex = index;
              });
            },
          ),
          items: _localBanners.map((bannerPath) {
            return Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(bannerPath),
                  fit: BoxFit.fill,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _localBanners.asMap().entries.map((entry) {
            return Container(
              width: 14.0,
              height: 4.0,
              margin: const EdgeInsets.symmetric(horizontal: 3.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: _currentBannerIndex == entry.key
                    ? const Color(0xFFFF0000)
                    : const Color(0xFFD1D5DB),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildVehicleSelector() {
    return Obx(() {
      final vehicles = homeController.dataController.onlyDevices;
      final selected = homeController.selectedDevice;
      final selectedId = homeController.selectedDeviceId.value;

      // Remove duplicate devices based on ID
      final uniqueVehicles = <int, DeviceItem>{};
      for (var device in vehicles) {
        if (device.id != null) {
          uniqueVehicles[device.id!] = device;
        }
      }
      final vehicleList = uniqueVehicles.values.toList();

      // Validate selectedId exists in the list
      final validSelectedId =
      vehicleList.any((d) => d.id == selectedId) ? selectedId : null;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: const Color(0xFFFF0000), // red border
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                isExpanded: true,
                value: (validSelectedId == 0 || validSelectedId == null)
                    ? null
                    : validSelectedId,
                hint: Text(
                  'Choose vehicle...',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 24),
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                items: vehicleList.map((device) {
                  final statusColor = _getStatusColor(device);
                  return DropdownMenuItem<int>(
                    value: device.id,
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            device.name ?? 'Unnamed',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          _getStatusLabel(device),
                          style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (id) {
                  if (id != null) homeController.onVehicleChanged(id);
                },
              ),
            ),
          ),

        ],
      );
    });
  }

  Widget _buildLiveStatus() {
    return Obx(() {
      final device = homeController.selectedDevice;
      if (device == null) return const SizedBox.shrink();

      final color = _getStatusColor(device);
      final status = _getVehicleStatus(device);
      final isEngineOn = _isEngineOn(device);

      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.gps_fixed, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    device.name ?? 'Vehicle',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getStatusIcon(device), color: color, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        _getStatusLabel(device),
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildLiveStat(Icons.speed, '${device.speed ?? 0}', 'km/h'),
                _buildLiveDivider(),
                _buildLiveStat(
                    Icons.explore, '${device.course ?? 0}Â°', 'Course'),
                _buildLiveDivider(),
                _buildLiveStat(
                  isEngineOn ? Icons.power : Icons.power_off,
                  isEngineOn ? 'ON' : 'OFF',
                  'Engine',
                ),
                _buildLiveDivider(),
                _buildLiveStat(
                    Icons.timer, Util.formatDurationString(device.stopDuration), 'Parking'),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildLiveStat(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveDivider() {
    return Container(
      height: 30,
      width: 1,
      color: Colors.white.withValues(alpha: 0.3),
    );
  }

  Widget _buildMileageChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, color: warningColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'Weekly Mileage',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              Text(
                homeController.getFormattedDateRange(),
                style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Obx(() {
            final data = homeController.mileageData;
            final isLoading = homeController.isLoadingMileage.value;

            if (isLoading) {
              return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (data.isEmpty) {
              return SizedBox(
                height: 160,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bar_chart, size: 40, color: Colors.grey[300]),
                      const SizedBox(height: 8),
                      Text(
                        'No data available',
                        style:
                        TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            }

            return SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _getMaxY(data),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _getInterval(data),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey[200]!,
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, _) => Text(
                          '${value.toInt()}',
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF475569), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) {
                          int i = value.toInt();
                          if (i < data.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                data[i].dayLabel,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF1E293B),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(data.length, (i) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: homeController.isDummyMileageData.value
                              ? 0
                              : data[i].distance,
                          color: warningColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                          width: 20,
                        ),
                      ],
                      showingTooltipIndicators: data[i].distance > 0 ? [0] : [],
                    );
                  }),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.white,
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      tooltipMargin: 0,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${rod.toY.toInt()} km',
                          const TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  double _getMaxY(List<MileageData> data) {
    if (data.isEmpty) return 400;
    final max = data.map((e) => e.distance).reduce((a, b) => a > b ? a : b);
    return (((max / 100).ceil() + 1) * 100).toDouble();
  }

  double _getInterval(List<MileageData> data) => _getMaxY(data) / 4;

  Widget _buildPeriodTabs() {
    final periods = [
      {'label': 'Today',      'period': ReportPeriod.today},
      {'label': 'Yesterday',  'period': ReportPeriod.yesterday},
      {'label': 'This Week',  'period': ReportPeriod.thisWeek},
      {'label': 'This Month', 'period': ReportPeriod.thisMonth},
      {'label': 'Custom',     'period': ReportPeriod.custom},
    ];

    return Obx(() {
      final currentPeriod = homeController.selectedPeriod.value;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: periods.map((p) {
            final isSelected = p['period'] == currentPeriod;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: InkWell(
                onTap: () async {
                  final tapped = p['period'] as ReportPeriod;
                  if (tapped == ReportPeriod.custom) {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDateRange: DateTimeRange(
                        start: DateTime.now().subtract(const Duration(days: 6)),
                        end: DateTime.now(),
                      ),
                      builder: (context, child) => Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: primaryColor,
                            onPrimary: Colors.white,
                            surface: Colors.white,
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      homeController.onCustomRangePicked(picked.start, picked.end);
                    }
                  } else {
                    homeController.onPeriodChanged(tapped);
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? primaryColor : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: isSelected
                        ? null
                        : Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: primaryColor.withValues(alpha: 0.40),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    p['label'] as String,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF475569),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    });
  }

  Widget _buildVehicleSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPeriodTabs(),
        const SizedBox(height: 16),
        Obx(() {
          final isLoading = homeController.isLoadingReport.value;
          final report = homeController.todayReport.value;
          final device = homeController.selectedDevice;
          final error = homeController.reportError.value;
          final period = homeController.selectedPeriod.value;

          String title = "Today's Summary";
          if (period == ReportPeriod.yesterday) {
            title = "Yesterday's Summary";
          } else if (period == ReportPeriod.thisWeek) {
            title = "Weekly Summary";
          } else if (period == ReportPeriod.thisMonth) {
            title = "Monthly Summary";
          } else if (period == ReportPeriod.custom) {
            final s = homeController.customStart.value;
            final e = homeController.customEnd.value;
            if (s != null && e != null) {
              title = "${s.day}/${s.month}/${s.year} â€“ ${e.day}/${e.month}/${e.year}";
            } else {
              title = "Custom Summary";
            }
          }

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.40),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 3,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  children: [
                    const Icon(Icons.analytics, color: primaryColor, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const Spacer(),
                    // Refresh button
                    if (!isLoading)
                      GestureDetector(
                        onTap: () {
                          if (device != null && device.id != null) {
                            homeController.loadTodayReport(device.id!,
                                forceRefresh: true);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(Icons.refresh,
                              size: 16, color: Colors.grey[600]),
                        ),
                      )
                    else
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // Content
                if (isLoading && report == null)
                  const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (device == null)
                  _buildEmptyState('Select a vehicle to view summary')
                else if (report == null || report.isEmpty)
                  _buildEmptyState(
                      error.isNotEmpty ? error : 'No data available for $title')
                else
                  // DATA AVAILABLE - Show Grid
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.4,
                    children: [
                      _buildSummaryItem(
                        Icons.route,
                        'Distance',
                        report.routeLength ?? '0 Km',
                        primaryColor,
                      ),
                      _buildSummaryItem(
                        Icons.speed,
                        'Top Speed',
                        report.topSpeed ?? '0 kph',
                        warningColor,
                      ),
                      _buildSummaryItem(
                        Icons.play_arrow,
                        'Moving',
                        report.moveDuration ?? '0h 0m',
                        successColor,
                      ),
                      _buildSummaryItem(
                        Icons.pause,
                        'Stopped',
                        Util.formatDurationString(report.stopDuration),
                        dangerColor,
                      ),
                      _buildSummaryItem(
                        Icons.speed_outlined,
                        'Avg Speed',
                        report.averageSpeed ?? '0 kph',
                        neutralColor,
                      ),
                      _buildSummaryItem(
                        Icons.engineering,
                        'Engine Hrs',
                        report.engineHours ?? '0h 0m',
                        successColor,
                      ),
                      _buildSummaryItem(
                        Icons.build_circle,
                        'Engine Work',
                        report.engineWork ?? '0s',
                        warningColor,
                      ),
                      _buildSummaryItem(
                        Icons.hourglass_empty,
                        'Engine Idle',
                        report.engineIdle ?? '0h 0m',
                        dangerColor,
                      ),
                      _buildSummaryItem(
                        Icons.warning_amber,
                        'Overspeed',
                        report.overspeedCount ?? '0',
                        dangerColor,
                      ),
                      _buildSummaryItem(
                        Icons.local_gas_station,
                        'Fuel',
                        report.fuelConsumption ??
                            device.deviceData?.fuelQuantity ??
                            '0 L',
                        successColor,
                      ),
                      _buildSummaryItem(
                        Icons.straighten,
                        'Odometer',
                        report.odometer ??
                            '${device.totalDistance?.toStringAsFixed(1) ?? '0'} Km',
                        primaryColor,
                      ),
                      _buildSummaryItem(
                        Icons.explore,
                        'Course',
                        '${device.course ?? 0}Â°',
                        neutralColor,
                      ),
                    ],
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSummaryItem(
      IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNearByPlacesCard() {
    final List<Map<String, dynamic>> items = [
      {
        'title': 'Hospital',
        'query': 'hospital near me',
        'assetPath': 'assets/images/nearby_hospital.svg',
      },
      {
        'title': 'Restaurant',
        'query': 'restaurant near me',
        'assetPath': 'assets/images/nearby_restaurant.svg',
      },
      {
        'title': 'ATM',
        'query': 'atm near me',
        'assetPath': 'assets/images/nearby_atm.svg',
      },
      {
        'title': 'Bus Stop',
        'query': 'bus stop near me',
        'assetPath': 'assets/images/nearby_bus_stop.svg',
      },
      {
        'title': 'Train Station',
        'query': 'train station near me',
        'assetPath': 'assets/images/nearby_train_station.svg',
      },
      {
        'title': 'Hotel',
        'query': 'hotel near me',
        'assetPath': 'assets/images/nearby_hotel.svg',
      },
      {
        'title': 'Gas Station',
        'query': 'gas station near me',
        'assetPath': 'assets/images/nearby_gas_station.svg',
      },
      {
        'title': 'Petrol Pump',
        'query': 'petrol pump near me',
        'assetPath': 'assets/images/nearby_petrol_pump.svg',
      },
      {
        'title': 'Police Station',
        'query': 'police station near me',
        'assetPath': 'assets/images/nearby_police_station.svg',
      },
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.place, color: Color(0xFFFF0000), size: 20),
              SizedBox(width: 8),
              Text(
                'Near By Place',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.95,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return InkWell(
                onTap: () => _launchMapQuery(item['query'] as String),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        item['assetPath'] as String,
                        width: 42,
                        height: 42,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item['title'] as String,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF475569),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _launchMapQuery(String query) async {
    try {
      final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}');
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error launching map: $e');
      Get.snackbar(
        'Error',
        'Could not open Google Maps. Make sure Google Maps is installed.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Widget _buildEmptyState(String message) {
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insert_chart_outlined,
                size: 40, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    return Obx(() {
      final total = homeController.totalVehicles.value;
      final paid = homeController.paidVehicles.value;
      final due = homeController.dueVehicles.value;
      final isLoading = homeController.isLoadingSubscription.value;

      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.card_membership,
                    color: primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Subscription',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const Spacer(),
                if (due > 0)
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: dangerColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$due Due',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (isLoading)
              const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Row(
                children: [
                  if (total > 0)
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 35,
                              sections: [
                                PieChartSectionData(
                                  color: successColor,
                                  value: paid.toDouble(),
                                  title: '',
                                  radius: 15,
                                ),
                                if (due > 0)
                                  PieChartSectionData(
                                    color: dangerColor,
                                    value: due.toDouble(),
                                    title: '',
                                    radius: 15,
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            total.toString(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      children: [
                        _buildSubLegend(primaryColor, 'Total', total),
                        const SizedBox(height: 8),
                        _buildSubLegend(successColor, 'Active', paid),
                        const SizedBox(height: 8),
                        _buildSubLegend(dangerColor, 'Inactive', due),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _showVehicleStatusDialog,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: primaryColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      'View All',
                      style: TextStyle(color: primaryColor, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => PaymentListScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      'Pay Now',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildSubLegend(Color color, String label, int value) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const Spacer(),
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  void _showVehicleStatusDialog() {
    final vehicles = homeController.dataController.onlyDevices;

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 450, maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: primaryColor,
                  borderRadius:
                  BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.list_alt, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'All Vehicles',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Get.back(),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 18),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  shrinkWrap: true,
                  itemCount: vehicles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final v = vehicles[index];
                    final color = _getStatusColor(v);
                    final status = _getStatusLabel(v);

                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border:
                        Border.all(color: color.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(_getStatusIcon(v),
                                color: color, size: 16),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  v.name ?? 'Unnamed',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${v.speed ?? 0} km/h',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              status,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickLinksCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grid_view, color: primaryColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'Quick Links',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: Colors.grey[200], height: 1),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            childAspectRatio: 1.8,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            children: [
              _buildQuickLinkItem(
                imagePath: 'assets/images/driving_instructor.png',
                label: 'Driving\nInstructor',
                onTap: () => Get.to(() => const DrivingInstructorScreen()),
              ),
              _buildQuickLinkItem(
                imagePath: 'assets/images/get_license.png',
                label: 'Get\nLicense',
                onTap: () => _launchURL('https://bsp.brta.gov.bd'),
              ),
              _buildQuickLinkItem(
                imagePath: 'assets/images/traffic_signs.png',
                label: 'Traffic\nSigns',
                onTap: () => Get.to(() => const TrafficSignsScreen()),
              ),
              _buildQuickLinkItem(
                imagePath: 'assets/images/brta_instruction.png',
                label: 'BRTA\nInstruction',
                onTap: () => _launchURL('https://brta.gov.bd'),
              ),
              _buildQuickLinkItem(
                imagePath: 'assets/images/car_knowledge.png',
                label: 'Car\nKnowledge',
                onTap: () => Get.to(() => const CarKnowledgeScreen()),
              ),
              _buildQuickLinkItem(
                imagePath: 'assets/images/blogs.png',
                label: 'Blogs',
                onTap: () => _launchURL('https://onfleetgps.com'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLinkItem({
    required String imagePath,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Image.asset(
              imagePath,
              width: 26,
              height: 26,
              cacheWidth: 52,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.link, color: primaryColor, size: 18),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11.0,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                  height: 1.1,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchURL(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        Get.snackbar('Error', 'Could not open link: $urlString',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: dangerColor.withValues(alpha: 0.8),
            colorText: Colors.white);
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }

  void _showDrivingInstructorDialog() {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Image.asset('assets/images/driving_instructor.png', width: 28, height: 28, errorBuilder: (_, __, ___) => const SizedBox()),
            const SizedBox(width: 8),
            const Text('Driving Instructors', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Top Registered Schools & Instructors:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              SizedBox(height: 8),
              Text('1. Onfleet Driving Training School\n   Phone: 01912609087\n'),
              Text('2. BRAC Driving School\n   Dhaka Office\n'),
              Text('3. BRTA Safety Training Center\n   Mirpur, Dhaka\n'),
              Divider(),
              Text(
                'Tip: Always learn from BRTA-licensed instructors for safe road habits.',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Close', style: TextStyle(color: primaryColor)),
          ),
        ],
      ),
    );
  }

  void _showTrafficSignsDialog() {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Image.asset('assets/images/traffic_signs.png', width: 28, height: 28, errorBuilder: (_, __, ___) => const SizedBox()),
            const SizedBox(width: 8),
            const Text('Traffic Signs Guide', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Key Traffic Guidelines in Bangladesh:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              SizedBox(height: 8),
              Text('â€¢ Red Light: Stop immediately.\n'
                  'â€¢ Yellow Light: Slow down and prepare to stop.\n'
                  'â€¢ Green Light: Go safely.\n'
                  'â€¢ Speed Limit: Observe speed limit signs in urban zones (typically 30-50 km/h).\n'
                  'â€¢ Overtaking: Do not overtake on bridges, curves, or narrow roads.'),
              Divider(),
              Text(
                'Tip: Onfleet GPS tracking sends dynamic notifications when you exceed speed limits.',
                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Close', style: TextStyle(color: primaryColor)),
          ),
        ],
      ),
    );
  }

  void _showCarKnowledgeDialog() {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Image.asset('assets/images/car_knowledge.png', width: 28, height: 28, errorBuilder: (_, __, ___) => const SizedBox()),
            const SizedBox(width: 8),
            const Text('Car Maintenance Tips', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Essential Vehicle Care Checkpoints:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              SizedBox(height: 8),
              Text('1. Engine Oil: Check the level weekly and change every 5,000 km.\n'
                  '2. Coolant Level: Ensure the radiator reservoir is filled.\n'
                  '3. Tire Pressure: Keep tires inflated to the recommended PSI (usually 30-32).\n'
                  '4. Brake Check: Inspect pads regularly for wear.\n'
                  '5. Battery Status: Keep terminal connectors clean and tight.'),
              Divider(),
              Text(
                'Tip: Configure geo-fence alerts to secure your car overnight.',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Close', style: TextStyle(color: primaryColor)),
          ),
        ],
      ),
    );
  }
}

/// Removes the Android overscroll glow indicator for a clean, fluid scroll feel.
/// This is a zero-cost wrapper â€” no animations, no extra layers.
class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child; // Simply skip the glow â€” nothing to render
}
