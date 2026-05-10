import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import 'package:smart_lock/constants/app_constants.dart';
import 'package:smart_lock/screens/home/home_controller.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
import 'data_controller/data_controller.dart';

// ─── Status enum (matches DevicePage) ───────────────────────────────────────
enum VehicleStatus { running, idle, stop, offline, inactive, expired }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HomeController homeController = Get.put(HomeController());
  late final DataController dataController;

  Timer? _statusRefreshTimer;

  final RxInt _runningCount  = 0.obs;
  final RxInt _idleCount     = 0.obs;
  final RxInt _stopCount     = 0.obs;
  final RxInt _offlineCount  = 0.obs;
  final RxInt _inactiveCount = 0.obs;
  final RxInt _expiredCount  = 0.obs;

  // Slider
  final PageController _sliderController = PageController();
  int _currentSlide = 0;
  Timer? _sliderTimer;

  final List<String> _sliderImages = [
    'assets/images/banner1.png',
    'assets/images/banner2.png',
    'assets/images/banner3.png',
  ];

  static const Color successColor  = Color(0xFF22C55E);
  static const Color warningColor  = Color(0xFFF59E0B);
  static const Color dangerColor   = Color(0xFFEF4444);
  static const Color neutralColor  = Color(0xFF9CA3AF);
  static const Color darkColor     = Color(0xFF374151);

  @override
  void initState() {
    super.initState();
    dataController = Get.put(DataController(), permanent: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _calculateStatusCounts();
        _startStatusRefresh();
        _startSliderAutoPlay();
      }
    });
  }

  void _startStatusRefresh() {
    _statusRefreshTimer?.cancel();
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _calculateStatusCounts();
    });
  }

  void _startSliderAutoPlay() {
    _sliderTimer?.cancel();
    _sliderTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final next = (_currentSlide + 1) % _sliderImages.length;
      _sliderController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  void _calculateStatusCounts() {
    if (!mounted) return;
    final vehicles = dataController.onlyDevices;
    int running = 0, idle = 0, stop = 0, offline = 0, inactive = 0, expired = 0;

    for (final device in vehicles) {
      switch (_getVehicleStatus(device)) {
        case VehicleStatus.running:  running++;  break;
        case VehicleStatus.idle:     idle++;     break;
        case VehicleStatus.stop:     stop++;     break;
        case VehicleStatus.offline:  offline++;  break;
        case VehicleStatus.inactive: inactive++; break;
        case VehicleStatus.expired:  expired++;  break;
      }
    }

    _runningCount.value  = running;
    _idleCount.value     = idle;
    _stopCount.value     = stop;
    _offlineCount.value  = offline;
    _inactiveCount.value = inactive;
    _expiredCount.value  = expired;
  }

  @override
  void dispose() {
    _statusRefreshTimer?.cancel();
    _sliderTimer?.cancel();
    _sliderController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════
  //  STATUS DETECTION  (copied 1-to-1 from DevicePage)
  // ══════════════════════════════════════════════════════

  VehicleStatus _getVehicleStatus(DeviceItem device) {
    if (_isExpired(device))       return VehicleStatus.expired;
    if (_isInactive(device))      return VehicleStatus.inactive;
    if (!_isDeviceOnline(device)) return VehicleStatus.offline;

    final speed = double.tryParse(device.speed.toString()) ?? 0;
    if (speed > 0) return VehicleStatus.running;
    return _isEngineOn(device) ? VehicleStatus.idle : VehicleStatus.stop;
  }

  bool _isDeviceOnline(DeviceItem device) {
    final online = device.online?.toLowerCase().trim() ?? '';
    if (online.contains('offline')) return false;
    if (online.contains('online'))  return true;

    final iconColor = device.iconColor?.toLowerCase().trim() ?? '';
    if (iconColor == 'green' || iconColor == 'yellow') return true;

    if (device.timestamp != null && device.timestamp! > 0) {
      final lastUpdate =
      DateTime.fromMillisecondsSinceEpoch(device.timestamp! * 1000);
      if (DateTime.now().difference(lastUpdate).inMinutes < 5) return true;
    }

    final speed = double.tryParse(device.speed.toString()) ?? 0;
    return speed > 0;
  }

  bool _isEngineOn(DeviceItem device) {
    if (device.engineStatus != null) {
      final status = device.engineStatus;
      if (status is bool)   return status;
      if (status is int)    return status == 1;
      if (status is String) {
        final s = status.toLowerCase().trim();
        if (['on', '1', 'true', 'ign on', 'engine on', 'acc on'].contains(s))    return true;
        if (['off', '0', 'false', 'ign off', 'engine off', 'acc off'].contains(s)) return false;
      }
    }

    if (device.sensors != null) {
      for (var sensor in device.sensors!) {
        try {
          final type  = (sensor['type']  ?? '').toString().toLowerCase();
          final name  = (sensor['name']  ?? '').toString().toLowerCase();
          final value =  sensor['value'];
          if (type == 'acc' || type == 'ignition' || type == 'engine' ||
              name.contains('ignition') || name.contains('acc') ||
              name.contains('engine')) {
            if (value == null) continue;
            if (value is bool)   return value;
            if (value is int)    return value == 1;
            if (value is String) {
              final v = value.toLowerCase().trim();
              if (['on', '1', 'true', 'ign on', 'acc on', 'engine on'].contains(v))    return true;
              if (['off', '0', 'false', 'ign off', 'acc off', 'engine off'].contains(v)) return false;
            }
          }
        } catch (_) {}
      }
    }

    final speed = double.tryParse(device.speed.toString()) ?? 0;
    if (speed > 0) return true;

    final iconColor = device.iconColor?.toLowerCase().trim() ?? '';
    return iconColor == 'yellow' || iconColor == 'green';
  }

  bool _isInactive(DeviceItem device) {
    if (device.deviceData == null) return false;
    final active = device.deviceData?.active;
    if (active == null) return false;
    return active == 0;
  }

  bool _isExpired(DeviceItem device) {
    try {
      final expiry = device.deviceData?.expirationDate?.toString();
      if (expiry == null || expiry.isEmpty) return false;
      final date = DateTime.tryParse(expiry);
      if (date == null) return false;
      return date.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  // ══════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          await homeController.refreshData();
          _calculateStatusCounts();
        },
        color: dangerColor,
        child: ListView(
          padding: const EdgeInsets.all(12),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildImageSlider(),
            const SizedBox(height: 16),
            RepaintBoundary(child: _buildStatusCard()),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      automaticallyImplyLeading: false,
      titleSpacing: 12,
      title: Row(
        children: [
          Image.asset(
            AppConstants.appIcon,
            height: 36,
            width: 36,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
            const Icon(Icons.apps, size: 36),
          ),
          const SizedBox(width: 40),
          Text(
            AppConstants.appName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
      actions: [
        Obx(() => _buildAppBarIcon(
          Icons.notifications_outlined,
              () {},
          badge: dataController.events.length,
        )),
        const SizedBox(width: 12),
      ],
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
                constraints:
                const BoxConstraints(minWidth: 18, minHeight: 18),
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

  // ── Image Slider ────────────────────────────────────────────────────────────
  Widget _buildImageSlider() {
    return Column(
      children: [
        Container(
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 2,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: PageView.builder(
              controller: _sliderController,
              itemCount: _sliderImages.length,
              onPageChanged: (index) =>
                  setState(() => _currentSlide = index),
              itemBuilder: (context, index) {
                return Image.asset(
                  _sliderImages[index],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[200],
                    child: Center(
                      child: Icon(
                        Icons.image_outlined,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _sliderImages.length,
                (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _currentSlide == index ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _currentSlide == index
                    ? dangerColor
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════
  //  VEHICLE STATUS CARD  (donut + legend)
  // ══════════════════════════════════════════════════════

  Widget _buildStatusCard() {
    return Obx(() {
      _calculateStatusCounts();

      final total    = dataController.onlyDevices.length;
      final running  = _runningCount.value;
      final idle     = _idleCount.value;
      final stopped  = _stopCount.value;
      final offline  = _offlineCount.value;
      final inactive = _inactiveCount.value;
      final expired  = _expiredCount.value;

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
            // ── Header ─────────────────────────────────
            Row(
              children: [
                const Icon(Icons.pie_chart,
                    color: dangerColor, size: 18),
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
                  '$total Total',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Chart + Legend row ──────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Donut chart
                SizedBox(
                  width: 160,
                  height: 160,
                  child: total == 0
                      ? _buildEmptyDonut()
                      : _buildDonut(
                    running: running,
                    idle: idle,
                    stopped: stopped,
                    offline: offline,
                    inactive: inactive,
                    expired: expired,
                    total: total,
                  ),
                ),

                const SizedBox(width: 20),

                // Legend
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLegendRow(
                          color: successColor,
                          label: 'Moving',
                          count: running),
                      const SizedBox(height: 8),
                      _buildLegendRow(
                          color: dangerColor,
                          label: 'Stopped',
                          count: stopped),
                      const SizedBox(height: 8),
                      _buildLegendRow(
                          color: warningColor,
                          label: 'Idle',
                          count: idle),
                      const SizedBox(height: 8),
                      _buildLegendRow(
                          color: neutralColor,
                          label: 'Offline',
                          count: offline),
                      const SizedBox(height: 8),
                      _buildLegendRow(
                          color: darkColor,
                          label: 'InActive',
                          count: inactive),
                      const SizedBox(height: 8),
                      _buildLegendRow(
                          color: Colors.black87,
                          label: 'Expired',
                          count: expired),
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

  // ── Donut chart ─────────────────────────────────────────────────────────────
  Widget _buildDonut({
    required int running,
    required int idle,
    required int stopped,
    required int offline,
    required int inactive,
    required int expired,
    required int total,
  }) {
    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 34,
            startDegreeOffset: -90,
            sections: _buildSections(
              running: running,
              idle: idle,
              stopped: stopped,
              offline: offline,
              inactive: inactive,
              expired: expired,
            ),
          ),
        ),
        // ── Center label (matches screenshot: "Total\n6") ──
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Total',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              total.toString(),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<PieChartSectionData> _buildSections({
    required int running,
    required int idle,
    required int stopped,
    required int offline,
    required int inactive,
    required int expired,
  }) {
    final entries = [
      _StatusEntry(color: successColor,  count: running,  label: ''),
      _StatusEntry(color: dangerColor,   count: stopped,  label: ''),
      _StatusEntry(color: warningColor,  count: idle,     label: ''),
      _StatusEntry(color: neutralColor,  count: offline,  label: ''),
      _StatusEntry(color: darkColor,     count: inactive, label: ''),
      _StatusEntry(color: Colors.black87, count: expired, label: ''),
    ].where((e) => e.count > 0).toList();

    // If nothing is non-zero, show grey placeholder
    if (entries.isEmpty) return _emptySection();

    return entries
        .map(
          (e) => PieChartSectionData(
        color: e.color,
        value: e.count.toDouble(),
        title: '',
        radius: 52,

      ),
    )
        .toList();
  }

  // ── Empty donut ─────────────────────────────────────────────────────────────
  Widget _buildEmptyDonut() {
    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sectionsSpace: 0,
            centerSpaceRadius: 44,
            sections: _emptySection(),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Total',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                    fontWeight: FontWeight.w500)),
            Text('0',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[400])),
          ],
        ),
      ],
    );
  }

  List<PieChartSectionData> _emptySection() => [
    PieChartSectionData(
        color: Colors.grey[200],
        value: 1,
        title: '',
        radius: 52),
  ];

  // ── Legend row (circle dot + label + count) ─────────────────────────────────
  //  Matches screenshot: ● Moving   1
  Widget _buildLegendRow({
    required Color color,
    required String label,
    required int count,
  }) {
    return Row(
      children: [
        // Circle dot — matches screenshot style
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            // slight border so pale colours are visible
            border: Border.all(
              color: color.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF374151),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          count.toString(),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151),
          ),
        ),
      ],
    );
  }
}

// ── Helper data class ──────────────────────────────────────────────────────────
class _StatusEntry {
  final Color color;
  final int count;
  final String label;
  const _StatusEntry(
      {required this.color, required this.count, required this.label});
}