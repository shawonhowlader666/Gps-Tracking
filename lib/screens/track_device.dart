import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;
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
import 'package:smart_lock/services/road_snap_service.dart';
import 'package:smart_lock/util/util.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:smart_lock/storage/user_repository.dart';

import 'common_method.dart';

enum DeviceStatus { running, idle, stop, offline, expired }

// ==================== GPS KALMAN FILTER ====================
// Industry-standard algorithm used by Google Maps, Waze, and professional
// GPS tracking platforms to smooth out GPS noise mathematically.
//
// How it works:
//  - Maintains a running estimate of position + uncertainty (variance)
//  - Each GPS measurement is weighted against current estimate reliability
//  - High uncertainty (long time passed) → trust new GPS more
//  - Low uncertainty (just updated) → trust current estimate more
//  - Result: smooth position that absorbs GPS noise and random jumps
class GpsKalmanFilter {
  double _lat;
  double _lng;

  // Variance (m²): uncertainty in current position estimate.
  double _variance = -1; // negative = not yet initialized
  int _lastTimestampMs = 0;

  // How fast position uncertainty grows per second (speed of vehicle in m/s).
  // 3.0 m/s is conservative — good for urban fleet vehicles.
  static const double _processNoise = 3.0;

  // Assumed GPS hardware accuracy (5-15m for typical vehicle GPS trackers).
  static const double _gpsAccuracy = 10.0;

  GpsKalmanFilter(this._lat, this._lng);

  /// Feed a new raw GPS fix. Returns the Kalman-smoothed position.
  LatLng process(double lat, double lng) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final dt = _lastTimestampMs > 0
        ? (nowMs - _lastTimestampMs) / 1000.0
        : 0.0;
    _lastTimestampMs = nowMs;

    if (_variance < 0) {
      // First measurement — accept raw GPS as starting truth
      _lat = lat;
      _lng = lng;
      _variance = _gpsAccuracy * _gpsAccuracy;
      return LatLng(_lat, _lng);
    }

    // Grow uncertainty with elapsed time (vehicle could have moved)
    _variance += dt * _processNoise * _processNoise;

    // Kalman gain K: k→1 means trust new reading, k→0 means trust estimate
    final K = _variance / (_variance + _gpsAccuracy * _gpsAccuracy);

    // Blend estimate towards new measurement
    _lat += K * (lat - _lat);
    _lng += K * (lng - _lng);

    // Uncertainty shrinks after a measurement
    _variance = (1 - K) * _variance;

    return LatLng(_lat, _lng);
  }
}

// ==================== SMOOTH ANIMATOR (Industry Grade) ====================
// Uses constant-time lerp over the GPS update interval.
// The marker moves continuously and arrives at target exactly when the next
// GPS update is expected — eliminating all visible jumps.
class SmoothCarAnimator {
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

  // --- Stable bearing: only updated when car moves meaningfully ---
  double _gpsBearing = 0.0;
  bool _bearingInitialized = false;

  // --- Animation progress ---
  double _t = 1.0;
  int _animStartMs = 0;
  int _animDurationMs = 9200;

  LatLng get currentPosition => _currentPos;
  double get currentBearing => _currentBearing;

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

  SmoothCarAnimator({
    required this.vsync,
    required this.onPositionUpdate,
    required LatLng initialPosition,
    double initialBearing = 0,
    int updateIntervalMs = 10000,
  })  : _currentPos = initialPosition,
        _currentBearing = initialBearing {
    _path = [initialPosition];
    _distances = [0.0];
    _totalDistance = 0.0;
    _gpsBearing = initialBearing;
    _ticker = vsync.createTicker(_onTick)..start();
  }

  /// [gpsBearing] = server-reported course field (most accurate heading source)
  void moveToPath(List<LatLng> path, double gpsBearing, {int? expectedIntervalMs}) {
    if (_isDisposed || path.isEmpty) return;

    // Build path starting from current animated position
    final fullPath = [_currentPos, ...path];

    // Compute cumulative distances
    final dists = List<double>.filled(fullPath.length, 0.0);
    for (int i = 1; i < fullPath.length; i++) {
      dists[i] = dists[i - 1] + RoadSnapService.distanceMeters(fullPath[i - 1], fullPath[i]);
    }
    final totalDist = dists.last;

    // ── Bearing: use server-reported course directly ──────────────────────
    // The GPS device sends the actual heading — more accurate than calculating
    // from two lat/lng points (which creates zigzag/spin artifacts).
    // Only update bearing if vehicle is actually moving (≥ 5m) to keep it
    // frozen when parked (prevents spinning on GPS noise).
    if (totalDist >= 5.0) {
      if (!_bearingInitialized) {
        _gpsBearing = gpsBearing;
        _bearingInitialized = true;
      } else {
        // Reject impossible U-turns from GPS glitches (> 150° sudden change)
        final diff = (((gpsBearing - _gpsBearing) % 360) + 360) % 360;
        final normalized = diff > 180 ? diff - 360 : diff;
        if (normalized.abs() <= 150) {
          _gpsBearing = gpsBearing;
        }
      }
      _currentBearing = _gpsBearing;
    }
    // If distance < 5m: bearing stays FROZEN — no spin when parked/idle

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
    final lat1 = start.latitude * math.pi / 180;
    final lon1 = start.longitude * math.pi / 180;
    final lat2 = end.latitude * math.pi / 180;
    final lon2 = end.longitude * math.pi / 180;

    final dLon = lon2 - lon1;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final radians = math.atan2(y, x);
    return ((radians * 180 / math.pi) + 360) % 360;
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

    // Advance animation
    final now = DateTime.now().millisecondsSinceEpoch;
    _t = _animDurationMs > 0
        ? ((now - _animStartMs) / _animDurationMs).clamp(0.0, 1.0)
        : 1.0;

    // Smooth ease in-out
    final easedT = _t * _t * (3 - 2 * _t);

    // ── Position along path ───────────────────────────────────────────────
    if (_totalDistance < 0.5 || _path.length < 2) {
      // Stationary — stay in place, bearing FROZEN (no spinning)
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
  double _currentZoom = 18.5;
  bool _trafficEnabled = true;
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
  int _currentUpdateId = 0;
  String? _lastIconPath;
  String? _lastStatusColor;
  String? _lastIconType;
  String? _lastDeviceName;
  int? _lastDeviceId;

  LatLng? _userLocationForDistance;
  List<LatLng> _distanceRoutePoints = [];
  bool _showingUserDistance = false;

  final List<LatLng> _polylinePoints = [];
  static const int _maxPolylinePoints = 2000;
  LatLng? _lastPolylinePoint;
  LatLng? _lastRawGpsPoint;
  LatLng? _lastSnappedPos;
  bool _historyTrailLoaded = false;
  double _lastGpsSpeed = 0.0;
  // Kalman filter: initialized with device's starting position
  late GpsKalmanFilter _kalman;
  int _lastUpdateTimestamp = 0;

  Timer? _dataTimer;
  Timer? _cameraTimer;

  // Colors
  static const _primaryRed = Color(0xFFCC0000);
  static const _successColor = Color(0xFF22C55E);
  static const _warningColor = Color(0xFFFFD600);
  static const _dangerColor = Color(0xFFEF4444);
  static const _primaryBlue = Color(0xFF3B82F6);
  static const _neutralColor = Color(0xFF4B5563);
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
    final rawInitialPos = _getInitialPosition();
    final initialBearing =
        double.tryParse(device?.course?.toString() ?? '0') ?? 0;

    // Initialize Kalman filter at the vehicle's current known position
    _kalman = GpsKalmanFilter(rawInitialPos.latitude, rawInitialPos.longitude);

    // Initialize animator instantly using raw position to avoid waiting for network
    _carAnimator = SmoothCarAnimator(
      vsync: this,
      onPositionUpdate: _onCarPositionUpdate,
      initialPosition: rawInitialPos,
      initialBearing: initialBearing,
    );
    await _loadMarkerIcon();
    _polylinePoints.add(rawInitialPos);
    _lastPolylinePoint = rawInitialPos;
    _lastRawGpsPoint = rawInitialPos;
    _lastSnappedPos = rawInitialPos;
    _updateMapMarkers();
    _startDataTimer();
    _startCameraTimer();
    _loadTodayTrail();



    // Snap starting point in the background asynchronously to prevent delays
    RoadSnapService.snapSingleLivePoint(rawInitialPos).then((snappedPos) {
      if (mounted && !_isDisposed && _carAnimator != null) {
        _carAnimator!.teleportTo(snappedPos, initialBearing);
        _lastSnappedPos = snappedPos;
        
        // Re-align starting polyline point to snapped road coordinate
        if (_polylinePoints.isNotEmpty && _polylinePoints.first == rawInitialPos) {
          _polylinePoints[0] = snappedPos;
        }
        _updateMapMarkers();
      }
    });
  }

  /// Called every time DataController emits a new device position.
  ///
  /// Industry-standard GPS tracking approach:
  ///  1. Feed raw GPS through Kalman filter (smooths noise mathematically)
  ///  2. If speed < 3 km/h: freeze marker completely (no GPS wobble)
  ///  3. Snap the filtered position to the nearest road using OSRM snap service
  ///  4. If moved ≥ 8m: animate marker along the road route + add trail points
  ///  5. Trail = snapped road points per real GPS update (not per animation frame)
  Future<void> updateMarker(DeviceItem element) async {
    if (_isDisposed || _carAnimator == null) return;

    _currentUpdateId++;
    final myUpdateId = _currentUpdateId;

    final double? rawLat = double.tryParse(element.lat?.toString() ?? '');
    final double? rawLng = double.tryParse(element.lng?.toString() ?? '');
    if (rawLat == null || rawLng == null) return;

    final gpsSpeed = double.tryParse(element.speed?.toString() ?? '0') ?? 0.0;
    final gpsBearing = double.tryParse(element.course?.toString() ?? '0.0') ?? 0.0;
    _lastGpsSpeed = gpsSpeed;

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
    // Mathematically smooth GPS noise. Even when parked, the filter will
    // dampen random jumps and keep the position stable.
    final filteredPos = _kalman.process(rawLat, rawLng);

    // ── Step 2: Freeze when stationary ───────────────────────────────────
    // Speed < 3 km/h = parked/idling. GPS accuracy is ~10m so small readings
    // are just noise. Freeze the marker completely to avoid wobbling.
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
        _isProgrammaticMove = true;
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

    // ── Step 5: Dynamic Expected Interval ──────────────────────────────────
    // Calculate the duration since the last GPS update to match animation speed dynamically.
    int expectedIntervalMs = 8000;
    if (_lastUpdateTimestamp != 0) {
      expectedIntervalMs = nowMs - _lastUpdateTimestamp;
    }
    _lastUpdateTimestamp = nowMs;
    // Clamp between 3s and 15s to keep animations smooth even with packet jitter.
    expectedIntervalMs = expectedIntervalMs.clamp(3000, 15000);

    // ── Step 6: Commit previous traveled path to history ──────────────────
    if (_carAnimator != null) {
      final traveled = _carAnimator!.getTraveledPath();
      if (traveled.isNotEmpty) {
        // Skip first point to avoid duplicate with the end of _polylinePoints
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
        size: 38,
        statusColor: statusColor,
        iconType: iconType,
        deviceName: element.name,
        deviceId: element.id,
      );
      if (!_isDisposed && icon != _markerIcon) {
        _markerIcon = icon;
        _isMarkerReady = true;
        _updateMapMarkers();
      }
    } catch (e) {
      debugPrint('Error updating marker icon: $e');
    }
  }

  /// History trail loading is disabled.
  /// Trail is built cleanly from real GPS updates in updateMarker() only.
  /// This prevents the spider-web of lines caused by history GPS points
  /// being connected with straight lines across water/buildings.
  Future<void> _loadTodayTrail() async {
    // No-op: trail builds live from GPS updates when speed > 3 km/h.
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
    }, onError: (e) {
      debugPrint("Map style error: $e");
      return null;
    });
  }

  Future<void> _loadMarkerIcon() async {
    if (device?.icon?.path == null) {
      _markerIcon = BitmapDescriptor.defaultMarker;
      _isMarkerReady = true;
      return;
    }
    final statusColor = Util.getDeviceStatusColorStr(device!);
    final iconType = device!.icon?.type ?? device!.iconType;

    // Cache current properties to prevent redundant reloads
    _lastIconPath = device!.icon!.path;
    _lastStatusColor = statusColor;
    _lastIconType = iconType;
    _lastDeviceName = device!.name;
    _lastDeviceId = device!.id;

    try {
      _markerIcon = await Util.getMarkerIcon(
        device!.icon!.path!,
        size: 38,
        statusColor: statusColor,
        iconType: iconType,
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


  // Throttle: max 30fps for marker updates (33ms between frames)
  int _lastMarkerUpdateMs = 0;


  void _onCarPositionUpdate(LatLng position, double bearing) {
    if (_isDisposed) return;

    // ── Marker & Polyline: throttle to 30fps ──────────────────────────────
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMarkerUpdateMs >= 33) {
      _lastMarkerUpdateMs = now;
      _updateMarkerPosition();
      _updatePolyline(); // Rebuild polyline at 30fps to keep tip snapped to car!
    }

    // ── Camera follow ────────────────────────────────────────────────────
    if (_followVehicle &&
        _isMapCreated &&
        _mapController != null &&
        !_isProgrammaticMove &&
        !_userInteracting) {
      _isProgrammaticMove = true;
      _mapController!.moveCamera(CameraUpdate.newLatLng(position));
    }
  }

  /// Cheap: only updates marker position/rotation. Called at 30fps.
  void _updateMarkerPosition() {
    if (_isDisposed || !_isMarkerReady || _carAnimator == null) return;
    
    final markers = <Marker>{};
    markers.add(Marker(
      markerId: const MarkerId('vehicle'),
      position: _carAnimator!.currentPosition,
      rotation: _carAnimator!.currentBearing,
      icon: _markerIcon ?? BitmapDescriptor.defaultMarker,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      zIndex: 10.0,
    ));

    if (_showingUserDistance && _userLocationForDistance != null) {
      markers.add(Marker(
        markerId: const MarkerId('user_location'),
        position: _userLocationForDistance!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        zIndex: 15.0,
      ));
    }
    
    _markersNotifier.value = markers;
  }

  /// Updates the polyline to show completed trail + dynamic portion traveled in the current step.
  void _updatePolyline() {
    if (_isDisposed || _polylinePoints.isEmpty) return;
    // Append the current step's traveled path to history so trail tip matches car
    final pts = List<LatLng>.from(_polylinePoints);
    if (_carAnimator != null) {
      final traveled = _carAnimator!.getTraveledPath();
      if (traveled.isNotEmpty) {
        pts.addAll(traveled.sublist(1));
      }
    }
    
    final polylines = <Polyline>{};
    polylines.add(Polyline(
      polylineId: const PolylineId('trail'),
      points: pts,
      color: _primaryBlue.withValues(alpha: 0.85),
      width: 3, // Sleeker line width for a more premium look
      geodesic: true,
      jointType: JointType.round,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      zIndex: 1,
    ));

    if (_showingUserDistance && _distanceRoutePoints.isNotEmpty) {
      polylines.add(Polyline(
        polylineId: const PolylineId('user_distance_route'),
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

  /// Called from icon update / init — rebuilds both marker and polyline.
  void _updateMapMarkers() {
    _updateMarkerPosition();
    _updatePolyline();
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
      case 'grey':
        return DeviceStatus.offline;
      case 'expired':
        return DeviceStatus.expired;
      default:
        return DeviceStatus.offline;
    }
  }

  Color _getStatusColor() {
    switch (_getDeviceStatus(device)) {
      case DeviceStatus.running:
        return const Color(0xFF22C55E);   // 🟢 Moving
      case DeviceStatus.idle:
        return const Color(0xFFFFD600);   // 🟡 Idle
      case DeviceStatus.stop:
        return const Color(0xFFEF4444);   // 🔴 Stopped
      case DeviceStatus.offline:
        return const Color(0xFFEF4444);   // 🔴 Offline (red — no signal)
      case DeviceStatus.expired:
        return const Color(0xFF94A3B8);   // ⬜ Expired (silver/light gray)
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

      // Update icon based on raw value — store name (string) not codePoint
      String iconName = 'battery_full';
      if (isVoltage) {
        iconName = 'battery_charging_full_outlined';
      } else {
        final pct = double.tryParse(rawVal?.toString() ?? '') ?? 100.0;
        if (pct <= 10) {
          iconName = 'battery_0_bar';
        } else if (pct <= 25) {
          iconName = 'battery_1_bar';
        } else if (pct <= 40) {
          iconName = 'battery_2_bar';
        } else if (pct <= 55) {
          iconName = 'battery_3_bar';
        } else if (pct <= 70) {
          iconName = 'battery_4_bar';
        } else if (pct <= 85) {
          iconName = 'battery_5_bar';
        } else {
          iconName = 'battery_full';
        }
      }
      _lastBatteryIconCache[devId] = _iconFromName(iconName);
      if (UserRepository.prefs != null) {
        UserRepository.prefs!.setString('battery_icon_$devId', iconName);
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

  /// Maps a stored icon name string to a constant [IconData].
  /// Avoids dynamic [IconData] construction which breaks tree-shaking.
  IconData _iconFromName(String name) {
    switch (name) {
      case 'battery_charging_full_outlined':
        return Icons.battery_charging_full_outlined;
      case 'battery_0_bar':
        return Icons.battery_0_bar;
      case 'battery_1_bar':
        return Icons.battery_1_bar;
      case 'battery_2_bar':
        return Icons.battery_2_bar;
      case 'battery_3_bar':
        return Icons.battery_3_bar;
      case 'battery_4_bar':
        return Icons.battery_4_bar;
      case 'battery_5_bar':
        return Icons.battery_5_bar;
      case 'battery_full':
      default:
        return Icons.battery_full;
    }
  }

  IconData _getBatteryIcon() {
    final devId = widget.id;
    if (devId != null && _lastBatteryIconCache.containsKey(devId)) {
      return _lastBatteryIconCache[devId]!;
    }
    if (devId != null && UserRepository.prefs != null) {
      final savedName = UserRepository.prefs!.getString('battery_icon_$devId');
      if (savedName != null) {
        final ic = _iconFromName(savedName);
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

  Future<void> _showDistanceToVehicle() async {
    if (_carAnimator == null) return;
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          Get.snackbar('Permission Denied', 'Location permission is required to calculate distance.',
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

      _updateMapMarkers();

      // Zoom out to show both points on the map
      double minLat = math.min(userLatLng.latitude, vehicleLatLng.latitude);
      double maxLat = math.max(userLatLng.latitude, vehicleLatLng.latitude);
      double minLng = math.min(userLatLng.longitude, vehicleLatLng.longitude);
      double maxLng = math.max(userLatLng.longitude, vehicleLatLng.longitude);

      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      _isProgrammaticMove = true;
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
                  const Icon(Icons.people_alt, color: _primaryBlue, size: 24),
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
                      color: _primaryBlue,
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
        _updateMapMarkers();
        _centerOnVehicle();
      });
    } catch (e) {
      Get.snackbar('Error', 'Could not get distance: $e',
          backgroundColor: Colors.red.withValues(alpha: 0.9),
          colorText: Colors.white);
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
                initialCameraPosition:
                    CameraPosition(target: _getInitialPosition(), zoom: _currentZoom),
                onCameraMove: (pos) {
                  _currentZoom = pos.zoom;
                  if (_isProgrammaticMove) {
                    _isProgrammaticMove = false;
                  }
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
                scrollGesturesEnabled: true,
                zoomGesturesEnabled: true,
                mapToolbarEnabled: false,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
              ),
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
                  color: Color(0xFF111827),
                  height: 1),
            ),
            const Text('Kmh',
                style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF1F2937),
                    fontWeight: FontWeight.w700)),
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
          _buildMapBtn(Icons.lock, Colors.white, _openLock,
              bgColor: const Color(0xFF22C55E)),
          const SizedBox(height: 8),
          _buildMapBtn(Icons.play_circle_fill, Colors.white, _openPlayback,
              bgColor: const Color(0xFF3B82F6)),
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

          _buildMapBtn(Icons.people_alt_outlined, _darkColor, _showDistanceToVehicle),
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
      initialChildSize: 0.37, // Increased height to prevent bottom details from clipping
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
              SizedBox(height: MediaQuery.of(context).padding.bottom + 24), // Dynamic bottom screen safety spacing
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
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w600)),
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
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF111827)),
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
                  fontSize: 16,
                  color: Color(0xFF030712),
                  fontWeight: FontWeight.w800)),
          Text(imei,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w600)),
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
      if (color == const Color(0xFF22C55E) || color == Colors.green || color == const Color(0xFF10B981)) {
        return const Color(0xFF15803D); // dark green
      } else if (color == const Color(0xFFFFD600) || color == Colors.amber || color == const Color(0xFFEAB308) || color == const Color(0xFFFEF08A)) {
        return const Color(0xFFA16207); // dark yellow/gold
      } else if (color == const Color(0xFFEF4444) || color == Colors.red || color == const Color(0xFFDC2626)) {
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
              color: bgColor.withValues(alpha: 1.0),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28), // darker shadow
                blurRadius: 3.5, // tight blur, won't spread too much
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Status Card
          buildCardItem(
            label: _getStatusText(),
            bgColor: statusBgColor,
            content: Text(
              status == DeviceStatus.running
                  ? '${double.tryParse(device?.speed?.toString() ?? '0')?.toInt() ?? 0} km/h'
                  : stopDuration,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: getDarkerContrastColor(_getStatusColor()),
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
            label: _getBatteryLabel(),
            bgColor: batteryBgColor,
            content: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getBatteryIcon(),
                  size: 13,
                  color: getDarkerContrastColor(_getBatteryColor()),
                ),
                const SizedBox(width: 2),
                Text(
                  _getBatteryText(),
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: getDarkerContrastColor(_getBatteryColor()),
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
            Text(
                todaytotalDistance.toLowerCase().contains('km')
                    ? todaytotalDistance
                    : '${todaytotalDistance} Km',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937))),
            Text('Today Mileage',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${totalMileage}Km',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937))),
            Text('Total Mileage',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
          ]),
        ],
      ),
    );
  }
}
