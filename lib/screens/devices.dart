import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';
import 'package:smart_lock/screens/common_method.dart';
import 'package:smart_lock/screens/track_device.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
import 'package:smart_lock/services/model/single_device.dart';
import 'package:smart_lock/storage/user_repository.dart';
import '../constants/app_constants.dart';
import '../services/payment_service.dart';
import '../widgets/device_expired_dialog.dart';
import '../widgets/address.dart';

// ─── Status enum ────────────────────────────────────────────────────────────
enum DeviceStatus { running, idle, stop, offline, expired }

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  final RxDouble totalDue = 0.0.obs;

  SingleDevice? sd;
  int expiryTime = 10;
  int? selectedIconId;

  final DataController controller = Get.find<DataController>();
  bool _isDisposed = false;

  int _selectedFilterIndex = 0;

  // ── Brand colours ─────────────────────────────────────────────────────────
  static const Color _primaryRed  = Color(0xFFCC0000);
  static const Color _greenColor  = Color(0xFF22C55E);
  static const Color _yellowColor = Color(0xFFF59E0B);
  static const Color _redColor    = Color(0xFFEF4444);
  static const Color _greyColor   = Color(0xFF9CA3AF);
  static const Color _blueColor   = Color(0xFF3B82F6);
  static const Color _purpleColor = Color(0xFF7B3FF5);
  static const Color _orangeColor = Color(0xFFF97316);

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) setState(fn);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed) {
        _loadDevices();
        _loadDueAmount();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _searchFocusNode.dispose();
    _searchController.dispose();
    _name.dispose();
    super.dispose();
  }

  // ── Data helpers ──────────────────────────────────────────────────────────
  Future<void> _loadDueAmount() async {
    try {
      final stats = await PaymentService.getStats();
      if (stats != null && mounted && !_isDisposed) {
        totalDue.value = stats.due;
      }
    } catch (e) {
      debugPrint('Error loading due amount: $e');
    }
  }

  List<Map<String, dynamic>> _parseSensors(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return [];

    final result = <Map<String, dynamic>>[];

    for (final s in raw) {
      try {
        if (s is Map) {
          result.add(Map<String, dynamic>.from(s));
        }
      } catch (_) {}
    }

    return result;
  }

  bool _isValidSensorValue(String? val) {
    if (val == null) return false;
    final clean = val.trim();
    if (clean.isEmpty || clean == '-' || clean.toLowerCase() == 'n/a' || clean.toLowerCase() == 'null') {
      return false;
    }
    return true;
  }

  static final Map<String, String> _sensorMemoryCache = {};

  String _getSensorValue(dynamic deviceId, String name, String? currentValue) {
    final cleanName = name.toLowerCase().trim();
    String displayName = name;
    if (cleanName == 'engine statust') {
      displayName = 'Engine Status';
    }

    final cacheKey = 'sensor_${deviceId ?? 'unknown'}_${displayName.toLowerCase().replaceAll(' ', '_')}';

    if (_isValidSensorValue(currentValue)) {
      final valStr = currentValue!.trim();
      if (_sensorMemoryCache[cacheKey] != valStr) {
        _sensorMemoryCache[cacheKey] = valStr;
        UserRepository.prefs?.setString(cacheKey, valStr);
      }
      return valStr;
    }

    if (_sensorMemoryCache.containsKey(cacheKey)) {
      return _sensorMemoryCache[cacheKey]!;
    }

    final cached = UserRepository.prefs?.getString(cacheKey);
    if (cached != null && _isValidSensorValue(cached)) {
      _sensorMemoryCache[cacheKey] = cached;
      return cached;
    }

    // Fallbacks if no cache exists
    final resolvedName = displayName.toLowerCase();
    if (resolvedName.contains('battery')) {
      return '100';
    } else if (resolvedName.contains('voltage') ||
        resolvedName.contains('adc') ||
        resolvedName.contains('analog')) {
      return '54.4';
    } else if (resolvedName.contains('lock')) {
      return 'Off';
    } else if (resolvedName.contains('engine')) {
      return 'Off';
    }

    return currentValue ?? '-';
  }

  Widget _buildSensorRow(DeviceItem device) {
    final rawSensors = device.sensors?.isNotEmpty == true
        ? device.sensors!
        : (device.deviceData?.sensors ?? []);

    final sensors = _parseSensors(rawSensors);

    if (sensors.isEmpty) {
      return const SizedBox();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: sensors.map((sensor) {
            final rawName =
            (sensor['name'] ?? sensor['type'] ?? 'Sensor').toString();

            // Correct the Engine Statust typo
            String displayName = rawName;
            if (rawName.toLowerCase().trim() == 'engine statust') {
              displayName = 'Engine Status';
            }

            final rawValue = (sensor['value'] ?? '').toString();
            final value = _getSensorValue(device.id, displayName, rawValue);

            return Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.grey.shade300,
                ),
              ),
              child: Text(
                '$displayName : $value',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _loadDevices() {
    if (_isDisposed || !mounted) return;
    controller.getDevices();
  }

  // ── Status logic ──────────────────────────────────────────────────────────

  /// True if the device has sent a position in the last 5 minutes.
  bool _isDeviceOnline(DeviceItem device) {
    final online = device.online?.toLowerCase().trim() ?? '';
    if (online.contains('offline')) return false;
    if (online.contains('online'))  return true;

    final iconColor = device.iconColor?.toLowerCase().trim() ?? '';
    if (iconColor == 'green' || iconColor == 'yellow') return true;

    if (device.timestamp != null && device.timestamp! > 0) {
      try {
        final lastUpdate =
        DateTime.fromMillisecondsSinceEpoch(device.timestamp! * 1000);
        if (DateTime.now().difference(lastUpdate).inMinutes < 5) return true;
      } catch (_) {}
    }

    final speed = double.tryParse(device.speed.toString()) ?? 0;
    return speed > 0;
  }

  /// True if the ignition / ACC sensor is reported as ON.
  bool _isEngineOn(DeviceItem device) {
    // 1. explicit engineStatus field
    if (device.engineStatus != null) {
      final status = device.engineStatus;
      if (status is bool)   return status;
      if (status is int)    return status == 1;
      if (status is String) {
        final s = status.toLowerCase().trim();
        if (['on', '1', 'true', 'ign on', 'engine on', 'acc on'].contains(s))  return true;
        if (['off', '0', 'false', 'ign off', 'engine off', 'acc off'].contains(s)) return false;
      }
    }

    // 2. sensor array
    if (device.sensors != null) {
      for (final sensor in device.sensors!) {
        try {
          final type  = (sensor['type']  ?? '').toString().toLowerCase();
          final sName = (sensor['name']  ?? '').toString().toLowerCase();
          final value =  sensor['value'];
          final isIgnSensor = type == 'acc' || type == 'ignition' || type == 'engine' ||
              sName.contains('ignition') || sName.contains('acc') ||
              sName.contains('engine');
          if (!isIgnSensor || value == null) continue;
          if (value is bool)   return value;
          if (value is int)    return value == 1;
          if (value is String) {
            final v = value.toLowerCase().trim();
            if (['on', '1', 'true', 'ign on', 'acc on', 'engine on'].contains(v))  return true;
            if (['off', '0', 'false', 'ign off', 'acc off', 'engine off'].contains(v)) return false;
          }
        } catch (_) {}
      }
    }

    // 3. iconColor fallback
    final iconColor = device.iconColor?.toLowerCase().trim() ?? '';
    if (iconColor == 'yellow' || iconColor == 'green') return true;

    // 4. speed fallback — if moving, engine must be on
    final speed = double.tryParse(device.speed.toString()) ?? 0;
    return speed > 0;
  }


  /// Whether the device's subscription has expired.
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

  /// Main status resolver — priority order matters:
  ///   expired → inactive → offline → running → idle → stop
  DeviceStatus _getDeviceStatus(DeviceItem device) {
    if (_isExpired(device))  return DeviceStatus.expired;
    if (!_isDeviceOnline(device)) return DeviceStatus.offline;

    final speed = double.tryParse(device.speed.toString()) ?? 0;
    if (speed > 0) return DeviceStatus.running;        // Moving
    if (_isEngineOn(device)) return DeviceStatus.idle; // Engine ON, speed == 0
    return DeviceStatus.stop;                          // Engine OFF, speed == 0
  }

  void _searchDevices(String query) {
    if (_isDisposed || !mounted) return;
    setState(() {});
  }

  // ── UI helpers ────────────────────────────────────────────────────────────
  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.running:  return _greenColor;
      case DeviceStatus.idle:     return _yellowColor;
      case DeviceStatus.stop:     return _redColor;
      case DeviceStatus.offline:  return _greyColor;
      case DeviceStatus.expired:  return _orangeColor;
    }
  }

  String _getStatusText(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.running:  return 'Moving Since';
      case DeviceStatus.idle:     return 'Idle Since';
      case DeviceStatus.stop:     return 'Stop Since';
      case DeviceStatus.offline:  return 'Offline Since';
      case DeviceStatus.expired:  return 'Expired';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: _buildAppBar(),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFCC0000)));
        }

        final query = _searchController.text.toLowerCase().trim();
        List<DeviceItem> all = controller.onlyDevices.toList();
        if (query.isNotEmpty) {
          all = all.where((d) => (d.name?.toLowerCase() ?? '').contains(query)).toList();
        }

        List<DeviceItem> displayDevices;
        switch (_selectedFilterIndex) {
          case 1: // Moving
            displayDevices = all.where((d) => _getDeviceStatus(d) == DeviceStatus.running).toList();
            break;
          case 2: // Stopped
            displayDevices = all.where((d) => _getDeviceStatus(d) == DeviceStatus.stop).toList();
            break;
          case 3: // Idle
            displayDevices = all.where((d) => _getDeviceStatus(d) == DeviceStatus.idle).toList();
            break;
          case 4: // Offline
            displayDevices = all.where((d) => _getDeviceStatus(d) == DeviceStatus.offline).toList();
            break;
          case 5: // Expired
            displayDevices = all.where((d) => _getDeviceStatus(d) == DeviceStatus.expired).toList();
            break;
          default:
            displayDevices = all;
        }

        return Column(
          children: [
            if (controller.isSearchVisible.value) _buildSearchBar(),
            _buildFilterChips(all),
            Expanded(child: _buildDeviceList(displayDevices)),
          ],
        );
      }),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: Center(
        child: Image.asset(
          AppConstants.logoPath,
          height: 46,
          width: 126,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
          const Icon(Icons.apps, size: 36),
        ),
      ),
      actions: [
        Obx(() => IconButton(
          icon: Icon(Icons.search,
              color: controller.isSearchVisible.value
                  ? _primaryRed
                  : const Color(0xFF374151),
              size: 24),
          onPressed: controller.toggleSearchVisibility,
        )),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          hintText: 'search'.tr,
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          prefixIcon:
          Icon(Icons.search, color: Colors.grey[400], size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              _searchController.clear();
              _searchDevices('');
            },
          )
              : null,
          border: InputBorder.none,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        onChanged: _searchDevices,
      ),
    );
  }

  Widget _buildFilterChips(List<DeviceItem> allDevices) {
    int all = allDevices.length;
    int running = 0, idle = 0, stop = 0, offline = 0, expired = 0;
    for (final d in allDevices) {
      switch (_getDeviceStatus(d)) {
        case DeviceStatus.running:  running++;  break;
        case DeviceStatus.idle:     idle++;     break;
        case DeviceStatus.stop:     stop++;     break;
        case DeviceStatus.offline:  offline++;  break;
        case DeviceStatus.expired:  expired++;  break;
      }
    }

    return Container(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        child: SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildChip(0, 'All',      all,      _purpleColor),
              _buildChip(1, 'Moving',   running,  _greenColor),
              _buildChip(2, 'Stopped',  stop,     _redColor),
              _buildChip(3, 'Idle',     idle,     _yellowColor),
              _buildChip(4, 'Offline',  offline,  _redColor),
              _buildChip(5, 'Expired',  expired,  _orangeColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(int index, String label, int count, Color color) {
    final isSelected = _selectedFilterIndex == index;
    return GestureDetector(
      onTap: () {
        _searchController.clear();
        setState(() {
          _selectedFilterIndex = index;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6, offset: const Offset(0, 2))]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList(List<DeviceItem> displayDevices) {
    if (displayDevices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_car_outlined,
                size: 64, color: Colors.grey[300]),
            const Gap(16),
            Text('noDeviceFound'.tr,
                style:
                TextStyle(fontSize: 16, color: Colors.grey[500])),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: _primaryRed,
      onRefresh: () async => _loadDevices(),
      child: ListView.builder(
        padding:
        const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        itemCount: displayDevices.length,
        itemBuilder: (context, index) {
          final device = displayDevices[index];
          return Column(
            children: [
              _buildDeviceCard(device),
              const Gap(10),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDeviceCard(DeviceItem device) {
    final status      = _getDeviceStatus(device);
    final statusColor = _getStatusColor(status);
    final statusText  = _getStatusText(status);

    return GestureDetector(
      onTap: () {
        if (_isExpired(device)) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => DeviceExpiredBlockingDialog(device: device),
          );
        } else {
          Get.to(() => TrackDevicePage(device.id, device.name, device));
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Left: icon + speed ──────────────────────────────────
              SizedBox(
                width: 72,
                child: Column(
                  children: [
                    SizedBox(
                      width: 58,
                      height: 58,
                      child: device.icon?.path != null
                          ? Image(
                        image: CachedNetworkImageProvider(
                          "${UserRepository.getServerUrl()}/${device.icon!.path!}",
                        ),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.directions_car,
                            size: 40,
                            color: statusColor),
                      )
                          : Icon(Icons.directions_car,
                          size: 40, color: statusColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getSpeedValue(device, status),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                        height: 1,
                      ),
                    ),
                    Text(
                      'KM/H',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Right: info rows ────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: vehicle icon + name
                    Row(
                      children: [
                        device.icon?.path != null
                            ? Image(
                          width: 15,
                          height: 16,
                          image: CachedNetworkImageProvider(
                            "${UserRepository.getServerUrl()}/${device.icon!.path!}",
                          ),
                          fit: BoxFit.fill,
                          errorBuilder: (_, __, ___) => Icon(
                              Icons.directions_car,
                              size: 16,
                              color: statusColor),
                        )
                            : Icon(Icons.directions_car,
                            size: 16, color: statusColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            device.name ??
                                device.deviceData?.imei ??
                                '',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: statusColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.only(left: 19),
                      child: Text(
                        'IMEI: ${device.imei ?? device.deviceData?.imei ?? 'N/A'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    _dotDivider(),

                    // Row 2: status dot + duration
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '$statusText  ${_getStatusDuration(device, status)}',
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF374151)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    _dotDivider(),

                    // Row 3: subscription status (remaining days / unlimited)
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 14,
                            color: _getRemainingColor(device)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _getRemainingText(device),
                            style: TextStyle(
                              fontSize: 13,
                              color: _getRemainingColor(device),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    _dotDivider(),

                    // Row 5: location address
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 14,
                            color: _blueColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: (device.lat == null || device.lng == null)
                              ? const Text(
                                  'Address not available',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF374151),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : addressLoad(
                                  device.lat.toString(),
                                  device.lng.toString(),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF374151),
                                  ),
                                ),
                        ),
                      ],
                    ),

                    _dotDivider(),

                    _buildSensorRow(device),
                  ],
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  Widget _dotDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Column(
        children: List.generate(
          2,
              (i) => Container(
            width: 2,
            height: 2,
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: const BoxDecoration(
                color: Colors.black45, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }

  // ── Value helpers ─────────────────────────────────────────────────────────
  String _getSpeedValue(DeviceItem device, DeviceStatus status) {
    if (status == DeviceStatus.running) {
      final speed = double.tryParse(device.speed.toString()) ?? 0;
      return speed.toInt().toString();
    }
    return '0';
  }

  String _getStatusDuration(DeviceItem device, DeviceStatus status) {
    switch (status) {
      case DeviceStatus.running:
        return convertSpeed(
            device.speed, device.distanceUnitHour ?? 'km/h');
      case DeviceStatus.idle:
        return device.stopDuration ?? '0s';
      case DeviceStatus.stop:
        return device.stopDuration ?? '0s';
      case DeviceStatus.offline:
        return _getOfflineDuration(device);
      case DeviceStatus.expired:
        return 'Subscription Expired';
    }
  }

  String _getOfflineDuration(DeviceItem device) {
    if (device.timestamp == null || device.timestamp == 0) return 'Unknown';
    try {
      final lastUpdate =
      DateTime.fromMillisecondsSinceEpoch(device.timestamp! * 1000);
      final d = DateTime.now().difference(lastUpdate);
      if (d.inDays > 0)  return '${d.inDays * 24 + d.inHours % 24}h ${d.inMinutes % 60}m ${d.inSeconds % 60}s';
      if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m ${d.inSeconds % 60}s';
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    } catch (_) {
      return 'Unknown';
    }
  }

  String _getRemainingText(DeviceItem device) {
    try {
      final expiry = device.deviceData?.expirationDate?.toString();
      if (expiry == null || expiry.isEmpty) return 'Unlimited';
      final date = DateTime.tryParse(expiry);
      if (date == null) return 'Unlimited';
      final diff = date.difference(DateTime.now());
      if (diff.inDays < 0)  return 'Expired';
      if (diff.inDays == 0) return 'Expires Today';
      return '${diff.inDays} Days Remaining';
    } catch (_) {
      return 'Unlimited';
    }
  }

  Color _getRemainingColor(DeviceItem device) {
    try {
      final expiry = device.deviceData?.expirationDate?.toString();
      if (expiry == null || expiry.isEmpty) return _greenColor;
      final date = DateTime.tryParse(expiry);
      if (date == null) return _greenColor;
      final diff = date.difference(DateTime.now());
      if (diff.inDays <= 7) return _redColor;
      return _greenColor;
    } catch (_) {
      return _greenColor;
    }
  }
}