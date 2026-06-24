import 'dart:async';
import 'dart:developer';
import 'dart:math' as m;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_lock/screens/device_details_screen.dart';
import 'package:smart_lock/screens/lock_unlock_screen.dart';
import 'package:smart_lock/screens/playback.dart';
import 'package:smart_lock/screens/report/get_today_report.dart';
import 'package:smart_lock/screens/report/mileage_report_screen.dart';
import 'package:smart_lock/screens/report/recent_events.dart';
import 'package:smart_lock/screens/report/report_screen.dart';
import 'package:smart_lock/screens/street_view_screen.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/util/util.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:smart_lock/storage/user_repository.dart';

import 'common_method.dart';

enum DeviceStatus { running, idle, stop, offline, expired }

// ==================== SMOOTH ANIMATOR ====================
class SmoothCarAnimator {
  final TickerProvider vsync;
  final void Function(LatLng position, double bearing) onPositionUpdate;

  Ticker? _ticker;
  LatLng _currentPosition;
  double _currentBearing;
  LatLng? _targetPosition;
  double _targetBearing = 0;
  bool _isRunning = false;
  int _lastTickTime = 0;

  static const double _maxSpeed = 25.0;
  static const double _minSpeed = 5.0;
  static const double _acceleration = 15.0;
  double _currentSpeed = 0;
  static const double _bearingSpeed = 180.0;

  SmoothCarAnimator({
    required this.vsync,
    required this.onPositionUpdate,
    required LatLng initialPosition,
    double initialBearing = 0,
  })  : _currentPosition = initialPosition,
        _currentBearing = initialBearing {
    _ticker = vsync.createTicker(_onTick);
  }

  LatLng get currentPosition => _currentPosition;
  double get currentBearing => _currentBearing;

  void moveTo(LatLng target, double bearing) {
    _targetPosition = target;
    _targetBearing = bearing;
    if (!_isRunning) {
      _isRunning = true;
      _lastTickTime = DateTime.now().millisecondsSinceEpoch;
      _ticker?.start();
    }
  }

  void _onTick(Duration elapsed) {
    if (_targetPosition == null) {
      _stop();
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final dt = ((now - _lastTickTime) / 1000.0).clamp(0.001, 0.1);
    _lastTickTime = now;

    final distance = _calculateDistance(_currentPosition, _targetPosition!);
    if (distance < 0.5) {
      _currentPosition = _targetPosition!;
      _currentBearing = _normalizeBearing(_targetBearing);
      onPositionUpdate(_currentPosition, _currentBearing);
      _targetPosition = null;
      _stop();
      return;
    }

    final speed = (distance / 1.5).clamp(5.0, 150.0);
    final moveRatio = ((speed * dt) / distance).clamp(0.0, 1.0);
    _currentPosition = LatLng(
      _currentPosition.latitude +
          (_targetPosition!.latitude - _currentPosition.latitude) * moveRatio,
      _currentPosition.longitude +
          (_targetPosition!.longitude - _currentPosition.longitude) * moveRatio,
    );
    _currentBearing = _interpolateBearing(
        _currentBearing, _targetBearing, _bearingSpeed * dt);
    onPositionUpdate(_currentPosition, _currentBearing);
  }

  double _interpolateBearing(double from, double to, double maxDelta) {
    from = _normalizeBearing(from);
    to = _normalizeBearing(to);
    double diff = to - from;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    if (diff.abs() <= maxDelta) return _normalizeBearing(to);
    return _normalizeBearing(from + diff.sign * maxDelta);
  }

  double _normalizeBearing(double b) {
    b = b % 360;
    return b < 0 ? b + 360 : b;
  }

  double _calculateDistance(LatLng a, LatLng b) {
    const R = 6371000.0;
    final lat1 = a.latitude * m.pi / 180;
    final lat2 = b.latitude * m.pi / 180;
    final dLat = (b.latitude - a.latitude) * m.pi / 180;
    final dLon = (b.longitude - a.longitude) * m.pi / 180;
    final x = m.sin(dLat / 2) * m.sin(dLat / 2) +
        m.cos(lat1) * m.cos(lat2) * m.sin(dLon / 2) * m.sin(dLon / 2);
    return R * 2 * m.atan2(m.sqrt(x), m.sqrt(1 - x));
  }

  void _stop() {
    _isRunning = false;
    _ticker?.stop();
  }

  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
  }
}

// ==================== MAIN WIDGET ====================
class TrackDevicePage extends StatefulWidget {
  final int? id;
  final String? name;
  final DeviceItem? device;

  const TrackDevicePage(this.id, this.name, this.device, {super.key});

  @override
  State<StatefulWidget> createState() => _TrackDeviceState();
}

class _TrackDeviceState extends State<TrackDevicePage>
    with TickerProviderStateMixin {
  static final Map<int, String> _lastBatteryTextCache = {};
  static final Map<int, Color> _lastBatteryColorCache = {};
  static final Map<int, IconData> _lastBatteryIconCache = {};
  static final Map<int, String> _lastBatteryLabelCache = {};

  GoogleMapController? _mapController;
  bool _isMapCreated = false;
  MapType _currentMapType = MapType.normal;
  double _currentZoom = 16.0;
  bool _trafficEnabled = false;
  bool _followVehicle = true;
  String? _mapStyle;
  bool _isDisposed = false;
  bool _userInteracting = false;
  bool _isProgrammaticMove = false;

  final ValueNotifier<Set<Marker>> _markersNotifier =
      ValueNotifier<Set<Marker>>({});
  final ValueNotifier<Set<Polyline>> _polylinesNotifier =
      ValueNotifier<Set<Polyline>>({});

  DeviceItem? device;
  String todaytotalDistance = "--";
  String todayEngineHours = "--";
  String? _address;
  String? _lastFetchedCoordinates;
  TodayReportData? todayData;

  SmoothCarAnimator? _carAnimator;
  BitmapDescriptor? _markerIcon;
  bool _isMarkerReady = false;
  String? _lastLocalIconPath;

  final List<LatLng> _polylinePoints = [];
  static const int _maxPolylinePoints = 100;
  LatLng? _lastPolylinePoint;

  Timer? _dataTimer;
  Timer? _cameraTimer;

  // Colors
  static const _primaryRed = Color(0xFFCC0000);
  static const _successColor = Color(0xFF22C55E);
  static const _warningColor = Color(0xFFF59E0B);
  static const _dangerColor = Color(0xFFEF4444);
  static const _primaryBlue = Color(0xFF3B82F6);
  static const _neutralColor = Color(0xFF9CA3AF);
  static const _darkColor = Color(0xFF374151);

  StreamSubscription? _onlyDevicesSubscription;

  bool _hasDeviceChanged(DeviceItem? a, DeviceItem b) {
    if (a == null) return true;
    final currentLocalPath =
        UserRepository.prefs?.getString("custom_icon_path_${b.id}");
    if (_lastLocalIconPath != currentLocalPath) {
      return true;
    }
    return a.lat != b.lat ||
        a.lng != b.lng ||
        a.speed != b.speed ||
        a.online != b.online ||
        a.course != b.course ||
        a.engineStatus != b.engineStatus ||
        a.stopDuration != b.stopDuration ||
        a.totalDistance != b.totalDistance ||
        a.power != b.power ||
        a.icon?.path != b.icon?.path ||
        a.icon?.type != b.icon?.type ||
        a.iconColor != b.iconColor;
  }

  @override
  void initState() {
    super.initState();
    device = widget.device;
    if (widget.device != null) {
      _lastLocalIconPath = UserRepository.prefs
          ?.getString("custom_icon_path_${widget.device!.id}");
      _updateBatteryStatus(widget.device!);
    }

    final DataController controller = Get.put(DataController());
    _onlyDevicesSubscription = controller.onlyDevices.listen((devices) {
      if (mounted && !_isDisposed) {
        for (var element in devices) {
          if (element.id == widget.id) {
            if (_hasDeviceChanged(device, element)) {
              _lastLocalIconPath = UserRepository.prefs
                  ?.getString("custom_icon_path_${element.id}");
              setState(() {
                device = element;
              });
              _updateBatteryStatus(element);
              updateMarker(element);
            }
            break;
          }
        }
      }
    });

    _loadMapStyle();
    _initializeAll();
  }

  Future<void> _initializeAll() async {
    final initialPos = _getInitialPosition();
    final initialBearing =
        double.tryParse(device?.course?.toString() ?? '0') ?? 0;
    _carAnimator = SmoothCarAnimator(
      vsync: this,
      onPositionUpdate: _onCarPositionUpdate,
      initialPosition: initialPos,
      initialBearing: initialBearing,
    );
    await _loadMarkerIcon();
    _polylinePoints.add(initialPos);
    _lastPolylinePoint = initialPos;
    _updateMapMarkers();
    _startDataTimer();
    _startCameraTimer();
  }

  LatLng _getInitialPosition() {
    if (device?.lat != null && device?.lng != null) {
      return LatLng(double.parse(device!.lat.toString()),
          double.parse(device!.lng.toString()));
    }
    return const LatLng(0, 0);
  }

  void _loadMapStyle() {
    rootBundle.loadString('assets/map_style.txt').then((string) {
      _mapStyle = string;
      if (_isMapCreated && _mapController != null) {
        _mapController!.setMapStyle(_mapStyle);
      }
    }).catchError((e) => debugPrint("Map style error: $e"));
  }

  Future<void> _loadMarkerIcon() async {
    if (device?.icon?.path == null) {
      _markerIcon = BitmapDescriptor.defaultMarker;
      _isMarkerReady = true;
      return;
    }
    try {
      _markerIcon = await Util.getMarkerIcon(
        device!.icon!.path!,
        statusColor: Util.getDeviceStatusColorStr(device!),
        iconType: device!.icon?.type ?? device!.iconType,
        deviceName: device!.name,
        deviceId: device!.id,
      );
      _isMarkerReady = true;
      if (mounted && !_isDisposed) _updateMapMarkers();
    } catch (e) {
      _markerIcon = BitmapDescriptor.defaultMarker;
      _isMarkerReady = true;
    }
  }

  void _startDataTimer() {
    _fetchAllData();
    _dataTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_isDisposed) _fetchAllData();
    });
  }

  void _startCameraTimer() {
    // Camera follow is updated instantly inside the animator callback
  }

  Future<void> _fetchAllData() async {
    if (_isDisposed || widget.device?.id == null) return;
    final deviceId = widget.device!.id!;
    try {
      final current = DateTime.now();
      final year = current.year;
      final month = current.month.toString().padLeft(2, '0');
      final day = current.day.toString().padLeft(2, '0');
      final fromDate = formatDateReport("$year-$month-$day 00:00:00");
      final toDate = formatDateReport("$year-$month-$day 23:59:59");

      try {
        final history = await APIService.getHistory(
            deviceId.toString(), fromDate, "00:00", toDate, "23:59");
        if (history != null && mounted && !_isDisposed) {
          setState(() => todaytotalDistance = history.distance_sum ?? "0");
        }
      } catch (e) {
        log("History error: $e");
      }

      try {
        final report =
            await ReportService.getTodayReportData(deviceId: deviceId);
        if (mounted && !_isDisposed) {
          setState(() {
            todayData = report;
            todayEngineHours = report.engineHours ?? "--";
          });
        }
      } catch (e) {
        log("Report error: $e");
      }
    } catch (e) {
      log("Data fetch error: $e");
    }
  }

  void updateMarker(DeviceItem element) async {
    if (_isDisposed || _carAnimator == null) return;
    final newPos = LatLng(double.parse(element.lat.toString()),
        double.parse(element.lng.toString()));
    final newBearing =
        double.tryParse(element.course?.toString() ?? '0.0') ?? 0.0;
    _carAnimator!.moveTo(newPos, newBearing);

    // Dynamically update marker icon on state change (status, color, local settings)
    if (element.icon?.path != null) {
      try {
        final icon = await Util.getMarkerIcon(
          element.icon!.path!,
          statusColor: Util.getDeviceStatusColorStr(element),
          iconType: element.icon?.type ?? element.iconType,
          deviceName: element.name,
          deviceId: element.id,
        );
        if (!_isDisposed && icon != _markerIcon) {
          _markerIcon = icon;
          _isMarkerReady = true;
          _updateMapMarkers();
        }
      } catch (e) {
        debugPrint("Error updating marker icon: $e");
      }
    }
  }

  void _onCarPositionUpdate(LatLng position, double bearing) {
    if (_isDisposed) return;
    if (_lastPolylinePoint == null ||
        _calculateDistance(_lastPolylinePoint!, position) > 5) {
      _polylinePoints.add(position);
      _lastPolylinePoint = position;
      if (_polylinePoints.length > _maxPolylinePoints) {
        _polylinePoints.removeAt(0);
      }
    }
    _updateMapMarkers();
    if (_followVehicle &&
        _isMapCreated &&
        _mapController != null &&
        !_isProgrammaticMove) {
      _mapController!.moveCamera(CameraUpdate.newLatLng(position));
    }
  }

  void _updateMapMarkers() {
    if (_isDisposed || !_isMarkerReady || _carAnimator == null) return;
    final marker = Marker(
      markerId: const MarkerId("vehicle"),
      position: _carAnimator!.currentPosition,
      rotation: _carAnimator!.currentBearing,
      icon: _markerIcon ?? BitmapDescriptor.defaultMarker,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      zIndex: 2,
    );
    final points = List<LatLng>.from(_polylinePoints);
    if (!points.contains(_carAnimator!.currentPosition)) {
      points.add(_carAnimator!.currentPosition);
    }
    final polyline = Polyline(
      polylineId: const PolylineId("trail"),
      points: points,
      color: _primaryBlue.withValues(alpha: 0.7),
      width: 4,
      geodesic: true,
      jointType: JointType.round,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    );
    _markersNotifier.value = {marker};
    _polylinesNotifier.value = {polyline};
  }

  double _calculateDistance(LatLng a, LatLng b) {
    const R = 6371000.0;
    final lat1 = a.latitude * m.pi / 180;
    final lat2 = b.latitude * m.pi / 180;
    final dLat = (b.latitude - a.latitude) * m.pi / 180;
    final dLon = (b.longitude - a.longitude) * m.pi / 180;
    final x = m.sin(dLat / 2) * m.sin(dLat / 2) +
        m.cos(lat1) * m.cos(lat2) * m.sin(dLon / 2) * m.sin(dLon / 2);
    return R * 2 * m.atan2(m.sqrt(x), m.sqrt(1 - x));
  }

  // ==================== STATUS ====================
  DeviceStatus _getDeviceStatus(DeviceItem? d) {
    if (d == null) return DeviceStatus.offline;
    final colorStr = Util.getDeviceStatusColorStr(d);
    switch (colorStr) {
      case 'green':
        return DeviceStatus.running;
      case 'yellow':
        return DeviceStatus.idle;
      case 'red':
        return DeviceStatus.stop;
      case 'orange':
        return DeviceStatus.expired;
      default:
        return DeviceStatus.offline;
    }
  }

  Color _getStatusColor() {
    switch (_getDeviceStatus(device)) {
      case DeviceStatus.running:
        return _successColor;
      case DeviceStatus.idle:
        return _warningColor;
      case DeviceStatus.stop:
        return _dangerColor;
      case DeviceStatus.offline:
        return _neutralColor;
      case DeviceStatus.expired:
        return Colors.orange;
    }
  }

  String _getStatusText() {
    switch (_getDeviceStatus(device)) {
      case DeviceStatus.running:
        return "Moving";
      case DeviceStatus.idle:
        return "Idle";
      case DeviceStatus.stop:
        return "Stopped";
      case DeviceStatus.offline:
        return "Offline";
      case DeviceStatus.expired:
        return "Expired";
    }
  }

  void _fetchAddress() {
    if (device?.lat == null) return;

    final double? latVal = double.tryParse(device!.lat.toString());
    final double? lngVal = double.tryParse(device!.lng.toString());
    if (latVal == null || lngVal == null) return;
    final currentCoordinates =
        "${latVal.toStringAsFixed(4)},${lngVal.toStringAsFixed(4)}";

    if (_lastFetchedCoordinates == currentCoordinates) return;
    _lastFetchedCoordinates = currentCoordinates;

    final cached = APIService.getCachedAddress(device!.lat, device!.lng);
    if (cached != null) {
      _address = cached.replaceAll('"', '');
      return;
    }

    APIService.getGeocoderAddress(
            device!.lat.toString(), device!.lng.toString())
        .then((addr) {
      if (!_isDisposed && mounted) {
        setState(() => _address = addr.replaceAll('"', ''));
      }
    });
  }

  // ==================== BATTERY HELPERS ====================

  void _updateBatteryStatus(DeviceItem element) {
    final devId = element.id;
    if (devId == null) return;

    final sensors = element.sensors;
    if (sensors == null || sensors.isEmpty) return;

    Map? batterySensor;
    Map? voltageSensor;

    // Search for battery and voltage/ADC/analog sensors in the list
    for (var s in sensors) {
      if (s is! Map) continue;
      final type = (s['type'] ?? '').toString().toLowerCase().trim();
      final name = (s['name'] ?? '').toString().toLowerCase().trim();

      if (type == 'battery' || name.contains('battery')) {
        batterySensor = s;
      } else if (type == 'voltage' ||
          name.contains('voltage') ||
          name.contains('power') ||
          type.contains('adc') ||
          name.contains('adc') ||
          name.contains('analog')) {
        voltageSensor = s;
      }
    }

    // Use battery sensor if available, otherwise fallback to voltage/ADC sensor
    final sensor = batterySensor ?? voltageSensor;
    if (sensor == null) return;

    final type = (sensor['type'] ?? '').toString().toLowerCase().trim();
    final name = (sensor['name'] ?? '').toString().toLowerCase().trim();

    // Extract text value
    final rawVal = sensor['val'];
    var formattedValue = sensor['value']?.toString() ?? '';

    // Normalize format: if it is just a number, append unit based on type
    if (formattedValue.isNotEmpty && formattedValue != 'null') {
      final cleanVal = formattedValue.trim();
      final isDigitsOnly = RegExp(r'^[0-9.]+$').hasMatch(cleanVal);
      if (isDigitsOnly) {
        final isVoltage = type == 'voltage' ||
            name.contains('voltage') ||
            name.contains('power') ||
            type.contains('adc') ||
            name.contains('adc') ||
            name.contains('analog');
        if (isVoltage) {
          formattedValue = '$cleanVal V';
        } else {
          formattedValue = cleanVal;
        }
      }
    }

    String text = '';
    if (formattedValue.isNotEmpty && formattedValue != 'null') {
      text = formattedValue;
    } else if (rawVal != null) {
      final isVoltage = type == 'voltage' ||
          name.contains('voltage') ||
          name.contains('power') ||
          type.contains('adc') ||
          name.contains('adc') ||
          name.contains('analog');
      if (isVoltage) {
        text = '$rawVal V';
      } else {
        text = rawVal.toString();
      }
    }

    if (text.isNotEmpty) {
      _lastBatteryTextCache[devId] = text;
      if (UserRepository.prefs != null) {
        UserRepository.prefs!.setString('battery_text_$devId', text);
      }

      final isVoltage = (type == 'voltage' ||
              name.contains('voltage') ||
              name.contains('power') ||
              type.contains('adc') ||
              name.contains('adc') ||
              name.contains('analog') ||
              text.toLowerCase().contains('v')) &&
          !(type == 'battery' ||
              name.contains('battery') ||
              text.contains('%'));
      final label = isVoltage ? 'Voltage' : 'Battery';
      _lastBatteryLabelCache[devId] = label;
      if (UserRepository.prefs != null) {
        UserRepository.prefs!.setString('battery_label_$devId', label);
      }

      // Update color based on raw value
      final val = double.tryParse(rawVal?.toString() ?? '') ??
          double.tryParse(formattedValue.replaceAll(RegExp(r'[^0-9.]'), '')) ??
          100.0;

      Color color = _successColor;
      if (isVoltage) {
        if (val <= 11.5 || (val > 30 && val <= 34) || (val > 40 && val <= 44)) {
          color = _dangerColor;
        } else if (val <= 12.0 ||
            (val > 30 && val <= 36) ||
            (val > 40 && val <= 47)) {
          color = _warningColor;
        } else {
          color = _successColor;
        }
      } else {
        if (val <= 20) {
          color = _dangerColor;
        } else if (val <= 50) {
          color = _warningColor;
        } else {
          color = _successColor;
        }
      }
      _lastBatteryColorCache[devId] = color;
      if (UserRepository.prefs != null) {
        UserRepository.prefs!.setInt('battery_color_$devId', color.value);
      }

      // Update icon based on raw value
      IconData icon = Icons.battery_full;
      if (isVoltage) {
        icon = Icons.battery_charging_full_outlined;
      } else {
        final pct = double.tryParse(rawVal?.toString() ?? '') ?? 100.0;
        if (pct <= 10) {
          icon = Icons.battery_0_bar;
        } else if (pct <= 25) {
          icon = Icons.battery_1_bar;
        } else if (pct <= 40) {
          icon = Icons.battery_2_bar;
        } else if (pct <= 55) {
          icon = Icons.battery_3_bar;
        } else if (pct <= 70) {
          icon = Icons.battery_4_bar;
        } else if (pct <= 85) {
          icon = Icons.battery_5_bar;
        } else {
          icon = Icons.battery_full;
        }
      }
      _lastBatteryIconCache[devId] = icon;
      if (UserRepository.prefs != null) {
        UserRepository.prefs!.setInt('battery_icon_$devId', icon.codePoint);
      }
    }
  }

  String _getBatteryText() {
    final devId = widget.id;
    if (devId != null && _lastBatteryTextCache.containsKey(devId)) {
      return _lastBatteryTextCache[devId]!;
    }
    if (devId != null && UserRepository.prefs != null) {
      final savedVal = UserRepository.prefs!.getString('battery_text_$devId');
      if (savedVal != null && savedVal.isNotEmpty) {
        _lastBatteryTextCache[devId] = savedVal;
        return savedVal;
      }
    }
    return '54.4'; // Fixed default fallback
  }

  Color _getBatteryColor() {
    final devId = widget.id;
    if (devId != null && _lastBatteryColorCache.containsKey(devId)) {
      return _lastBatteryColorCache[devId]!;
    }
    if (devId != null && UserRepository.prefs != null) {
      final savedVal = UserRepository.prefs!.getInt('battery_color_$devId');
      if (savedVal != null) {
        final c = Color(savedVal);
        _lastBatteryColorCache[devId] = c;
        return c;
      }
    }
    return _successColor; // Default fallback to green
  }

  IconData _getBatteryIcon() {
    final devId = widget.id;
    if (devId != null && _lastBatteryIconCache.containsKey(devId)) {
      return _lastBatteryIconCache[devId]!;
    }
    if (devId != null && UserRepository.prefs != null) {
      final savedVal = UserRepository.prefs!.getInt('battery_icon_$devId');
      if (savedVal != null) {
        final ic = IconData(savedVal, fontFamily: 'MaterialIcons');
        _lastBatteryIconCache[devId] = ic;
        return ic;
      }
    }
    return Icons.battery_full; // Default fallback icon
  }

  String _getBatteryLabel() {
    final devId = widget.id;
    if (devId != null && _lastBatteryLabelCache.containsKey(devId)) {
      return _lastBatteryLabelCache[devId]!;
    }
    if (devId != null && UserRepository.prefs != null) {
      final savedVal = UserRepository.prefs!.getString('battery_label_$devId');
      if (savedVal != null && savedVal.isNotEmpty) {
        _lastBatteryLabelCache[devId] = savedVal;
        return savedVal;
      }
    }
    return 'Battery'; // Default fallback label
  }

  // ==================== ACTIONS ====================
  void _centerOnVehicle() async {
    if (_carAnimator == null || _mapController == null) return;
    setState(() {
      _isProgrammaticMove = true;
      _followVehicle = true;
    });
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(
          target: _carAnimator!.currentPosition,
          zoom: 17,
          bearing: _carAnimator!.currentBearing,
          tilt: 45,
        )),
      );
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isProgrammaticMove = false;
        });
      }
    }
  }

  // ==================== MY LOCATION ====================
  Future<void> _goToMyLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          Get.snackbar('Permission Denied', 'Location permission is required.',
              backgroundColor: Colors.red.withValues(alpha: 0.9),
              colorText: Colors.white);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        Get.snackbar(
            'Permission Denied', 'Enable location permission in settings.',
            backgroundColor: Colors.red.withValues(alpha: 0.9),
            colorText: Colors.white);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final myLatLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _isProgrammaticMove = true;
        _followVehicle = false;
      });

      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(CameraPosition(
            target: myLatLng,
            zoom: 17,
          )),
        );
      }
    } catch (e) {
      Get.snackbar('Error', 'Could not get your location: $e',
          backgroundColor: Colors.red.withValues(alpha: 0.9),
          colorText: Colors.white);
    } finally {
      if (mounted) {
        setState(() {
          _isProgrammaticMove = false;
        });
      }
    }
  }

  // ==================== TRAFFIC TOGGLE ====================
  void _toggleTraffic() {
    setState(() => _trafficEnabled = !_trafficEnabled);
  }

  void _openPlayback() => Get.to(
      () => PlaybackScreen(id: widget.id, name: widget.name, device: device));

  void _openLock() async {
    if (device == null) return;
    final updatedDevice = await Get.to<DeviceItem>(
      () => LockUnlockScreen(device: device!),
    );
    if (updatedDevice != null && mounted) {
      setState(() => device = updatedDevice);
    }
  }

  void _openDetails() {
    if (device != null) Get.to(() => DeviceDetailsScreen(device: device!));
  }

  void _showReport(DeviceItem device) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => ReportScreen(
              deviceId: device.id ?? 0, deviceName: device.name ?? '')),
    );
  }

  void _navigate() {
    if (device?.lat == null) return;
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=${device!.lat},${device!.lng}';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _openStreetView() {
    if (device?.lat != null) {
      Get.to(() =>
          StreetViewScreen(latitude: device!.lat!, longitude: device!.lng!));
    }
  }

  void _callDevice() async {
    final sim = device?.deviceData?.simNumber;
    if (sim != null && sim.isNotEmpty) {
      await launchUrl(Uri(scheme: 'tel', path: sim));
    } else {
      Get.snackbar('Error', 'Phone number not found',
          backgroundColor: Colors.red.withValues(alpha: 0.9),
          colorText: Colors.white);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _onlyDevicesSubscription?.cancel();
    _dataTimer?.cancel();
    _cameraTimer?.cancel();
    _carAnimator?.dispose();
    _mapController = null;
    _markersNotifier.dispose();
    _polylinesNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        _buildMap(),
        _buildLeftControls(),
        _buildRightControls(),
        _buildBackButton(),
        _buildSpeedOverlay(),
        _buildBottomSheet(),
      ],
    );
  }

  Widget _buildMap() {
    return ValueListenableBuilder<Set<Marker>>(
      valueListenable: _markersNotifier,
      builder: (context, markers, _) {
        return ValueListenableBuilder<Set<Polyline>>(
          valueListenable: _polylinesNotifier,
          builder: (context, polylines, _) {
            return GoogleMap(
              mapType: _currentMapType,
              trafficEnabled: _trafficEnabled,
              initialCameraPosition:
                  CameraPosition(target: _getInitialPosition(), zoom: 16),
              onCameraMove: (pos) {
                _currentZoom = pos.zoom;
              },
              onMapCreated: (controller) {
                _mapController = controller;
                _isMapCreated = true;
                if (_mapStyle != null) controller.setMapStyle(_mapStyle);
                if (_carAnimator != null) {
                  controller.animateCamera(CameraUpdate.newCameraPosition(
                    CameraPosition(
                        target: _carAnimator!.currentPosition, zoom: 16),
                  ));
                }
              },
              markers: markers,
              polylines: polylines,
              padding: const EdgeInsets.only(bottom: 260),
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              scrollGesturesEnabled: !_followVehicle,
              zoomGesturesEnabled: true,
              mapToolbarEnabled: false,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
            );
          },
        );
      },
    );
  }

  Widget _buildSpeedOverlay() {
    final speed = double.tryParse(device?.speed.toString() ?? '0') ?? 0;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 56,
      left: 12,
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: _dangerColor, width: 3),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              speed.toInt().toString(),
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151),
                  height: 1),
            ),
            const Text('Kmh',
                style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      child: Material(
        elevation: 2,
        shape: const CircleBorder(),
        color: Colors.white,
        child: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
          onPressed: () => Get.back(),
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ),
    );
  }

  Widget _buildLeftControls() {
    return Positioned(
      left: 12,
      top: MediaQuery.of(context).padding.top + 136,
      child: Column(
        children: [
          _buildMapBtn(Icons.lock, _darkColor, _openLock),
          const SizedBox(height: 8),
          _buildMapBtn(Icons.play_arrow, _darkColor, _openPlayback),
          const SizedBox(height: 8),
          _buildMapBtn(
            Icons.bar_chart,
            _darkColor,
            () {
              if (device != null) _showReport(device!);
            },
          ),
          const SizedBox(height: 8),
          _buildMapBtn(
            Icons.directions_car,
            _darkColor,
            () {
              if (device != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MileageReportScreen(
                      deviceId: device!.id ?? 0,
                      deviceName: device!.name,
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRightControls() {
    return Positioned(
      right: 12,
      top: MediaQuery.of(context).padding.top + 8,
      child: Column(
        children: [
          // Satellite / Normal map toggle
          _buildMapBtn(
            Icons.map_outlined,
            _darkColor,
            () => setState(() {
              _currentMapType = _currentMapType == MapType.normal
                  ? MapType.hybrid
                  : MapType.normal;
            }),
            selected: _currentMapType == MapType.hybrid,
            selectedColor: _successColor,
          ),
          const SizedBox(height: 8),

          // Follow vehicle / GPS
          _buildMapBtn(
            _followVehicle ? Icons.gps_fixed : Icons.gps_not_fixed,
            _primaryBlue,
            _centerOnVehicle,
            selected: _followVehicle,
            selectedColor: _primaryBlue,
          ),
          const SizedBox(height: 8),

          // Traffic toggle
          _buildMapBtn(
            Icons.traffic,
            _trafficEnabled ? Colors.white : _darkColor,
            _toggleTraffic,
            selected: _trafficEnabled,
            selectedColor: _successColor,
          ),
          const SizedBox(height: 8),

          // My Location
          _buildMapBtn(
            Icons.my_location,
            _primaryBlue,
            _goToMyLocation,
          ),
          const SizedBox(height: 8),

          _buildMapBtn(Icons.people_alt_outlined, _darkColor, () {}),
          const SizedBox(height: 8),
          _buildMapBtn(Icons.navigation, _darkColor, _navigate),
          const SizedBox(height: 8),
          _buildMapBtn(Icons.streetview, _primaryBlue, _openStreetView),
          const SizedBox(height: 8),

          // Support button (red with green dot)
          Stack(
            children: [
              _buildMapBtn(Icons.headset_mic, Colors.white, _callDevice,
                  bgColor: _dangerColor),
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _successColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMapBtn(IconData icon, Color iconColor, VoidCallback onTap,
      {bool selected = false, Color? selectedColor, Color? bgColor}) {
    final bg =
        bgColor ?? (selected ? (selectedColor ?? _primaryBlue) : Colors.white);
    final ic =
        bgColor != null ? Colors.white : (selected ? Colors.white : iconColor);
    return Material(
      color: bg,
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: ic),
        ),
      ),
    );
  }

  Widget _buildBottomSheet() {
    _fetchAddress();
    return DraggableScrollableSheet(
      initialChildSize: 0.30,
      minChildSize: 0.08,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 15,
                  offset: Offset(0, -5))
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              _buildSheetHandle(),
              _buildActionButtons(),
              _buildAddressRow(),
              _buildImeiRow(),
              _buildStatusRow(),
              _buildMileageRow(),
              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSheetHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(2)),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _buildActionBtn(Icons.play_circle_fill, 'Play Back',
              const Color(0xFF3B82F6), _openPlayback),
          _buildActionBtn(
              Icons.notifications_active, 'Alert', const Color(0xFFF59E0B), () {
            Get.to(() => EventsPage());
          }),
          _buildActionBtn(
              Icons.lock, 'Lock', const Color(0xFF22C55E), _openLock),
          _buildActionBtn(
              Icons.settings, 'Setting', const Color(0xFF0EA5E9), _openDetails),
        ],
      ),
    );
  }

  Widget _buildActionBtn(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 5),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF374151),
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6)))),
      child: Text(
        _address ?? '',
        style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
      ),
    );
  }

  Widget _buildImeiRow() {
    final name = device?.name ?? device?.deviceData?.name ?? widget.name ?? '';
    final imei = device?.imei ?? device?.deviceData?.imei ?? '';
    final displayName = name.isNotEmpty ? name : imei;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(displayName,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF374151),
                  fontWeight: FontWeight.w500)),
          Text(imei,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF374151),
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    final status = _getDeviceStatus(device);
    final isEngineOn = device != null ? Util.isEngineOn(device!) : false;
    final stopDuration = device?.stopDuration ?? '--';
    String expiryStr = '--';
    try {
      final expiry = device?.deviceData?.expirationDate?.toString() ?? '';
      if (expiry.isNotEmpty) {
        final date = DateTime.tryParse(expiry);
        if (date != null) {
          expiryStr =
              '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
        }
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Status / Speed
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_getStatusText(),
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3)),
            Text(
              status == DeviceStatus.running
                  ? '${double.tryParse(device?.speed?.toString() ?? '0')?.toInt() ?? 0} km/h'
                  : stopDuration,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _getStatusColor()),
            ),
          ]),

          // ACC / Engine
          Column(children: [
            Text('Acc',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500)),
            Text(isEngineOn ? 'On' : 'Off',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937))),
          ]),

          // ==================== BATTERY (FIXED) ====================
          Column(children: [
            Text(_getBatteryLabel(),
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getBatteryIcon(),
                  size: 14,
                  color: _getBatteryColor(),
                ),
                const SizedBox(width: 2),
                Text(
                  _getBatteryText(),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _getBatteryColor()),
                ),
              ],
            ),
          ]),
          // =========================================================

          // Expiry
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Expired On',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500)),
            Text(expiryStr,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937))),
          ]),
        ],
      ),
    );
  }

  Widget _buildMileageRow() {
    final totalMileage = device?.totalDistance?.toStringAsFixed(1) ?? '0';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${todaytotalDistance}Km',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937))),
            Text('Today Mileage',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${totalMileage}Km',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937))),
            Text('Total Mileage',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ]),
        ],
      ),
    );
  }
}
