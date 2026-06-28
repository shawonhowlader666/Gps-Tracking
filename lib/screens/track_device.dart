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
import 'package:geolocator/geolocator.dart';
import 'package:gpspro/screens/lock_unlock_screen.dart';
import 'package:gpspro/screens/playback.dart';
import 'package:gpspro/screens/report/get_today_report.dart';
import 'package:gpspro/screens/report/report_screen.dart';
import 'package:gpspro/screens/street_view_screen.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/services/road_snap_service.dart';
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

// ==================== GPS KALMAN FILTER ====================
class GpsKalmanFilter {
  double _lat;
  double _lng;
  double _variance = -1;
  int _lastTimestampMs = 0;
  static const double _processNoise = 3.0;
  static const double _gpsAccuracy = 10.0;

  GpsKalmanFilter(this._lat, this._lng);

  LatLng process(double lat, double lng) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final dt = _lastTimestampMs > 0 ? (nowMs - _lastTimestampMs) / 1000.0 : 0.0;
    _lastTimestampMs = nowMs;

    if (_variance < 0) {
      _lat = lat;
      _lng = lng;
      _variance = _gpsAccuracy * _gpsAccuracy;
      return LatLng(_lat, _lng);
    }

    _variance += dt * _processNoise * _processNoise;
    final K = _variance / (_variance + _gpsAccuracy * _gpsAccuracy);
    _lat += K * (lat - _lat);
    _lng += K * (lng - _lng);
    _variance = (1 - K) * _variance;

    return LatLng(_lat, _lng);
  }
}

// ==================== ULTRA SMOOTH CAR ANIMATOR ====================
class UltraSmoothCarAnimator {
  final TickerProvider vsync;
  final void Function(LatLng position, double bearing) onPositionUpdate;

  Ticker? _ticker;
  bool _isDisposed = false;

  // --- Current animated state ---
  LatLng _currentPos;
  double _currentBearing;

  // --- Target path ---
  List<LatLng> _path = [];
  List<double> _distances = [];
  double _totalDistance = 0.0;

  // --- Stable bearing ---
  double _gpsBearing = 0.0;
  bool _bearingInitialized = false;

  // --- Animation progress ---
  double _t = 1.0;
  int _animStartMs = 0;
  int _animDurationMs = 9200;

  LatLng get currentPosition => _currentPos;
  double get currentBearing => _currentBearing;
  LatLng get targetPosition => _path.isNotEmpty ? _path.last : _currentPos;

  List<LatLng> getTraveledPath() {
    if (_isDisposed || _path.isEmpty) return [];
    if (_t >= 1.0) return _path;

    final easedT = _t * _t * (3 - 2 * _t);
    final targetD = _totalDistance * easedT;

    int idx = 0;
    while (idx < _path.length - 2 && _distances[idx + 1] < targetD) {
      idx++;
    }
    return [..._path.sublist(0, idx + 1), _currentPos];
  }

  UltraSmoothCarAnimator({
    required this.vsync,
    required this.onPositionUpdate,
    required LatLng initialPosition,
    double initialBearing = 0,
  })  : _currentPos = initialPosition,
        _currentBearing = initialBearing {
    _path = [initialPosition];
    _distances = [0.0];
    _totalDistance = 0.0;
    _gpsBearing = initialBearing;
    _ticker = vsync.createTicker(_onTick)..start();
  }

  void moveToPath(List<LatLng> path, double gpsBearing, {int? expectedIntervalMs}) {
    if (_isDisposed || path.isEmpty) return;

    final fullPath = [_currentPos, ...path];

    final dists = List<double>.filled(fullPath.length, 0.0);
    for (int i = 1; i < fullPath.length; i++) {
      dists[i] = dists[i - 1] + RoadSnapService.distanceMeters(fullPath[i - 1], fullPath[i]);
    }
    final totalDist = dists.last;

    if (totalDist >= 5.0) {
      if (!_bearingInitialized) {
        _gpsBearing = gpsBearing;
        _bearingInitialized = true;
      } else {
        final diff = (((gpsBearing - _gpsBearing) % 360) + 360) % 360;
        final normalized = diff > 180 ? diff - 360 : diff;
        if (normalized.abs() <= 150) {
          _gpsBearing = gpsBearing;
        }
      }
      _currentBearing = _gpsBearing;
    }

    _path = fullPath;
    _distances = dists;
    _totalDistance = totalDist;

    _animDurationMs = ((expectedIntervalMs ?? 8000) * 0.92).round();
    _animStartMs = DateTime.now().millisecondsSinceEpoch;
    _t = 0.0;
  }

  void teleportTo(LatLng position, double bearing) {
    if (_isDisposed) return;
    _currentPos = position;
    _currentBearing = bearing;
    _path = [position];
    _distances = [0.0];
    _totalDistance = 0.0;
    _t = 1.0;
    _gpsBearing = bearing;
    onPositionUpdate(position, bearing);
  }

  double _calculateBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * m.pi / 180;
    final lon1 = start.longitude * m.pi / 180;
    final lat2 = end.latitude * m.pi / 180;
    final lon2 = end.longitude * m.pi / 180;

    final dLon = lon2 - lon1;

    final y = m.sin(dLon) * m.cos(lat2);
    final x = m.cos(lat1) * m.sin(lat2) -
        m.sin(lat1) * m.cos(lat2) * m.cos(dLon);

    final radians = m.atan2(y, x);
    return ((radians * 180 / m.pi) + 360) % 360;
  }

  double _interpolateBearing(double from, double to, double maxDelta) {
    from = from % 360;
    to = to % 360;

    double diff = to - from;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    if (diff.abs() <= maxDelta) {
      return to;
    }
    return (from + diff.sign * maxDelta) % 360;
  }

  void _onTick(Duration elapsed) {
    if (_isDisposed) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    _t = _animDurationMs > 0
        ? ((now - _animStartMs) / _animDurationMs).clamp(0.0, 1.0)
        : 1.0;

    final easedT = _t * _t * (3 - 2 * _t);

    if (_totalDistance < 0.5 || _path.length < 2) {
      onPositionUpdate(_currentPos, _currentBearing);
      return;
    }

    final targetD = _totalDistance * easedT;
    int idx = 0;
    while (idx < _path.length - 2 && _distances[idx + 1] < targetD) {
      idx++;
    }

    final segLen = _distances[idx + 1] - _distances[idx];
    final segRatio = segLen > 0 ? (targetD - _distances[idx]) / segLen : 0.0;
    _currentPos = _lerpLatLng(_path[idx], _path[idx + 1], segRatio);

    // Only update bearing if the segment is long enough (prevents spinning on tiny GPS drift segments)
    if (segLen > 2.0) {
      final segmentBearing = _calculateBearing(_path[idx], _path[idx + 1]);
      
      // Calculate absolute difference between the segment bearing and the physical GPS heading
      double diff = (segmentBearing - _gpsBearing).abs();
      if (diff > 180.0) diff = 360.0 - diff;
      
      // Follow the road segment direction so the car always faces forward along the road
      final targetB = segmentBearing;
      
      _currentBearing = _interpolateBearing(_currentBearing, targetB, 6.0);
    }

    onPositionUpdate(_currentPos, _currentBearing);
  }

  static LatLng _lerpLatLng(LatLng a, LatLng b, double t) => LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

  void dispose() {
    _isDisposed = true;
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
  }
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
  double _currentZoom = 18.5;
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
  bool _isCodeMovingCamera = false;
  String? _lastLocalIconPath;
  late GpsKalmanFilter _kalman;
  int _lastUpdateTimestamp = 0;
  int _currentUpdateId = 0;
  String? _lastIconPath;
  String? _lastStatusColor;
  String? _lastIconType;
  String? _lastDeviceName;
  int? _lastDeviceId;
  LatLng? _lastRawGpsPoint;
  LatLng? _lastSnappedPos;

  LatLng? _userLocationForDistance;
  List<LatLng> _distanceRoutePoints = [];
  bool _showingUserDistance = false;

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
    final currentLocalPath = UserRepository.prefs?.getString("custom_icon_path_${b.id}");
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
      _lastLocalIconPath = UserRepository.prefs?.getString("custom_icon_path_${widget.device!.id}");
    }

    final DataController controller = Get.put(DataController());
    _onlyDevicesSubscription = controller.onlyDevices.listen((devices) {
      if (mounted && !_isDisposed) {
        for (var element in devices) {
          if (element.id == widget.id) {
            if (_hasDeviceChanged(device, element)) {
              _lastLocalIconPath = UserRepository.prefs?.getString("custom_icon_path_${element.id}");
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
    final rawInitialPos = _getInitialPosition();
    _fetchAddressForCoordinates(rawInitialPos.latitude, rawInitialPos.longitude);
    final initialBearing =
        double.tryParse(device?.course?.toString() ?? '0') ?? 0;

    // Initialize Kalman filter
    _kalman = GpsKalmanFilter(rawInitialPos.latitude, rawInitialPos.longitude);

    // Initialize animator instantly using raw position to avoid waiting for network
    _carAnimator = UltraSmoothCarAnimator(
      vsync: this,
      onPositionUpdate: _onCarPositionUpdate,
      initialPosition: rawInitialPos,
      initialBearing: initialBearing,
    );

    // Load marker icon (smaller size = 40)
    await _loadMarkerIcon();

    // Add initial polyline point
    _polylinePoints.add(rawInitialPos);
    _lastRawGpsPoint = rawInitialPos;
    _lastSnappedPos = rawInitialPos;

    // Update map
    _updateMapMarker();
    _updateMapPolyline();

    // Start data fetching
    _startDataTimer();

    // Snap starting point in the background asynchronously to prevent delays
    RoadSnapService.snapSingleLivePoint(rawInitialPos).then((snappedPos) {
      if (mounted && !_isDisposed && _carAnimator != null) {
        _carAnimator!.teleportTo(snappedPos, initialBearing);
        _lastSnappedPos = snappedPos;
        
        // Re-align starting polyline point to snapped road coordinate
        if (_polylinePoints.isNotEmpty && _polylinePoints.first == rawInitialPos) {
          _polylinePoints[0] = snappedPos;
        }
        _updateMapMarker();
        _updateMapPolyline();
      }
    });
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
    final statusColor = Util.getDeviceStatusColorStr(device!);
    final iconType = device?.icon?.type ?? device?.iconType;

    // Cache current properties to prevent redundant reloads
    _lastIconPath = device!.icon!.path;
    _lastStatusColor = statusColor;
    _lastIconType = iconType;
    _lastDeviceName = device!.name;
    _lastDeviceId = device!.id;

    try {
      final path = device!.icon!.path!;
      _markerIcon = await Util.getMarkerIcon(path,
          size: _currentMarkerSize,
          statusColor: statusColor,
          iconType: iconType,
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

  /// Returns true if the engine/ignition is ON for the given device.
  /// Logic is identical to home_screen.dart and devices.dart for consistency.
  bool _isEngineOn(DeviceItem d) {
    // 1. If speed > 0, engine must be on
    final speed = double.tryParse(d.speed.toString()) ?? 0;
    if (speed > 0) return true;

    // 2. Check engineStatus field directly
    if (d.engineStatus != null) {
      final status = d.engineStatus;
      if (status is bool) return status;
      if (status is int) return status == 1;
      if (status is String) {
        final s = status.toLowerCase().trim();
        if (['on', '1', 'true', 'ign on', 'engine on', 'acc on'].contains(s)) {
          return true;
        }
        if (['off', '0', 'false', 'ign off', 'engine off', 'acc off'].contains(s)) {
          return false;
        }
      }
    }

    // 3. Check sensors for ignition / ACC status
    if (d.sensors != null && d.sensors!.isNotEmpty) {
      for (var sensor in d.sensors!) {
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
              if (['on', '1', 'true', 'ign on', 'acc on', 'engine on'].contains(v)) return true;
              if (['off', '0', 'false', 'ign off', 'acc off', 'engine off'].contains(v)) return false;
            }
          }
        } catch (_) {
          continue;
        }
      }
    }

    // 4. Fallback: iconColor yellow/green → engine considered on
    final iconColor = d.iconColor?.toLowerCase().trim() ?? '';
    if (iconColor == 'yellow' || iconColor == 'green') return true;

    return false;
  }

  String getEngineStatus() {
    if (device == null) return 'Off';
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
  // ==================== SMOOTH MARKER UPDATE ====================
  Future<void> updateMarker(DeviceItem element) async {
    if (_isDisposed || _carAnimator == null) return;

    _currentUpdateId++;
    final myUpdateId = _currentUpdateId;

    final double? rawLat = double.tryParse(element.lat?.toString() ?? '');
    final double? rawLng = double.tryParse(element.lng?.toString() ?? '');
    if (rawLat == null || rawLng == null) return;

    final gpsSpeed = double.tryParse(element.speed?.toString() ?? '0') ?? 0.0;
    final gpsBearing = double.tryParse(element.course?.toString() ?? '0.0') ?? 0.0;

    // ── Outlier Rejection (LBS Jump / GPS Drift Filter) ───────────────────
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastRawGpsPoint != null && _lastUpdateTimestamp > 0) {
      final double dtSeconds = (nowMs - _lastUpdateTimestamp) / 1000.0;
      if (dtSeconds > 1.0) { // Only check if at least 1s elapsed
        final double rawGpsDist = RoadSnapService.distanceMeters(_lastRawGpsPoint!, LatLng(rawLat, rawLng));
        final double calculatedSpeedMps = rawGpsDist / dtSeconds;
        final double reportedSpeedMps = gpsSpeed / 3.6;

        // Reject if calculated speed is > 45 m/s (162 km/h) AND > 3.5x reported speed
        if (calculatedSpeedMps > 45.0 && calculatedSpeedMps > 3.5 * reportedSpeedMps) {
          _updateIconIfChanged(element);
          return;
        }
      }
    }

    // ── Step 1: Kalman filter ─────────────────────────────────────────────
    final filteredPos = _kalman.process(rawLat, rawLng);

    // ── Step 2: Freeze when stationary ───────────────────────────────────
    if (gpsSpeed < 3.0) {
      _updateIconIfChanged(element);
      return;
    }

    // ── Step 3: Minimum distance gate ─────────────────────────────────────
    // Check if the vehicle has actually moved at least 6 meters on the road.
    final refPos = _lastSnappedPos ?? filteredPos;
    final rawDist = RoadSnapService.distanceMeters(refPos, filteredPos);
    if (rawDist < 6.0) {
      _updateIconIfChanged(element);
      return;
    }

    // ── Step 3.5: Jump Teleport Gate ──────────────────────────────────────
    // If the distance is > 1500 meters, it represents a network wake-up delay or GPS teleport.
    // Teleport the car instantly to the destination to prevent it from flying through buildings.
    if (rawDist > 1500.0) {
      final snappedTeleport = await RoadSnapService.snapSingleLivePoint(filteredPos);
      if (_isDisposed || myUpdateId != _currentUpdateId) return;

      _carAnimator!.teleportTo(snappedTeleport, gpsBearing);
      
      // Clear trail history to prevent drawing a straight line cutting through buildings
      _polylinePoints.clear();
      _polylinePoints.add(snappedTeleport);
      
      _lastRawGpsPoint = filteredPos;
      _lastSnappedPos = snappedTeleport;
      
      // Center camera immediately on teleport to avoid off-screen vehicle
      if (_followVehicle && _mapController != null) {
        _isCodeMovingCamera = true;
        _mapController!.moveCamera(CameraUpdate.newLatLng(snappedTeleport));
      }

      _updateIconIfChanged(element);
      return;
    }

    // ── Step 4: Get Snapped Road Path ─────────────────────────────────────
    // Snaps start and end coordinates directly via OSRM route network.
    // This avoids snapping to side streets by analyzing the route trajectory.
    List<LatLng> animPath;
    LatLng snappedPos;

    if (rawDist > 800.0) {
      // Big jump: do not snap/route over streets to avoid winding paths.
      // Just interpolate a straight line.
      animPath = [refPos, filteredPos];
      snappedPos = filteredPos;
    } else {
      // Normal movement: get OSRM road route. OSRM automatically snaps start/end to road.
      animPath = await RoadSnapService.getRoutePath(refPos, filteredPos);
      if (_isDisposed || myUpdateId != _currentUpdateId) return;

      if (animPath.length == 2 && animPath[0] == refPos && animPath[1] == filteredPos) {
        // OSRM route service returned straight fallback.
        // Snap the destination point to the nearest road so the vehicle doesn't go off-road!
        final snappedGoal = await RoadSnapService.snapSingleLivePoint(filteredPos);
        if (_isDisposed || myUpdateId != _currentUpdateId) return;
        animPath = [refPos, snappedGoal];
        snappedPos = snappedGoal;
      } else if (animPath.isNotEmpty) {
        // Detect massive detours (e.g. flyover vs ground road snapping level mismatches)
        double pathLength = 0.0;
        for (int i = 1; i < animPath.length; i++) {
          pathLength += RoadSnapService.distanceMeters(animPath[i - 1], animPath[i]);
        }

        if (pathLength > 3.5 * rawDist && pathLength > 60.0) {
          // Snap directly to the nearest road point instead of driving the detour route
          final snappedGoal = await RoadSnapService.snapSingleLivePoint(filteredPos);
          if (_isDisposed || myUpdateId != _currentUpdateId) return;
          animPath = [refPos, snappedGoal];
          snappedPos = snappedGoal;
        } else {
          snappedPos = animPath.last;
        }
      } else {
        // Ultimate fallback: snap destination point
        final snappedGoal = await RoadSnapService.snapSingleLivePoint(filteredPos);
        if (_isDisposed || myUpdateId != _currentUpdateId) return;
        animPath = [refPos, snappedGoal];
        snappedPos = snappedGoal;
      }
    }

    // Fetch address for updated coordinates
    _fetchAddressForCoordinates(snappedPos.latitude, snappedPos.longitude);

    // ── Step 5: Dynamic Expected Interval ──────────────────────────────────
    int expectedIntervalMs = 8000;
    if (_lastUpdateTimestamp != 0) {
      expectedIntervalMs = nowMs - _lastUpdateTimestamp;
    }
    _lastUpdateTimestamp = nowMs;
    expectedIntervalMs = expectedIntervalMs.clamp(3000, 15000);

    // ── Step 6: Commit previous traveled path to history ──────────────────
    if (_carAnimator != null) {
      final traveled = _carAnimator!.getTraveledPath();
      if (traveled.isNotEmpty) {
        _polylinePoints.addAll(traveled.sublist(1));
      }
    }
    if (_polylinePoints.length > _maxPolylinePoints) {
      _polylinePoints.removeRange(0, _polylinePoints.length - _maxPolylinePoints);
    }

    // ── Step 7: Update state ───────────────────────────────────────────────
    _lastRawGpsPoint = filteredPos;
    _lastSnappedPos = snappedPos;

    // ── Step 8: Smooth animation along the road path ───────────────────────
    _carAnimator!.moveToPath(
      animPath,
      gpsBearing,
      expectedIntervalMs: expectedIntervalMs,
    );
    _updateIconIfChanged(element);
  }

  int _lastMarkerUpdateMs = 0;

  void _onCarPositionUpdate(LatLng position, double bearing) {
    if (_isDisposed) return;

    // ── Marker & Polyline: throttle to 30fps ──────────────────────────────
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMarkerUpdateMs >= 33) {
      _lastMarkerUpdateMs = now;
      _updateMapMarker();
      _updateMapPolyline();
    }

    // Smoothly follow the vehicle in real-time on every ticker update
    if (_followVehicle &&
        _isMapCreated &&
        _mapController != null &&
        !_userInteracting) {
      _isCodeMovingCamera = true;
      _mapController!.moveCamera(
        CameraUpdate.newLatLng(position),
      );
    }
  }

  void _updateMapMarker() {
    if (_isDisposed || !_isMarkerReady || _carAnimator == null) return;

    final markers = <Marker>{};
    markers.add(Marker(
      markerId: const MarkerId("vehicle"),
      position: _carAnimator!.currentPosition,
      rotation: _carAnimator!.currentBearing,
      icon: _markerIcon ?? BitmapDescriptor.defaultMarker,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      zIndex: 2,
    ));

    if (_showingUserDistance && _userLocationForDistance != null) {
      markers.add(Marker(
        markerId: const MarkerId("user_location"),
        position: _userLocationForDistance!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        zIndex: 3,
      ));
    }

    _markersNotifier.value = markers;
  }

  void _updateMapPolyline() {
    if (_isDisposed || _carAnimator == null || _polylinePoints.isEmpty) return;

    // Draw the line up to the current animated position of the vehicle
    final points = List<LatLng>.from(_polylinePoints);
    if (_carAnimator != null) {
      final traveled = _carAnimator!.getTraveledPath();
      if (traveled.isNotEmpty) {
        points.addAll(traveled.sublist(1));
      }
    }

    final trailColor = _getStatusColor();
    final polylines = <Polyline>{};

    polylines.add(Polyline(
      polylineId: const PolylineId("trail"),
      points: points,
      color: trailColor.withValues(alpha: 0.8),
      width: 3, // Sleeker line width for a more premium look
      geodesic: true,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    ));

    if (_showingUserDistance && _distanceRoutePoints.isNotEmpty) {
      polylines.add(Polyline(
        polylineId: const PolylineId("user_distance_route"),
        points: _distanceRoutePoints,
        color: const Color(0xFF10B981), // Green color for distance route
        width: 4,
        geodesic: true,
        jointType: JointType.round,
        patterns: _distanceRoutePoints.length == 2
            ? [PatternItem.dash(15), PatternItem.gap(10)]
            : [],
      ));
    }

    _polylinesNotifier.value = polylines;
  }

  void _updateIconIfChanged(DeviceItem element) async {
    if (element.icon?.path == null) return;
    final statusColor = Util.getDeviceStatusColorStr(element);
    final iconType = element.icon?.type ?? element.iconType;

    // Check if the icon appearance actually changed.
    // This stops the marker from flashing/blinking on the map during every GPS update.
    if (_markerIcon != null &&
        _lastIconPath == element.icon!.path &&
        _lastStatusColor == statusColor &&
        _lastIconType == iconType &&
        _lastDeviceName == element.name &&
        _lastDeviceId == element.id) {
      return;
    }

    _lastIconPath = element.icon!.path;
    _lastStatusColor = statusColor;
    _lastIconType = iconType;
    _lastDeviceName = element.name;
    _lastDeviceId = element.id;

    try {
      final icon = await Util.getMarkerIcon(
        element.icon!.path!,
        size: _currentMarkerSize,
        statusColor: statusColor,
        iconType: iconType,
        deviceName: element.name,
        deviceId: element.id,
      );
      if (!_isDisposed && icon != _markerIcon) {
        _markerIcon = icon;
        _isMarkerReady = true;
        _updateMapMarker();
      }
    } catch (e) {
      debugPrint("Error updating marker icon: $e");
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
    final colorStr = Util.getDeviceStatusColorStr(device);
    switch (colorStr) {
      case 'green': return DeviceStatus.running;
      case 'yellow': return DeviceStatus.idle;
      case 'red': return DeviceStatus.stop;
      default: return DeviceStatus.offline;
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

// Replace the _buildMap method  Widget _buildMap() {
    return ValueListenableBuilder<Set<Marker>>(
      valueListenable: _markersNotifier,
      builder: (context, markers, _) {
        return ValueListenableBuilder<Set<Polyline>>(
          valueListenable: _polylinesNotifier,
          builder: (context, polylines, _) {
            return Listener(
              onPointerDown: (_) {
                _userInteracting = true;
                _followVehicle = false;
              },
              onPointerUp: (_) {
                _userInteracting = false;
              },
              onPointerCancel: (_) {
                _userInteracting = false;
              },
              child: GoogleMap(
                mapType: _currentMapType,
                trafficEnabled: _trafficEnabled,
                initialCameraPosition: CameraPosition(
                  target: _getInitialPosition(),
                  zoom: _currentZoom,
                ),
                onCameraMove: (pos) {
                  _currentZoom = pos.zoom;
                  if (_isCodeMovingCamera) {
                    _isCodeMovingCamera = false; // Code-driven movement, ignore
                  }
                },
                onCameraIdle: () {
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
              ),
            );
            },
          );
        },
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
            icon: Icons.people_alt_outlined,
            isWhiteVariant: true,
            onTap: _showDistanceToVehicle,
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: Icons.headset_mic,
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

  // ==================== DISTANCE TO VEHICLE ====================
  Future<void> _showDistanceToVehicle() async {
    if (_carAnimator == null) return;
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          Get.snackbar('Permission Denied', 'Location permission is required to calculate distance.',
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: Colors.red.withValues(alpha: 0.9),
              colorText: Colors.white);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        Get.snackbar(
            'Permission Denied', 'Enable location permission in settings.',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red.withValues(alpha: 0.9),
            colorText: Colors.white);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final userLatLng = LatLng(position.latitude, position.longitude);
      final vehicleLatLng = _carAnimator!.currentPosition;

      final double distanceMeters = RoadSnapService.distanceMeters(userLatLng, vehicleLatLng);
      String distanceStr;
      if (distanceMeters >= 1000) {
        distanceStr = '${(distanceMeters / 1000).toStringAsFixed(2)} km';
      } else {
        distanceStr = '${distanceMeters.toStringAsFixed(0)} meters';
      }

      final deviceName = device?.name ?? 'Vehicle';

      // 1. Fetch route points using OSRM if distance is reasonably small (< 100 km)
      List<LatLng> routePoints = [];
      if (distanceMeters < 100000) {
        try {
          routePoints = await RoadSnapService.getRoutePath(userLatLng, vehicleLatLng);
        } catch (e) {
          debugPrint("OSRM routing error: $e");
        }
      }

      if (routePoints.isEmpty) {
        // Fallback: draw straight dashed line
        routePoints = [userLatLng, vehicleLatLng];
      }

      // Update state to show user location and route polyline
      setState(() {
        _showingUserDistance = true;
        _userLocationForDistance = userLatLng;
        _distanceRoutePoints = routePoints;
        _followVehicle = false; // Disable auto-centering on vehicle so we can fit bounds
      });

      _updateMapPolyline();
      _updateMapMarker();

      // Zoom out to show both points on the map
      double minLat = m.min(userLatLng.latitude, vehicleLatLng.latitude);
      double maxLat = m.max(userLatLng.latitude, vehicleLatLng.latitude);
      double minLng = m.min(userLatLng.longitude, vehicleLatLng.longitude);
      double maxLng = m.max(userLatLng.longitude, vehicleLatLng.longitude);

      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      _isCodeMovingCamera = true;
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));

      // Display the metrics in a premium bottom sheet modal
      Get.bottomSheet(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                spreadRadius: 2,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.people_alt, color: CustomColor.primary, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Distance to $deviceName',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Separation Distance:',
                    style: TextStyle(fontSize: 15, color: Colors.grey),
                  ),
                  Text(
                    distanceStr,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: CustomColor.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey[300]!),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Get.back(); // Closes bottom sheet
                      },
                      child: const Text('Close Route', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _dangerColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        _navigate();
                      },
                      icon: const Icon(Icons.navigation_rounded, size: 18),
                      label: const Text('Start Navigate', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        isDismissible: true,
        enableDrag: true,
      ).then((_) {
        // When the bottom sheet is dismissed, clean up distance variables and resume tracking
        setState(() {
          _showingUserDistance = false;
          _userLocationForDistance = null;
          _distanceRoutePoints = [];
          _followVehicle = true; // Resume centering on vehicle
        });
        _updateMapPolyline();
        _updateMapMarker();
        _centerOnVehicle();
      });
    } catch (e) {
      Get.snackbar('Error', 'Could not get distance: $e',
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
      initialChildSize: 0.38,
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
              SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
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
    final status = _getDeviceStatus(device);
    final statusText = _getStatusText();
    final statusColor = _getStatusColor();
    final statColor = statusColor;

    final isEngineOn = device != null ? getEngineStatus() == 'On' : false;
    String durationDisplay = '-';
    if (device != null) {
      final statusVal = _getDeviceStatus(device);
      final sd = device!.stopDuration ?? '';
      
      if (statusVal == DeviceStatus.running) {
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
      } else if ((statusVal == DeviceStatus.idle || statusVal == DeviceStatus.stop || statusVal == DeviceStatus.offline) &&
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
        durationDisplay = (statusVal != DeviceStatus.running && sd.isNotEmpty) ? Util.formatDurationString(sd) : '-';
      }
    }
    final totalKmDisplay =
        todaytotalDistance.isNotEmpty && todaytotalDistance != '0'
            ? (todaytotalDistance.toLowerCase().contains('km')
                ? todaytotalDistance
                : '$todaytotalDistance Km')
            : '--';
    final batVal = getBatteryVoltage();

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

    // Status styling helper
    Color statusBgColor = const Color(0xFFE5E7EB);
    if (status == DeviceStatus.running) {
      statusBgColor = const Color(0xFFBBF7D0); // vibrant light green
    } else if (status == DeviceStatus.idle) {
      statusBgColor = const Color(0xFFFEF08A); // vibrant light yellow
    } else if (status == DeviceStatus.stop) {
      statusBgColor = const Color(0xFFFECACA); // vibrant light red
    }

    final engineBgColor = isEngineOn ? const Color(0xFFBBF7D0) : const Color(0xFFE5E7EB);
    final batteryBgColor = const Color(0xFFBFDBFE); // vibrant light blue
    const expiryBgColor = Color(0xFFE5E7EB); // clean light grey

    Color getDarkerContrastColor(Color color) {
      if (color == const Color(0xFF22C55E) || color == Colors.green || color == const Color(0xFF10B981) || color == _successColor) {
        return const Color(0xFF15803D); // dark green
      } else if (color == const Color(0xFFFFD600) || color == Colors.amber || color == const Color(0xFFEAB308) || color == const Color(0xFFFEF08A) || color == _warningColor) {
        return const Color(0xFFA16207); // dark yellow/gold
      } else if (color == const Color(0xFFEF4444) || color == Colors.red || color == const Color(0xFFDC2626) || color == _dangerColor) {
        return const Color(0xFFB91C1C); // dark red
      }
      return color;
    }

    Widget buildCardItem({
      required String label,
      required Widget content,
      required Color bgColor,
    }) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: bgColor.withOpacity(1.0),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28), // darker shadow
                blurRadius: 3.5, // tight blur
                spreadRadius: 0.5,
                offset: const Offset(0, 2.5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF4B5563), // gray-600
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: content,
              ),
            ],
          ),
        ),
      );
    }

    // Determine battery icon
    IconData batteryIcon = Icons.battery_std;
    try {
      final numericBat = int.tryParse(batVal.replaceAll(RegExp(r'[^0-9]'), ''));
      if (numericBat != null) {
        if (numericBat > 85) {
          batteryIcon = Icons.battery_full;
        } else if (numericBat > 50) {
          batteryIcon = Icons.battery_4_bar;
        } else if (numericBat > 20) {
          batteryIcon = Icons.battery_2_bar;
        } else {
          batteryIcon = Icons.battery_0_bar;
        }
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Status Card
          buildCardItem(
            label: statusText,
            bgColor: statusBgColor,
            content: Text(
              status == DeviceStatus.running
                  ? '${double.tryParse(device?.speed?.toString() ?? '0')?.toInt() ?? 0} km/h'
                  : durationDisplay,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: getDarkerContrastColor(statColor),
              ),
            ),
          ),

          // Engine Card
          buildCardItem(
            label: 'Engine',
            bgColor: engineBgColor,
            content: Text(
              isEngineOn ? 'On' : 'Off',
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isEngineOn ? const Color(0xFF15803D) : const Color(0xFF1F2937),
              ),
            ),
          ),

          // Battery Card
          buildCardItem(
            label: 'Battery',
            bgColor: batteryBgColor,
            content: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  batteryIcon,
                  size: 13,
                  color: const Color(0xFF1E3A8A), // dark blue contrast
                ),
                const SizedBox(width: 2),
                Text(
                  batVal,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
              ],
            ),
          ),

          // Expiry Card
          buildCardItem(
            label: 'Expired On',
            bgColor: expiryBgColor,
            content: Text(
              expiryStr,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
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
    final bgCol = iconColor.withValues(alpha: 0.15);
    final borderCol = iconColor.withValues(alpha: 0.35);
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgCol,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderCol, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28), // darker shadow
            blurRadius: 3.5, // tight blur, won't spread too much
            spreadRadius: 0.5,
            offset: const Offset(0, 2.5),
          ),
        ],
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
                  color: Color(0xFF4B5563),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
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
