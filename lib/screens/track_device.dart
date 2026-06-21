import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' as m;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
import 'package:fluttertoast/fluttertoast.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gpspro/widgets/svg_asset_colorizer.dart';
import 'package:gpspro/services/model/single_device.dart';
import 'package:gpspro/storage/user_repository.dart';

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

  // Queue of pending positions and bearings to ensure no intermediate updates are skipped
  final List<LatLng> _positionQueue = [];
  final List<double> _bearingQueue = [];

  // Target state
  LatLng? _targetPosition;
  double _targetBearing = 0;

  // Animation state
  bool _isRunning = false;
  int _lastTickTime = 0;

  // Speed configuration (meters per second)
  static const double _maxSpeed = 50.0; // 180 km/h base speed limit
  static const double _minSpeed = 5.0; // ~18 km/h min speed
  static const double _acceleration =
      40.0; // m/s² acceleration for responsive updates

  double _currentSpeed = 0;

  // Bearing interpolation
  static const double _bearingSpeed =
      360.0; // degrees per second (fast turning)

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
  LatLng get targetPosition => _targetPosition ?? _currentPosition;

  void moveTo(LatLng target, double bearing) {
    _positionQueue.add(target);
    _bearingQueue.add(bearing);

    // Keep queue bounded to at most 10 elements to prevent excessive backlog
    if (_positionQueue.length > 10) {
      _positionQueue.removeRange(0, _positionQueue.length - 10);
      _bearingQueue.removeRange(0, _bearingQueue.length - 10);
    }

    if (!_isRunning) {
      _isRunning = true;
      _lastTickTime = DateTime.now().millisecondsSinceEpoch;
      _ticker?.start();
    }
  }

  void _onTick(Duration elapsed) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = now - _lastTickTime;
    if (elapsedMs < 33) return; // Throttle to ~30fps

    if (_targetPosition == null) {
      if (_positionQueue.isNotEmpty) {
        _targetPosition = _positionQueue.removeAt(0);
        _targetBearing = _bearingQueue.removeAt(0);
      } else {
        _stop();
        return;
      }
    }

    final deltaTime = elapsedMs / 1000.0; // seconds
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

      // If no more items in queue, reset speed and stop
      if (_positionQueue.isEmpty) {
        _currentSpeed = 0;
        _stop();
      }
      return;
    }

    // Dynamic speed cap multiplier based on queue backlog to catch up quickly
    double speedCap = _maxSpeed;
    if (_positionQueue.length > 1) {
      speedCap = _maxSpeed * _positionQueue.length.toDouble();
    }

    // Calculate target speed based on distance (slow down when approaching final target)
    double targetSpeed;
    if (_positionQueue.isEmpty && distance < 10) {
      targetSpeed = _minSpeed;
    } else if (_positionQueue.isEmpty && distance < 50) {
      targetSpeed = _minSpeed + (distance - 10) / 40 * (speedCap - _minSpeed);
    } else {
      targetSpeed = speedCap;
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
  bool _isLoading = false;
  String? _lockCommandType;
  String? _lockCommandId;
  String? _unlockCommandType;
  String? _unlockCommandId;

  // MAP
  GoogleMapController? _mapController;
  bool _isMapCreated = false;
  MapType _currentMapType = MapType.normal;
  double _currentZoom = 15.5;
  int _currentMarkerSize = 38;
  bool _trafficEnabled = false;
  bool _followVehicle = true;
  String? _mapStyle;
  bool _isDisposed = false;
  bool _userInteracting = false;
  bool _isProgrammaticMove = false;

  // Optimized ValueNotifiers for high performance updates
  final ValueNotifier<Set<Marker>> _markersNotifier =
      ValueNotifier<Set<Marker>>({});
  final ValueNotifier<Set<Polyline>> _polylinesNotifier =
      ValueNotifier<Set<Polyline>>({});

  // DEVICE DATA
  DeviceItem? device;
  String todaytotalDistance = "--";
  String todayEngineHours = "--";
  String? _address;
  TodayReportData? todayData;

  // Optimized Address Fetching state
  double? _lastFetchedLat;
  double? _lastFetchedLng;
  bool _isFetchingAddress = false;
  DateTime? _lastAddressFetchTime;

  // SMOOTH ANIMATION
  UltraSmoothCarAnimator? _carAnimator;
  BitmapDescriptor? _markerIcon;
  bool _isMarkerReady = false;

  // POLYLINE
  final List<LatLng> _polylinePoints = [];
  static const int _maxPolylinePoints = 3000;

  StreamSubscription? _onlyDevicesSubscription;

  // TIMERS
  Timer? _dataTimer;

  // COLORS
  static const _successColor = Color(0xFF00C853);
  static const _warningColor = Color(0xFFFF9100);
  static const _dangerColor = CustomColor.primary;
  static const _primaryColor = CustomColor.primary;
  static const _neutralColor = Color(0xFF475569);

  bool _hasDeviceChanged(DeviceItem? a, DeviceItem b) {
    if (a == null) return true;
    return a.lat != b.lat ||
        a.lng != b.lng ||
        a.speed != b.speed ||
        a.online != b.online ||
        a.course != b.course ||
        a.engineStatus != b.engineStatus ||
        a.stopDuration != b.stopDuration ||
        a.totalDistance != b.totalDistance ||
        a.power != b.power;
  }

  @override
  void initState() {
    super.initState();
    device = widget.device;

    final DataController controller = Get.put(DataController());
    _onlyDevicesSubscription = controller.onlyDevices.listen((devices) {
      if (mounted && !_isDisposed) {
        for (var element in devices) {
          if (element.id == widget.id) {
            if (_hasDeviceChanged(device, element)) {
              setState(() {
                device = element;
              });
              updateMarker(element);
            }
            break;
          }
        }
      }
    });

    _loadMapStyle();
    _initializeAll();
    _loadLockUnlockCommands();
  }

  Future<void> _initializeAll() async {
    // Initialize position first
    final initialPos = _getInitialPosition();
    _fetchAddressForCoordinates(initialPos.latitude, initialPos.longitude);
    final initialBearing =
        double.tryParse(device?.course?.toString() ?? '0') ?? 0;

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

    // Update map
    _updateMapMarker();
    _updateMapPolyline();

    // Start data fetching
    _startDataTimer();
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
    _mapStyle = null; // Default to colorful Google Maps
  }

  Future<void> _loadMarkerIcon() async {
    if (device?.icon?.path == null) {
      _markerIcon = BitmapDescriptor.defaultMarker;
      _isMarkerReady = true;
      return;
    }

    try {
      final path = device!.icon!.path!;
      _markerIcon = await Util.getMarkerIcon(path,
          size: _currentMarkerSize,
          statusColor: device?.iconColor,
          iconType: device?.icon?.type ?? device?.iconType,
          deviceName: device?.name,
          deviceId: device?.id);

      _isMarkerReady = true;

      if (mounted && !_isDisposed) {
        _updateMapMarker();
      }
    } catch (e) {
      debugPrint('Marker icon error: $e');
      _markerIcon = BitmapDescriptor.defaultMarker;
      _isMarkerReady = true;
    }
  }

  void _startDataTimer() {
    _fetchAllData();
    _dataTimer = Timer.periodic(const Duration(seconds: 30), (_) {
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
              if (history.distance_sum != null &&
                  history.move_duration != null) {
                try {
                  double distance = double.parse(
                      history.distance_sum!.replaceAll(RegExp(r'[^0-9.]'), ''));
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
                engineHours:
                    device?.engineHours ?? device?.deviceData?.engineHours,
              );
              todayEngineHours = device?.engineHours ??
                  device?.deviceData?.engineHours ??
                  "--";
            }
          });
        }
      } catch (e) {
        log("History error: $e");
      }

      // Fetch report
      try {
        final report =
            await ReportService.getTodayReportData(deviceId: deviceId);
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
      final xmlMatch =
          RegExp('<$key>(.*?)</$key>', caseSensitive: false).firstMatch(other);
      if (xmlMatch != null && xmlMatch.group(1) != null) {
        final val = xmlMatch.group(1);
        if (val != null && val.trim().isNotEmpty) {
          return val;
        }
      }
      final jsonMatch = RegExp(
              '["\']?$key["\']?\\s*:\\s*(true|false|"[^"]*"|\'[^\']*\'|\\d+\\.?\\d*)',
              caseSensitive: false)
          .firstMatch(other);
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
      final jsonMatch = RegExp(
              '["\']?$key["\']?\\s*:\\s*(true|false|"[^"]*"|\'[^\']*\'|\\d+\\.?\\d*)',
              caseSensitive: false)
          .firstMatch(params);
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
      if (val == 'true' || val == '1' || val == 'blocked' || val == 'lock')
        return 'Locked';
      if (val == 'false' || val == '0' || val == 'unblocked' || val == 'unlock')
        return 'Unlocked';
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
    String? power = _getRawParameter('power') ??
        _getRawParameter('voltage') ??
        _getRawParameter('adc1');
    if (power != null && power.isNotEmpty) {
      if (!power.toLowerCase().contains('v')) {
        try {
          double vol = double.parse(power);
          return "${vol.toStringAsFixed(1)}V";
        } catch (_) {}
      }
      return power;
    }
    String? bat =
        _getRawParameter('battery') ?? _getRawParameter('batterylevel');
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

  String getNetworkStatus() {
    String? rssiVal = _getRawParameter('rssi') ??
        _getRawParameter('signal') ??
        _getRawParameter('gsm') ??
        _getRawParameter('sq') ??
        _getRawParameter('network') ??
        _getRawParameter('signalLevel') ??
        _getRawParameter('signalPercent');

    if (rssiVal != null && rssiVal.trim().isNotEmpty) {
      final val = rssiVal.trim();
      try {
        final dVal = double.parse(val);
        // 1. Negative value -> dBm
        if (dVal < 0) {
          return "${dVal.toInt()} dBm";
        }
        // 2. 1 to 5 scale -> convert to percentage
        if (dVal >= 1 && dVal <= 5 && val.indexOf('.') == -1) {
          return "${(dVal * 20).toInt()}%";
        }
        // 3. CSQ range (6 to 31) -> convert to percentage
        if (dVal > 5 && dVal <= 31) {
          final pct = (dVal / 31 * 100).clamp(0, 100).toInt();
          return "$pct%";
        }
        // 4. Already percentage (32 to 100)
        if (dVal > 31 && dVal <= 100) {
          return "${dVal.toInt()}%";
        }
      } catch (_) {}
      return val;
    }

    // Fallback 1: GPS satellites count if available
    String? sat = _getRawParameter('sat') ??
        _getRawParameter('satellite') ??
        _getRawParameter('satellites') ??
        _getRawParameter('satVisible') ??
        _getRawParameter('gpsSats');

    if (sat != null && sat.trim().isNotEmpty) {
      return "$sat Sat";
    }

    // Fallback 2: Check online status from device itself
    if (device != null && device!.online != null) {
      final isOnline = device!.online!.toLowerCase() == 'online' ||
          device!.online!.toLowerCase() == 'true';
      return isOnline ? 'Connected' : 'Offline';
    }

    return '--';
  }

  // ==================== SMOOTH MARKER UPDATE ====================
  void updateMarker(DeviceItem element) {
    if (_isDisposed || !_isMarkerReady || _carAnimator == null) return;

    final newPos = LatLng(
      double.parse(element.lat.toString()),
      double.parse(element.lng.toString()),
    );

    // Fetch address and update raw polyline only if location actually changed
    final bool locationChanged = _polylinePoints.isEmpty ||
        _polylinePoints.last.latitude != newPos.latitude ||
        _polylinePoints.last.longitude != newPos.longitude;

    if (locationChanged) {
      _fetchAddressForCoordinates(newPos.latitude, newPos.longitude);

      final lastTarget = _carAnimator!.targetPosition;
      if (_polylinePoints.isEmpty ||
          _calculateDistance(_polylinePoints.last, lastTarget) > 1.0) {
        _polylinePoints.add(lastTarget);
        if (_polylinePoints.length > _maxPolylinePoints) {
          _polylinePoints.removeAt(0);
        }
      }
    }

    final newBearing = double.tryParse(element.course.toString()) ?? 0.0;

    // Just set the target - animator handles smooth movement
    _carAnimator!.moveTo(newPos, newBearing);
  }

  void _onCarPositionUpdate(LatLng position, double bearing) {
    if (_isDisposed) return;

    // Update marker position on map (runs at 60fps ticker speed)
    _updateMapMarker();

    // Dynamically update polyline trail in real-time
    _updateMapPolyline();

    // Smoothly follow the vehicle in real-time on every ticker update
    if (_followVehicle &&
        _isMapCreated &&
        _mapController != null &&
        !_userInteracting) {
      _mapController!.moveCamera(
        CameraUpdate.newLatLng(position),
      );
    }
  }

  void _updateMapMarker() {
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

    // Update value notifier instead of rebuilding polyline
    _markersNotifier.value = {marker};
  }

  void _updateMapPolyline() {
    if (_isDisposed || _carAnimator == null) return;

    // Draw the line up to the current animated position of the vehicle
    final points = List<LatLng>.from(_polylinePoints);
    points.add(_carAnimator!.currentPosition);

    final trailColor = _getStatusColor();

    // Create polyline
    final polyline = Polyline(
      polylineId: const PolylineId("trail"),
      points: points,
      color: trailColor.withValues(alpha: 0.8),
      width: 4,
      geodesic: true,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    );

    // Update value notifier
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

  // ==================== STATUS DETECTION ====================
  DeviceStatus _getDeviceStatus(DeviceItem? device) {
    if (device == null) return DeviceStatus.offline;

    final isOnline = _isDeviceOnline(device);
    if (!isOnline) return DeviceStatus.offline;

    final speed = double.tryParse(device.speed?.toString() ?? '') ?? 0;
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

    final speed = double.tryParse(device.speed?.toString() ?? '') ?? 0;
    return speed > 0;
  }

  bool _isEngineOn(DeviceItem device) {
    // 1. If speed > 0, engine must be on (telematics override for wiring/reporting issues)
    final speed = double.tryParse(device.speed?.toString() ?? '') ?? 0;
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
        return "Stopped";
      case DeviceStatus.offline:
        return "Offline";
    }
  }

  void _fetchAddressForCoordinates(double lat, double lng) {
    if (_isDisposed) return;
    if (_lastFetchedLat == lat && _lastFetchedLng == lng) return;
    if (_isFetchingAddress) return;

    final now = DateTime.now();
    if (_lastAddressFetchTime != null &&
        now.difference(_lastAddressFetchTime!) < const Duration(seconds: 15)) {
      return; // Throttle address requests to maximum once per 15s when moving
    }

    _isFetchingAddress = true;
    _lastFetchedLat = lat;
    _lastFetchedLng = lng;
    _lastAddressFetchTime = now;

    APIService.getGeocoderAddress(
      lat.toString(),
      lng.toString(),
    ).then((addr) {
      if (!_isDisposed && mounted) {
        setState(() {
          _address = addr.replaceAll('"', '');
          _isFetchingAddress = false;
        });
      }
    }).catchError((_) {
      if (!_isDisposed) {
        _isFetchingAddress = false;
      }
    });
  }

  // ==================== ACTIONS ====================

  void _centerOnVehicle() {
    if (_carAnimator == null || _mapController == null) return;

    // Set flag BEFORE animating
    _isProgrammaticMove = true;

    setState(() => _followVehicle = true);

    _mapController!
        .animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _carAnimator!.currentPosition,
          zoom: _currentZoom,
          bearing: _carAnimator!.currentBearing, // Keep vehicle bearing
          tilt: 0,
        ),
      ),
    )
        .then((_) {
      // Reset flag after animation completes
      Future.delayed(const Duration(milliseconds: 100), () {
        _isProgrammaticMove = false;
      });
    });
  }

  void _zoomIn() {
    if (_mapController != null) {
      _mapController!.animateCamera(CameraUpdate.zoomIn());
    }
  }

  void _zoomOut() {
    if (_mapController != null) {
      _mapController!.animateCamera(CameraUpdate.zoomOut());
    }
  }

  // Camera auto centering timer removed as it is now centered in real-time on tick updates

// Replace the _buildMap method
  Widget _buildMap() {
    return Listener(
      onPointerDown: (_) {
        _userInteracting = true;
      },
      child: ValueListenableBuilder<Set<Marker>>(
        valueListenable: _markersNotifier,
        builder: (context, markers, _) {
          return ValueListenableBuilder<Set<Polyline>>(
            valueListenable: _polylinesNotifier,
            builder: (context, polylines, _) {
              return GoogleMap(
                mapType: _currentMapType,
                trafficEnabled: _trafficEnabled,
                initialCameraPosition: CameraPosition(
                  target: _getInitialPosition(),
                  zoom: _currentZoom,
                ),
                onCameraMove: (pos) {
                  _currentZoom = pos.zoom;
                },
                onCameraIdle: () {
                  _userInteracting = false;

                  // Zoom-based marker sizing update
                  final int newSize = Util.getMarkerSizeForZoom(_currentZoom);
                  if (newSize != _currentMarkerSize) {
                    _currentMarkerSize = newSize;
                    _loadMarkerIcon();
                  }
                },
                onMapCreated: (controller) {
                  _mapController = controller;
                  _isMapCreated = true;
                  if (_mapStyle != null) controller.setMapStyle(_mapStyle);

                  if (_carAnimator != null) {
                    _isProgrammaticMove = true;
                    controller
                        .animateCamera(
                      CameraUpdate.newCameraPosition(
                        CameraPosition(
                            target: _carAnimator!.currentPosition, zoom: _currentZoom),
                      ),
                    )
                        .then((_) {
                      Future.delayed(const Duration(milliseconds: 100), () {
                        _isProgrammaticMove = false;
                      });
                    });
                  }
                },
                markers: markers,
                polylines: polylines,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).size.height * 0.10,
                ),
                rotateGesturesEnabled: true,
                tiltGesturesEnabled: true,
                scrollGesturesEnabled: true, // Make sure this is true
                zoomGesturesEnabled: true, // Make sure this is true
                mapToolbarEnabled: false,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                buildingsEnabled: false,
                indoorViewEnabled: false,
              );
            },
          );
        },
      ),
    );
  }

  // UPDATED: Map with camera move detection

  Widget _buildMapControls() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 8,
      child: Column(
        children: [
          _MapButton(
            icon: Icons.map,
            isWhiteVariant: false,
            onTap: () => setState(() {
              _currentMapType = _currentMapType == MapType.normal
                  ? MapType.hybrid
                  : MapType.normal;
            }),
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: Icons.traffic,
            isWhiteVariant: false,
            onTap: () => setState(() => _trafficEnabled = !_trafficEnabled),
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: _followVehicle ? Icons.gps_fixed : Icons.gps_not_fixed,
            isWhiteVariant: true,
            onTap: () {
              if (_followVehicle) {
                setState(() => _followVehicle = false);
              } else {
                _centerOnVehicle();
              }
            },
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: Icons.navigation_rounded,
            isWhiteVariant: true,
            onTap: _navigate,
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: Icons.person,
            isWhiteVariant: true,
            onTap: _callDevice,
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
    Get.to(
        () => PlaybackScreen(id: widget.id, name: widget.name, device: device));
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
        final matches = RegExp(
                '["\']?(\\w+)["\']?\\s*:\\s*(true|false|"[^"]*"|\'[^\']*\'|\\d+\\.?\\d*)',
                caseSensitive: false)
            .allMatches(params);
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
                  Icon(Icons.analytics_rounded,
                      color: CustomColor.primaryColor, size: 24),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiagSection(String title, dynamic data) {
    if (data == null ||
        (data is Map && data.isEmpty) ||
        (data is List && data.isEmpty)) {
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
          Text(label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
          Text(
            value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B)),
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
      Get.to(() =>
          StreetViewScreen(latitude: device!.lat!, longitude: device!.lng!));
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _onlyDevicesSubscription?.cancel();
    _dataTimer?.cancel();
    _carAnimator?.dispose();
    _markersNotifier.dispose();
    _polylinesNotifier.dispose();
    _mapController = null;
    super.dispose();
  }

  void _loadLockUnlockCommands() {
    if (widget.id == null) return;
    APIService.getSavedCommands(widget.id.toString()).then((value) {
      if (value != null && mounted && !_isDisposed) {
        try {
          final List<dynamic> list = json.decode(value.body);
          for (var element in list) {
            if (element is Map) {
              final title = (element["title"] ?? "").toString().toLowerCase();
              final type = (element["type"] ?? "").toString();
              final id = (element["id"] ?? "").toString();
              if (title.contains("unlock") ||
                  title.contains("resume") ||
                  title.contains("start")) {
                _unlockCommandType = type;
                _unlockCommandId = id;
              } else if (title.contains("lock") || title.contains("stop")) {
                _lockCommandType = type;
                _lockCommandId = id;
              }
            }
          }
          debugPrint(
              "TrackDevice: Mapped Lock command: $_lockCommandType (ID: $_lockCommandId)");
          debugPrint(
              "TrackDevice: Mapped Unlock command: $_unlockCommandType (ID: $_unlockCommandId)");
        } catch (e) {
          debugPrint("TrackDevice: Error loading saved commands: $e");
        }
      }
    });
  }

  void _sendEngineCommand(bool isUnlockAction) async {
    final devId = device?.id ?? widget.id;
    if (devId == null) {
      Fluttertoast.showToast(msg: "Device ID not found");
      return;
    }

    final commandType = isUnlockAction
        ? (_unlockCommandType ?? 'engineResume')
        : (_lockCommandType ?? 'engineStop');
    final commandId = isUnlockAction ? _unlockCommandId : _lockCommandId;

    setState(() => _isLoading = true);

    try {
      Map<String, String> requestBody = <String, String>{
        'id': commandId ?? "",
        'device_id': devId.toString(),
        'type': commandType
      };

      final res = await APIService.sendCommands(requestBody);

      if (res.statusCode == 200) {
        Map<String, dynamic>? responseJson;
        try {
          responseJson = json.decode(res.body);
        } catch (_) {}

        if (responseJson != null &&
            responseJson.containsKey('status') &&
            responseJson['status'] == 0) {
          Fluttertoast.showToast(
            msg: responseJson['message'] ?? 'Failed to send command',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: _dangerColor,
            textColor: Colors.white,
          );
          return;
        }

        Fluttertoast.showToast(
          msg: isUnlockAction
              ? 'Vehicle unlocked successfully'
              : 'Vehicle locked successfully',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: _successColor,
          textColor: Colors.white,
        );
      } else {
        Fluttertoast.showToast(
          msg: 'Failed to send command',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: _dangerColor,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Connection error',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: _dangerColor,
        textColor: Colors.white,
      );
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
              ),
              const SizedBox(height: 24),
              const Text(
                'Sending command...',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLockUnlockSection() {
    if (device == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                _sendEngineCommand(false); // Lock (Engine Stop)
              },
              borderRadius: BorderRadius.circular(30),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: _dangerColor.withValues(alpha: 0.1), // soft red
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock,
                        color: _dangerColor, // red
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Engine Lock',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _dangerColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () {
                _sendEngineCommand(true); // Unlock (Engine Resume)
              },
              borderRadius: BorderRadius.circular(30),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: _successColor.withValues(alpha: 0.1), // soft green
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_open,
                        color: _successColor, // green
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Engine Unlock',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _successColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final speed = device?.speed ?? 0;
    return Stack(
      children: [
        // MAP
        _buildMap(),

        // MAP CONTROLS (right side - 9 red circle buttons)
        _buildMapControls(),

        // BOTTOM SHEET
        _buildBottomSheet(),

        // BACK BUTTON (top left, small white circle)
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          child: Material(
            elevation: 2,
            shape: const CircleBorder(),
            color: Colors.white,
            child: InkWell(
              onTap: () => Get.back(),
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.arrow_back, color: Colors.black, size: 18),
              ),
            ),
          ),
        ),

        // LEFT-SIDE MAP CONTROLS OVERLAY (Report, Info, Speedometer)
        Positioned(
          left: 8,
          bottom: MediaQuery.of(context).size.height * 0.34,
          child: Column(
            children: [
              _MapButton(
                icon: Icons.bar_chart_rounded,
                isWhiteVariant: true,
                onTap: _openReport,
              ),
              const SizedBox(height: 6),
              _MapButton(
                icon: Icons.info_outline_rounded,
                isWhiteVariant: true,
                onTap: () => _showDiagnosticsDialog(context),
              ),
              const SizedBox(height: 6),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: CustomColor.primary, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$speed',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                        height: 1.0,
                      ),
                    ),
                    const Text(
                      'km/hr',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // LOADING OVERLAY
        if (_isLoading) _buildLoadingOverlay(),
      ],
    );
  }

  // ==================== REFERENCE DESIGN BOTTOM SHEET ====================
  Widget _buildBottomSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.32,
      minChildSize: 0.08,
      maxChildSize: 0.55,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 12,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              _buildDragHandle(),
              _buildDeviceHeader(),
              _buildStatColumns(),
              _buildAddressRow(),
              _buildInfoCardsRow(),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              _buildActionButtons(),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ── Drag handle ──────────────────────────────────────────
  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ── Header: device name + speed pill ─────────────────────
  Widget _buildDeviceHeader() {
    final speed = device?.speed ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.name ?? device?.name ?? 'Track Device',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEB),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Speed: $speed km/hr',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: CustomColor.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 4-column stat row ─────────────────────────────────────
  Widget _buildStatColumns() {
    final statusText = _getStatusText();
    final statusColor = _getStatusColor();
    final statColor = statusColor;

    final engineVal = device != null ? getEngineStatus() : '--';
    String durationDisplay = '-';
    if (device != null) {
      final status = _getDeviceStatus(device);
      final sd = device!.stopDuration ?? '';
      
      if (status == DeviceStatus.running) {
        final movedAtStr = device!.deviceData?.traccar?.movedAt;
        if (movedAtStr != null && movedAtStr.isNotEmpty) {
          try {
            final DateTime movedTime = DateTime.parse(movedAtStr).toLocal();
            final diff = DateTime.now().difference(movedTime);
            if (!diff.isNegative) {
              durationDisplay = Util.formatDuration(diff);
            } else {
              durationDisplay = '-';
            }
          } catch (_) {
            durationDisplay = '-';
          }
        } else {
          durationDisplay = '-';
        }
      } else if ((status == DeviceStatus.idle || status == DeviceStatus.stop || status == DeviceStatus.offline) &&
          device!.movedTimestamp != null &&
          device!.movedTimestamp! > 0) {
        final int movedTime = device!.movedTimestamp!;
        final DateTime lastMoved = movedTime > 1000000000000
            ? DateTime.fromMillisecondsSinceEpoch(movedTime)
            : DateTime.fromMillisecondsSinceEpoch(movedTime * 1000);
        final diff = DateTime.now().difference(lastMoved.toLocal());
        final double diffSec = diff.inSeconds.toDouble();

        double serverStopSec = 0;
        if (device!.stopDurationSec != null) {
          serverStopSec = device!.stopDurationSec!.toDouble();
        } else if (sd.isNotEmpty) {
          serverStopSec = Util.parseDurationToSeconds(sd);
        }

        if (serverStopSec > 0 && diffSec < serverStopSec) {
          durationDisplay = Util.formatDuration(diff);
        } else {
          durationDisplay = sd.isNotEmpty ? Util.formatDurationString(sd) : Util.formatDuration(diff);
        }
      } else {
        durationDisplay = (status != DeviceStatus.running && sd.isNotEmpty) ? Util.formatDurationString(sd) : '-';
      }
    }
    final totalKmDisplay =
        todaytotalDistance.isNotEmpty && todaytotalDistance != '0'
            ? (todaytotalDistance.toLowerCase().contains('km')
                ? todaytotalDistance
                : '$todaytotalDistance Km')
            : '--';
    final batVal = getBatteryVoltage();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFE5E7EB)),
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: Row(
        children: [
          _buildStatCol(statusText, durationDisplay, statColor),
          _buildStatSep(),
          _buildStatCol('Acc', engineVal, const Color(0xFF0F172A)),
          _buildStatSep(),
          _buildStatCol('Today Km', totalKmDisplay, const Color(0xFF0F172A)),
          _buildStatSep(),
          _buildStatCol('Battery', batVal, const Color(0xFF0F172A)),
        ],
      ),
    );
  }

  Widget _buildStatCol(String label, String value, Color valueColor) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatSep() {
    return Container(width: 1, height: 36, color: const Color(0xFFE5E7EB));
  }

  // ── Address row ───────────────────────────────────────────
  Widget _buildAddressRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on, size: 16, color: Color(0xFF6B7280)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _address ?? 'Loading address...',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Horizontal info cards ─────────────────────────────────
  Widget _buildInfoCardsRow() {
    String totalDist = '--';
    if (device?.totalDistance != null) {
      final td = device!.totalDistance;
      if (td is num) {
        totalDist = td.toStringAsFixed(2);
      } else if (td is String) {
        final parsed = double.tryParse(td);
        totalDist = parsed != null ? parsed.toStringAsFixed(2) : td;
      } else {
        totalDist = td.toString();
      }
    }

    final engineVal = device != null ? getEngineStatus() : '--';
    final batVal = getBatteryVoltage();
    final netVal = getNetworkStatus();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        children: [
          _buildInfoCard(
              Icons.route,
              'Total Distance',
              totalDist != '--' ? '$totalDist Km' : '--',
              const Color(0xFFEF5350)),
          const SizedBox(width: 8),
          _buildInfoCard(Icons.power_settings_new, 'Engine Status', engineVal,
              const Color(0xFFF97316)),
          const SizedBox(width: 8),
          _buildInfoCard(Icons.battery_charging_full, 'Battery', batVal,
              const Color(0xFF10B981)),
          const SizedBox(width: 8),
          _buildInfoCard(Icons.signal_cellular_alt, 'Net', netVal,
              const Color(0xFF2563EB)),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
      IconData icon, String label, String value, Color iconColor) {
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC), // neutral slate light bg
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFFE2E8F0), width: 1.2), // clean slate border
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 22,
            color: iconColor,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF64748B), // professional slate grey label
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 4 action buttons ──────────────────────────────────────
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildActionBtn(
            iconWidget: const Icon(
              Icons.history,
              size: 22,
              color: Colors.white,
            ),
            label: 'Play Back',
            color: const Color(0xFF03A9F4), // Play Back light blue
            onTap: _openPlayback,
          ),
          _buildActionBtn(
            iconWidget: const Icon(
              Icons.directions_car,
              size: 22,
              color: Colors.white,
            ),
            label: 'Icon',
            color: const Color(0xFFFF9800), // Vehicle icon orange
            onTap: _openIconSelection,
          ),
          _buildActionBtn(
            iconWidget: const Icon(
              Icons.lock,
              size: 22,
              color: Colors.white,
            ),
            label: 'Lock',
            color: const Color(0xFF00C853), // Lock green
            onTap: _openLock,
          ),
          _buildActionBtn(
            iconWidget: const Icon(
              Icons.settings,
              size: 22,
              color: Colors.white,
            ),
            label: 'Setting',
            color: const Color(0xFF1E88E5), // Settings deep blue
            onTap: () => _showDiagnosticsDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn({
    IconData? icon,
    Widget? iconWidget,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: iconWidget ?? Icon(icon!, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  void _openIconSelection() {
    final devId = device?.id ?? widget.id;
    if (devId == null) {
      Fluttertoast.showToast(msg: "Device ID not found");
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const Center(
        child: CircularProgressIndicator(color: _primaryColor),
      ),
    );

    APIService.editDeviceData({'device_id': devId.toString()}).then((value) {
      Navigator.pop(context); // Close loading dialog
      try {
        final decoded = json.decode(value.body.replaceAll("ï»¿", ""));
        if (decoded is Map<String, dynamic> && decoded.containsKey('message')) {
          Fluttertoast.showToast(msg: decoded['message'].toString());
          return;
        }

        final singleDev = SingleDevice.fromJson(decoded);
        if (singleDev.device_icons != null &&
            singleDev.device_icons!.isNotEmpty) {
          _showChangeIconDialog(singleDev);
        } else {
          Fluttertoast.showToast(msg: "No icons available");
        }
      } catch (e) {
        debugPrint("Error loading icons: $e");
        Fluttertoast.showToast(msg: "Error loading icons");
      }
    }).catchError((e) {
      Navigator.pop(context); // Close loading dialog
      Fluttertoast.showToast(msg: "Failed to fetch icons");
    });
  }

  void _showChangeIconDialog(SingleDevice singleDev) {
    String? tempSelectedPath;
    final devId = device?.id ?? widget.id;
    final savedPath = UserRepository.prefs?.getString("custom_icon_path_${devId}");

    final List<Map<String, dynamic>> localIconsList = [
      {"id": 87, "path": "assets/images/ambulance_toprunning.png", "name": "Ambulance"},
      {"id": 93, "path": "assets/images/bike_toprunning.png", "name": "Bike"},
      {"id": 92, "path": "assets/images/bus_toprunning.png", "name": "Bus"},
      {"id": 59, "path": "assets/images/car_toprunning.png", "name": "Car"},
      {"id": 56, "path": "assets/images/car_green.png", "name": "Green Car"},
      {"id": 43, "path": "assets/images/crane_toprunning.png", "name": "Crane"},
      {"id": 47, "path": "assets/images/garbage_toprunning.png", "name": "Garbage"},
      {"id": 45, "path": "assets/images/mixer_toprunning.png", "name": "Mixer"},
      {"id": 65, "path": "assets/images/muv_toprunning.png", "name": "MUV"},
      {"id": 67, "path": "assets/images/pickup_toprunning.png", "name": "Pickup"},
      {"id": 92, "path": "assets/images/school_toprunning.png", "name": "School Bus"},
      {"id": 93, "path": "assets/images/scotty_toprunning.png", "name": "Scotty"},
      {"id": 57, "path": "assets/images/suv_toprunning.png", "name": "SUV"},
      {"id": 47, "path": "assets/images/tanker_toprunning.png", "name": "Tanker"},
      {"id": 95, "path": "assets/images/tempotvr_toprunning.png", "name": "CNG"},
      {"id": 47, "path": "assets/images/truck_toprunning.png", "name": "Truck"},
    ];

    if (savedPath != null && savedPath.isNotEmpty) {
      tempSelectedPath = savedPath;
    } else {
      final currentIconPath = device?.icon?.path;
      if (currentIconPath != null) {
        final mapped = Util.getLocalMappedAsset(currentIconPath, iconType: device?.icon?.type ?? device?.iconType, deviceName: device?.name, deviceId: devId);
        if (mapped != null) {
          tempSelectedPath = mapped;
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.image_outlined, color: _primaryColor, size: 22),
              SizedBox(width: 8),
              Text(
                'Change Device Icon',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A)),
              ),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.95,
              ),
              itemCount: localIconsList.length,
              itemBuilder: (context, index) {
                final icon = localIconsList[index];
                final isSelected = tempSelectedPath == icon["path"];

                return GestureDetector(
                  onTap: () =>
                      setDialogState(() => tempSelectedPath = icon["path"]),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _primaryColor.withValues(alpha: 0.08)
                          : const Color(0xFFF8FAFC),
                      border: Border.all(
                        color: isSelected
                            ? _primaryColor
                            : const Color(0xFFE2E8F0),
                        width: isSelected ? 2.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Image.asset(
                            icon["path"],
                            width: 45,
                            height: 45,
                            fit: BoxFit.contain,
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: _primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 10,
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () {
                if (tempSelectedPath == null) {
                  Navigator.pop(context);
                  return;
                }
                Navigator.pop(context);
                
                UserRepository.prefs?.setString("custom_icon_path_${devId}", tempSelectedPath!);
                
                int serverIconId = 59;
                for (var item in localIconsList) {
                  if (item["path"] == tempSelectedPath) {
                    serverIconId = item["id"];
                    break;
                  }
                }
                
                _saveSelectedIcon(serverIconId, singleDev);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('OK',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _saveSelectedIcon(int iconId, SingleDevice singleDev) {
    final devId = device?.id ?? widget.id;
    if (devId == null || singleDev.item == null) return;

    setState(() => _isLoading = true);

    Map<String, String> requestBody = {
      'name': device?.name ?? widget.name ?? '',
      'fuel_measurement_id': singleDev.item!["fuel_measurement_id"].toString(),
      'device_id': devId.toString(),
      'icon_id': iconId.toString(),
    };

    APIService.editDevice(requestBody).then((value) {
      setState(() => _isLoading = false);

      // Find the new path and update locally
      String? newPath;
      for (var icon in singleDev.device_icons!) {
        if (icon["id"] == iconId) {
          newPath = icon["path"];
          break;
        }
      }

      if (newPath != null && device != null) {
        setState(() {
          if (device!.icon == null) {
            // Safe fallback: local reload
            _fetchAllData();
          } else {
            device!.icon!.path = newPath;
          }
        });
        _loadMarkerIcon(); // Dynamically reload marker on the map!
      }

      Fluttertoast.showToast(
        msg: "Icon updated successfully",
        backgroundColor: _successColor,
        textColor: Colors.white,
      );
    }).catchError((e) {
      setState(() => _isLoading = false);
      Fluttertoast.showToast(
        msg: "Failed to update icon",
        backgroundColor: _dangerColor,
        textColor: Colors.white,
      );
    });
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isWhiteVariant;

  const _MapButton({
    required this.icon,
    required this.onTap,
    this.isWhiteVariant = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isWhiteVariant ? Colors.white : CustomColor.primary;
    final iconColor = isWhiteVariant ? CustomColor.primary : Colors.white;

    return Material(
      color: bgColor,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isWhiteVariant
            ? const BorderSide(color: CustomColor.primary, width: 1.5)
            : BorderSide.none,
      ),
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 20,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}
