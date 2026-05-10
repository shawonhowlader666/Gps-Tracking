import 'dart:async';
import 'dart:developer';
import 'dart:math' as m;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_lock/screens/device_details_screen.dart';
import 'package:smart_lock/screens/lock_unlock_screen.dart';
import 'package:smart_lock/screens/playback.dart';
import 'package:smart_lock/screens/report/get_today_report.dart';
import 'package:smart_lock/screens/report/recent_events.dart';
import 'package:smart_lock/screens/report/report_screen.dart';
import 'package:smart_lock/screens/street_view_screen.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/util/util.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common_method.dart';

enum DeviceStatus { running, idle, stop, offline }

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
    if (_targetPosition == null) { _stop(); return; }
    final now = DateTime.now().millisecondsSinceEpoch;
    final dt = ((now - _lastTickTime) / 1000.0).clamp(0.001, 0.1);
    _lastTickTime = now;

    final distance = _calculateDistance(_currentPosition, _targetPosition!);
    if (distance < 0.5) {
      _currentPosition = _targetPosition!;
      _currentBearing = _normalizeBearing(_targetBearing);
      onPositionUpdate(_currentPosition, _currentBearing);
      _targetPosition = null;
      _currentSpeed = 0;
      _stop();
      return;
    }

    double targetSpeed = distance < 10 ? _minSpeed
        : distance < 50 ? _minSpeed + (distance - 10) / 40 * (_maxSpeed - _minSpeed)
        : _maxSpeed;

    _currentSpeed = _currentSpeed < targetSpeed
        ? m.min(_currentSpeed + _acceleration * dt, targetSpeed)
        : m.max(_currentSpeed - _acceleration * dt, targetSpeed);

    final moveRatio = ((_currentSpeed * dt) / distance).clamp(0.0, 1.0);
    _currentPosition = LatLng(
      _currentPosition.latitude + (_targetPosition!.latitude - _currentPosition.latitude) * moveRatio,
      _currentPosition.longitude + (_targetPosition!.longitude - _currentPosition.longitude) * moveRatio,
    );
    _currentBearing = _interpolateBearing(_currentBearing, _targetBearing, _bearingSpeed * dt);
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

  void _stop() { _isRunning = false; _ticker?.stop(); }
  void dispose() { _ticker?.stop(); _ticker?.dispose(); }
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

class _TrackDeviceState extends State<TrackDevicePage> with TickerProviderStateMixin {
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

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  DeviceItem? device;
  String todaytotalDistance = "--";
  String todayEngineHours = "--";
  String? _address;
  TodayReportData? todayData;

  SmoothCarAnimator? _carAnimator;
  BitmapDescriptor? _markerIcon;
  bool _isMarkerReady = false;

  final List<LatLng> _polylinePoints = [];
  static const int _maxPolylinePoints = 100;
  LatLng? _lastPolylinePoint;

  Timer? _dataTimer;
  Timer? _cameraTimer;

  // Colors matching reference app
  static const _primaryRed = Color(0xFFCC0000);
  static const _successColor = Color(0xFF22C55E);
  static const _warningColor = Color(0xFFF59E0B);
  static const _dangerColor = Color(0xFFEF4444);
  static const _primaryBlue = Color(0xFF3B82F6);
  static const _neutralColor = Color(0xFF9CA3AF);
  static const _darkColor = Color(0xFF374151);

  @override
  void initState() {
    super.initState();
    device = widget.device;
    _loadMapStyle();
    _initializeAll();
  }

  Future<void> _initializeAll() async {
    final initialPos = _getInitialPosition();
    final initialBearing = double.tryParse(device?.course?.toString() ?? '0') ?? 0;
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
      return LatLng(double.parse(device!.lat.toString()), double.parse(device!.lng.toString()));
    }
    return const LatLng(0, 0);
  }

  void _loadMapStyle() {
    rootBundle.loadString('assets/map_style.txt').then((string) {
      _mapStyle = string;
      if (_isMapCreated && _mapController != null) _mapController!.setMapStyle(_mapStyle);
    }).catchError((e) => debugPrint("Map style error: $e"));
  }

  Future<void> _loadMarkerIcon() async {
    if (device?.icon?.path == null) {
      _markerIcon = BitmapDescriptor.defaultMarker;
      _isMarkerReady = true;
      return;
    }
    try {
      _markerIcon = await Util.getMarkerIcon(device!.icon!.path!);
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
    _cameraTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_followVehicle && _isMapCreated && _carAnimator != null &&
          !_userInteracting && !_isProgrammaticMove) {
        _isProgrammaticMove = true;
        _mapController?.animateCamera(CameraUpdate.newLatLng(_carAnimator!.currentPosition));
        Future.delayed(const Duration(milliseconds: 50), () => _isProgrammaticMove = false);
      }
    });
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
        final history = await APIService.getHistory(deviceId.toString(), fromDate, "00:00", toDate, "23:59");
        if (history != null && mounted && !_isDisposed) {
          setState(() => todaytotalDistance = history.distance_sum ?? "0");
        }
      } catch (e) { log("History error: $e"); }

      try {
        final report = await ReportService.getTodayReportData(deviceId: deviceId);
        if (mounted && !_isDisposed) {
          setState(() { todayData = report; todayEngineHours = report.engineHours ?? "--"; });
        }
      } catch (e) { log("Report error: $e"); }
    } catch (e) { log("Data fetch error: $e"); }
  }

  void updateMarker(DeviceItem element) {
    if (_isDisposed || !_isMarkerReady || _carAnimator == null) return;
    final newPos = LatLng(double.parse(element.lat.toString()), double.parse(element.lng.toString()));
    final rotation = element.iconType == "arrow" || element.iconType == "rotating";
    final newBearing = rotation ? double.parse(element.course.toString()) : 0.0;
    _carAnimator!.moveTo(newPos, newBearing);
  }

  void _onCarPositionUpdate(LatLng position, double bearing) {
    if (_isDisposed) return;
    if (_lastPolylinePoint == null || _calculateDistance(_lastPolylinePoint!, position) > 5) {
      _polylinePoints.add(position);
      _lastPolylinePoint = position;
      if (_polylinePoints.length > _maxPolylinePoints) _polylinePoints.removeAt(0);
    }
    _updateMapMarkers();
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
    final polyline = Polyline(
      polylineId: const PolylineId("trail"),
      points: List.from(_polylinePoints),
      color: _primaryBlue.withValues(alpha: 0.7),
      width: 3,
      geodesic: true,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    );
    if (mounted) setState(() { _markers = {marker}; _polylines = {polyline}; });
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
    if (!_isDeviceOnline(d)) return DeviceStatus.offline;
    final speed = double.tryParse(d.speed.toString()) ?? 0;
    if (speed > 0) return DeviceStatus.running;
    return _isEngineOn(d) ? DeviceStatus.idle : DeviceStatus.stop;
  }

  bool _isDeviceOnline(DeviceItem d) {
    final online = d.online?.toLowerCase().trim() ?? '';
    if (online.contains('offline')) return false;
    if (online.contains('online')) return true;
    final iconColor = d.iconColor?.toLowerCase() ?? '';
    if (iconColor == 'green' || iconColor == 'yellow') return true;
    final speed = double.tryParse(d.speed.toString()) ?? 0;
    return speed > 0;
  }

  bool _isEngineOn(DeviceItem d) {
    if (d.engineStatus != null) {
      final status = d.engineStatus;
      if (status is bool) return status;
      if (status is int) return status == 1;
      if (status is String) {
        final s = status.toLowerCase();
        if (['on', '1', 'true'].contains(s)) return true;
      }
    }
    final speed = double.tryParse(d.speed.toString()) ?? 0;
    if (speed > 0) return true;
    return d.iconColor?.toLowerCase() == 'yellow';
  }

  Color _getStatusColor() {
    switch (_getDeviceStatus(device)) {
      case DeviceStatus.running: return _successColor;
      case DeviceStatus.idle: return _warningColor;
      case DeviceStatus.stop: return _dangerColor;
      case DeviceStatus.offline: return _neutralColor;
    }
  }

  String _getStatusText() {
    switch (_getDeviceStatus(device)) {
      case DeviceStatus.running: return "Moving";
      case DeviceStatus.idle: return "Idle";
      case DeviceStatus.stop: return "Stopped";
      case DeviceStatus.offline: return "Offline";
    }
  }

  void _fetchAddress() {
    if (device?.lat == null || _address != null) return;
    APIService.getGeocoderAddress(device!.lat.toString(), device!.lng.toString()).then((addr) {
      if (!_isDisposed && mounted) setState(() => _address = addr.replaceAll('"', ''));
    });
  }

  // ==================== ACTIONS ====================
  void _centerOnVehicle() {
    if (_carAnimator == null || _mapController == null) return;
    _isProgrammaticMove = true;
    setState(() => _followVehicle = true);
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(
        target: _carAnimator!.currentPosition,
        zoom: 17,
        bearing: _carAnimator!.currentBearing,
        tilt: 45,
      )),
    ).then((_) => Future.delayed(const Duration(milliseconds: 100), () => _isProgrammaticMove = false));
  }

  void _openPlayback() => Get.to(() => PlaybackScreen(id: widget.id, name: widget.name, device: device));
  void _openLock() { if (device != null) Get.to(() => LockUnlockScreen(device: device!)); }
  void _openDetails() { if (device != null) Get.to(() => DeviceDetailsScreen(device: device!)); }
  void _showReport(DeviceItem device) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ReportScreen(deviceId: device.id ?? 0, deviceName: device.name ?? '')),
    );
  }

  void _navigate() {
    if (device?.lat == null) return;
    final url = 'https://www.google.com/maps/dir/?api=1&destination=${device!.lat},${device!.lng}';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _openStreetView() {
    if (device?.lat != null) Get.to(() => StreetViewScreen(latitude: device!.lat!, longitude: device!.lng!));
  }

  void _callDevice() async {
    final sim = device?.deviceData?.simNumber;
    if (sim != null && sim.isNotEmpty) {
      await launchUrl(Uri(scheme: 'tel', path: sim));
    } else {
      Get.snackbar('Error', 'Phone number not found', backgroundColor: Colors.red.withValues(alpha: 0.9), colorText: Colors.white);
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
            if (element.id == widget.id) { device = element; updateMarker(element); }
          }
          return _buildBody();
        },
      ),
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
    return GoogleMap(
      mapType: _currentMapType,
      trafficEnabled: _trafficEnabled,
      initialCameraPosition: CameraPosition(target: _getInitialPosition(), zoom: 16),
      onCameraMove: (pos) => _currentZoom = pos.zoom,
      onCameraMoveStarted: () { if (!_isProgrammaticMove) _userInteracting = true; },
      onCameraIdle: () {
        if (_userInteracting && !_isProgrammaticMove && _followVehicle && _carAnimator != null) {
          _mapController?.getLatLng(ScreenCoordinate(
            x: (MediaQuery.of(context).size.width / 2).toInt(),
            y: (MediaQuery.of(context).size.height / 2).toInt(),
          )).then((centerLatLng) {
            if (mounted && _calculateDistance(_carAnimator!.currentPosition, centerLatLng) > 100) {
              setState(() => _followVehicle = false);
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
          controller.animateCamera(CameraUpdate.newCameraPosition(
            CameraPosition(target: _carAnimator!.currentPosition, zoom: 16),
          ));
        }
      },
      markers: _markers,
      polylines: _polylines,
      padding: const EdgeInsets.only(bottom: 260),
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      mapToolbarEnabled: false,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              speed.toInt().toString(),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF374151), height: 1),
            ),
            const Text('Kmh', style: TextStyle(fontSize: 10, color: Color(0xFF6B7280), fontWeight: FontWeight.w600)),
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
              if (device != null) {
                _showReport(device!);
              }
            },
          ),
          const SizedBox(height: 8),
          _buildMapBtn(Icons.directions_car, _darkColor, _openDetails),
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
          _buildMapBtn(Icons.map_outlined, _darkColor, () => setState(() {
            _currentMapType = _currentMapType == MapType.normal ? MapType.hybrid : MapType.normal;
          }), selected: _currentMapType == MapType.hybrid, selectedColor: _successColor),
          const SizedBox(height: 8),
          _buildMapBtn(
            _followVehicle ? Icons.gps_fixed : Icons.gps_not_fixed,
            _primaryBlue, _centerOnVehicle,
            selected: _followVehicle, selectedColor: _primaryBlue,
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
              _buildMapBtn(Icons.headset_mic, Colors.white, _callDevice, bgColor: _dangerColor),
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: _successColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
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
    final bg = bgColor ?? (selected ? (selectedColor ?? _primaryBlue) : Colors.white);
    final ic = bgColor != null ? Colors.white : (selected ? Colors.white : iconColor);
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
            boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 15, offset: Offset(0, -5))],
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
          decoration: BoxDecoration(color: const Color(0xFFD1D5DB), borderRadius: BorderRadius.circular(2)),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _buildActionBtn(Icons.play_circle_fill, 'Play Back', const Color(0xFF3B82F6), _openPlayback),
          _buildActionBtn(Icons.notifications_active, 'Alert', const Color(0xFFF59E0B), () {

            Get.to(() => EventsPage());
          }),
          _buildActionBtn(Icons.lock, 'Lock', const Color(0xFF22C55E), _openLock),
          _buildActionBtn(Icons.settings, 'Setting', const Color(0xFF0EA5E9), _openDetails),
        ],
      ),
    );
  }

  Widget _buildActionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 5),
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Text(
        _address ?? 'Loading address...',
        style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
      ),
    );
  }

  Widget _buildImeiRow() {
    final imei = device?.deviceData?.imei ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(imei, style: const TextStyle(fontSize: 12, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          Text(imei, style: const TextStyle(fontSize: 12, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    final status = _getDeviceStatus(device);
    final isEngineOn = device != null ? _isEngineOn(device!) : false;
    final stopDuration = device?.stopDuration ?? '--';
    String expiryStr = '--';
    try {
      final expiry = device?.deviceData?.expirationDate?.toString() ?? '';
      if (expiry.isNotEmpty) {
        final date = DateTime.tryParse(expiry);
        if (date != null) {
          expiryStr = '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
        }
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_getStatusText(), style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w500, letterSpacing: 0.3)),
            Text(
              status == DeviceStatus.running ? '${double.tryParse(device?.speed?.toString() ?? '0')?.toInt() ?? 0} km/h' : stopDuration,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _getStatusColor()),
            ),
          ]),
          Column(children: [
            Text('Acc', style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w500)),
            Text(isEngineOn ? 'On' : 'Off', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
          ]),
          Column(children: [
            Text('Battery', style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w500)),
            const Text('-', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Expired On', style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w500)),
            Text(expiryStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
          ]),
        ],
      ),
    );
  }

  Widget _buildMileageRow() {
    final totalMileage = device?.totalDistance?.toStringAsFixed(1) ?? '0';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${todaytotalDistance}Km', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
            Text('Today Mileage', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${totalMileage}Km', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
            Text('Total Mileage', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ]),
        ],
      ),
    );
  }

}