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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final HomeController homeController = Get.put(HomeController());

  // Use DataController instead of EventsController
  late final DataController dataController;

  Timer? _countdownTimer;
  Duration? _timeLeft;
  double? _dueAmount;
  bool _isVisible = true;

  // Simple color palette - 4 main status colors
  static const Color primaryColor = Color(0xFF2563EB);
  static const Color successColor = Color(0xFF22C55E);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color dangerColor = Color(0xFFEF4444);
  static const Color neutralColor = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize DataController - use put to create if not exists
    dataController = Get.put(DataController(), permanent: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkPaymentStatus();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Pause timer when app is not visible to reduce frame issues
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _isVisible = false;
        _countdownTimer?.cancel();
        break;
      case AppLifecycleState.resumed:
        _isVisible = true;
        if (_timeLeft != null && _dueAmount != null) {
          _resumeCountdownIfNeeded();
        }
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
    _countdownTimer = null;
    super.dispose();
  }

  Future<void> _checkPaymentStatus() async {
    if (!mounted) return;

    try {
      final stats = await PaymentService.getStats();
      if (!mounted) return;

      // No due amount - clear everything
      if (stats == null || stats.due <= 0) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('grace_end_time'); // Clear grace period
        if (mounted) setState(() => _dueAmount = null);
        return;
      }

      if (mounted) setState(() => _dueAmount = stats.due);

      final prefs = await SharedPreferences.getInstance();
      final graceEnd = prefs.getInt('grace_end_time');

      if (!mounted) return;

      if (graceEnd == null) {
        // First time showing - allow snooze
        _showPaymentDialog(stats.due, allowSnooze: true, isBlocking: false);
      } else {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now > graceEnd) {
          // Grace period expired - blocking mode
          // But still allow payment button to work
          _showPaymentDialog(stats.due, allowSnooze: false, isBlocking: true);
        } else {
          // Within grace period - show countdown
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

    // Use longer interval to reduce frame drops
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
      // Only update if difference is significant (avoid unnecessary rebuilds)
      if (_timeLeft == null ||
          (_timeLeft!.inSeconds - newTimeLeft.inSeconds).abs() >= 1) {
        setState(() => _timeLeft = newTimeLeft);
      }
    }
  }

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
                // Header with gradient
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

                // Amount section
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text(
                        'মোট বকেয়া',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
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

                // Buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      // Pay Now Button - ALWAYS WORKS
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            // ALWAYS close dialog first, then navigate
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

                      // Snooze Button - Only show if allowed AND not blocking
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

                      // Contact Support - Show when blocking
                      if (isBlocking) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton(
                            onPressed: () {
                              // Close dialog and open support
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

// Add this method for support contact
  void _contactSupport() {
    // Option 1: Open phone dialer
    // launchUrl(Uri.parse('tel:+8801XXXXXXXXX'));

    // Option 2: Open WhatsApp
    // launchUrl(Uri.parse('https://wa.me/8801XXXXXXXXX'));

    // Option 3: Show contact dialog
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => homeController.refreshData(),
          color: primaryColor,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _buildAppBar(),
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Due Reminder Container
                    if (_dueAmount != null && _dueAmount! > 0)
                      RepaintBoundary(child: _buildDueReminderContainer()),
                    if (_dueAmount != null && _dueAmount! > 0)
                      const SizedBox(height: 16),
                    RepaintBoundary(child: _buildStatsRow()),
                    // const SizedBox(height: 16),
                    // RepaintBoundary(child: _buildBannerCarousel()),
                    const SizedBox(height: 16),
                    RepaintBoundary(child: _buildVehicleSelector()),
                    const SizedBox(height: 16),
                    RepaintBoundary(child: _buildLiveStatus()),
                    const SizedBox(height: 16),
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
                // Wrap with Obx for reactive updates
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
      final dc = homeController.dataController;
      final vehicles = dc.onlyDevices;

      int runningCount = 0;
      int idleCount = 0;
      int stopCount = 0;
      //int stopCount = 0;

      for (final d in vehicles) {
        switch (_getDeviceStatus(d)) {
          case 'running':
            runningCount++;
            break;
          case 'idle':
            idleCount++;
            break;
          case 'stop':
            stopCount++;
            break;
          }
      }

      return Row(
        children: [
          _buildStatChip('All', dc.allCount.value, primaryColor),
          _buildStatChip('Running', runningCount, successColor),
          _buildStatChip('Idle', idleCount, warningColor),
          _buildStatChip('Stop', stopCount, dangerColor),
        ],
      );
    });
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerCarousel() {
    return CarouselSlider(
      options: CarouselOptions(
        height: 150,
        autoPlay: true,
        enlargeCenterPage: true,
        viewportFraction: 0.95,
        autoPlayInterval: const Duration(seconds: 4),
      ),
      items: BANNER_IMAGE.map((url) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            width: double.infinity,
            placeholder: (_, __) => Container(
              color: Colors.grey[200],
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (_, __, ___) => Container(
              color: Colors.grey[200],
              child: Icon(Icons.image, color: Colors.grey[400], size: 40),
            ),
          ),
        );
      }).toList(),
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
                    return DropdownMenuItem<int>(
                      value: device.id,
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _getStatusColor(device),
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
              const SizedBox(height: 12),
              _buildSelectedVehiclePreview(selected),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildSelectedVehiclePreview(DeviceItem device) {
    final color = _getStatusColor(device);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: device.icon?.path != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl:
                          "${UserRepository.getServerUrl()}/${device.icon!.path!}",
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) =>
                          Icon(Icons.directions_car, color: color, size: 18),
                    ),
                  )
                : Icon(Icons.directions_car, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name ?? 'Unnamed',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${device.speed ?? 0} km/h • ${device.stopDuration ?? 'Active'}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _getStatusLabel(device),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatus() {
    return Obx(() {
      final device = homeController.selectedDevice;
      if (device == null) return const SizedBox.shrink();

      final color = _getStatusColor(device).withValues(alpha: 0.6);
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color,
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
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                  _isEngineOn(device) ? Icons.power : Icons.power_off,
                  _isEngineOn(device) ? 'ON' : 'OFF',
                  'Engine',
                ),
                _buildLiveDivider(),
                _buildLiveStat(Icons.timer, device.stopDuration ?? '-', 'Stop'),
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
                      getTooltipColor: (_) => Colors.grey[800]!,
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      tooltipMargin: 4,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${rod.toY.toInt()} km',
                          const TextStyle(
                            color: Colors.white,
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
              ],
            ),
            const SizedBox(height: 14),
            if (isLoading)
              const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (device == null)
              _buildEmptyState('Select a vehicle to view summary')
            else
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
                    report?.routeLength ?? '0 Km',
                    primaryColor,
                  ),
                  _buildSummaryItem(
                    Icons.speed,
                    'Top Speed',
                    report?.topSpeed ?? '0 kph',
                    warningColor,
                  ),
                  _buildSummaryItem(
                    Icons.play_arrow,
                    'Moving',
                    report?.moveDuration ?? '0h 0m',
                    successColor,
                  ),
                  _buildSummaryItem(
                    Icons.pause,
                    'Stopped',
                    report?.stopDuration ?? '0h 0m',
                    dangerColor,
                  ),
                  _buildSummaryItem(
                    Icons.speed_outlined,
                    'Avg Speed',
                    report?.averageSpeed ?? '0 kph',
                    dangerColor,
                  ),
                  _buildSummaryItem(
                    Icons.engineering,
                    'Engine Hrs',
                    report?.engineHours ?? '0h 0m',
                    successColor,
                  ),
                  _buildSummaryItem(
                    Icons.build_circle,
                    'Engine Work',
                    report?.engineWork ?? '0h 0m',
                    warningColor,
                  ),
                  _buildSummaryItem(
                    Icons.hourglass_empty,
                    'Engine Idle',
                    report?.engineIdle ?? '0h 0m',
                    dangerColor,
                  ),
                  _buildSummaryItem(
                    Icons.warning_amber,
                    'Overspeed',
                    report?.overspeedCount ?? '0',
                    dangerColor,
                  ),
                  _buildSummaryItem(
                    Icons.local_gas_station,
                    'Fuel',
                    device.deviceData?.fuelQuantity ?? '0.00 L',
                    successColor,
                  ),
                  _buildSummaryItem(
                    Icons.straighten,
                    'Total Dist',
                    '${device.totalDistance?.toStringAsFixed(1) ?? '0.0'} Km',
                    primaryColor,
                  ),
                  _buildSummaryItem(
                    Icons.explore,
                    'Course',
                    '${device.course ?? 0}°',
                    dangerColor,
                  ),
                ],
              ),
          ],
        ),
      );
    });
  }

  Widget _buildSummaryItem(
      IconData icon, String label, String value, Color color) {
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
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

  Widget _buildEmptyState(String message) {
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_car_outlined,
                size: 40, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      ),
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

  // ENHANCED STATUS DETECTION LOGIC

  /// Check if the GPS device is online/connected
  /// Returns true if device is communicating with server
  bool _isDeviceOnline(DeviceItem device) {
    final online = device.online?.toLowerCase().trim() ?? '';

    // Explicit stop indicators
    if (online.contains('stop')) return false;
    if (online == 'ack' || online.contains('ack')) return false;

    // Explicit online indicators
    if (online.contains('online')) return true;

    // Check device active status from deviceData
    if (device.deviceData?.active != null) {
      final active = device.deviceData!.active.toString();
      if (active == "0" || active == "false") return false;
    }

    // Check timestamp - if last update was too long ago, consider stop
    if (device.timestamp != null && device.timestamp! > 0) {
      try {
        final lastUpdate =
            DateTime.fromMillisecondsSinceEpoch(device.timestamp! * 1000);
        final diff = DateTime.now().difference(lastUpdate);

        // Consider stop if no update in last 10 minutes
        if (diff.inMinutes > 10) return false;

        return true;
      } catch (_) {
        // If timestamp parsing fails, continue to other checks
      }
    }

    // Check movedTimestamp as alternative
    if (device.movedTimestamp != null && device.movedTimestamp! > 0) {
      try {
        final lastMoved =
            DateTime.fromMillisecondsSinceEpoch(device.movedTimestamp! * 1000);
        final diff = DateTime.now().difference(lastMoved);

        // If moved recently, device is online
        if (diff.inMinutes < 30) return true;
      } catch (_) {}
    }

    // Check time string if available
    if (device.time != null && device.time!.isNotEmpty) {
      try {
        final lastTime = DateTime.parse(device.time!);
        final diff = DateTime.now().difference(lastTime);
        if (diff.inMinutes > 10) return false;
        return true;
      } catch (_) {}
    }

    // If we have coordinates but no other indicators, check if they're valid
    if (device.lat != null && device.lng != null) {
      final lat = double.tryParse(device.lat.toString()) ?? 0;
      final lng = double.tryParse(device.lng.toString()) ?? 0;
      if (lat != 0 && lng != 0) {
        // Has valid coordinates, assume online if no explicit stop indicator
        if (online.isEmpty) return true;
      }
    }

    // Default to stop if no positive indicators found
    return false;
  }

  /// Check if engine/ignition is ON
  /// Returns true if engine is running (key is ON)
  bool _isEngineOn(DeviceItem device) {
    // Check engineStatus field directly
    if (device.engineStatus != null) {
      final status = device.engineStatus;

      if (status is bool) return status;
      if (status is int) return status == 1;

      if (status is String) {
        final s = status.toLowerCase().trim();

        // Positive indicators
        if (s == 'on' || s == '1' || s == 'true') return true;
        if (s == 'ign on' || s == 'ignition on' || s == 'engine on') {
          return true;
        }
        if (s.contains('on') && !s.contains('off')) return true;

        // Negative indicators
        if (s == 'off' || s == '0' || s == 'false') return false;
        if (s == 'ign off' || s == 'ignition off' || s == 'engine off') {
          return false;
        }
      }
    }

    // Check traccar data for engine timestamps
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

      // Only engine on time exists
      if (engineOnAt != null && engineOffAt == null) return true;

      // Only engine off time exists
      if (engineOffAt != null && engineOnAt == null) return false;
    }

    // Check detectEngine from deviceData
    if (device.deviceData?.detectEngine != null) {
      final detectEngine = device.deviceData!.detectEngine!.toLowerCase();
      if (detectEngine == 'on' || detectEngine == '1' || detectEngine == 'true') {
        return true;
      }
      if (detectEngine == 'off' ||
          detectEngine == '0' ||
          detectEngine == 'false') {
        return false;
      }
    }

    // Check detectEngine from device (root level)
    if (device.detectEngine != null) {
      final detectEngine = device.detectEngine!.toLowerCase();
      if (detectEngine == 'on' || detectEngine == '1' || detectEngine == 'true') {
        return true;
      }
      if (detectEngine == 'off' ||
          detectEngine == '0' ||
          detectEngine == 'false') {
        return false;
      }
    }

    // Infer from stop duration - if stopped for very short time, might still have engine on
    if (device.stopDurationSec != null) {
      // If stopped for less than 60 seconds, likely engine is still on
      if (device.stopDurationSec! < 60) return true;
    }

    // If vehicle is moving, engine must be on
    final speed = double.tryParse(device.speed.toString()) ?? 0;
    if (speed > 0) return true;

    // Default to off if no positive indicators
    return false;
  }

  /// Get the current status of the device
  /// Priority: stop → running → idle → stop
  ///
  /// Status definitions:
  /// - **running**: Vehicle is moving (speed > 0)
  /// - **idle**: Vehicle is not moving but engine/key is ON (speed = 0, engine ON)
  /// - **stop**: Vehicle is stopped, engine OFF, but device is connected (speed = 0, engine OFF, online)
  /// - **stop**: GPS device is disconnected/not communicating
  String _getDeviceStatus(DeviceItem device) {
    // STEP 1: Check if device is online/connected
    // If device is not online, it's OFFLINE regardless of other states
    if (!_isDeviceOnline(device)) {
      return 'stop';
    }

    // STEP 2: Device is online, check if vehicle is moving
    final speed = double.tryParse(device.speed.toString()) ?? 0;

    // If speed > 0, vehicle is RUNNING
    if (speed > 0) {
      return 'running';
    }

    // STEP 3: Vehicle is not moving (speed = 0), check engine status
    final engineOn = _isEngineOn(device);

    // If engine is ON but not moving, vehicle is IDLE
    if (engineOn) {
      return 'idle';
    }

    // STEP 4: Engine is OFF and not moving, but device is connected = STOP
    return 'stop';
  }

  /// Get the color for the current status
  Color _getStatusColor(DeviceItem device) {
    switch (_getDeviceStatus(device)) {
      case 'running':
        return successColor; // Green
      case 'idle':
        return warningColor; // Orange/Yellow
      case 'stop':
        return dangerColor; default:
        return dangerColor; // Grey
    }
  }

  /// Get the label text for the current status
  String _getStatusLabel(DeviceItem device) {
    switch (_getDeviceStatus(device)) {
      case 'running':
        return 'Running';
      case 'idle':
        return 'Idle';
      case 'stop':
        return 'Stopped';
      default:
        return 'Offline';
    }
  }

  /// Get the icon for the current status
  IconData _getStatusIcon(DeviceItem device) {
    switch (_getDeviceStatus(device)) {
      case 'running':
        return Icons.directions_car; // Car icon for running
      case 'idle':
        return Icons.local_parking; // Parking icon for idle
      case 'stop':
        return Icons.power_off; default:
        return Icons.signal_wifi_off; // No signal for stop
    }
  }
}
