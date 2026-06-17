import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';
import 'package:gpspro/flutter_flow/flutter_flow_util.dart';
import 'package:gpspro/screens/common_method.dart';
import 'package:gpspro/screens/lock_unlock_screen.dart';
import 'package:gpspro/screens/payment_list.dart';
import 'package:gpspro/screens/playback.dart';
import 'package:gpspro/screens/report/report_screen.dart';
import 'package:gpspro/screens/street_view_screen.dart';
import 'package:gpspro/screens/track_device.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/admob_service.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/services/model/share_perm.dart';
import 'package:gpspro/services/model/single_device.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/widgets/address.dart';
import 'package:gpspro/widgets/banner_ad_widget.dart';
import 'package:gpspro/widgets/scale_button.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/payment_service.dart';
import 'package:gpspro/services/model/billing_vehicle.dart';

enum DeviceStatus { running, idle, stop, offline }

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Due amount observable
  final RxDouble totalDue = 0.0.obs;

  // Billing info state
  List<BillingVehicle> _billingVehicles = [];
  Map<String, BillingVehicle> _billingMap = {};
  bool _isLoadingBilling = false;

  SingleDevice? sd;
  int expiryTime = 10;
  int? selectedIconId;

  final DataController controller = Get.find<DataController>();
  bool _isDisposed = false;

  int _selectedFilterIndex = 0;
  List<DeviceItem> _displayDevices = [];

  // Use reactive variables for counts
  final RxInt _allCount = 0.obs;
  final RxInt _runningCount = 0.obs;
  final RxInt _idleCount = 0.obs;
  final RxInt _stopCount = 0.obs;
  final RxInt _offlineCount = 0.obs;

  // Colors
  static const Color _primaryBlue = Color(0xFF1B851C); // Brand Green
  static const Color _greenColor = Color(0xFF22C55E);
  static const Color _yellowColor = Color(0xFFF59E0B);
  static const Color _redColor = Color(0xFFEF4444);
  static const Color _greyColor = Color(0xFF6B7280);

  Timer? _refreshTimer;

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) setState(fn);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed) {
        _loadDevices();
        _startPeriodicRefresh();
        _loadDueAmount();
        _loadBillingInfo();
      }
    });
  }

  /// Load due amount from payment service
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

  /// Load billing info from payment service
  Future<void> _loadBillingInfo() async {
    if (_isDisposed || !mounted) return;
    _safeSetState(() {
      _isLoadingBilling = true;
    });

    try {
      final billingList = await PaymentService.getBillingVehicles();
      if (billingList != null && mounted && !_isDisposed) {
        _billingVehicles = billingList;
        _billingMap = {for (var v in billingList) v.imei: v};
        debugPrint('LOADED BILLING MAP KEYS: ${_billingMap.keys.toList()}');
      } else {
        debugPrint('Billing list is null or empty');
      }
    } catch (e) {
      debugPrint('Error loading billing info: $e');
    } finally {
      if (mounted && !_isDisposed) {
        _safeSetState(() {
          _isLoadingBilling = false;
        });
      }
    }
  }

  bool _isDeviceSuspended(DeviceItem device) {
    final imei = device.imei ?? device.deviceData?.imei;
    if (imei == null) return false;
    final billingInfo = _billingMap[imei];
    if (billingInfo == null) return false;

    // Suspend if explicitly marked inactive in billing
    if (!billingInfo.isActive) {
      return true;
    }

    // Check expiration date
    if (billingInfo.expirationDate != null) {
      try {
        final expDate = DateTime.parse(billingInfo.expirationDate!);
        if (expDate.isBefore(DateTime.now())) {
          final daysPassed = DateTime.now().difference(expDate).inDays;
          if (daysPassed > 10) {
            return true;
          }
        }
      } catch (_) {}
    }
    return false;
  }

  String _formatBillingDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return "${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}";
    } catch (_) {
      return dateString.split(' ').first;
    }
  }

  void _showSuspendedDialog(DeviceItem device) {
    final imei = device.imei ?? device.deviceData?.imei;
    final billingInfo = imei != null ? _billingMap[imei] : null;
    final monthlyBillStr = billingInfo?.monthlyBill != null 
        ? " (মান্থলি বিল: ৳${billingInfo!.monthlyBill!.toStringAsFixed(0)})" 
        : "";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_clock_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('সেবা সাময়িকভাবে স্থগিত', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'আপনার "${device.name ?? 'ডিভাইস'}" গাড়িটির বিল বকেয়া থাকায় বা মেয়াদ শেষ হওয়ায় ট্র্যাকিং সাময়িকভাবে স্থগিত করা হয়েছে$monthlyBillStr। অবিলম্বে ট্র্যাকিং সচল করতে বকেয়া বিল পরিশোধ করুন।',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('বন্ধ করুন', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Get.to(() => const PaymentListScreen())?.then((_) {
                _loadDueAmount();
                _loadBillingInfo();
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('বিল পরিশোধ করুন', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  bool _checkNoPermission(DeviceItem device) {
    if (device.id != null && device.id! < 0) {
      _showNoPermissionDialog(device);
      return true;
    }
    return false;
  }

  void _showNoPermissionDialog(DeviceItem device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('ট্র্যাকিং অনুমতি নেই', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'আপনার "${device.name ?? 'ডিভাইস'}" গাড়িটি দেখার পর্যাপ্ত অনুমতি জিপিএস ট্র্যাকিং সার্ভারে নেই। ম্যাপ বা লাইভ ট্র্যাকিং দেখতে অনুগ্রহ করে অ্যাডমিন প্যানেল থেকে অনুমতি সক্রিয় করুন।',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('বন্ধ করুন', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && !_isDisposed) {
        _calculateCounts();
        _applyCurrentFilter();
      }
    });
  }

  void _loadDevices() {
    if (_isDisposed || !mounted) return;
    controller.filterDevicesByStatus("all");
    _calculateCounts();
    _filterDevices("all");
  }

  List<DeviceItem> _getMergedDevices() {
    final trackingDevices = controller.filteredDevices.toList();
    final List<DeviceItem> merged = List.from(trackingDevices);

    for (final bv in _billingVehicles) {
      final exists = trackingDevices.any((td) {
        final trackingImei = td.imei ?? td.deviceData?.imei;
        return trackingImei != null && trackingImei == bv.imei;
      });

      if (!exists) {
        final mockDevice = DeviceItem(
          id: -bv.id,
          name: bv.name ?? 'ভেইকেল ${bv.id}',
          imei: bv.imei,
          online: 'offline',
          iconColor: 'red',
          speed: 0,
          lat: null,
          lng: null,
          deviceData: DeviceData(
            imei: bv.imei,
          ),
        );
        merged.add(mockDevice);
      }
    }
    return merged;
  }

  void _calculateCounts() {
    if (_isDisposed || !mounted) return;

    final allDevices = _getMergedDevices();

    int running = 0;
    int idle = 0;
    int stop = 0;
    int offline = 0;

    for (var device in allDevices) {
      final status = _getDeviceStatus(device);
      switch (status) {
        case DeviceStatus.running:
          running++;
          break;
        case DeviceStatus.idle:
          idle++;
          break;
        case DeviceStatus.stop:
          stop++;
          break;
        case DeviceStatus.offline:
          offline++;
          break;
      }
    }

    _allCount.value = allDevices.length;
    _runningCount.value = running;
    _idleCount.value = idle;
    _stopCount.value = stop;
    _offlineCount.value = offline;
  }

  /// Check if device is online based on multiple factors
  /// Check if device is online based on multiple factors
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

    // Check if has recent activity (speed > 0 means device must be online)
    final speed = double.tryParse(device.speed.toString()) ?? 0;
    if (speed > 0) {
      return true;
    }

    return false;
  }

  /// Check if engine/ignition is on - MASTER ENGINE CHECK
  bool _isEngineOn(DeviceItem device) {
    // 1. If speed > 0, engine must be on (telematics override for wiring/reporting issues)
    final speed = double.tryParse(device.speed.toString()) ?? 0;
    if (speed > 0) {
      return true;
    }

    // 2. Check engineStatus field directly
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

    // 3. Check sensors for ignition/acc status
    if (device.sensors != null && device.sensors!.isNotEmpty) {
      for (var sensor in device.sensors!) {
        try {
          final type = (sensor['type'] ?? '').toString().toLowerCase();
          final name = (sensor['name'] ?? '').toString().toLowerCase();
          final value = sensor['value'];

          // Check for ignition or ACC sensors
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
                  .contains(v)) {
                return true;
              }
              if (['off', '0', 'false', 'ign off', 'acc off', 'engine off']
                  .contains(v)) {
                return false;
              }
            }
          }
        } catch (e) {
          continue;
        }
      }
    }

    // 4. Fallback: Check iconColor as indicator
    final iconColor = device.iconColor?.toLowerCase().trim() ?? '';
    if (iconColor == 'yellow' || iconColor == 'green') {
      return true; 
    }

    // Default: engine is off
    return false;
  }


  /// Get device status - MASTER STATUS DETERMINATION
  DeviceStatus _getDeviceStatus(DeviceItem device) {
    // STEP 1: Check if device is online first
    final isOnline = _isDeviceOnline(device);

    if (!isOnline) {
      return DeviceStatus.offline;
    }

    // STEP 2: Device is online, check speed
    final speed = double.tryParse(device.speed.toString()) ?? 0;

    // STEP 3: Check engine status
    final isEngineOn = _isEngineOn(device);

    // STEP 4: Determine status based on online + speed + engine
    if (speed > 0) {
      // Moving = Running (engine must be on if moving)
      return DeviceStatus.running;
    } else {
      // Not moving (speed = 0)
      if (isEngineOn) {
        // Engine on but not moving = Idle
        return DeviceStatus.idle;
      } else {
        // Engine off and not moving = Stop/Parking
        return DeviceStatus.stop;
      }
    }
  }

  void _applyCurrentFilter() {
    _filterDevices(_getFilterName(_selectedFilterIndex));
  }

  void _filterDevices(String filter) {
    if (_isDisposed || !mounted) return;

    controller.filterDevicesByStatus("all");
    final allDevices = _getMergedDevices();

    // Recalculate counts
    _calculateCounts();

    switch (filter) {
      case "running":
        _displayDevices = allDevices
            .where((d) => _getDeviceStatus(d) == DeviceStatus.running)
            .toList();
        _selectedFilterIndex = 1;
        break;
      case "idle":
        _displayDevices = allDevices
            .where((d) => _getDeviceStatus(d) == DeviceStatus.idle)
            .toList();
        _selectedFilterIndex = 2;
        break;
      case "stop":
        _displayDevices = allDevices
            .where((d) => _getDeviceStatus(d) == DeviceStatus.stop)
            .toList();
        _selectedFilterIndex = 3;
        break;
      case "offline":
        _displayDevices = allDevices
            .where((d) => _getDeviceStatus(d) == DeviceStatus.offline)
            .toList();
        _selectedFilterIndex = 4;
        break;
      default:
        _displayDevices = allDevices;
        _selectedFilterIndex = 0;
    }
    _safeSetState(() {});
  }

  void _searchDevices(String query) {
    if (_isDisposed || !mounted) return;
    if (query.isEmpty) {
      _filterDevices(_getFilterName(_selectedFilterIndex));
    } else {
      controller.filterDevicesByStatus("all");
      final allDevices = _getMergedDevices();

      // Apply current filter first, then search
      List<DeviceItem> filtered;
      switch (_selectedFilterIndex) {
        case 1:
          filtered = allDevices
              .where((d) => _getDeviceStatus(d) == DeviceStatus.running)
              .toList();
          break;
        case 2:
          filtered = allDevices
              .where((d) => _getDeviceStatus(d) == DeviceStatus.idle)
              .toList();
          break;
        case 3:
          filtered = allDevices
              .where((d) => _getDeviceStatus(d) == DeviceStatus.stop)
              .toList();
          break;
        case 4:
          filtered = allDevices
              .where((d) => _getDeviceStatus(d) == DeviceStatus.offline)
              .toList();
          break;
        default:
          filtered = allDevices;
      }

      _displayDevices = filtered
          .where((d) =>
          (d.name?.toLowerCase() ?? '').contains(query.toLowerCase()))
          .toList();
      _safeSetState(() {});
    }
  }

  String _getFilterName(int index) {
    const names = ["all", "running", "idle", "stop", "offline"];
    return names[index];
  }

  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.running:
        return _greenColor;
      case DeviceStatus.idle:
        return _yellowColor;
      case DeviceStatus.stop:
        return _greyColor;
      case DeviceStatus.offline:
        return _redColor;
    }
  }

  String _getStatusText(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.running:
        return 'RUNNING';
      case DeviceStatus.idle:
        return 'IDLE';
      case DeviceStatus.stop:
        return 'PARKING';
      case DeviceStatus.offline:
        return 'OFFLINE';
    }
  }

  IconData _getStatusIcon(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.running:
        return Icons.directions_car;
      case DeviceStatus.idle:
        return Icons.pause_circle;
      case DeviceStatus.stop:
        return Icons.local_parking;
      case DeviceStatus.offline:
        return Icons.signal_wifi_off;
    }
  }

  String? _getRawParameter(DeviceItem? device, String key) {
    if (device == null) return null;
    
    // 1. Try to search in device.sensors list
    final sensors = device.sensors;
    if (sensors != null) {
      for (var s in sensors) {
        if (s is Map) {
          final name = (s['name'] ?? '').toString().toLowerCase();
          if (name.contains(key.toLowerCase())) {
            final val = s['value']?.toString();
            if (val != null && val.trim().isNotEmpty) {
              return val;
            }
          }
        }
      }
    }

    // 2. Try to search in deviceData.sensors
    final ddSensors = device.deviceData?.sensors;
    if (ddSensors != null) {
      for (var s in ddSensors) {
        if (s is Map) {
          final name = (s['name'] ?? '').toString().toLowerCase();
          if (name.contains(key.toLowerCase())) {
            final val = s['value']?.toString();
            if (val != null && val.trim().isNotEmpty) {
              return val;
            }
          }
        }
      }
    }

    // 3. Try to extract from traccar.other (XML or JSON)
    final other = device.deviceData?.traccar?.other;
    if (other != null && other.isNotEmpty) {
      final xmlMatch = RegExp('<$key>(.*?)</$key>', caseSensitive: false).firstMatch(other);
      if (xmlMatch != null && xmlMatch.group(1) != null) {
        final val = xmlMatch.group(1);
        if (val != null && val.trim().isNotEmpty) {
          return val;
        }
      }
      final jsonMatch = RegExp('["\']?$key["\']?\\s*:\\s*(true|false|"[^"]*"|\'[^\']*\'|\\d+\\.?\\d*)', caseSensitive: false).firstMatch(other);
      if (jsonMatch != null && jsonMatch.group(1) != null) {
        final val = jsonMatch.group(1)!.replaceAll('"', '').replaceAll("'", '');
        if (val.trim().isNotEmpty) {
          return val;
        }
      }
    }

    // 4. Try from deviceData.parameters or currents
    final params = device.deviceData?.parameters;
    if (params != null && params.isNotEmpty) {
      final jsonMatch = RegExp('["\']?$key["\']?\\s*:\\s*(true|false|"[^"]*"|\'[^\']*\'|\\d+\\.?\\d*)', caseSensitive: false).firstMatch(params);
      if (jsonMatch != null && jsonMatch.group(1) != null) {
        final val = jsonMatch.group(1)!.replaceAll('"', '').replaceAll("'", '');
        if (val.trim().isNotEmpty) {
          return val;
        }
      }
    }

    return null;
  }

  Widget _buildSignalWidget(DeviceItem? device) {
    if (device == null) return const SizedBox.shrink();
    final rssiVal = _getRawParameter(device, 'rssi') ?? _getRawParameter(device, 'signal') ?? _getRawParameter(device, 'gsm');
    if (rssiVal == null || rssiVal.isEmpty) {
      return const SizedBox.shrink();
    }
    
    int bars = 0;
    try {
      final val = double.parse(rssiVal).toInt();
      if (val > 20) {
        bars = 5;
      } else {
        bars = val.clamp(0, 5);
      }
    } catch (_) {
      bars = 4;
    }

    // Determine signal color based on strength
    Color sigColor = Colors.grey;
    if (bars >= 4) {
      sigColor = const Color(0xFF10B981); // Green
    } else if (bars == 3) {
      sigColor = const Color(0xFFF59E0B); // Orange/Amber
    } else {
      sigColor = const Color(0xFFEF4444); // Red
    }

    IconData signalIcon = Icons.signal_cellular_alt;
    if (bars == 0) {
      signalIcon = Icons.signal_cellular_null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 8),
        Container(
          width: 1.5,
          height: 10,
          color: Colors.grey[300],
        ),
        const SizedBox(width: 8),
        Icon(
          signalIcon,
          size: 14,
          color: sigColor,
        ),
        const SizedBox(width: 4),
        Text(
          rssiVal,
          style: TextStyle(
            color: sigColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _refreshTimer?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isDisposed) {
            _calculateCounts();
            if (_searchController.text.isEmpty) {
              _applyCurrentFilter();
            }
          }
        });

        return Column(
          children: [
            if (controller.isSearchVisible.value) _buildSearchBar(),
            _buildFilterChips(),
            Expanded(child: _buildDeviceList()),
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
      title: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Text(
            'vehicles'.tr,
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Obx(() {
            final due = totalDue.value;
            if (due <= 0) return const SizedBox.shrink();

            return TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                Get.to(() => PaymentListScreen())?.then((_) {
                  _loadDueAmount();
                });
              },
              child: Text(
                'বকেয়া টাকা ৳${(due)}',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }),
        ],
      ),
      centerTitle: true,
      actions: [
        Obx(() => IconButton(
          icon: Icon(
            Icons.search,
            color: controller.isSearchVisible.value
                ? _primaryBlue
                : const Color(0xFF6B7280),
          ),
          onPressed: controller.toggleSearchVisibility,
        )),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          hintText: 'search'.tr,
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              _searchController.clear();
              _searchDevices('');
            },
          )
              : null,
          border: InputBorder.none,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: _searchDevices,
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SizedBox(
        height: 40,
        child: Obx(() => ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _buildFilterChip(0, 'All', _allCount.value, _primaryBlue),
            _buildFilterChip(
                1, 'Running', _runningCount.value, _greenColor),
            _buildFilterChip(2, 'Idle', _idleCount.value, _yellowColor),
            _buildFilterChip(3, 'Parking', _stopCount.value, _greyColor),
            _buildFilterChip(4, 'Offline', _offlineCount.value, _redColor),
          ],
        )),
      ),
    );
  }

  Widget _buildFilterChip(int index, String label, int count, Color color) {
    final isSelected = _selectedFilterIndex == index;
    return GestureDetector(
      onTap: () {
        _searchController.clear();
        _filterDevices(_getFilterName(index));
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? color : Colors.grey[300]!),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              _getStatusIconForFilter(index),
              size: 14,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.3)
                    : color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  color: isSelected ? Colors.white : color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIconForFilter(int index) {
    switch (index) {
      case 0:
        return Icons.apps;
      case 1:
        return Icons.directions_car;
      case 2:
        return Icons.pause_circle;
      case 3:
        return Icons.local_parking;
      case 4:
        return Icons.signal_wifi_off;
      default:
        return Icons.apps;
    }
  }

  Widget _buildDeviceList() {
    if (_displayDevices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_car_outlined,
                size: 64, color: Colors.grey[300]),
            const Gap(16),
            Text(
              'noDeviceFound'.tr,
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
            const Gap(8),
            Text(
              'Try selecting a different filter',
              style: TextStyle(fontSize: 14, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _loadDevices();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _displayDevices.length,
        itemBuilder: (context, index) {
          final device = _displayDevices[index];
          return Column(
            children: [
              if (index > 0 && index % 5 == 0) BannerAdWidget(),
              _buildDeviceCard(device),
              const Gap(12),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDeviceCard(DeviceItem device) {
    final status = _getDeviceStatus(device);
    final statusColor = _getStatusColor(status);
    final isEngineOn = _isEngineOn(device);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Card Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: InkWell(
              onTap: () {
                if (_isDeviceSuspended(device)) {
                  _showSuspendedDialog(device);
                } else if (!_checkNoPermission(device)) {
                  Get.to(() => TrackDevicePage(device.id, device.name, device));
                }
              },
              child: Row(
                children: [
                  // Vehicle Icon with status indicator
                  Stack(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        // child: Image.asset(
                        //   "assets/images/car-icon.png",
                        //   fit: BoxFit.contain,
                        //   errorBuilder: (_, __, ___) => Icon(
                        //     Icons.directions_car,
                        //     color: statusColor,
                        //     size: 28,
                        //   ),
                        // ),
                        child: Padding(
                          padding: const EdgeInsets.all(2.0),
                          child: (device.icon?.path != null)
                              ? Image(
                                  image: CachedNetworkImageProvider(
                                    "${UserRepository.getServerUrl()}/${device.icon!.path!}",
                                  ),
                                )
                              : Icon(
                                  Icons.directions_car,
                                  color: statusColor,
                                  size: 28,
                                ),
                        ),
                      ),
                      // Status dot
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Device Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name ?? '',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          device.deviceData?.imei ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Billing and Expiration Row
                        () {
                          final imei = device.imei ?? device.deviceData?.imei;
                          final billingInfo = imei != null ? _billingMap[imei] : null;
                          if (billingInfo == null) return const SizedBox.shrink();

                          final isSuspended = _isDeviceSuspended(device);

                          // Check if expired but within grace period
                          bool isGracePeriod = false;
                          if (billingInfo.expirationDate != null) {
                            try {
                              final expDate = DateTime.parse(billingInfo.expirationDate!);
                              if (expDate.isBefore(DateTime.now()) && !isSuspended) {
                                isGracePeriod = true;
                              }
                            } catch (_) {}
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (isSuspended) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEE2E2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFFFCA5A5)),
                                      ),
                                      child: const Text(
                                        'সেবা স্থগিত',
                                        style: TextStyle(
                                          color: Color(0xFFEF4444),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ] else if (isGracePeriod) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFFFCD34D)),
                                      ),
                                      child: const Text(
                                        'মেয়াদ শেষ (১০ দিন ছাড়)',
                                        style: TextStyle(
                                          color: Color(0xFFD97706),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ] else if (billingInfo.expirationDate != null) ...[
                                    Text(
                                      'মেয়াদ: ${_formatBillingDate(billingInfo.expirationDate!)}',
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  if (billingInfo.monthlyBill != null)
                                    Text(
                                      'বিল: ৳${billingInfo.monthlyBill!.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        color: Color(0xFF1B851C),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          );
                        }(),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              isEngineOn ? Icons.power : Icons.power_off,
                              size: 14,
                              color: isEngineOn ? _greenColor.withValues(alpha: 0.4) : _redColor.withValues(alpha: 0.4),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                isEngineOn ? 'Engine On' : 'Engine Off',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _buildSignalWidget(device),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IntrinsicWidth(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusColor),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 🔹 Top part with status color background
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(2),
                                topRight: Radius.circular(2),
                              ),
                            ),
                            child: Text(
                              _getStatusInfoTime(device, status),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _getStatusText(status),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                ],
              ),
            ),
          ),

          Divider(height: 1, color: Colors.grey[200]),

          // Bottom Action Buttons
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                _buildBottomButton(
                  icon: Icons.info_outline,
                  label: 'details'.tr,
                  onTap: () {
                    if (!_checkNoPermission(device)) {
                      _showDetailsSheet(device);
                    }
                  },
                ),
                _buildBottomButton(
                  icon: Icons.description_outlined,
                  label: 'Report'.tr,
                  onTap: () {
                    if (!_checkNoPermission(device)) {
                      _showReport(device);
                    }
                  },
                ),
                _buildBottomButton(
                  icon: Icons.my_location,
                  label: 'tracking'.tr,
                  onTap: () {
                    if (!_checkNoPermission(device)) {
                      AdMobService().showInterstitialAd();
                      _openTracking(device);
                    }
                  },
                ),
                _buildBottomButton(
                  icon: Icons.play_circle_outline,
                  label: 'playback'.tr,
                  onTap: () {
                    if (!_checkNoPermission(device)) {
                      AdMobService().showInterstitialAd(ignoreFrequency: true);
                      _openPlayback(device);
                    }
                  },
                ),
                _buildBottomButton(
                  icon: Icons.more_horiz,
                  label: 'more'.tr,
                  onTap: () {
                    if (!_checkNoPermission(device)) {
                      _showMoreOptions(device);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusInfoTime(DeviceItem device, DeviceStatus status) {
    switch (status) {
      case DeviceStatus.running:
        return convertSpeed(device.speed, device.distanceUnitHour ?? 'km/h');
      case DeviceStatus.idle:
        return device.stopDuration ?? "0s";
      case DeviceStatus.stop:
        return device.stopDuration ?? "";
      case DeviceStatus.offline:
        return _getLastSeen(device);
    }
  }

  String _getLastSeen(DeviceItem device) {
    if (device.timestamp == null || device.timestamp == 0) {
      return 'Unknown';
    }
    try {
      final lastUpdate =
      DateTime.fromMillisecondsSinceEpoch(device.timestamp! * 1000);
      final difference = DateTime.now().difference(lastUpdate);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      }
      return 'Just now';
    } catch (_) {
      return 'Unknown';
    }
  }

  Widget _buildBottomButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: ScaleButton(
        onTap: onTap,
        child: Container(
          color: Colors.transparent, // Ensures the entire area is tappable
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: Colors.black54),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  void _showDetailsSheet(DeviceItem device) {
    final status = _getDeviceStatus(device);
    final statusColor = _getStatusColor(status);
    final isEngineOn = _isEngineOn(device);
    final isOnline = _isDeviceOnline(device);
    final deviceData = device.deviceData;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _buildSheetHeader(device, status, statusColor),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  children: [
                    _buildQuickStats(device, isEngineOn, isOnline),
                    const SizedBox(height: 16),
                    _buildQuickActions(device),
                    const SizedBox(height: 20),
                    if (_hasVehicleInfo(deviceData))
                      _buildVehicleInfoSection(deviceData),
                    _buildEngineSection(device, isEngineOn),
                    _buildLocationSection(device),
                    _buildDeviceInfoSection(device, deviceData, isOnline),
                    if (_hasFuelInfo(deviceData)) _buildFuelSection(deviceData),
                    if (_hasSimInfo(deviceData)) _buildSimSection(deviceData),
                    if (_hasOwnerInfo(deviceData))
                      _buildOwnerSection(deviceData),
                    if (_hasConfigInfo(deviceData))
                      _buildConfigSection(deviceData),
                    if (device.sensors != null && device.sensors!.isNotEmpty)
                      _buildSensorsSection(device),
                    if (deviceData?.services != null &&
                        deviceData!.services!.isNotEmpty)
                      _buildServicesSection(deviceData),
                    if (device.driverData != null || deviceData?.driver != null)
                      _buildDriverSection(device, deviceData),
                    _buildAddressSection(device),
                    _buildTimestampsSection(device, deviceData),
                    const SizedBox(height: 16),
                    _buildMainActions(device),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheetHeader(
      DeviceItem device, DeviceStatus status, Color statusColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _getVehicleIcon(device),
                      color: statusColor,
                      size: 28,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name ?? 'Unknown Vehicle',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getStatusIcon(status),
                                color: Colors.white,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _getStatusText(status),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (device.deviceData?.plateNumber != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Text(
                              device.deviceData!.plateNumber!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close, color: Colors.grey[600]),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey[100],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(DeviceItem device, bool isEngineOn, bool isOnline) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _primaryBlue.withValues(alpha: 0.05),
            _primaryBlue.withValues(alpha: 0.1)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryBlue.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildQuickStatItem(
            icon: Icons.speed,
            value: '${device.speed ?? 0}',
            unit: 'km/h',
            label: 'Speed',
            color: _primaryBlue,
          ),
          _buildQuickStatDivider(),
          _buildQuickStatItem(
            icon: isEngineOn ? Icons.power : Icons.power_off,
            value: isEngineOn ? 'ON' : 'OFF',
            unit: '',
            label: 'Engine',
            color: isEngineOn ? _greenColor : _redColor,
          ),
          _buildQuickStatDivider(),
          _buildQuickStatItem(
            icon: isOnline ? Icons.wifi : Icons.wifi_off,
            value: isOnline ? 'Online' : 'Offline',
            unit: '',
            label: 'Status',
            color: isOnline ? _greenColor : _redColor,
          ),
          _buildQuickStatDivider(),
          _buildQuickStatItem(
            icon: Icons.explore,
            value: '${device.course ?? 0}°',
            unit: '',
            label: 'Course',
            color: _greyColor,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatItem({
    required IconData icon,
    required String value,
    required String unit,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (unit.isNotEmpty)
              Text(
                unit,
                style: TextStyle(
                  fontSize: 10,
                  color: color.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStatDivider() {
    return Container(
      height: 40,
      width: 1,
      color: Colors.grey[300],
    );
  }

  Widget _buildQuickActions(DeviceItem device) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildQuickActionButton(
            icon: Icons.navigation,
            label: 'Navigate',
            color: _primaryBlue,
            onTap: () {
              Navigator.pop(context);
              _navigate(device);
            },
          ),
          _buildQuickActionButton(
            icon: Icons.play_arrow,
            label: 'Playback',
            color: Colors.orange,
            onTap: () {
              Navigator.pop(context);
              _openPlayback(device);
            },
          ),
          _buildQuickActionButton(
            icon: Icons.gps_fixed,
            label: 'Track',
            color: _greenColor,
            onTap: () {
              Navigator.pop(context);
              _openTracking(device);
            },
          ),
          _buildQuickActionButton(
            icon: Icons.lock,
            label: 'Lock',
            color: _redColor,
            onTap: () {
              Navigator.pop(context);
              _openLockUnlock(device);
            },
          ),
          _buildQuickActionButton(
            icon: Icons.streetview,
            label: 'Street View',
            color: Colors.purple,
            onTap: () {
              Navigator.pop(context);
              _openStreetView(device);
            },
          ),
          _buildQuickActionButton(
            icon: Icons.share,
            label: 'Share',
            color: Colors.teal,
            onTap: () {
              Navigator.pop(context);
              _showShareDialog(context, device);
            },
          ),
          _buildQuickActionButton(
            icon: Icons.directions,
            label: 'Directions',
            color: Colors.indigo,
            onTap: () {
              Navigator.pop(context);
              _openDirections(device);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(children: children),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    bool showCopy = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 16, color: _primaryBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 13,
                ),
              ),
            ),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: valueColor ?? Colors.black87,
                      ),
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showCopy) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _copyToClipboard(value),
                      child:
                      Icon(Icons.copy, size: 14, color: Colors.grey[400]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, color: Colors.grey[200]);
  }

  bool _hasVehicleInfo(DeviceData? data) {
    if (data == null) return false;
    return data.plateNumber != null ||
        data.vin != null ||
        data.registrationNumber != null ||
        data.deviceModel != null;
  }

  Widget _buildVehicleInfoSection(DeviceData? data) {
    if (data == null) return const SizedBox.shrink();

    List<Widget> items = [];

    if (data.plateNumber != null && data.plateNumber!.isNotEmpty) {
      items.add(_buildInfoRow(
        icon: Icons.confirmation_number,
        label: 'Plate Number',
        value: data.plateNumber!,
        showCopy: true,
      ));
    }

    if (data.vin != null && data.vin!.isNotEmpty) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.pin,
        label: 'VIN',
        value: data.vin!,
        showCopy: true,
      ));
    }

    if (data.registrationNumber != null &&
        data.registrationNumber!.isNotEmpty) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.app_registration,
        label: 'Registration',
        value: data.registrationNumber!,
      ));
    }

    if (data.deviceModel != null && data.deviceModel!.isNotEmpty) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.devices,
        label: 'Device Model',
        value: data.deviceModel!,
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return _buildSection(
      title: 'Vehicle Info',
      icon: Icons.directions_car,
      color: _primaryBlue,
      children: items,
    );
  }

  Widget _buildEngineSection(DeviceItem device, bool isEngineOn) {
    return _buildSection(
      title: 'Engine & Speed',
      icon: Icons.speed,
      color: Colors.orange,
      children: [
        _buildInfoRow(
          icon: Icons.power_settings_new,
          label: 'Engine Status',
          value: isEngineOn ? 'ON' : 'OFF',
          valueColor: isEngineOn ? _greenColor : _redColor,
        ),
        _buildDivider(),
        _buildInfoRow(
          icon: Icons.speed,
          label: 'Current Speed',
          value: convertSpeed(device.speed, device.distanceUnitHour ?? 'km/h'),
          valueColor: _primaryBlue,
        ),
        _buildDivider(),
        _buildInfoRow(
          icon: Icons.timer_outlined,
          label: 'Stop Duration',
          value: device.stopDuration ?? 'N/A',
          valueColor: _greyColor,
        ),
        if (device.deviceData?.engineHours != null) ...[
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.access_time_filled,
            label: 'Engine Hours',
            value: device.deviceData!.engineHours!,
          ),
        ],
        if (device.totalDistance != null) ...[
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.route,
            label: 'Total Distance',
            value: '${device.totalDistance!.toStringAsFixed(2)} km',
          ),
        ],
      ],
    );
  }

  Widget _buildLocationSection(DeviceItem device) {
    return _buildSection(
      title: 'Location',
      icon: Icons.location_on,
      color: _greenColor,
      children: [
        _buildInfoRow(
          icon: Icons.my_location,
          label: 'Latitude',
          value: device.lat?.toStringAsFixed(6) ?? 'N/A',
          showCopy: true,
        ),
        _buildDivider(),
        _buildInfoRow(
          icon: Icons.location_on_outlined,
          label: 'Longitude',
          value: device.lng?.toStringAsFixed(6) ?? 'N/A',
          showCopy: true,
        ),
        _buildDivider(),
        _buildInfoRow(
          icon: Icons.height,
          label: 'Altitude',
          value: '${device.altitude ?? 0} m',
        ),
        _buildDivider(),
        _buildInfoRow(
          icon: Icons.explore_outlined,
          label: 'Course',
          value:
          '${device.course ?? 0}° ${_getCourseDirection(device.course ?? 0)}',
        ),
        _buildDivider(),
        InkWell(
          onTap: () => _openInMaps(device.lat, device.lng),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.map, size: 16, color: _primaryBlue),
                ),
                const SizedBox(width: 12),
                Text(
                  'Open in Maps',
                  style: TextStyle(
                    color: _primaryBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(Icons.open_in_new, size: 16, color: _primaryBlue),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceInfoSection(
      DeviceItem device, DeviceData? data, bool isOnline) {
    return _buildSection(
      title: 'Device Info',
      icon: Icons.devices,
      color: Colors.purple,
      children: [
        if (data?.imei != null) ...[
          _buildInfoRow(
            icon: Icons.confirmation_number_outlined,
            label: 'IMEI',
            value: data!.imei!,
            showCopy: true,
          ),
          _buildDivider(),
        ],
        _buildInfoRow(
          icon: Icons.wifi,
          label: 'Connection',
          value: isOnline ? 'Online' : 'Offline',
          valueColor: isOnline ? _greenColor : _redColor,
        ),
        _buildDivider(),
        _buildInfoRow(
          icon: Icons.perm_identity,
          label: 'Device ID',
          value: device.id?.toString() ?? 'N/A',
          showCopy: true,
        ),
        if (data?.traccarDeviceId != null) ...[
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.numbers,
            label: 'Traccar ID',
            value: data!.traccarDeviceId.toString(),
          ),
        ],
        if (data?.groupId != null) ...[
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.folder,
            label: 'Group ID',
            value: data!.groupId.toString(),
          ),
        ],
        _buildDivider(),
        _buildInfoRow(
          icon: Icons.access_time,
          label: 'Last Update',
          value: device.timestamp != null
              ? _formatTimestamp(device.timestamp!)
              : 'N/A',
        ),
        if (data?.active != null) ...[
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.check_circle_outline,
            label: 'Active',
            value: data!.active == 1 ? 'Yes' : 'No',
            valueColor: data.active == 1 ? _greenColor : _redColor,
          ),
        ],
      ],
    );
  }

  bool _hasFuelInfo(DeviceData? data) {
    if (data == null) return false;
    return data.fuelQuantity != null ||
        data.fuelPrice != null ||
        data.fuelPerKm != null ||
        data.fuelPerH != null;
  }

  Widget _buildFuelSection(DeviceData? data) {
    if (data == null) return const SizedBox.shrink();

    List<Widget> items = [];

    if (data.fuelQuantity != null && data.fuelQuantity!.isNotEmpty) {
      items.add(_buildInfoRow(
        icon: Icons.local_gas_station,
        label: 'Fuel Quantity',
        value: '${data.fuelQuantity} L',
      ));
    }

    if (data.fuelPrice != null && data.fuelPrice!.isNotEmpty) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.attach_money,
        label: 'Fuel Price',
        value: data.fuelPrice!,
      ));
    }

    if (data.fuelPerKm != null && data.fuelPerKm!.isNotEmpty) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.local_gas_station_outlined,
        label: 'Fuel per KM',
        value: '${data.fuelPerKm} L/km',
      ));
    }

    if (data.fuelPerH != null && data.fuelPerH!.isNotEmpty) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.timer,
        label: 'Fuel per Hour',
        value: '${data.fuelPerH} L/h',
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return _buildSection(
      title: 'Fuel Info',
      icon: Icons.local_gas_station,
      color: Colors.amber,
      children: items,
    );
  }

  bool _hasSimInfo(DeviceData? data) {
    if (data == null) return false;
    return data.simNumber != null ||
        data.msisdn != null ||
        data.simExpirationDate != null ||
        data.simActivationDate != null;
  }

  Widget _buildSimSection(DeviceData? data) {
    if (data == null) return const SizedBox.shrink();

    List<Widget> items = [];

    if (data.simNumber != null && data.simNumber!.isNotEmpty) {
      items.add(_buildInfoRow(
        icon: Icons.sim_card,
        label: 'SIM Number',
        value: data.simNumber!,
        showCopy: true,
      ));
    }

    if (data.msisdn != null) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.phone,
        label: 'MSISDN',
        value: data.msisdn.toString(),
        showCopy: true,
      ));
    }

    if (data?.simActivationDate != null) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.calendar_today,
        label: 'SIM Activation',
        value: _formatDate(data?.simActivationDate),
      ));
    }

    if (data?.simExpirationDate != null) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.event_busy,
        label: 'SIM Expiration',
        value: _formatDate(data?.simExpirationDate),
        valueColor: _isExpired(data?.simExpirationDate) ? _redColor : null,
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return _buildSection(
      title: 'SIM Card',
      icon: Icons.sim_card,
      color: Colors.teal,
      children: items,
    );
  }

  bool _hasOwnerInfo(DeviceData? data) {
    if (data == null) return false;
    return (data.objectOwner != null && data.objectOwner!.isNotEmpty) ||
        (data.additionalNotes != null && data.additionalNotes!.isNotEmpty);
  }

  Widget _buildOwnerSection(DeviceData? data) {
    if (data == null) return const SizedBox.shrink();

    List<Widget> items = [];

    if (data.objectOwner != null && data.objectOwner!.isNotEmpty) {
      items.add(_buildInfoRow(
        icon: Icons.person_outline,
        label: 'Owner',
        value: data.objectOwner!,
      ));
    }

    if (data.additionalNotes != null && data.additionalNotes!.isNotEmpty) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.note_outlined,
                        size: 16, color: _primaryBlue),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Additional Notes',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                data.additionalNotes!,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return _buildSection(
      title: 'Owner Info',
      icon: Icons.person,
      color: Colors.indigo,
      children: items,
    );
  }

  bool _hasConfigInfo(DeviceData? data) {
    if (data == null) return false;
    return data.minMovingSpeed != null ||
        data.detectEngine != null ||
        data.tailLength != null ||
        data.snapToRoad != null;
  }

  Widget _buildConfigSection(DeviceData? data) {
    if (data == null) return const SizedBox.shrink();

    List<Widget> items = [];

    if (data.minMovingSpeed != null) {
      items.add(_buildInfoRow(
        icon: Icons.speed,
        label: 'Min Moving Speed',
        value: '${data.minMovingSpeed} km/h',
      ));
    }

    if (data.detectEngine != null && data.detectEngine!.isNotEmpty) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.settings,
        label: 'Detect Engine',
        value: data.detectEngine!,
      ));
    }

    if (data.detectSpeed != null && data.detectSpeed!.isNotEmpty) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.speed,
        label: 'Detect Speed',
        value: data.detectSpeed!,
      ));
    }

    if (data.tailLength != null) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.timeline,
        label: 'Tail Length',
        value: data.tailLength.toString(),
      ));
    }

    if (data.tailColor != null && data.tailColor!.isNotEmpty) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.color_lens,
        label: 'Tail Color',
        value: data.tailColor!,
      ));
    }

    if (data.snapToRoad != null) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.route,
        label: 'Snap to Road',
        value: data.snapToRoad == 1 ? 'Yes' : 'No',
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return _buildSection(
      title: 'Configuration',
      icon: Icons.settings,
      color: Colors.blueGrey,
      children: items,
    );
  }

  Widget _buildSensorsSection(DeviceItem device) {
    return _buildSection(
      title: 'Sensors (${device.sensors!.length})',
      icon: Icons.sensors,
      color: Colors.cyan,
      children: _buildSensorItems(device.sensors!),
    );
  }

  List<Widget> _buildSensorItems(List<dynamic> sensors) {
    List<Widget> items = [];

    for (int i = 0; i < sensors.length; i++) {
      final sensor = sensors[i];
      if (sensor['value'] != null) {
        if (items.isNotEmpty) items.add(_buildDivider());

        items.add(_buildInfoRow(
          icon: _getSensorIcon(sensor['type'] ?? ''),
          label: sensor['name'] ?? _getSensorName(sensor['type'] ?? ''),
          value: _formatSensorValue(sensor['value'], sensor['type']),
          valueColor: _getSensorValueColor(sensor),
        ));
      }
    }

    return items;
  }

  Color? _getSensorValueColor(Map<String, dynamic> sensor) {
    final type = (sensor['type'] ?? '').toString().toLowerCase();
    final value = sensor['value'];

    if (type == 'acc' || type == 'ignition' || type == 'engine') {
      if (value == true ||
          value == 1 ||
          value == '1' ||
          value.toString().toLowerCase() == 'on') {
        return _greenColor;
      }
      return _redColor;
    }

    if (type == 'battery') {
      final numValue = double.tryParse(value.toString()) ?? 0;
      if (numValue < 20) return _redColor;
      if (numValue < 50) return Colors.orange;
      return _greenColor;
    }

    return null;
  }

  String _formatSensorValue(dynamic value, String? type) {
    if (value == null) return 'N/A';

    final t = (type ?? '').toLowerCase();

    if (t == 'acc' || t == 'ignition' || t == 'engine') {
      if (value == true || value == 1 || value == '1') return 'ON';
      if (value == false || value == 0 || value == '0') return 'OFF';
    }

    if (t == 'fuel') return '$value L';
    if (t == 'temperature') return '$value°C';
    if (t == 'battery') return '$value%';
    if (t == 'speed') return '$value km/h';
    if (t == 'odometer') return '$value km';

    return value.toString();
  }

  Widget _buildServicesSection(DeviceData data) {
    return _buildSection(
      title: 'Services (${data.services!.length})',
      icon: Icons.build_circle,
      color: Colors.deepOrange,
      children: data.services!.map((service) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: _greenColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  service['name'] ?? 'Service',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDriverSection(DeviceItem device, DeviceData? data) {
    final driver = device.driverData ?? data?.driver;
    if (driver == null) return const SizedBox.shrink();

    return _buildSection(
      title: 'Driver Info',
      icon: Icons.person,
      color: Colors.brown,
      children: [
        _buildInfoRow(
          icon: Icons.person_outline,
          label: 'Name',
          value: driver.name ?? 'N/A',
        ),
        if (driver.phone != null && driver.phone.isNotEmpty) ...[
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.phone,
            label: 'Phone',
            value: driver.phone,
            onTap: () => _callPhone(driver.phone),
          ),
        ],
        if (driver.email != null && driver.email.isNotEmpty) ...[
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.email,
            label: 'Email',
            value: driver.email,
            onTap: () => _sendEmail(driver.email),
          ),
        ],
      ],
    );
  }

  Widget _buildAddressSection(DeviceItem device) {
    return _buildSection(
      title: 'Address',
      icon: Icons.place,
      color: _redColor,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_on, color: _primaryBlue, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: addressLoadMarque(
                device.lat.toString(),
                device.lng.toString(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimestampsSection(DeviceItem device, DeviceData? data) {
    List<Widget> items = [];

    if (device.timestamp != null) {
      items.add(_buildInfoRow(
        icon: Icons.update,
        label: 'Last Position',
        value: _formatTimestamp(device.timestamp!),
      ));
    }

    if (data?.createdAt != null) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.add_circle_outline,
        label: 'Created At',
        value: _formatDateString(data!.createdAt!),
      ));
    }

    if (data?.updatedAt != null) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.edit,
        label: 'Updated At',
        value: _formatDateString(data!.updatedAt!),
      ));
    }

    if (data?.installationDate != null) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.build,
        label: 'Installation Date',
        value: _formatDate(data!.installationDate),
      ));
    }

    if (data?.expirationDate != null) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(_buildInfoRow(
        icon: Icons.event_busy,
        label: 'Expiration Date',
        value: _formatDate(data!.expirationDate),
        valueColor: _isExpired(data!.expirationDate) ? _redColor : null,
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return _buildSection(
      title: 'Timestamps',
      icon: Icons.access_time,
      color: _greyColor,
      children: items,
    );
  }

  Widget _buildMainActions(DeviceItem device) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _navigate(device);
                },
                icon: const Icon(Icons.navigation, size: 18),
                label: Text('Navigate'.tr),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _openTracking(device);
                },
                icon: const Icon(Icons.gps_fixed, size: 18),
                label: Text('Track Live'.tr),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _greenColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _openPlayback(device);
                },
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: Text('Playback'.tr),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: const BorderSide(color: Colors.orange),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showShareDialog(context, device);
                },
                icon: const Icon(Icons.share, size: 18),
                label: Text('Share'.tr),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(color: _primaryBlue),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    Get.snackbar(
      'Copied',
      text,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
      backgroundColor: Colors.black87,
      colorText: Colors.white,
      margin: const EdgeInsets.all(10),
      borderRadius: 10,
    );
  }

  String _getCourseDirection(int course) {
    if (course >= 337.5 || course < 22.5) return 'N';
    if (course >= 22.5 && course < 67.5) return 'NE';
    if (course >= 67.5 && course < 112.5) return 'E';
    if (course >= 112.5 && course < 157.5) return 'SE';
    if (course >= 157.5 && course < 202.5) return 'S';
    if (course >= 202.5 && course < 247.5) return 'SW';
    if (course >= 247.5 && course < 292.5) return 'W';
    return 'NW';
  }

  IconData _getVehicleIcon(DeviceItem device) {
    final iconType = device.deviceData?.iconType?.toLowerCase() ?? '';
    if (iconType.contains('truck')) return Icons.local_shipping;
    if (iconType.contains('bike') || iconType.contains('motorcycle')) {
      return Icons.two_wheeler;
    }
    if (iconType.contains('bus')) return Icons.directions_bus;
    return Icons.directions_car;
  }

  IconData _getSensorIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('fuel')) return Icons.local_gas_station;
    if (t.contains('temp')) return Icons.thermostat;
    if (t.contains('battery')) return Icons.battery_full;
    if (t.contains('ignition') || t.contains('acc')) return Icons.key;
    if (t.contains('door')) return Icons.door_front_door;
    if (t.contains('speed')) return Icons.speed;
    if (t.contains('odometer')) return Icons.timeline;
    if (t.contains('gsm')) return Icons.signal_cellular_alt;
    if (t.contains('gps')) return Icons.gps_fixed;
    if (t.contains('voltage')) return Icons.bolt;
    return Icons.sensors;
  }

  String _getSensorName(String type) {
    final t = type.toLowerCase();
    final names = {
      'fuel': 'Fuel Level',
      'temperature': 'Temperature',
      'battery': 'Battery',
      'ignition': 'Ignition',
      'acc': 'ACC',
      'door': 'Door',
      'speed': 'Speed',
      'odometer': 'Odometer',
      'gsm': 'GSM Signal',
      'gps': 'GPS',
      'voltage': 'Voltage',
    };
    return names[t] ?? type.toUpperCase();
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('dd MMM yyyy, HH:mm:ss').format(date);
  }

  String _formatDateString(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy, HH:mm').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is String) {
      try {
        final d = DateTime.parse(date);
        return DateFormat('dd MMM yyyy').format(d);
      } catch (_) {
        return date;
      }
    }
    return date.toString();
  }

  bool _isExpired(dynamic date) {
    if (date == null) return false;
    try {
      DateTime d;
      if (date is String) {
        d = DateTime.parse(date);
      } else {
        return false;
      }
      return d.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  void _navigate(DeviceItem device) {
    if (device.lat == null || device.lng == null) return;
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=${device.lat},${device.lng}';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _openPlayback(DeviceItem device) {
    if (_isDeviceSuspended(device)) {
      _showSuspendedDialog(device);
      return;
    }
    Get.to(() => PlaybackScreen(
      id: device.id,
      name: device.name,
      device: device,
    ));
  }

  void _openTracking(DeviceItem device) {
    if (_isDeviceSuspended(device)) {
      _showSuspendedDialog(device);
      return;
    }
    Get.to(() => TrackDevicePage(device.id, device.name, device));
  }

  void _openLockUnlock(DeviceItem device) {
    if (_isDeviceSuspended(device)) {
      _showSuspendedDialog(device);
      return;
    }
    Get.to(() => LockUnlockScreen(device: device));
  }

  void _openStreetView(DeviceItem device) {
    if (_isDeviceSuspended(device)) {
      _showSuspendedDialog(device);
      return;
    }
    if (device.lat == null || device.lng == null) return;
    Get.to(() => StreetViewScreen(
      latitude: device.lat!,
      longitude: device.lng!,
    ));
  }

  void _openInMaps(double? lat, double? lng) {
    if (lat == null || lng == null) return;
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _openDirections(DeviceItem device) {
    if (_isDeviceSuspended(device)) {
      _showSuspendedDialog(device);
      return;
    }
    if (device.lat == null || device.lng == null) return;
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=${device.lat},${device.lng}&travelmode=driving';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _callPhone(String phone) {
    launchUrl(Uri.parse('tel:$phone'));
  }

  void _sendEmail(String email) {
    launchUrl(Uri.parse('mailto:$email'));
  }

  void _showMoreOptions(DeviceItem device) {
    if (_isDeviceSuspended(device)) {
      _showSuspendedDialog(device);
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Gap(20),
            Text(
              device.name ?? '',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Gap(20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildOptionItem(
                  Icons.description_outlined,
                  'Report',
                  Colors.indigo,
                      () {
                    Navigator.pop(sheetContext);
                    _showReport(device);
                  },
                ),
                _buildOptionItem(
                  Icons.phone_outlined,
                  'Call',
                  _greenColor,
                      () {
                    Navigator.pop(sheetContext);
                    _callDeviceSim(device);
                  },
                ),
                _buildOptionItem(
                  Icons.lock_outline,
                  'Lock',
                  _yellowColor,
                      () {
                    Navigator.pop(sheetContext);
                    Get.to(() => LockUnlockScreen(device: device));
                  },
                ),
                _buildOptionItem(
                  Icons.share_outlined,
                  'Share',
                  _primaryBlue,
                      () {
                    Navigator.pop(sheetContext);
                    _showShareDialog(context, device);
                  },
                ),
              ],
            ),
            const Gap(16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildOptionItem(
                  Icons.navigation_outlined,
                  'Navigate',
                  Colors.teal,
                      () {
                    Navigator.pop(sheetContext);
                    _navigate(device);
                  },
                ),
                _buildOptionItem(
                  Icons.car_crash_outlined,
                  'Edit Device',
                  _greyColor,
                      () {
                    Navigator.pop(sheetContext);
                    Future.delayed(const Duration(milliseconds: 200), () {
                      _getEditDeviceData(device.id);
                    });
                  },
                ),
                _buildOptionItem(
                  Icons.sos,
                  'sosNumber'.tr,
                  Colors.redAccent,
                      () {
                    Navigator.pop(sheetContext);
                    _showSOSDialog(device);
                  },
                ),
                _buildOptionItem(
                  Icons.add_alert_outlined,
                  'Add Alert',
                  Theme.of(context).primaryColor,
                      () {
                    Navigator.pop(sheetContext);
                    Navigator.pushNamed(context, "/alertList", arguments: device.id);
                  },
                ),
              ],
            ),
            const Gap(20),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionItem(
      IconData icon,
      String label,
      Color color,
      VoidCallback onTap,
      ) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 70,
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // void _showReport(DeviceItem device) {
  //   AdMobService().showInterstitialAd(ignoreFrequency: true);
  //   DateTime current = DateTime.now();
  //   String month =
  //   current.month < 10 ? "0${current.month}" : current.month.toString();
  //   int dayCon = current.day + 1;
  //   String today = dayCon < 10 ? "0$dayCon" : dayCon.toString();
  //   var date = DateTime.parse("${current.year}-$month-$today 00:00:00");
  //
  //   Navigator.pushNamed(
  //     context,
  //     "/reportList",
  //     arguments: ReportArguments(
  //       device.id ?? 0,
  //       formatDateReport(DateTime.now().toString()),
  //       "00:00:00",
  //       formatDateReport(date.toString()),
  //       "00:00:00",
  //       device.name ?? '',
  //       0,
  //       device,
  //     ),
  //   );
  // }

  void _showReport(DeviceItem device) {
    if (_isDeviceSuspended(device)) {
      _showSuspendedDialog(device);
      return;
    }
    AdMobService().showInterstitialAd(ignoreFrequency: true);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportScreen(
          deviceId: device.id ?? 0,
          deviceName: device.name ?? '',
        ),
      ),
    );
  }

  void _callDeviceSim(DeviceItem device) async {
    final simNumber = device.deviceData?.simNumber;

    if (simNumber != null && simNumber.isNotEmpty) {
      await launchUrl(Uri(scheme: 'tel', path: simNumber));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('phoneNumberNotFound'.tr)),
      );
    }
  }

  void _showSOSDialog(DeviceItem device) {
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController commandController = TextEditingController();

    // Common protocols/formats for GPS trackers
    final List<Map<String, String>> protocols = [
      {
        'name': 'Concox / GT06 / TK103 (sos,A,number#)',
        'format': 'sos,A,{phone}#',
      },
      {
        'name': 'SinoTrack (101#number#)',
        'format': '101#{phone}#',
      },
      {
        'name': 'Coban / TK Star (admin123456 number)',
        'format': 'admin123456 {phone}',
      },
      {
        'name': 'Concox Alternative (SOS,1,number#)',
        'format': 'SOS,1,{phone}#',
      },
      {
        'name': 'Custom Command (Raw)',
        'format': '{phone}',
      },
    ];

    int selectedProtocolIndex = 0;

    void updateCommandText() {
      final phone = phoneController.text.trim();
      final format = protocols[selectedProtocolIndex]['format']!;
      if (phone.isEmpty) {
        commandController.text = '';
      } else {
        commandController.text = format.replaceAll('{phone}', phone);
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.sos, color: Colors.redAccent, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'sosNumber'.tr,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set up the phone number to receive emergency SOS alerts/calls from the tracker.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const Gap(16),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  onChanged: (value) {
                    setDialogState(() {
                      updateCommandText();
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'SOS Phone Number',
                    hintText: 'Enter phone number...',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const Gap(16),
                DropdownButtonFormField<int>(
                  value: selectedProtocolIndex,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Tracker Command Format',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  items: protocols.asMap().entries.map((entry) {
                    return DropdownMenuItem<int>(
                      value: entry.key,
                      child: Text(
                        entry.value['name']!,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        selectedProtocolIndex = value;
                        updateCommandText();
                      });
                    }
                  },
                ),
                const Gap(16),
                TextField(
                  controller: commandController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'GPRS Command to Send',
                    helperText: 'Verify the command before sending.',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('cancel'.tr, style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final phone = phoneController.text.trim();
                final command = commandController.text.trim();
                if (phone.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a phone number.')),
                  );
                  return;
                }
                if (command.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Command cannot be empty.')),
                  );
                  return;
                }

                Navigator.pop(dialogContext);
                showProgress(true, context);

                try {
                  final requestBody = <String, String>{
                    'id': '',
                    'device_id': device.id.toString(),
                    'type': 'custom',
                    'data': command,
                  };

                  final res = await APIService.sendCommands(requestBody);
                  
                  if (!mounted) return;
                  showProgress(false, context);

                  if (res.statusCode == 200) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.white),
                            const SizedBox(width: 8),
                            Text('command_sent'.tr),
                          ],
                        ),
                        backgroundColor: _greenColor,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.error, color: Colors.white),
                            const SizedBox(width: 8),
                            Text('errorMsg'.tr),
                          ],
                        ),
                        backgroundColor: _redColor,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  }
                } catch (e) {
                  if (!mounted) return;
                  showProgress(false, context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.error, color: Colors.white),
                          const SizedBox(width: 8),
                          Text('connectionError'.tr),
                        ],
                      ),
                      backgroundColor: _redColor,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.send, size: 16),
              label: Text('sendCommand'.tr),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }


  void _showShareDialog(BuildContext context, DeviceItem device) {
    final options = [
      {'label': '10 min', 'time': 10},
      {'label': '30 min', 'time': 30},
      {'label': '60 min', 'time': 60},
      {'label': '120 min', 'time': 120},
    ];
    int selectedIndex = 0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('shareLocation'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.asMap().entries.map((entry) {
              return RadioListTile<int>(
                title: Text(entry.value['label'] as String),
                value: entry.key,
                groupValue: selectedIndex,
                onChanged: (value) => setState(() => selectedIndex = value!),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel'.tr),
            ),
            ElevatedButton(
              onPressed: () {
                expiryTime = options[selectedIndex]['time'] as int;
                _shareLink(device);
              },
              child: Text('share'.tr),
            ),
          ],
        ),
      ),
    );
  }

  void _shareLink(DeviceItem device) {
    DateTime newDateTime = DateTime.now().add(Duration(minutes: expiryTime));
    APIService.generateShare(
      device.id.toString(),
      DateFormat('yyyy-MM-dd HH:mm:ss').format(newDateTime),
      device.name,
    ).then((value) {
      Navigator.pop(context);
      if (value is SharePerm) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Check Permission")),
        );
      } else {
        Share.share(
          "Device : ${value.name} \n ${UserRepository.getServerUrl()}/sharing/${value.hash}",
          subject: "Device : ${value.name}",
        );
      }
    });
  }

  void _getEditDeviceData(deviceId) {
    showProgress(true, context);
    APIService.editDeviceData({'device_id': deviceId.toString()}).then((value) {
      showProgress(false, context);
      try {
        final decoded = json.decode(value.body.replaceAll("ï»¿", ""));
        if (decoded is Map<String, dynamic> && decoded.containsKey('message')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(decoded['message'].toString())),
          );
          return;
        }
        
        sd = SingleDevice.fromJson(decoded);
        if (sd != null && sd!.item != null) {
          _name.text = sd!.item!["name"] ?? "";
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showEditDialog(sd!.item);
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to parse device data")),
          );
        }
      } catch (e) {
        debugPrint("Error parsing edit device data: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }).catchError((e) {
      showProgress(false, context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to fetch device data: $e")),
      );
    });
  }

  void _showEditDialog(dynamic device) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.edit, color: _primaryBlue, size: 22),
              const SizedBox(width: 8),
              Text(
                'reportDeviceName'.tr,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name Input Field
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: 'sharedName'.tr,
                    prefixIcon: const Icon(Icons.label_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _primaryBlue, width: 2),
                    ),
                  ),
                ),

                // Icon Selection Section
                if (sd?.device_icons != null && sd!.device_icons!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(Icons.image_outlined,
                          color: _primaryBlue, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        "selectIcon".tr,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 3-Column Grid Layout
                  Container(
                    constraints: const BoxConstraints(maxHeight: 280),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[200]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: GridView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.95,
                      ),
                      itemCount: sd!.device_icons!.length,
                      itemBuilder: (context, index) {
                        final icon = sd!.device_icons![index];
                        final isSelected = selectedIconId == icon["id"];

                        return GestureDetector(
                          onTap: () => setState(() => selectedIconId = icon["id"]),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _primaryBlue.withValues(alpha: 0.08)
                                  : Colors.grey[50],
                              border: Border.all(
                                color: isSelected
                                    ? _primaryBlue
                                    : Colors.grey[300]!,
                                width: isSelected ? 2.5 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: isSelected
                                  ? [
                                BoxShadow(
                                  color: _primaryBlue.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                                  : [],
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: CachedNetworkImage(
                                    imageUrl: "${APIService.serverURL ?? ''}/${icon["path"]}",
                                    width: 55,
                                    height: 55,
                                    fit: BoxFit.contain,
                                    placeholder: (context, url) => const SizedBox(
                                      width: 30,
                                      height: 30,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        Icon(Icons.image_not_supported,
                                            color: Colors.grey[400]),
                                  ),
                                ),
                                if (isSelected)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: _primaryBlue,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.close, size: 18),
                  const SizedBox(width: 4),
                  Text('cancel'.tr),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => _updateDevice(device["id"]),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check, size: 18),
                  const SizedBox(width: 4),
                  Text('ok'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateDevice(deviceId) {
    showProgress(true, context);
    Map<String, String> requestBody = {
      'name': _name.text,
      'fuel_measurement_id': sd!.item!["fuel_measurement_id"].toString(),
      'device_id': deviceId.toString(),
      if (selectedIconId != null) 'icon_id': selectedIconId.toString(),
    };

    APIService.editDevice(requestBody).then((value) {
      showProgress(false, context);
      Navigator.pop(context);
      _loadDevices();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text('deviceUpdatedSuccessfully'.tr),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }).catchError((error) {
      showProgress(false, context);

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Text('updateFailed'.tr),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    });
  }
}