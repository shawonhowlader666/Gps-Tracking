import 'dart:async';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import 'package:gpspro/config.dart';
import 'package:gpspro/screens/home/home_controller.dart';
import 'package:gpspro/screens/payment_list.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/payment_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final HomeController homeController = Get.put(HomeController());
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  Timer? _countdownTimer;
  Duration? _timeLeft;

  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();

    // Check payment status after a slight delay to ensure context is ready
    Future.delayed(const Duration(seconds: 1), () {
      _checkPaymentStatus();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPaymentStatus() async {
    final stats = await PaymentService.getStats();
    if (stats == null || stats.due <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final graceEnd = prefs.getInt('grace_end_time');

    if (!mounted) return;

    if (graceEnd == null) {
      _showPaymentDialog(stats.due, allowSnooze: true);
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now > graceEnd) {
        // Expired. Blocking.
        _showPaymentDialog(stats.due, allowSnooze: false, isBlocking: true);
      } else {
        // Active. Start countdown.
        final end = DateTime.fromMillisecondsSinceEpoch(graceEnd);
        _startCountdown(end);
      }
    }
  }

  void _startCountdown(DateTime endTime) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final now = DateTime.now();
      if (now.isAfter(endTime)) {
        timer.cancel();
        setState(() {
          _timeLeft = null;
        });
        _checkPaymentStatus(); // Re-trigger blocking
      } else {
        setState(() {
          _timeLeft = endTime.difference(now);
        });
      }
    });
  }

  void _showPaymentDialog(double due, {bool allowSnooze = true, bool isBlocking = false}) {
    showDialog(
      context: context,
      barrierDismissible: !isBlocking,
      builder: (context) => PopScope(
        canPop: !isBlocking,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              const SizedBox(width: 10),
              const Text('Payment Due'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have a total due of BDT ${due.toStringAsFixed(2)}.',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 10),
              if (isBlocking)
                const Text(
                  'Your grace period has expired. Please pay now to continue using the app.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                )
              else
                const Text('Please clear your dues to avoid service interruption.'),
            ],
          ),
          actions: [
            if (allowSnooze)
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  final later = DateTime.now().add(const Duration(days: 5));
                  await prefs.setInt('grace_end_time', later.millisecondsSinceEpoch);

                  if (context.mounted) {
                    Navigator.pop(context);
                    _startCountdown(later);
                  }
                },
                child: const Text('Need 5 Days'),
              ),
            ElevatedButton(
              onPressed: () {
                if (!isBlocking) Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PaymentListScreen()),
                ).then((_) {
                  // Re-check after returning from payment screen
                  _checkPaymentStatus();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3E6FB8),
                foregroundColor: Colors.white,
              ),
              child: const Text('Pay Now'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    int days = duration.inDays;
    int hours = duration.inHours % 24;
    int minutes = duration.inMinutes % 60;
    return '${days}d ${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: RefreshIndicator(
              onRefresh: () => homeController.refreshData(),
              color: const Color(0xFF3E6FB8),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Custom App Bar
                  _buildSliverAppBar(),

                  // Content
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),

                        // Welcome Section
                        _buildWelcomeSection(),

                        const SizedBox(height: 24),

                        // Banner Carousel
                        _buildModernCarousel(),

                        const SizedBox(height: 20),

                        // Quick Stats Overview Cards
                        _buildQuickStatsGrid(),

                        const SizedBox(height: 24),

                        // Vehicle Selector Card
                        _buildVehicleSelectorCard(),

                        const SizedBox(height: 24),

                        // Live Status Card
                        _buildLiveStatusCard(),

                        const SizedBox(height: 24),


                        // Vehicle Mileage Chart
                        _buildMileageChartCard(),

                        const SizedBox(height: 24),

                        // Vehicle Summary Card
                        _buildVehicleSummaryCard(),

                        const SizedBox(height: 24),

                        // Subscription Status Card
                        _buildSubscriptionStatusCard(),

                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      floating: true,
      snap: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      toolbarHeight: 70,
      automaticallyImplyLeading: false,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF3E6FB8),
              const Color(0xFF5C8ACF),
            ],
          ),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3E6FB8).withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Image.asset(
                      'images/logo.png',
                      height: 28,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.directions_car,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GPS Pro',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Obx(() => Text(
                        '${homeController.dataController.allCount.value} Vehicles',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      )),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  _buildAppBarButton(
                    Icons.notifications_outlined,
                    onTap: () {
                      Get.snackbar(
                        'Notifications',
                        'No new notifications',
                        snackPosition: SnackPosition.TOP,
                        backgroundColor: Colors.white,
                        colorText: Colors.black87,
                      );
                    },
                    badgeCount: 3,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBarButton(IconData icon,
      {required VoidCallback onTap, int? badgeCount}) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 22,
            ),
          ),
          if (badgeCount != null && badgeCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _getGreeting(),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Dashboard',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF22C55E),
                      const Color(0xFF16A34A),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Live',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning 👋';
    if (hour < 17) return 'Good Afternoon 👋';
    return 'Good Evening 👋';
  }

  Widget _buildQuickStatsGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Obx(() {
        final dataController = homeController.dataController;

        // Calculate stop count
        int stopCount = 0;
        for (var device in dataController.onlyDevices) {
          if (_getDeviceStatus(device) == 'stop') {
            stopCount++;
          }
        }

        return Column(
          children: [
            // First Row - All and Running
            Row(
              children: [
                Expanded(
                  child: _buildModernStatCard(
                    icon: Icons.apps_rounded,
                    title: "All Vehicles",
                    value: dataController.allCount.value.toString(),
                    subtitle: "Total fleet",
                    gradient: [
                      const Color(0xFF5B8DEE),
                      const Color(0xFF3E6FB8),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildModernStatCard(
                    icon: Icons.directions_car_filled_rounded,
                    title: "Running",
                    value: dataController.movingCount.value.toString(),
                    subtitle: "On the move",
                    gradient: [
                      const Color(0xFF22C55E),
                      const Color(0xFF16A34A),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Second Row - Idle, Stop, Offline
            Row(
              children: [
                Expanded(
                  child: _buildCompactStatCard(
                    icon: Icons.pause_circle_filled_rounded,
                    title: "Idle",
                    value: dataController.idleCount.value.toString(),
                    color: const Color(0xFFF59E0B),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildCompactStatCard(
                    icon: Icons.local_parking_rounded,
                    title: "Stop",
                    value: stopCount.toString(),
                    color: const Color(0xFF3B82F6),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildCompactStatCard(
                    icon: Icons.power_off_rounded,
                    title: "Offline",
                    value: dataController.offlineCount.value.toString(),
                    color: const Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }

  String _getDeviceStatus(DeviceItem device) {
    double speed = double.tryParse(device.speed?.toString() ?? '0') ?? 0;
    String? iconColor = device.iconColor?.toLowerCase();

    if (iconColor == "red") return 'offline';
    if (iconColor == "green" && speed > 0) return 'running';
    if (iconColor == "yellow") return 'idle';
    if (iconColor == "green" && speed == 0) {
      String? stopDuration = device.stopDuration;
      if (stopDuration != null && stopDuration.isNotEmpty) {
        return 'stop';
      }
      return 'idle';
    }
    return 'offline';
  }

  Widget _buildModernStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required List<Color> gradient,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withValues(alpha: 0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Live',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernCarousel() {
    return CarouselSlider(
      options: CarouselOptions(
        height: 170.0,
        autoPlay: true,
        enlargeCenterPage: true,
        viewportFraction: 0.9,
        autoPlayInterval: const Duration(seconds: 4),
        autoPlayAnimationDuration: const Duration(milliseconds: 800),
        autoPlayCurve: Curves.fastOutSlowIn,
      ),
      items: BANNER_IMAGE.map((url) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.image, size: 50, color: Colors.grey),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildVehicleSelectorCard() {
    return Obx(() {
      final vehicleList = homeController.dataController.onlyDevices;
      final selectedDevice = homeController.selectedDevice;
      final selectedDeviceId = homeController.selectedDeviceId.value;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF667EEA),
                      const Color(0xFF764BA2),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.directions_car,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Vehicle',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${vehicleList.length} vehicles available',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selectedDevice != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getStatusColorByDevice(selectedDevice),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getStatusText(selectedDevice),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Dropdown
              Padding(
                padding: const EdgeInsets.all(20),
                child: vehicleList.isEmpty
                    ? _buildEmptyVehicleState()
                    : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFE2E8F0),
                          width: 1.5,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: selectedDeviceId == 0
                              ? null
                              : selectedDeviceId,
                          hint: Row(
                            children: [
                              Icon(Icons.search,
                                  size: 20, color: Colors.grey[500]),
                              const SizedBox(width: 10),
                              Text(
                                "Choose a vehicle...",
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF667EEA)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Color(0xFF667EEA),
                            ),
                          ),
                          items: vehicleList.map((device) {
                            return DropdownMenuItem<int>(
                              value: device.id,
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color:
                                      _getStatusColorByDevice(device)
                                          .withValues(alpha: 0.15),
                                      borderRadius:
                                      BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: _getStatusColorByDevice(
                                              device),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                      MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          device.name ??
                                              'Unnamed Vehicle',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          _getStatusText(device),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: _getStatusColorByDevice(
                                                device),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (deviceId) {
                            if (deviceId != null) {
                              homeController.onVehicleChanged(deviceId);
                            }
                          },
                        ),
                      ),
                    ),

                    // Selected Vehicle Info
                    if (selectedDevice != null) ...[
                      const SizedBox(height: 16),
                      _buildSelectedVehicleInfo(selectedDevice),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildEmptyVehicleState() {
    return Container(
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 60,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No vehicles available',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add vehicles to get started',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedVehicleInfo(DeviceItem device) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getStatusColorByDevice(device).withValues(alpha: 0.1),
            _getStatusColorByDevice(device).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getStatusColorByDevice(device).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          // Vehicle Icon
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: _getStatusColorByDevice(device).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: device.icon?.path != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl:
                "${UserRepository.getServerUrl()}/${device.icon!.path!}",
                fit: BoxFit.contain,
                errorWidget: (context, url, error) => Icon(
                  Icons.directions_car,
                  color: _getStatusColorByDevice(device),
                  size: 28,
                ),
              ),
            )
                : Icon(
              Icons.directions_car,
              color: _getStatusColorByDevice(device),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name ?? 'Unnamed',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.speed,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${device.speed ?? 0} km/h',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        device.stopDuration ?? 'Active',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getStatusColorByDevice(device),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _getStatusText(device),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColorByDevice(DeviceItem device) {
    String status = _getDeviceStatus(device);
    switch (status) {
      case 'running':
        return const Color(0xFF22C55E);
      case 'idle':
        return const Color(0xFFF59E0B);
      case 'stop':
        return const Color(0xFF3B82F6);
      case 'offline':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(DeviceItem device) {
    String status = _getDeviceStatus(device);
    switch (status) {
      case 'running':
        return 'Running';
      case 'idle':
        return 'Idle';
      case 'stop':
        return 'Stopped';
      case 'offline':
        return 'Offline';
      default:
        return 'Unknown';
    }
  }

  Widget _buildMileageChartCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF9800),
                    Color(0xFFFF5722),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.show_chart_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mileage Analytics',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Weekly distance traveled',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '7 Days',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Chart Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: _buildVehicleMileageChart(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleMileageChart() {
    return Obx(() {
      final mileageData = homeController.mileageData;
      final isLoading = homeController.isLoadingMileage.value;
      final selectedDevice = homeController.selectedDevice;

      if (isLoading) {
        return const SizedBox(
          height: 200,
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
            ),
          ),
        );
      }

      if (mileageData.isEmpty) {
        return SizedBox(
          height: 200,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bar_chart, size: 60, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text(
                  selectedDevice == null
                      ? "Select a vehicle to view mileage"
                      : "No mileage data available",
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
              ],
            ),
          ),
        );
      }

      return Column(
        children: [
          // Date Range
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 16, color: Color(0xFFFF9800)),
                const SizedBox(width: 8),
                Text(
                  homeController.getFormattedDateRange(),
                  style: const TextStyle(
                    color: Color(0xFFE65100),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Chart
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => const Color(0xFF1E293B),
                    tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    tooltipMargin: 10,
                    tooltipBorderRadius: BorderRadius.circular(12),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${rod.toY.toInt()} km',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      );
                    },
                  ),
                ),
                alignment: BarChartAlignment.spaceAround,
                maxY: _getMaxY(mileageData),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: _getInterval(mileageData),
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey.shade200,
                      strokeWidth: 1,
                      dashArray: [5, 5],
                    );
                  },
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toInt()}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        int index = value.toInt();
                        if (index < mileageData.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              mileageData[index].dayLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(mileageData.length, (index) {
                  final data = mileageData[index];
                  final displayDistance =
                  homeController.isDummyMileageData.value
                      ? 0.0
                      : data.distance;

                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: displayDistance,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF9800), Color(0xFFFFB74D)],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                        width: 24,
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      );
    });
  }

  double _getMaxY(List<MileageData> data) {
    if (data.isEmpty) return 400;
    final maxValue =
    data.map((e) => e.distance).reduce((a, b) => a > b ? a : b);
    final roundedMax = ((maxValue / 100).ceil() + 1) * 100;
    return roundedMax.toDouble();
  }

  double _getInterval(List<MileageData> data) {
    final maxY = _getMaxY(data);
    return maxY / 4;
  }

  Widget _buildVehicleSummaryCard() {
    return Obx(() {
      final isLoading = homeController.isLoadingReport.value;
      final todayData = homeController.todayReport.value;
      final selectedDevice = homeController.selectedDevice;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF3E6FB8),
                      const Color(0xFF5C8ACF),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.insert_chart_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Vehicle Summary',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            selectedDevice?.name ?? "Select a vehicle",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Today',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Stats Grid
              Padding(
                padding: const EdgeInsets.all(16),
                child: isLoading
                    ? const SizedBox(
                  height: 300,
                  child: Center(child: CircularProgressIndicator()),
                )
                    : selectedDevice == null
                    ? _buildNoVehicleSelectedState()
                    : Column(
                  children: [
                    // First Row - 2 Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryStatCard(
                            icon: "assets/icons/route-length.png",
                            fallbackIcon: Icons.route,
                            title: "Route Length",
                            value: todayData?.routeLength ?? '0 Km',
                            color: const Color(0xFF5B8DEE),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSummaryStatCard(
                            icon: "assets/icons/speed.png",
                            fallbackIcon: Icons.speed,
                            title: "Top Speed",
                            value: todayData?.topSpeed ?? '0 kph',
                            color: const Color(0xFFFF9800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Second Row - 2 Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryStatCard(
                            icon: "assets/icons/hourglass-start.png",
                            fallbackIcon: Icons.play_circle,
                            title: "Move Duration",
                            value:
                            todayData?.moveDuration ?? '0h 0min',
                            color: const Color(0xFF22C55E),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSummaryStatCard(
                            icon: "assets/icons/hourglass-end.png",
                            fallbackIcon: Icons.pause_circle,
                            title: "Stop Duration",
                            value:
                            todayData?.stopDuration ?? '0h 0min',
                            color: const Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Third Row - 2 Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryStatCard(
                            icon: "assets/icons/speed-average.png",
                            fallbackIcon: Icons.analytics,
                            title: "Avg Speed",
                            value:
                            todayData?.averageSpeed ?? '0 kph',
                            color: const Color(0xFF9D4EDD),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSummaryStatCard(
                            icon: "assets/icons/engine_hours.png",
                            fallbackIcon: Icons.settings,
                            title: "Engine Hours",
                            value:
                            todayData?.engineHours ?? '0h 0min',
                            color: const Color(0xFF06D6A0),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Divider
                    Container(
                      height: 1,
                      color: Colors.grey[200],
                    ),
                    const SizedBox(height: 16),

                    // Additional Stats List
                    _buildDetailStatRow(
                      icon: Icons.engineering,
                      title: "Engine Works",
                      value: todayData?.engineWork ?? '0h 0min',
                      color: const Color(0xFF118AB2),
                    ),
                    _buildDetailStatRow(
                      icon: Icons.hourglass_empty,
                      title: "Engine Idle",
                      value: todayData?.engineIdle ?? '0h 0min',
                      color: const Color(0xFFEF476F),
                    ),
                    _buildDetailStatRow(
                      icon: Icons.warning_amber,
                      title: "Overspeed Count",
                      value: todayData?.overspeedCount ?? '0',
                      color: const Color(0xFFFF6B6B),
                    ),
                    _buildDetailStatRow(
                      icon: Icons.local_gas_station,
                      title: "Fuel Consumption",
                      value:
                      selectedDevice.deviceData?.fuelQuantity ??
                          '0.00 L',
                      color: const Color(0xFF26547C),
                    ),
                    _buildDetailStatRow(
                      icon: Icons.straighten,
                      title: "Total Distance",
                      value:
                      "${selectedDevice.totalDistance?.toStringAsFixed(2) ?? '0.00'} Km",
                      color: const Color(0xFF5B8DEE),
                      isLast: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildNoVehicleSelectedState() {
    return SizedBox(
      height: 250,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.directions_car_outlined,
                size: 50,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Vehicle Selected',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a vehicle to view summary',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStatCard({
    required String icon,
    required IconData fallbackIcon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.asset(
              icon,
              width: 22,
              height: 22,
              color: color,
              errorBuilder: (context, error, stackTrace) => Icon(
                fallbackIcon,
                size: 22,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailStatRow({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: Colors.grey[200],
          ),
      ],
    );
  }

  Widget _buildLiveStatusCard() {
    return Obx(() {
      final selectedDevice = homeController.selectedDevice;

      if (selectedDevice == null) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _getStatusColorByDevice(selectedDevice),
                _getStatusColorByDevice(selectedDevice).withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _getStatusColorByDevice(selectedDevice).withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.gps_fixed,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Live Status',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            selectedDevice.name ?? 'Vehicle',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _getStatusColorByDevice(selectedDevice),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _getStatusText(selectedDevice),
                            style: TextStyle(
                              color: _getStatusColorByDevice(selectedDevice),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Live Stats Row
                Row(
                  children: [
                    _buildLiveStatItem(
                      icon: Icons.speed,
                      value: '${selectedDevice.speed ?? 0}',
                      unit: 'km/h',
                      label: 'Speed',
                    ),
                    _buildLiveStatDivider(),
                    _buildLiveStatItem(
                      icon: Icons.explore,
                      value: '${selectedDevice.course ?? 0}°',
                      unit: '',
                      label: 'Course',
                    ),
                    _buildLiveStatDivider(),
                    _buildLiveStatItem(
                      icon: Icons.timer,
                      value: selectedDevice.stopDuration ?? '-',
                      unit: '',
                      label: 'Stop Time',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildLiveStatItem({
    required IconData icon,
    required String value,
    required String unit,
    required String label,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.8),
            size: 22,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (unit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, left: 2),
                  child: Text(
                    unit,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatDivider() {
    return Container(
      height: 50,
      width: 1,
      color: Colors.white.withValues(alpha: 0.3),
    );
  }

  Widget _buildSubscriptionStatusCard() {
    return Obx(() {
      final totalVehicles = homeController.totalVehicles.value;
      final paidVehicles = homeController.paidVehicles.value;
      final dueVehicles = homeController.dueVehicles.value;
      final isLoading = homeController.isLoadingSubscription.value;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF8B5CF6),
                      const Color(0xFFA78BFA),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.card_membership_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Subscription Status',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (dueVehicles > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$dueVehicles Due',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: isLoading
                    ? const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                )
                    : Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Pie Chart
                        if (totalVehicles > 0)
                          SizedBox(
                            width: 140,
                            height: 140,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                PieChart(
                                  PieChartData(
                                    sectionsSpace: 4,
                                    centerSpaceRadius: 45,
                                    sections: [
                                      PieChartSectionData(
                                        color: const Color(0xFF22C55E),
                                        value: paidVehicles.toDouble(),
                                        title: '',
                                        radius: 25,
                                      ),
                                      if (dueVehicles > 0)
                                        PieChartSectionData(
                                          color: const Color(0xFFEF4444),
                                          value: dueVehicles.toDouble(),
                                          title: '',
                                          radius: 25,
                                        ),
                                    ],
                                  ),
                                ),
                                Column(
                                  mainAxisAlignment:
                                  MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      totalVehicles.toString(),
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      'Total',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )
                        else
                          SizedBox(
                            width: 140,
                            height: 140,
                            child: Center(
                              child: Text(
                                "No Data",
                                style:
                                TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                          ),

                        const SizedBox(width: 24),

                        // Stats
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSubscriptionLegend(
                                color: const Color(0xFF5B8DEE),
                                label: "Total Vehicles",
                                value: totalVehicles.toString(),
                                icon: Icons.directions_car,
                              ),
                              const SizedBox(height: 14),
                              _buildSubscriptionLegend(
                                color: const Color(0xFF22C55E),
                                label: "Active",
                                value: paidVehicles.toString(),
                                icon: Icons.check_circle,
                              ),
                              const SizedBox(height: 14),
                              _buildSubscriptionLegend(
                                color: const Color(0xFFEF4444),
                                label: "Inactive",
                                value: dueVehicles.toString(),
                                icon: Icons.cancel,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            label: "Pay Now",
                            icon: Icons.payment_rounded,
                            onPressed: () {
                              Get.snackbar(
                                "Payment",
                                "Payment feature coming soon!",
                                snackPosition: SnackPosition.BOTTOM,
                                backgroundColor: const Color(0xFF8B5CF6),
                                colorText: Colors.white,
                              );
                            },
                            isPrimary: true,
                            gradientColors: [
                              const Color(0xFF8B5CF6),
                              const Color(0xFFA78BFA),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionButton(
                            label: "View All",
                            icon: Icons.list_alt_rounded,
                            onPressed: () => _showVehicleStatusDialog(),
                            isPrimary: false,
                            borderColor: const Color(0xFF8B5CF6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildSubscriptionLegend({
    required Color color,
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required bool isPrimary,
    List<Color>? gradientColors,
    Color? borderColor,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: isPrimary && gradientColors != null
            ? LinearGradient(colors: gradientColors)
            : null,
        color: isPrimary ? null : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: !isPrimary && borderColor != null
            ? Border.all(color: borderColor, width: 2)
            : null,
        boxShadow: isPrimary
            ? [
          BoxShadow(
            color: (gradientColors?.first ?? Colors.blue).withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ]
            : null,
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isPrimary ? Colors.white : borderColor,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isPrimary ? Colors.white : borderColor,
              ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 500, maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF3E6FB8),
                      const Color(0xFF5C8ACF),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.list_alt_rounded,
                          color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Vehicle Status',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Get.back(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  shrinkWrap: true,
                  itemCount: vehicles.length,
                  separatorBuilder: (context, index) =>
                  const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final vehicle = vehicles[index];
                    final status = _getDeviceStatus(vehicle);
                    final statusColor = _getStatusColorByDevice(vehicle);

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.directions_car,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vehicle.name ?? 'Unnamed Vehicle',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${vehicle.speed ?? 0} km/h',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: statusColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _getStatusText(vehicle),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
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