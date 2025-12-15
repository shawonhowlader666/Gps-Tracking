import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import 'package:gpspro/config.dart';
import 'package:gpspro/screens/home/home_controller.dart';
import 'package:gpspro/services/model/device.dart' hide Icon;
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/services/payment_service.dart';
import 'package:gpspro/screens/payment_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

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

  @override
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
                  if (_timeLeft != null)
                    Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.timer, color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(_timeLeft!),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Payment Button
                  _buildAppBarButton(
                    Icons.payment,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => PaymentListScreen()),
                      );
                    },
                  ),
                  const SizedBox(width: 12),

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
                  child: _buildModernStatCard(
                    icon: Icons.access_time_filled_rounded,
                    title: "Idle",
                    value: dataController.idleCount.value.toString(),
                    subtitle: "Engine on",
                    gradient: [
                      const Color(0xFFF59E0B),
                      const Color(0xFFD97706),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildModernStatCard(
                    icon: Icons.stop_circle_rounded,
                    title: "Stopped",
                    value: stopCount.toString(),
                    subtitle: "Engine off",
                    gradient: [
                      const Color(0xFFEF4444),
                      const Color(0xFFDC2626),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildModernStatCard(
                    icon: Icons.wifi_off_rounded,
                    title: "Offline",
                    value: dataController.offlineCount.value.toString(),
                    subtitle: "No signal",
                    gradient: [
                      const Color(0xFF64748B),
                      const Color(0xFF475569),
                    ],
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
    if (device.online!.contains('online')) {
      return 'online';
    } else if (device.online!.contains('ack')) {
      return 'ack';
    } else {
      if (double.parse(device.speed.toString()) > 0) {
        return 'online';
      } else {
        return 'stop';
      }
    }
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
            color: gradient[0].withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernCarousel() {
    return CarouselSlider(
      options: CarouselOptions(
        height: 160.0,
        autoPlay: true,
        enlargeCenterPage: true,
        viewportFraction: 0.9,
        aspectRatio: 2.0,
        initialPage: 0,
      ),
      items: [1, 2, 3].map((i) {
        return Builder(
          builder: (BuildContext context) {
            return Container(
              width: MediaQuery.of(context).size.width,
              margin: const EdgeInsets.symmetric(horizontal: 5.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                image: const DecorationImage(
                  image: AssetImage('assets/images/banner.png'),
                  fit: BoxFit.cover,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3E6FB8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Premium Features',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Track Your Fleet Real-Time',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }

  Widget _buildVehicleSelectorCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.local_shipping_outlined,
                          color: Color(0xFF3E6FB8),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Your Vehicles',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('View All'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 120,
              child: Obx(() {
                if (homeController.dataController.onlyDevices.isEmpty) {
                  return const Center(child: Text("No vehicles found"));
                }
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: homeController.dataController.onlyDevices.length,
                  itemBuilder: (context, index) {
                    final device = homeController.dataController.onlyDevices[index];
                    return _buildVehicleItem(device);
                  },
                );
              }),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleItem(DeviceItem device) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Container(
            height: 70,
            width: 70,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            ),
            child: Center(
              child: Image.asset(
                "assets/images/car_icon.png", // Make sure this asset exists
                height: 40,
                errorBuilder: (ctx, err, stack) => Icon(Icons.directions_car, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            device.name ?? "Unknown",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            _getDeviceStatus(device).toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              color: _getDeviceStatus(device) == 'online' || _getDeviceStatus(device) == 'ack'
                  ? Colors.green
                  : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatusCard() {
    // Placeholder implementation
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.map, color: Colors.blue),
                SizedBox(width: 10),
                Text("Live Map", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(height: 20),
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text("Map Preview")),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildMileageChartCard() {
    return const SizedBox(); // Placeholder
  }

  Widget _buildVehicleSummaryCard() {
    return const SizedBox(); // Placeholder
  }

  Widget _buildSubscriptionStatusCard() {
    return const SizedBox(); // Placeholder
  }
}