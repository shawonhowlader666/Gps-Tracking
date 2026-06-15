import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' as m;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gpspro/screens/lock_unlock_screen.dart';
import 'package:gpspro/screens/playback.dart';
import 'package:gpspro/screens/report/get_today_report.dart';
import 'package:gpspro/screens/report/report_screen.dart';
import 'package:gpspro/screens/street_view_screen.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/util/util.dart';
import 'package:gpspro/widgets/scale_button.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common_method.dart';

enum DeviceStatus { running, idle, stop, offline }

// ==================== ULTRA SMOOTH CAR ANIMATOR ====================
class UltraSmoothCarAnimator {
  final TickerProvider vsync;
  final void Function(LatLng position, double bearing) onPositionUpdate;

  Ticker? _ticker;

  // Current state
  LatLng _currentPosition;
  double _currentBearing;

  // Target state
  LatLng? _targetPosition;
  double _targetBearing = 0;

  // Animation state
  bool _isRunning = false;
  int _lastTickTime = 0;

  // Speed configuration (meters per second)
  static const double _maxSpeed = 25.0; // ~90 km/h max animation speed
  static const double _minSpeed = 5.0;  // ~18 km/h min animation speed
  static const double _acceleration = 15.0; // m/s²

  double _currentSpeed = 0;

  // Bearing interpolation
  static const double _bearingSpeed = 180.0; // degrees per second

  UltraSmoothCarAnimator({
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
    final deltaTime = (now - _lastTickTime) / 1000.0; // seconds
    _lastTickTime = now;

    // Clamp delta time to prevent jumps
    final dt = deltaTime.clamp(0.001, 0.1);

    // Calculate distance to target
    final distance = _calculateDistance(_currentPosition, _targetPosition!);

    if (distance < 0.5) {
      // Very close to target, snap to it
      _currentPosition = _targetPosition!;
      _currentBearing = _normalizeBearing(_targetBearing);
      onPositionUpdate(_currentPosition, _currentBearing);
      _targetPosition = null;
      _currentSpeed = 0;
      _stop();
      return;
    }

    // Calculate target speed based on distance (slow down when approaching)
    double targetSpeed;
    if (distance < 10) {
      targetSpeed = _minSpeed;
    } else if (distance < 50) {
      targetSpeed = _minSpeed + (distance - 10) / 40 * (_maxSpeed - _minSpeed);
    } else {
      targetSpeed = _maxSpeed;
    }

    // Smooth acceleration/deceleration
    if (_currentSpeed < targetSpeed) {
      _currentSpeed = m.min(_currentSpeed + _acceleration * dt, targetSpeed);
    } else {
      _currentSpeed = m.max(_currentSpeed - _acceleration * dt, targetSpeed);
    }

    // Calculate movement this frame
    final moveDistance = _currentSpeed * dt;
    final moveRatio = (moveDistance / distance).clamp(0.0, 1.0);

    // Interpolate position
    final newLat = _currentPosition.latitude +
        (_targetPosition!.latitude - _currentPosition.latitude) * moveRatio;
    final newLng = _currentPosition.longitude +
        (_targetPosition!.longitude - _currentPosition.longitude) * moveRatio;

    _currentPosition = LatLng(newLat, newLng);

    // Smooth bearing interpolation
    _currentBearing = _interpolateBearing(
      _currentBearing,
      _targetBearing,
      _bearingSpeed * dt,
    );

    onPositionUpdate(_currentPosition, _currentBearing);
  }

  double _interpolateBearing(double from, double to, double maxDelta) {
    from = _normalizeBearing(from);
    to = _normalizeBearing(to);

    double diff = to - from;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    if (diff.abs() <= maxDelta) {
      return _normalizeBearing(to);
    }

    return _normalizeBearing(from + diff.sign * maxDelta);
  }

  double _normalizeBearing(double bearing) {
    bearing = bearing % 360;
    return bearing < 0 ? bearing + 360 : bearing;
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
  // MAP
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

  // MARKERS - Direct state, no streams
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  // DEVICE DATA
  DeviceItem? device;
  String todaytotalDistance = "--";
  String todayEngineHours = "--";
  String? _address;
  TodayReportData? todayData;


  // SMOOTH ANIMATION
  UltraSmoothCarAnimator? _carAnimator;
  BitmapDescriptor? _markerIcon;
  bool _isMarkerReady = false;

  // POLYLINE
  final List<LatLng> _polylinePoints = [];
  static const int _maxPolylinePoints = 100;
  LatLng? _lastPolylinePoint;

  // TIMERS
  Timer? _dataTimer;
  Timer? _cameraTimer;

  // COLORS
  static const _successColor = Color(0xFF22C55E);
  static const _warningColor = Color(0xFFF59E0B);
  static const _dangerColor = Color(0xFFEF4444);
  static const _primaryColor = Color(0xFF1B851C);
  static const _neutralColor = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    device = widget.device;

    _loadMapStyle();
    _initializeAll();
  }

  Future<void> _initializeAll() async {
    // Initialize position first
    final initialPos = _getInitialPosition();
    final initialBearing = double.tryParse(device?.course?.toString() ?? '0') ?? 0;

    // Initialize animator
    _carAnimator = UltraSmoothCarAnimator(
      vsync: this,
      onPositionUpdate: _onCarPositionUpdate,
      initialPosition: initialPos,
      initialBearing: initialBearing,
    );

    // Load marker icon (smaller size = 40)
    await _loadMarkerIcon();

    // Add initial polyline point
    _polylinePoints.add(initialPos);
    _lastPolylinePoint = initialPos;

    // Update map
    _updateMapMarkers();

    // Start data fetching
    _startDataTimer();

    // Start smooth camera updates
    _startCameraTimer();
  }

  LatLng _getInitialPosition() {
    if (device?.lat != null && device?.lng != null) {
      return LatLng(
        double.parse(device!.lat.toString()),
        double.parse(device!.lng.toString()),
      );
    }
    return const LatLng(0, 0);
  }

  void _loadMapStyle() {
    rootBundle.loadString('assets/map_style.txt').then((string) {
      _mapStyle = string;
      if (_isMapCreated && _mapController != null) {
        _mapController!.setMapStyle(_mapStyle);
      }
    }).catchError((e) => debugPrint('Map style error: $e'));
  }

  Future<void> _loadMarkerIcon() async {
    if (device?.icon?.path == null) {
      _markerIcon = BitmapDescriptor.defaultMarker;
      _isMarkerReady = true;
      return;
    }

    try {
      final path = device!.icon!.path!;
      _markerIcon = await Util.getMarkerIcon(path);

      _isMarkerReady = true;

      if (mounted && !_isDisposed) {
        _updateMapMarkers();
      }
    } catch (e) {
      debugPrint('Marker icon error: $e');
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

  // void _startCameraTimer() {
  //   // Smooth camera following - update every 100ms
  //   _cameraTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
  //     if (_followVehicle && _isMapCreated && _carAnimator != null) {
  //       _mapController?.moveCamera(
  //         CameraUpdate.newLatLng(_carAnimator!.currentPosition),
  //       );
  //     }
  //   });
  // }

  Future<void> _fetchAllData() async {
    if (_isDisposed || widget.device?.id == null) return;

    final deviceId = widget.device!.id!;

    // Diagnostic log to investigate satellite count and sensor values
    debugPrint("--- DIAGNOSTICS CHECK ---");
    debugPrint("Device Sensors: ${device?.sensors}");
    debugPrint("Device Parameters: ${device?.deviceData?.parameters}");
    debugPrint("Traccar Other: ${device?.deviceData?.traccar?.other}");
    debugPrint("-------------------------");

    try {
      final current = DateTime.now();
      final year = current.year;
      final month = current.month.toString().padLeft(2, '0');
      final day = current.day.toString().padLeft(2, '0');

      final fromDate = formatDateReport("$year-$month-$day 00:00:00");
      final toDate = formatDateReport("$year-$month-$day 23:59:59");

      // Fetch history
      try {
        final history = await APIService.getHistory(
          deviceId.toString(),
          fromDate,
          "00:00",
          toDate,
          "23:59",
        );
        if (history != null && mounted && !_isDisposed) {
          setState(() {
            todaytotalDistance = history.distance_sum ?? "0";

            // If report data is not yet loaded, populate with history data
            if (todayData == null || todayData!.isEmpty) {
              String avgSpeed = '--';
              if (history.distance_sum != null && history.move_duration != null) {
                try {
                  double distance = double.parse(history.distance_sum!.replaceAll(RegExp(r'[^0-9.]'), ''));
                  double hours = _parseDurationToHours(history.move_duration!);
                  if (hours > 0) {
                    avgSpeed = "${(distance / hours).toStringAsFixed(1)} km/h";
                  }
                } catch (_) {}
              }

              todayData = TodayReportData(
                routeLength: history.distance_sum,
                moveDuration: history.move_duration,
                stopDuration: history.stop_duration,
                topSpeed: history.top_speed,
                averageSpeed: avgSpeed,
                engineHours: device?.engineHours ?? device?.deviceData?.engineHours,
              );
              todayEngineHours = device?.engineHours ?? device?.deviceData?.engineHours ?? "--";
            }
          });
        }
      } catch (e) {
        log("History error: $e");
      }

      // Fetch report
      try {
        final report = await ReportService.getTodayReportData(deviceId: deviceId);
        if (report.isNotEmpty && mounted && !_isDisposed) {
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

  double _parseDurationToHours(String durationStr) {
    try {
      durationStr = durationStr.toLowerCase().trim();
      
      // If it contains colon (e.g. 02:30:00)
      if (durationStr.contains(':')) {
        final parts = durationStr.split(':');
        if (parts.length >= 2) {
          final hours = double.parse(parts[0]);
          final minutes = double.parse(parts[1]);
          final seconds = parts.length > 2 ? double.parse(parts[2]) : 0.0;
          return hours + (minutes / 60.0) + (seconds / 3600.0);
        }
      }
      
      // If it contains h, m, s (e.g. 2h 30m)
      double totalHours = 0.0;
      final hourReg = RegExp(r'(\d+)\s*h');
      final minReg = RegExp(r'(\d+)\s*m');
      final secReg = RegExp(r'(\d+)\s*s');
      
      final hourMatch = hourReg.firstMatch(durationStr);
      if (hourMatch != null) {
        totalHours += double.parse(hourMatch.group(1)!);
      }
      
      final minMatch = minReg.firstMatch(durationStr);
      if (minMatch != null) {
        totalHours += double.parse(minMatch.group(1)!) / 60.0;
      }
      
      final secMatch = secReg.firstMatch(durationStr);
      if (secMatch != null) {
        totalHours += double.parse(secMatch.group(1)!) / 3600.0;
      }
      
      return totalHours;
    } catch (_) {
      return 0.0;
    }
  }

  String? _getRawParameter(String key) {
    if (device == null) return null;
    
    // 1. Try to search in device.sensors list
    final sensors = device!.sensors;
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
    final ddSensors = device!.deviceData?.sensors;
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
    final other = device!.deviceData?.traccar?.other;
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
    final params = device!.deviceData?.parameters;
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

  String getEngineStatus() {
    if (_isEngineOn(device!)) {
      return 'On';
    }
    String? val = _getRawParameter('ignition') ?? _getRawParameter('engine');
    if (val != null) {
      val = val.toLowerCase().trim();
      if (val == 'true' || val == '1' || val == 'on') return 'On';
      if (val == 'false' || val == '0' || val == 'off') return 'Off';
    }
    return 'Off';
  }

  String getLockStatus() {
    String? val = _getRawParameter('blocked') ?? _getRawParameter('lock');
    if (val != null) {
      val = val.toLowerCase().trim();
      if (val == 'true' || val == '1' || val == 'blocked' || val == 'lock') return 'Locked';
      if (val == 'false' || val == '0' || val == 'unblocked' || val == 'unlock') return 'Unlocked';
    }
    return 'Unlocked';
  }

  String getChargeStatus() {
    String? val = _getRawParameter('charge') ?? _getRawParameter('charging');
    if (val != null) {
      val = val.toLowerCase().trim();
      if (val == 'true' || val == '1' || val == 'yes') return 'Charging';
      if (val == 'false' || val == '0' || val == 'no') return 'Discharging';
    }
    return 'Discharging';
  }

  String getBatteryVoltage() {
    String? power = _getRawParameter('power') ?? _getRawParameter('voltage') ?? _getRawParameter('adc1');
    if (power != null && power.isNotEmpty) {
      if (!power.toLowerCase().contains('v')) {
        try {
          double vol = double.parse(power);
          return "${vol.toStringAsFixed(1)}V";
        } catch (_) {}
      }
      return power;
    }
    String? bat = _getRawParameter('battery') ?? _getRawParameter('batterylevel');
    if (bat != null && bat.isNotEmpty) {
      if (!bat.contains('%')) {
        return "$bat%";
      }
      return bat;
    }
    return '--';
  }

  String getSatelliteCount() {
    return _getRawParameter('sat') ?? 
           _getRawParameter('satellite') ?? 
           _getRawParameter('satellites') ?? 
           _getRawParameter('satVisible') ?? 
           _getRawParameter('gpsSats') ?? 
           '--';
  }

  // ==================== SMOOTH MARKER UPDATE ====================
  void updateMarker(DeviceItem element) {
    if (_isDisposed || !_isMarkerReady || _carAnimator == null) return;

    final newPos = LatLng(
      double.parse(element.lat.toString()),
      double.parse(element.lng.toString()),
    );

    final rotation = element.iconType == "arrow" || element.iconType == "rotating";
    final newBearing = rotation ? double.parse(element.course.toString()) : 0.0;

    // Just set the target - animator handles smooth movement
    _carAnimator!.moveTo(newPos, newBearing);
  }

  void _onCarPositionUpdate(LatLng position, double bearing) {
    if (_isDisposed) return;

    // Update polyline (less frequently)
    if (_lastPolylinePoint == null ||
        _calculateDistance(_lastPolylinePoint!, position) > 5) {
      _polylinePoints.add(position);
      _lastPolylinePoint = position;

      if (_polylinePoints.length > _maxPolylinePoints) {
        _polylinePoints.removeAt(0);
      }
    }

    // Update markers
    _updateMapMarkers();
  }

  void _updateMapMarkers() {
    if (_isDisposed || !_isMarkerReady || _carAnimator == null) return;

    // Create marker
    final marker = Marker(
      markerId: const MarkerId("vehicle"),
      position: _carAnimator!.currentPosition,
      rotation: _carAnimator!.currentBearing,
      icon: _markerIcon ?? BitmapDescriptor.defaultMarker,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      zIndex: 2,
    );

    // Create polyline
    final polyline = Polyline(
      polylineId: const PolylineId("trail"),
      points: List.from(_polylinePoints),
      color: _primaryColor.withValues(alpha: 0.7),
      width: 3,
      geodesic: true,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    );

    // Update state efficiently
    if (mounted) {
      setState(() {
        _markers = {marker};
        _polylines = {polyline};
      });
    }
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

  // ==================== STATUS DETECTION ====================
  DeviceStatus _getDeviceStatus(DeviceItem? device) {
    if (device == null) return DeviceStatus.offline;

    final isOnline = _isDeviceOnline(device);
    if (!isOnline) return DeviceStatus.offline;

    final speed = double.tryParse(device.speed.toString()) ?? 0;
    final isEngineOn = _isEngineOn(device);

    if (speed > 0) return DeviceStatus.running;
    return isEngineOn ? DeviceStatus.idle : DeviceStatus.stop;
  }

  bool _isDeviceOnline(DeviceItem device) {
    final online = device.online?.toLowerCase().trim() ?? '';
    if (online.contains('offline')) return false;
    if (online.contains('online')) return true;

    final iconColor = device.iconColor?.toLowerCase() ?? '';
    if (iconColor == 'green' || iconColor == 'yellow') return true;

    final speed = double.tryParse(device.speed.toString()) ?? 0;
    return speed > 0;
  }

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

    // 3. Check sensors for ignition/ACC status
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

  Color _getStatusColor() {
    switch (_getDeviceStatus(device)) {
      case DeviceStatus.running:
        return _successColor;
      case DeviceStatus.idle:
        return _warningColor;
      case DeviceStatus.stop:
        return _neutralColor;
      case DeviceStatus.offline:
        return _dangerColor;
    }
  }

  String _getStatusText() {
    switch (_getDeviceStatus(device)) {
      case DeviceStatus.running:
        return "Running";
      case DeviceStatus.idle:
        return "Idle";
      case DeviceStatus.stop:
        return "Parking";
      case DeviceStatus.offline:
        return "Offline";
    }
  }

  void _fetchAddress() {
    if (device?.lat == null || _address != null) return;

    APIService.getGeocoderAddress(
      device!.lat.toString(),
      device!.lng.toString(),
    ).then((addr) {
      if (!_isDisposed && mounted) {
        setState(() => _address = addr.replaceAll('"', ''));
      }
    });
  }

  // ==================== ACTIONS ====================

  void _centerOnVehicle() {
    if (_carAnimator == null || _mapController == null) return;

    // Set flag BEFORE animating
    _isProgrammaticMove = true;

    setState(() => _followVehicle = true);

    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _carAnimator!.currentPosition,
          zoom: 17,
          bearing: _carAnimator!.currentBearing, // Keep vehicle bearing
          tilt: 45, // Add slight tilt for better view
        ),
      ),
    ).then((_) {
      // Reset flag after animation completes
      Future.delayed(const Duration(milliseconds: 100), () {
        _isProgrammaticMove = false;
      });
    });
  }

// Replace the _startCameraTimer method
  void _startCameraTimer() {
    _cameraTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_followVehicle &&
          _isMapCreated &&
          _carAnimator != null &&
          !_userInteracting &&
          !_isProgrammaticMove) {

        _isProgrammaticMove = true;

        _mapController?.animateCamera(
          CameraUpdate.newLatLng(_carAnimator!.currentPosition),
        );

        Future.delayed(const Duration(milliseconds: 50), () {
          _isProgrammaticMove = false;
        });
      }
    });
  }

// Replace the _buildMap method
  Widget _buildMap() {
    return GoogleMap(
      mapType: _currentMapType,
      trafficEnabled: _trafficEnabled,
      initialCameraPosition: CameraPosition(
        target: _getInitialPosition(),
        zoom: 16,
      ),
      onCameraMove: (pos) {
        _currentZoom = pos.zoom;
      },
      onCameraMoveStarted: () {
        // Only mark user interaction if NOT a programmatic move
        if (!_isProgrammaticMove) {
          _userInteracting = true;
        }
      },
      onCameraIdle: () {
        // Only disable follow mode if user manually moved the map
        if (_userInteracting && !_isProgrammaticMove && _followVehicle && _carAnimator != null) {
          _mapController?.getLatLng(ScreenCoordinate(
            x: (MediaQuery.of(context).size.width / 2).toInt(),
            y: (MediaQuery.of(context).size.height / 2).toInt(),
          )).then((centerLatLng) {
            if (mounted) {
              final distance = _calculateDistance(
                  _carAnimator!.currentPosition,
                  centerLatLng
              );

              // Only disable if user moved more than 100 meters
              if (distance > 100) {
                setState(() => _followVehicle = false);
              }
            }
          });
        }
        _userInteracting = false;
      },
      onMapCreated: (controller) {
        _mapController = controller;
        _isMapCreated = true;
        if (_mapStyle != null) controller.setMapStyle(_mapStyle);

        if (_carAnimator != null) {
          controller.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: _carAnimator!.currentPosition, zoom: 16),
            ),
          );
        }
      },
      markers: _markers,
      polylines: _polylines,
      padding: const EdgeInsets.only(bottom: 200),
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      scrollGesturesEnabled: true,  // Make sure this is true
      zoomGesturesEnabled: true,    // Make sure this is true
      mapToolbarEnabled: false,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      buildingsEnabled: false,
      indoorViewEnabled: false,
    );
  }

  // UPDATED: Map with camera move detection


  Widget _buildMapControls() {
    return Positioned(
      top: 80,
      right: 8,
      child: Column(
        children: [
          _MapButton(
            icon: Icons.map,
            selected: _currentMapType == MapType.hybrid,
            onTap: () => setState(() {
              _currentMapType = _currentMapType == MapType.normal
                  ? MapType.hybrid
                  : MapType.normal;
            }),
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: Icons.traffic,
            selected: _trafficEnabled,
            onTap: () => setState(() => _trafficEnabled = !_trafficEnabled),
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: _followVehicle ? Icons.gps_fixed : Icons.gps_not_fixed,
            selected: _followVehicle,
            onTap: _centerOnVehicle,
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: Icons.play_circle_fill,
            iconColor: Colors.orange,
            onTap: _openPlayback,
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: Icons.lock,
            iconColor: _dangerColor,
            onTap: _openLock,
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: Icons.phone,
            iconColor: _successColor,
            onTap: _callDevice,
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: Icons.navigation_rounded,
            iconColor: Colors.purple,
            onTap: _navigate,
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: Icons.share_rounded,
            iconColor: Colors.teal,
            onTap: _shareLocation,
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: Icons.description,
            iconColor: Colors.indigo,
            onTap: _openReport,
          ),
        ],
      ),
    );
  }

  void _openReport() {
    if (device == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportScreen(
          deviceId: device!.id ?? 0,
          deviceName: device!.name ?? '',
          device: device,
        ),
      ),
    );
  }

  void _openPlayback() {
    Get.to(() => PlaybackScreen(id: widget.id, name: widget.name, device: device));
  }

  void _callDevice() async {
    final sim = device?.deviceData?.simNumber;
    if (sim != null && sim.isNotEmpty) {
      await launchUrl(Uri(scheme: 'tel', path: sim));
    } else {
      Get.snackbar('Error', 'Phone number not found',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.9),
          colorText: Colors.white);
    }
  }

  void _openLock() {
    if (device != null) Get.to(() => LockUnlockScreen(device: device!));
  }

  void _showDiagnosticsDialog(BuildContext context) {
    if (device == null) return;
    
    // Parse traccar.other
    Map<String, dynamic> traccarParams = {};
    final other = device!.deviceData?.traccar?.other;
    if (other != null && other.isNotEmpty) {
      try {
        traccarParams = Util.convertXmlToJson(other);
      } catch (_) {
        // Try parsing as JSON
        try {
          traccarParams = json.decode(other);
        } catch (_) {}
      }
    }

    // Parse parameters
    Map<String, dynamic> rawParams = {};
    final params = device!.deviceData?.parameters;
    if (params != null && params.isNotEmpty) {
      try {
        rawParams = json.decode(params);
      } catch (_) {
        // Fallback: manually parse simple key-value pairs
        final matches = RegExp('["\']?(\\w+)["\']?\\s*:\\s*(true|false|"[^"]*"|\'[^\']*\'|\\d+\\.?\\d*)', caseSensitive: false).allMatches(params);
        for (var m in matches) {
          if (m.groupCount >= 2) {
            final key = m.group(1)!;
            final val = m.group(2)!.replaceAll('"', '').replaceAll("'", '');
            rawParams[key] = val;
          }
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(Icons.analytics_rounded, color: CustomColor.primaryColor, size: 24),
                  const SizedBox(width: 10),
                  const Text(
                    'Device Telemetry Diagnostics',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Raw GPRS parameter values currently reported by the device.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDiagSection('Sensors', device!.sensors ?? []),
                      _buildDiagSection('GPRS Parameters', rawParams),
                      _buildDiagSection('Telemetry (Traccar)', traccarParams),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CustomColor.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiagSection(String title, dynamic data) {
    if (data == null || (data is Map && data.isEmpty) || (data is List && data.isEmpty)) {
      return const SizedBox.shrink();
    }

    List<Widget> items = [];
    if (data is Map) {
      data.forEach((key, val) {
        items.add(_buildDiagRow(key.toString(), val.toString()));
      });
    } else if (data is List) {
      for (var item in data) {
        if (item is Map) {
          items.add(_buildDiagRow(
            (item['name'] ?? 'Unknown').toString(),
            (item['value'] ?? '--').toString(),
          ));
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: items,
          ),
        ),
      ],
    );
  }

  Widget _buildDiagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
        ],
      ),
    );
  }

  void _shareLocation() {
    if (device?.lat == null) return;
    final url =
        'https://www.google.com/maps/search/?api=1&query=${device!.lat},${device!.lng}';
    Share.share('Vehicle: ${device!.name}\nLocation: $url',
        subject: 'Vehicle Location - ${device!.name}');
  }

  void _navigate() {
    if (device?.lat == null) return;
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=${device!.lat},${device!.lng}';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _openStreetView() {
    if (device?.lat != null) {
      Get.to(() => StreetViewScreen(latitude: device!.lat!, longitude: device!.lng!));
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _dataTimer?.cancel();
    _cameraTimer?.cancel();
    _carAnimator?.dispose();
    _mapController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GetX<DataController>(
        init: DataController(),
        builder: (controller) {
          for (var element in controller.onlyDevices) {
            if (element.id == widget.id) {
              device = element;
              updateMarker(element);
            }
          }
          return _buildBody();
        },
      ),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        // MAP
        _buildMap(),

        // MAP CONTROLS
        _buildMapControls(),

        // BOTTOM SHEET
        _buildBottomSheet(),

        // BACK BUTTON
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          child: Material(
            elevation: 2,
            shape: const CircleBorder(),
            color: Colors.white,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Get.back(),
            ),
          ),
        ),
      ],
    );
  }



  // ==================== ORIGINAL BOTTOM SHEET DESIGN ====================
  Widget _buildBottomSheet() {
    _fetchAddress();

    return DraggableScrollableSheet(
      initialChildSize: 0.31,
      minChildSize: 0.08,
      maxChildSize: 0.80,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 15,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              _buildCurvedHeader(),
              _buildSpeedSection(),
              _buildSensorsSection(),
              const Divider(height: 1),
              _buildInfoSection(),
              const Divider(height: 1),
              _buildRouteCard(),
              const Divider(height: 1),
              _buildSummarySection(),
              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCurvedHeader() {
    return SizedBox(
      height: 40,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: HeaderCurvePainter()),
          ),
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                widget.name ?? 'Track Device',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedSection() {
    final speed = device?.speed ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              children: [
                _MiniSensor(
                  icon: Icons.route,
                  label: 'Today KM',
                  value: todaytotalDistance,
                  statusColor: _getStatusColor(),
                ),
                const SizedBox(height: 8),
                _MiniSensor(
                  icon: Icons.engineering,
                  label: 'Engine',
                  value: todayData?.engineHours ?? todayEngineHours,
                  statusColor: _getStatusColor(),
                ),
              ],
            ),
            ),
            Expanded(
              flex: 3,
              child: _Speedometer(speed: speed),
            ),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  _MiniSensor(
                    icon: Icons.moving,
                    label: 'Moving',
                    value: todayData?.moveDuration ?? '--',
                    statusColor: _getStatusColor(),
                  ),
                  const SizedBox(height: 8),
                  _MiniSensor(
                    icon: Icons.speed,
                    label: 'Top Speed',
                    value: todayData?.topSpeed ?? '--',
                    statusColor: _getStatusColor(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

  Widget _buildSensorsSection() {
    if (device == null) return const SizedBox.shrink();

    final engineVal = getEngineStatus();
    final lockVal = getLockStatus();
    final voltVal = getBatteryVoltage();
    final chargeVal = getChargeStatus();
    final satVal = getSatelliteCount();

    final List<Widget> cards = [
      ScaleButton(
        onTap: () => _showDiagnosticsDialog(context),
        child: _StatusCard(
          icon: Icons.power,
          label: 'Engine',
          value: engineVal,
          color: engineVal == 'On' ? Colors.green : Colors.amber,
        ),
      ),
      ScaleButton(
        onTap: _openLock,
        child: _StatusCard(
          icon: lockVal == 'Locked' ? Icons.lock : Icons.lock_open,
          label: 'Lock',
          value: lockVal,
          color: lockVal == 'Locked' ? Colors.red : Colors.blue,
        ),
      ),
      ScaleButton(
        onTap: () => _showDiagnosticsDialog(context),
        child: _StatusCard(
          icon: Icons.bolt,
          label: 'Charge',
          value: chargeVal,
          color: chargeVal == 'Charging' ? Colors.orange : Colors.grey,
        ),
      ),
      ScaleButton(
        onTap: () => _showDiagnosticsDialog(context),
        child: _StatusCard(
          icon: Icons.battery_charging_full,
          label: 'Voltage',
          value: voltVal,
          color: Colors.teal,
        ),
      ),
      ScaleButton(
        onTap: () => _showDiagnosticsDialog(context),
        child: _StatusCard(
          icon: Icons.satellite_alt,
          label: 'Sats',
          value: satVal,
          color: Colors.indigo,
        ),
      ),
    ];

    // Append other custom sensors
    final sensors = device!.sensors ?? [];
    for (var s in sensors) {
      if (s is Map) {
        final name = (s['name'] ?? '').toString();
        final lowerName = name.toLowerCase();
        if (lowerName.contains('ignition') ||
            lowerName.contains('engine') ||
            lowerName.contains('blocked') ||
            lowerName.contains('lock') ||
            lowerName.contains('charge') ||
            lowerName.contains('voltage') ||
            lowerName.contains('power') ||
            lowerName.contains('battery') ||
            lowerName.contains('sat')) {
          continue;
        }

        cards.add(
          _StatusCard(
            icon: Icons.sensors,
            label: name,
            value: s['value']?.toString() ?? '--',
            color: Colors.blueGrey,
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.dashboard_customize, size: 16, color: CustomColor.primaryColor),
              const SizedBox(width: 8),
              const Text(
                "Device Diagnostics",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: IntrinsicHeight(
            child: Row(
              children: cards.map((card) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: card,
                ),
              )).toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
  // Add these methods inside _TrackDeviceState class

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _primaryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildRouteCard() {
    final routeStart = todayData?.routeStart;
    final routeEnd = todayData?.routeEnd;

    // If no route data at all, don't show
    if (routeStart == null && routeEnd == null && _address == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.route, size: 16, color: _primaryColor),
              const SizedBox(width: 6),
              Text(
                "Today's Route",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Start Point
          _buildSimpleRoutePoint(
            label: 'Start',
            value: routeStart ?? 'No start location',
            color: Colors.green,
            isStart: true,
          ),

          // Line
          Container(
            margin: const EdgeInsets.only(left: 9),
            width: 2,
            height: 20,
            color: Colors.grey[300],
          ),

          // End/Current Point
          _buildSimpleRoutePoint(
            label: routeEnd != null ? 'End' : 'Current',
            value: routeEnd ?? _address ?? 'Loading...',
            color: routeEnd != null ? Colors.red : _primaryColor,
            isStart: false,
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleRoutePoint({
    required String label,
    required String value,
    required Color color,
    required bool isStart,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Circle indicator
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isStart ? Icons.play_arrow : Icons.location_on,
            size: 12,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        // Text
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A2E),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection() {
    if (device == null) return const SizedBox.shrink();

    final statusColor = _getStatusColor();
    final statusText = _getStatusText();
    final isEngineOn = _isEngineOn(device!);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isEngineOn ? Icons.power : Icons.power_off,
                      size: 12,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _address ?? 'Loading address...',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _QuickStat(
                icon: Icons.directions_car,
                label: 'Move',
                value: todayData?.moveDuration ?? '--',
              ),
              _QuickStat(
                icon: Icons.local_parking,
                label: 'Stop',
                value: todayData?.stopDuration ?? '--',
              ),
              _QuickStat(
                icon: Icons.route,
                label: 'Distance',
                value: '${device?.totalDistance?.toStringAsFixed(1) ?? '0'}',
              ),
            ],
          ),
        ],
      ),
    );
  }



  Widget _buildSummarySection() {
    final report = todayData;

    return Container(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: _primaryColor, size: 18),
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
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.3,
            children: [
              _SummaryItem(
                icon: Icons.route,
                label: 'Distance',
                value: todaytotalDistance,
                color: _primaryColor,
              ),
              _SummaryItem(
                icon: Icons.speed,
                label: 'Top Speed',
                value: report?.topSpeed ?? '--',
                color: _warningColor,
              ),
              _SummaryItem(
                icon: Icons.play_arrow,
                label: 'Moving',
                value: report?.moveDuration ?? '--',
                color: _successColor,
              ),
              _SummaryItem(
                icon: Icons.pause,
                label: 'Stopped',
                value: report?.stopDuration ?? '--',
                color: _dangerColor,
              ),
              _SummaryItem(
                icon: Icons.speed_outlined,
                label: 'Avg Speed',
                value: report?.averageSpeed ?? '--',
                color: _neutralColor,
              ),
              _SummaryItem(
                icon: Icons.engineering,
                label: 'Engine',
                value: report?.engineHours ?? todayEngineHours,
                color: _successColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final Color? iconColor;
  final Color? backgroundColor;

  const _MapButton({
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.iconColor,
  }) : backgroundColor = null;

  @override
  Widget build(BuildContext context) {
    final defaultIconColor = selected ? Colors.white : (iconColor ?? CustomColor.primaryColor);
    final defaultBgColor = selected ? CustomColor.primaryColor : (backgroundColor ?? Colors.white);

    return Material(
      color: defaultBgColor,
      elevation: 2,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 20,
            color: defaultIconColor,
          ),
        ),
      ),
    );
  }
}

class _Speedometer extends StatelessWidget {
  final int speed;
  final int maxSpeed;

  const _Speedometer({required this.speed}) : maxSpeed = 140;

  Color get statusColor {
    if (speed >= 120) return const Color(0xFFE53935);
    if (speed >= 80) return const Color(0xFFFF5722);
    if (speed >= 60) return const Color(0xFFFFA726);
    return const Color(0xFF4CAF50);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      width: 180,
      child: CustomPaint(
        painter: SpeedometerPainter(
          speed: speed.toDouble(),
          maxSpeed: maxSpeed.toDouble(),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 14),
              Text(
                '$speed',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                  letterSpacing: 1,
                  shadows: [
                    Shadow(
                      color: statusColor.withValues(alpha: 0.5),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
              Text(
                'km/h',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SpeedometerPainter extends CustomPainter {
  final double speed;
  final double maxSpeed;

  SpeedometerPainter({required this.speed, this.maxSpeed = 140});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.55);
    final radius = m.min(size.width, size.height) / 2 - 10;

    const startAngle = m.pi;
    const sweepAngle = m.pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = Colors.grey[200]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );

    final speedRatio = (speed / maxSpeed).clamp(0.0, 1.0);
    final progressAngle = speedRatio * sweepAngle;

    if (speed > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        progressAngle,
        false,
        Paint()
          ..color = _getSpeedColor(speed)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round,
      );
    }

    _drawTickMarks(canvas, center, radius, startAngle, sweepAngle);
  }

  void _drawTickMarks(Canvas canvas, Offset center, double radius,
      double startAngle, double sweepAngle) {
    final int totalTicks = (maxSpeed ~/ 10);

    for (int i = 0; i <= totalTicks; i++) {
      final angle = startAngle + (i / totalTicks) * sweepAngle;
      final isMajor = i % 2 == 0;
      final tickLength = isMajor ? 6 : 3;
      final tickWidth = isMajor ? 2.0 : 1.0;

      final outerPoint = Offset(
        center.dx + (radius - 8) * m.cos(angle),
        center.dy + (radius - 8) * m.sin(angle),
      );
      final innerPoint = Offset(
        center.dx + (radius - 8 - tickLength) * m.cos(angle),
        center.dy + (radius - 8 - tickLength) * m.sin(angle),
      );

      final speedAtTick = (i / totalTicks) * maxSpeed;
      Color tickColor = Colors.grey[400]!;
      if (speedAtTick >= 120) {
        tickColor = const Color(0xFFE53935);
      } else if (speedAtTick >= 80) {
        tickColor = const Color(0xFFFF5722);
      }

      canvas.drawLine(
        innerPoint,
        outerPoint,
        Paint()
          ..color = tickColor
          ..strokeWidth = tickWidth
          ..strokeCap = StrokeCap.round,
      );

      if (isMajor) {
        final labelRadius = radius - 22;
        final labelPos = Offset(
          center.dx + labelRadius * m.cos(angle),
          center.dy + labelRadius * m.sin(angle),
        );

        final speedValue = (i * 10);

        final textPainter = TextPainter(
          text: TextSpan(
            text: '$speedValue',
            style: TextStyle(
              color: speedValue >= 80 ? const Color(0xFFE53935) : Colors.grey[600],
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            labelPos.dx - textPainter.width / 2,
            labelPos.dy - textPainter.height / 2,
          ),
        );
      }
    }
  }

  Color _getSpeedColor(double speed) {
    if (speed >= 120) return const Color(0xFFE53935);
    if (speed >= 80) return const Color(0xFFFF5722);
    if (speed >= 60) return const Color(0xFFFFA726);
    return const Color(0xFF4CAF50);
  }

  @override
  bool shouldRepaint(covariant SpeedometerPainter oldDelegate) {
    return oldDelegate.speed != speed;
  }
}

class _MiniSensor extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color statusColor;

  const _MiniSensor({
    required this.icon,
    required this.label,
    required this.value,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: statusColor),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
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
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatusCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w500,
              color: Colors.grey[500],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _QuickStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _QuickStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: CustomColor.primaryColor),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
      ],
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class HeaderCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF5F5F5)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(0, size.height * 0.5);
    path.quadraticBezierTo(
        size.width * 0.25, size.height * 0.9, size.width * 0.5, size.height * 0.95);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.9, size.width, size.height * 0.5);
    path.lineTo(size.width, 0);
    path.close();

    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = Colors.grey[300]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final borderPath = Path();
    borderPath.moveTo(0, size.height * 0.5);
    borderPath.quadraticBezierTo(
        size.width * 0.25, size.height * 0.9, size.width * 0.5, size.height * 0.95);
    borderPath.quadraticBezierTo(
        size.width * 0.75, size.height * 0.9, size.width, size.height * 0.5);

    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}