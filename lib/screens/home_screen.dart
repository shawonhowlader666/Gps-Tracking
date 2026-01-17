import 'dart:async';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import 'package:gpspro/config.dart';
import 'package:gpspro/constants/app_constants.dart';
import 'package:gpspro/screens/home/home_controller.dart';
import 'package:gpspro/screens/payment_list.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/payment_service.dart';
import 'data_controller/data_controller.dart';

// Status enum for consistency
enum VehicleStatus { running, idle, stop, offline }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final HomeController homeController = Get.put(HomeController());
  late final DataController dataController;

  Timer? _countdownTimer;
  Timer? _statusRefreshTimer;
  Duration? _timeLeft;
  double? _dueAmount;
  bool _isVisible = true;

  // Reactive counts for status
  final RxInt _runningCount = 0.obs;
  final RxInt _idleCount = 0.obs;
  final RxInt _stopCount = 0.obs;
  final RxInt _offlineCount = 0.obs;

  // Simple color palette
  static const Color primaryColor = Color(0xFF2563EB);
  static const Color successColor = Color(0xFF22C55E);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color dangerColor = Color(0xFFEF4444);
  static const Color neutralColor = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    dataController = Get.put(DataController(), permanent: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkPaymentStatus();
        _calculateStatusCounts();
        _startStatusRefresh();
      }
    });
  }

  void _startStatusRefresh() {
    _statusRefreshTimer?.cancel();
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && _isVisible) {
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
      }
    }

    _runningCount.value = running;
    _idleCount.value = idle;
    _stopCount.value = stop;
    _offlineCount.value = offline;
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
        if (_timeLeft != null && _dueAmount != null) {
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
        if (mounted) setState(() => _dueAmount = null);
        return;
      }

      if (mounted) setState(() => _dueAmount = stats.due);

      final prefs = await SharedPreferences.getInstance();
      final graceEnd = prefs.getInt('grace_end_time');

      if (!mounted) return;

      if (graceEnd == null) {
        _showPaymentDialog(stats.due, allowSnooze: true, isBlocking: false);
      } else {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now > graceEnd) {
          _showPaymentDialog(stats.due, allowSnooze: false, isBlocking: true);
        } else {
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
      if (!mounted || !_isVisible) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      if (now.isAfter(endTime)) {
        timer.cancel();
        if (mounted) {
          setState(() => _timeLeft = null);
          _checkPaymentStatus();
        }
      } else {
        _updateTimeLeft(endTime);
      }
    });
  }

  void _updateTimeLeft(DateTime endTime) {
    if (!mounted) return;

    final now = DateTime.now();
    if (now.isBefore(endTime)) {
      final newTimeLeft = endTime.difference(now);
      if (_timeLeft == null ||
          (_timeLeft!.inSeconds - newTimeLeft.inSeconds).abs() >= 1) {
        setState(() => _timeLeft = newTimeLeft);
      }
    }
  }

  // ==================== STATUS DETECTION METHODS ====================

  /// PRIMARY: Use iconColor from server (most reliable source)
  /// FALLBACK: Calculate based on online status, speed, and engine
  VehicleStatus _getVehicleStatus(DeviceItem device) {
    // 1. PRIMARY: Check iconColor from server
    final iconColor = device.iconColor?.toLowerCase().trim() ?? '';

    if (iconColor == 'green') {
      return VehicleStatus.running;
    } else if (iconColor == 'yellow') {
      return VehicleStatus.idle;
    } else if (iconColor == 'red') {
      // Red can mean stopped OR offline - check online status
      if (_isDeviceOnline(device)) {
        return VehicleStatus.stop;
      } else {
        return VehicleStatus.offline;
      }
    }

    // 2. FALLBACK: Calculate status manually if iconColor is not available

    // Check if device is online first
    if (!_isDeviceOnline(device)) {
      return VehicleStatus.offline;
    }

    // Check speed
    final speed = double.tryParse(device.speed.toString()) ?? 0;

    // If moving, it's running
    if (speed > 0) {
      return VehicleStatus.running;
    }

    // Speed is 0, check engine status
    if (_isEngineOn(device)) {
      return VehicleStatus.idle;
    }

    // Speed is 0, engine is off, but device is online = stopped
    return VehicleStatus.stop;
  }

  /// Check if device is online/connected to server
  bool _isDeviceOnline(DeviceItem device) {
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

  /// Check if engine/ignition is ON
  bool _isEngineOn(DeviceItem device) {
    // 1. Check engineStatus field directly
    if (device.engineStatus != null) {
      final status = device.engineStatus;
      if (status is bool) return status;
      if (status is int) return status == 1;
      if (status is String) {
        final s = status.toLowerCase().trim();
        if (['on', '1', 'true', 'ign on', 'engine on', 'acc on'].contains(s)) {
          return true;
        }
        if (['off', '0', 'false', 'ign off', 'engine off', 'acc off']
            .contains(s)) {
          return false;
        }
      }
    }

    // 2. Check sensors for ignition/ACC status
    if (device.sensors != null && device.sensors!.isNotEmpty) {
      for (var sensor in device.sensors!) {
        try {
          final type = (sensor['type'] ?? '').toString().toLowerCase();
          final name = (sensor['name'] ?? '').toString().toLowerCase();
          final value = sensor['value'];

          if (type == 'acc' ||
              type == 'ignition' ||
              type == 'engine' ||
              name.contains('ignition') ||
              name.contains('acc') ||
              name.contains('engine')) {
            if (value == null) continue;

            if (value is bool) return value;
            if (value is int) return value == 1;
            if (value is String) {
              final v = value.toLowerCase().trim();
              if (['on', '1', 'true', 'ign on', 'acc on', 'engine on']
                  .contains(v)) return true;
              if (['off', '0', 'false', 'ign off', 'acc off', 'engine off']
                  .contains(v)) return false;
            }
          }
        } catch (e) {
          continue;
        }
      }
    }

    // 3. Check iconColor as indicator
    final iconColor = device.iconColor?.toLowerCase().trim() ?? '';
    if (iconColor == 'yellow') {
      return true; // Idle means engine is on but not moving
    }
    if (iconColor == 'green') {
      return true; // Running means engine is definitely on
    }

    // 4. If speed > 0, engine must be on
    final speed = double.tryParse(device.speed.toString()) ?? 0;
    if (speed > 0) {
      return true;
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
        return neutralColor;
      case VehicleStatus.offline:
        return dangerColor;
    }
  }

  /// Get the label text for the current status
  String _getStatusLabel(DeviceItem device) {
    switch (_getVehicleStatus(device)) {
      case VehicleStatus.running:
        return 'Running';
      case VehicleStatus.idle:
        return 'Idle';
      case VehicleStatus.stop:
        return 'Parking';
      case VehicleStatus.offline:
        return 'Offline';
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
                          ? [const Color(0xFFE53935), const Color(0xFFD32F2F)]
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
                        isBlocking ? 'পেমেন্ট জরুরি!' : 'পেমেন্ট বকেয়া',
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
                        'মোট বকেয়া',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '৳',
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
                                    ? 'আপনার গ্রেস পিরিয়ড শেষ। সেবা চালু রাখতে এখনই পেমেন্ট করুন।'
                                    : 'সেবা অব্যাহত রাখতে বকেয়া পরিশোধ করুন।',
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
                                'এখনই পেমেন্ট করুন',
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
                                  '৭ দিন পরে মনে করিয়ে দিন',
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
                                  'সাপোর্টে যোগাযোগ করুন',
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
            Text('সাপোর্ট', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone, color: successColor),
              title: const Text('ফোন করুন'),
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
            child: const Text('বন্ধ করুন'),
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await homeController.refreshData();
            _calculateStatusCounts();
          },
          color: primaryColor,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _buildAppBar(),
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (_dueAmount != null && _dueAmount! > 0)
                      RepaintBoundary(child: _buildDueReminderContainer()),
                    if (_dueAmount != null && _dueAmount! > 0)
                      const SizedBox(height: 16),
                    RepaintBoundary(child: _buildStatsRow()),
                    const SizedBox(height: 16),
                    RepaintBoundary(child: _buildVehicleSelector()),
                    const SizedBox(height: 16),
                    // RepaintBoundary(child: _buildLiveStatus()),
                    // const SizedBox(height: 16),
                    RepaintBoundary(child: _buildMileageChart()),
                    const SizedBox(height: 16),
                    RepaintBoundary(child: _buildVehicleSummary()),
                    const SizedBox(height: 16),
                    RepaintBoundary(child: _buildSubscriptionCard()),
                    const SizedBox(height: 24),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
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
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: dangerColor.withValues(alpha: 0.3),
            offset: const Offset(0, 4),
            blurRadius: 2,
            spreadRadius: 0,
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
                      'পেমেন্ট বকেয়া রয়েছে!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'মোট বকেয়া: ৳ ${_dueAmount?.toStringAsFixed(2) ?? '0.00'}',
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
          if (_timeLeft != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'গ্রেস পিরিয়ড বাকি: ${_formatDuration(_timeLeft!)}',
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'সেবা অব্যাহত রাখতে অনুগ্রহ করে বকেয়া পরিশোধ করুন।',
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
                  'পেমেন্ট করুন',
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

  Widget _buildAppBar() {
    return SliverAppBar(
      floating: true,
      snap: true,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 48,
      automaticallyImplyLeading: false,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Image.asset(
                  AppConstants.appIcon,
                  height: 40,
                  width: 40,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                  const Icon(Icons.apps, size: 40),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      AppConstants.appName,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Obx(() => _buildAppBarIcon(
                  Icons.notifications_outlined,
                      () {
                    // Navigate to events page
                    // Get.toNamed('/events');
                  },
                  badge: dataController.events.length,
                )),
              ],
            ),
          ),
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
      // Recalculate counts when devices change
      _calculateStatusCounts();

      final allCount = dataController.onlyDevices.length;
      final running = _runningCount.value;
      final idle = _idleCount.value;
      final parking = _stopCount.value;
      final offline = _offlineCount.value;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              offset: const Offset(0, 2),
              blurRadius: 4,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pie_chart, color: primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Vehicle Status',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const Spacer(),
                Text(
                  '$allCount Total',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Pie Chart
                SizedBox(
                  width: 120,
                  height: 120,
                  child: allCount == 0
                      ? _buildEmptyPieChart()
                      : Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 40,
                          startDegreeOffset: -90,
                          sections: _buildPieSections(
                            running: running,
                            idle: idle,
                            parking: parking,
                            offline: offline,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            allCount.toString(),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                          Text(
                            'Vehicles',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Legend
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLegendItem(
                        color: successColor,
                        label: 'Running',
                        count: running,
                        total: allCount,
                      ),
                      const SizedBox(height: 10),
                      _buildLegendItem(
                        color: warningColor,
                        label: 'Idle',
                        count: idle,
                        total: allCount,
                      ),
                      const SizedBox(height: 10),
                      _buildLegendItem(
                        color: neutralColor,
                        label: 'Parking',
                        count: parking,
                        total: allCount,
                      ),
                      const SizedBox(height: 10),
                      _buildLegendItem(
                        color: dangerColor,
                        label: 'Offline',
                        count: offline,
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
  }) {
    final total = running + idle + parking + offline;
    if (total == 0) return [];

    final sections = <PieChartSectionData>[];

    if (running > 0) {
      sections.add(
        PieChartSectionData(
          color: successColor,
          value: running.toDouble(),
          title: running > 0 ? '$running' : '',
          radius: 20,
          titleStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          titlePositionPercentageOffset: 0.55,
        ),
      );
    }

    if (idle > 0) {
      sections.add(
        PieChartSectionData(
          color: warningColor,
          value: idle.toDouble(),
          title: idle > 0 ? '$idle' : '',
          radius: 20,
          titleStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          titlePositionPercentageOffset: 0.55,
        ),
      );
    }

    if (parking > 0) {
      sections.add(
        PieChartSectionData(
          color: neutralColor,
          value: parking.toDouble(),
          title: parking > 0 ? '$parking' : '',
          radius: 20,
          titleStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          titlePositionPercentageOffset: 0.55,
        ),
      );
    }

    if (offline > 0) {
      sections.add(
        PieChartSectionData(
          color: dangerColor,
          value: offline.toDouble(),
          title: offline > 0 ? '$offline' : '',
          radius: 20,
          titleStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          titlePositionPercentageOffset: 0.55,
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
            centerSpaceRadius: 40,
            sections: [
              PieChartSectionData(
                color: Colors.grey[200],
                value: 1,
                title: '',
                radius: 20,
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
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[400],
              ),
            ),
            Text(
              'Vehicles',
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
    final percentage = total > 0 ? (count / total * 100).toStringAsFixed(0) : '0';

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$percentage%',
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
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

      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              offset: const Offset(0, 2),
              blurRadius: 4,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car, color: primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Select Vehicle',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const Spacer(),
                Text(
                  '${vehicleList.length} available',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: (validSelectedId == 0 || validSelectedId == null)
                      ? null
                      : validSelectedId,
                  hint: Text(
                    'Choose vehicle...',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                  icon:
                  Icon(Icons.keyboard_arrow_down, color: Colors.grey[600]),
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
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            _getStatusLabel(device),
                            style: TextStyle(
                              fontSize: 10,
                              color: statusColor,
                              fontWeight: FontWeight.w500,
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
            if (selected != null) ...[
              const SizedBox(height: 8),
              _buildLiveStatus(),
            ],
          ],
        ),
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
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              offset: const Offset(0, 4),
              blurRadius: 8,
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
                    Icons.explore, '${device.course ?? 0}°', 'Course'),
                _buildLiveDivider(),
                _buildLiveStat(
                  isEngineOn ? Icons.power : Icons.power_off,
                  isEngineOn ? 'ON' : 'OFF',
                  'Engine',
                ),
                _buildLiveDivider(),
                _buildLiveStat(Icons.timer, device.stopDuration ?? '-', 'Parking'),
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
          Icon(icon, color: Colors.white70, size: 16),
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
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, 2),
            blurRadius: 4,
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
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
              const Spacer(),
              Text(
                homeController.getFormattedDateRange(),
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
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
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
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
                          style:
                          TextStyle(fontSize: 10, color: Colors.grey[500]),
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
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
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

  Widget _buildVehicleSummary() {
    return Obx(() {
      final isLoading = homeController.isLoadingReport.value;
      final report = homeController.todayReport.value;
      final device = homeController.selectedDevice;
      final error = homeController.reportError.value;

      // Debug log
      debugPrint('🎨 [UI] Building summary:');
      debugPrint('   isLoading: $isLoading');
      debugPrint('   device: ${device?.id}');
      debugPrint('   report: ${report != null ? "exists" : "null"}');
      debugPrint('   report.isEmpty: ${report?.isEmpty}');
      debugPrint('   routeLength: ${report?.routeLength}');

      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              offset: const Offset(0, 2),
              blurRadius: 4,
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
                  "Today's Summary",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const Spacer(),
                // Refresh button
                if (!isLoading)
                  GestureDetector(
                    onTap: () {
                      if (device != null && device.id != null) {
                        homeController.loadTodayReport(device.id!, forceRefresh: true);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.refresh, size: 16, color: Colors.grey[600]),
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
                _buildEmptyState(error.isNotEmpty ? error : 'No data available for today')
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
                      report.stopDuration ?? '0h 0m',
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
                      report.fuelConsumption ?? device.deviceData?.fuelQuantity ?? '0 L',
                      successColor,
                    ),
                    _buildSummaryItem(
                      Icons.straighten,
                      'Odometer',
                      report.odometer ?? '${device.totalDistance?.toStringAsFixed(1) ?? '0'} Km',
                      primaryColor,
                    ),
                    _buildSummaryItem(
                      Icons.explore,
                      'Course',
                      '${device.course ?? 0}°',
                      neutralColor,
                    ),
                  ],
                ),
          ],
        ),
      );
    });
  }

  Widget _buildSummaryItem(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insert_chart_outlined, size: 40, color: Colors.grey[300]),
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
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              offset: const Offset(0, 2),
              blurRadius: 4,
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
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
                            child:
                            Icon(_getStatusIcon(v), color: color, size: 16),
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
}