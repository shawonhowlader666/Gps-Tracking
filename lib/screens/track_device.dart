import 'dart:async';
import 'dart:developer';
import 'dart:math' as m;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/screens/lock_unlock_screen.dart';
import 'package:gpspro/screens/playback.dart';
import 'package:gpspro/screens/report/get_today_report.dart';
import 'package:gpspro/screens/street_view_screen.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/util/util.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'common_method.dart';

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
  // MAP CONTROLLER
  GoogleMapController? _mapController;
  bool _isMapCreated = false;

  // TRACKING VARIABLES
  final List<Marker> _markers = <Marker>[];
  bool isLoading = false;
  MapType _currentMapType = MapType.normal;
  double currentZoom = 16.0;
  bool _trafficEnabled = false;

  bool first = true;
  LatLng? oldPin;
  String? _mapStyle;

  final _mapMarkerSC = StreamController<List<Marker>>.broadcast();

  StreamSink<List<Marker>> get _mapMarkerSink => _mapMarkerSC.sink;

  Stream<List<Marker>> get mapMarkerStream => _mapMarkerSC.stream;

  DeviceItem? device;
  Timer? _todayKmTimer;
  Timer? _todayDetailsTimer;
  List<LatLng> polylineCoordinates = [];
  Map<PolylineId, Polyline> polylines = {};
  TodayReportData? todayData;
  List<LatLng> newPolylinesData = [];

  bool _isDisposed = false;
  String todaytotalDistance = "loading".tr;
  String todayEngineHours = "--";
  String? fuelConsumption;
  String? _address;

  // SMOOTH ANIMATION VARIABLES
  AnimationController? _carAnimationController;
  LatLng? _currentCarPosition;
  double _currentCarBearing = 0.0;
  bool _isAnimatingCar = false;

  // Pending position queue for smooth animation
  LatLng? _pendingPosition;
  double? _pendingBearing;
  BitmapDescriptor? _cachedMarkerIcon;

  // Blinking/Pulse Animation
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;
  Set<Circle> _pulseCircles = {};

  // Debounce control
  DateTime? _lastUpdateTime;
  static const int _minUpdateIntervalMs = 800;

  // Animation frame counter for camera updates
  int _animationFrameCount = 0;
  static const int _cameraUpdateInterval = 5;

  // Colors
  static const _successColor = Color(0xFF22C55E);
  static const _warningColor = Color(0xFFF59E0B);
  static const _dangerColor = Color(0xFFEF4444);
  static const _primaryColor = Color(0xFF2563EB);
  static const _neutralColor = Color(0xFF64748B);

  // SAFE MAP CONTROLLER ACCESS
  Future<void> _safeAnimateCamera(CameraUpdate cameraUpdate) async {
    if (!mounted || _isDisposed || _mapController == null || !_isMapCreated) {
      return;
    }
    try {
      await _mapController!.animateCamera(cameraUpdate);
    } catch (e) {
      debugPrint('Error animating camera: $e');
    }
  }

  Future<void> _safeMoveCamera(CameraUpdate cameraUpdate) async {
    if (!mounted || _isDisposed || _mapController == null || !_isMapCreated) {
      return;
    }
    try {
      await _mapController!.moveCamera(cameraUpdate);
    } catch (e) {
      debugPrint('Error moving camera: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    device = widget.device;

    // Initialize pulse animation controller
    _initPulseAnimation();

    rootBundle.loadString('assets/map_style.txt').then((string) {
      _mapStyle = string;
    }).catchError((error) {
      debugPrint('Error loading map style: $error');
    });

    _initTrackingData();
  }

  void _initPulseAnimation() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInOut),
    );

    _pulseController!.repeat(reverse: true);

    _pulseAnimation!.addListener(() {
      if (mounted && !_isDisposed && _currentCarPosition != null) {
        _updatePulseCircles();
      }
    });
  }

  void _updatePulseCircles() {
    if (_currentCarPosition == null) return;

    final statusColor = _getStatusColor();
    final pulseValue = _pulseAnimation?.value ?? 0.5;

    // Create blinking circles
    _pulseCircles = {
      // Outer blinking circle
      Circle(
        circleId: const CircleId('pulse_outer'),
        center: _currentCarPosition!,
        radius: 25 + (pulseValue * 25),
        // 25-50 meters
        fillColor: statusColor.withValues(alpha: 0.08 + (pulseValue * 0.12)),
        strokeColor: statusColor.withValues(alpha: 0.2 + (pulseValue * 0.3)),
        strokeWidth: 2,
      ),
      // Middle blinking circle
      Circle(
        circleId: const CircleId('pulse_middle'),
        center: _currentCarPosition!,
        radius: 15 + (pulseValue * 10),
        // 15-25 meters
        fillColor: statusColor.withValues(alpha: 0.12 + (pulseValue * 0.1)),
        strokeColor: statusColor.withValues(alpha: 0.3 + (pulseValue * 0.2)),
        strokeWidth: 2,
      ),
      // Inner solid circle
      Circle(
        circleId: const CircleId('pulse_inner'),
        center: _currentCarPosition!,
        radius: 10,
        fillColor: statusColor.withValues(alpha: 0.2),
        strokeColor: statusColor.withValues(alpha: 0.5),
        strokeWidth: 2,
      ),
    };

    if (mounted) setState(() {});
  }

  void _initTrackingData() {
    drawPolyline();
    drawPolyline2();

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_isDisposed) {
        getTodayKm();
        getTodayDetails();
      }
    });
  }

  void getTodayKm() {
    if (!mounted || _isDisposed) return;

    _todayKmTimer?.cancel();

    final current = DateTime.now();
    final month = current.month.toString().padLeft(2, '0');
    final day = current.day.toString().padLeft(2, '0');

    final start = DateTime.parse("${current.year}-$month-$day 00:00:00");
    final end = DateTime.parse("${current.year}-$month-$day 23:59:59");

    final fromDate = formatDateReport(start.toString());
    final toDate = formatDateReport(end.toString());
    final fromTime = formatTimeReport(start.toString());
    final toTime = formatTimeReport(end.toString());

    APIService.getHistory(
      widget.device!.id.toString(),
      fromDate,
      fromTime,
      toDate,
      toTime,
    ).then((value) {
      if (value != null && mounted && !_isDisposed) {
        setState(() {
          todaytotalDistance = value.distance_sum ?? "0";
          fuelConsumption = value.fuel_consumption ?? '0';
        });
      }
    }).catchError((error) {
      log("Error fetching today's km: $error");
    }).whenComplete(() {
      if (mounted && !_isDisposed) {
        _todayKmTimer = Timer(const Duration(seconds: 10), getTodayKm);
      }
    });
  }

  void getTodayDetails() async {
    if (!mounted || _isDisposed) return;

    _todayDetailsTimer?.cancel();

    try {
      final value = await ReportService.getTodayReportData(
        deviceId: widget.device?.id ?? 0,
      );

      if (mounted && !_isDisposed) {
        setState(() {
          todayData = value;
          if (value?.engineHours != null && value!.engineHours!.isNotEmpty) {
            todayEngineHours = value.engineHours!;
          }
        });
      }
    } catch (error) {
      log("Error fetching today's data: $error");
    } finally {
      if (mounted && !_isDisposed) {
        _todayDetailsTimer =
            Timer(const Duration(seconds: 10), getTodayDetails);
      }
    }
  }

  void _fetchAddress() {
    if (device == null || device!.lat == null || _address != null) return;

    APIService.getGeocoderAddress(
      device!.lat.toString(),
      device!.lng.toString(),
    ).then((addr) {
      if (!_isDisposed && mounted) {
        setState(() => _address = addr.replaceAll('"', ''));
      }
    });
  }

  void drawPolyline2() {
    if (!mounted || _isDisposed) return;
    PolylineId id = const PolylineId("polyAnim");
    Polyline polyline = Polyline(
      width: 4,
      polylineId: id,
      color: Colors.blueAccent.withValues(alpha: 0.7),
      points: List.from(newPolylinesData),
      geodesic: true,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    );
    polylines[id] = polyline;
  }

  void drawPolyline() {
    if (!mounted || _isDisposed) return;
    PolylineId id = const PolylineId("poly");
    Polyline polyline = Polyline(
      width: 4,
      polylineId: id,
      color: _primaryColor,
      points: List.from(polylineCoordinates),
      geodesic: true,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    );
    polylines[id] = polyline;
  }

  void updateMarker(DeviceItem element) async {
    if (!mounted || _isDisposed) return;

    final now = DateTime.now();
    if (_lastUpdateTime != null &&
        now.difference(_lastUpdateTime!).inMilliseconds <
            _minUpdateIntervalMs) {
      return;
    }
    _lastUpdateTime = now;

    try {
      if (_cachedMarkerIcon == null) {
        await Util.fetchAndCacheImages(
          "${UserRepository.getServerUrl()!}/${element.icon!.path!}",
        );
        _cachedMarkerIcon = await Util.getMarkerIcon(element.icon!.path!);
      }

      if (!mounted || _isDisposed) return;

      bool rotation =
          element.iconType == "arrow" || element.iconType == "rotating";

      var newPosition = LatLng(
        double.parse(element.lat.toString()),
        double.parse(element.lng.toString()),
      );

      double targetBearing =
          rotation ? double.parse(element.course.toString()) : 0;

      if (first) {
        await _initializeFirstMarker(newPosition, targetBearing);
      } else if (_currentCarPosition != null) {
        double distance = _calculateDistance(_currentCarPosition!, newPosition);

        if (distance > 2) {
          if (_isAnimatingCar) {
            _pendingPosition = newPosition;
            _pendingBearing = targetBearing;
          } else {
            _startSmoothAnimation(
              _currentCarPosition!,
              newPosition,
              targetBearing,
              _cachedMarkerIcon!,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error updating marker: $e');
    }
  }

  Future<void> _initializeFirstMarker(LatLng position, double bearing) async {
    _currentCarPosition = position;
    _currentCarBearing = bearing;

    CameraPosition cPosition = CameraPosition(
      target: position,
      zoom: currentZoom,
    );

    final pickupMarker = Marker(
      markerId: const MarkerId("driverMarker"),
      position: position,
      rotation: _currentCarBearing,
      icon: _cachedMarkerIcon!,
      anchor: const Offset(0.5, 0.5),
      flat: true,
    );

    _markers.clear();
    _markers.add(pickupMarker);

    if (!_mapMarkerSC.isClosed) {
      _mapMarkerSink.add(_markers);
    }

    // Initialize pulse circles
    _updatePulseCircles();

    oldPin = position;

    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted && !_isDisposed) {
      await _safeMoveCamera(CameraUpdate.newCameraPosition(cPosition));
    }

    isLoading = false;
    first = false;
    if (mounted) setState(() {});
  }

  void _startSmoothAnimation(
    LatLng fromPosition,
    LatLng toPosition,
    double targetBearing,
    BitmapDescriptor markerIcon,
  ) {
    if (!mounted || _isDisposed || _mapMarkerSC.isClosed) return;

    _isAnimatingCar = true;
    _animationFrameCount = 0;

    double distance = _calculateDistance(fromPosition, toPosition);
    int durationMs = _calculateAnimationDuration(distance);

    _carAnimationController?.dispose();

    _carAnimationController = AnimationController(
      duration: Duration(milliseconds: durationMs),
      vsync: this,
    );

    double fromBearing = _normalizeBearing(_currentCarBearing);
    double toBearing = _normalizeBearing(targetBearing);

    double bearingDiff = toBearing - fromBearing;
    if (bearingDiff > 180) {
      bearingDiff -= 360;
    } else if (bearingDiff < -180) {
      bearingDiff += 360;
    }
    toBearing = fromBearing + bearingDiff;

    final Animation<double> animation = CurvedAnimation(
      parent: _carAnimationController!,
      curve: Curves.easeInOutCubic,
    );

    animation.addListener(() {
      if (!mounted || _isDisposed || _mapMarkerSC.isClosed) {
        _carAnimationController?.stop();
        _isAnimatingCar = false;
        return;
      }

      final double t = animation.value;
      _animationFrameCount++;

      double lat = _lerp(fromPosition.latitude, toPosition.latitude, t);
      double lng = _lerp(fromPosition.longitude, toPosition.longitude, t);
      LatLng interpolatedPosition = LatLng(lat, lng);

      double interpolatedBearing = _lerp(fromBearing, toBearing, t);
      interpolatedBearing = _normalizeBearing(interpolatedBearing);

      _currentCarPosition = interpolatedPosition;
      _currentCarBearing = interpolatedBearing;

      final carMarker = Marker(
        markerId: const MarkerId("driverMarker"),
        position: interpolatedPosition,
        icon: markerIcon,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        rotation: interpolatedBearing,
      );

      _markers.clear();
      _markers.add(carMarker);

      if (!_mapMarkerSC.isClosed) {
        _mapMarkerSink.add(_markers);
      }

      if (newPolylinesData.isEmpty ||
          _calculateDistance(newPolylinesData.last, interpolatedPosition) >
              10) {
        newPolylinesData.add(interpolatedPosition);
      }

      if (_animationFrameCount % _cameraUpdateInterval == 0) {
        _updateCameraSmoothly(interpolatedPosition);
      }
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finishAnimation(toPosition);
      }
    });

    _carAnimationController?.forward();
  }

  void _updateCameraSmoothly(LatLng position) {
    if (!mounted || _isDisposed || !_isMapCreated) return;

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: position,
          zoom: currentZoom,
        ),
      ),
    );
  }

  int _calculateAnimationDuration(double distanceMeters) {
    int duration = 2000 + (distanceMeters / 10 * 100).toInt();
    return duration.clamp(2000, 5000);
  }

  void _finishAnimation(LatLng finalPosition) {
    _isAnimatingCar = false;

    oldPin = finalPosition;
    polylineCoordinates.add(finalPosition);

    if (newPolylinesData.isNotEmpty) {
      polylineCoordinates.addAll(newPolylinesData);
      newPolylinesData.clear();
    }

    if (polylineCoordinates.length > 150) {
      polylineCoordinates.removeRange(0, polylineCoordinates.length - 150);
    }

    drawPolyline();
    drawPolyline2();

    if (mounted && !_isDisposed) {
      setState(() {});
    }

    _carAnimationController?.dispose();
    _carAnimationController = null;

    if (_pendingPosition != null && _cachedMarkerIcon != null) {
      LatLng pending = _pendingPosition!;
      double bearing = _pendingBearing ?? 0;
      _pendingPosition = null;
      _pendingBearing = null;

      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_isDisposed && _currentCarPosition != null) {
          _startSmoothAnimation(
            _currentCarPosition!,
            pending,
            bearing,
            _cachedMarkerIcon!,
          );
        }
      });
    }
  }

  double _lerp(double a, double b, double t) {
    return a + (b - a) * t;
  }

  double _calculateDistance(LatLng from, LatLng to) {
    const double earthRadius = 6371000;

    double lat1 = from.latitude * m.pi / 180;
    double lat2 = to.latitude * m.pi / 180;
    double dLat = (to.latitude - from.latitude) * m.pi / 180;
    double dLon = (to.longitude - from.longitude) * m.pi / 180;

    double a = m.sin(dLat / 2) * m.sin(dLat / 2) +
        m.cos(lat1) * m.cos(lat2) * m.sin(dLon / 2) * m.sin(dLon / 2);
    double c = 2 * m.atan2(m.sqrt(a), m.sqrt(1 - a));

    return earthRadius * c;
  }

  double _normalizeBearing(double bearing) {
    bearing = bearing % 360;
    if (bearing < 0) bearing += 360;
    return bearing;
  }

  Color _getStatusColor() {
    if (device?.iconColor == "green") return _successColor;
    if (device?.iconColor == "yellow") return _warningColor;
    return _dangerColor;
  }

  String _getStatusText() {
    if (device?.iconColor == "green") return "Running";
    if (device?.iconColor == "yellow") return "Idle";
    return "Stopped";
  }

  IconData _getStatusIcon() {
    if (device?.iconColor == "green") return Icons.directions_car;
    if (device?.iconColor == "yellow") return Icons.pause_circle;
    return Icons.local_parking;
  }

  // ============ ACTION METHODS ============

  void _openReport() {
    if (device == null) return;

    DateTime current = DateTime.now();
    String month =
        current.month < 10 ? "0${current.month}" : current.month.toString();
    int dayCon = current.day + 1;
    String today = dayCon < 10 ? "0$dayCon" : dayCon.toString();
    var date = DateTime.parse("${current.year}-$month-$today 00:00:00");

    Navigator.pushNamed(
      context,
      "/reportList",
      arguments: ReportArguments(
        device!.id ?? 0,
        formatDateReport(DateTime.now().toString()),
        "00:00:00",
        formatDateReport(date.toString()),
        "00:00:00",
        device!.name ?? '',
        0,
        device!,
      ),
    );
  }

  void _openPlayback() {
    Get.to(() => PlaybackScreen(
          id: widget.id,
          name: widget.name,
          device: device,
        ));
  }

  void _callDevice() async {
    final simNumber = device?.deviceData?.simNumber;
    if (simNumber != null && simNumber.isNotEmpty) {
      await launchUrl(Uri(scheme: 'tel', path: simNumber));
    } else {
      Get.snackbar(
        'Error',
        'Phone number not found',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.9),
        colorText: Colors.white,
      );
    }
  }

  void _openLock() {
    if (device != null) {
      Get.to(() => LockUnlockScreen(device: device!));
    }
  }

  void _shareLocation() {
    if (device == null || device!.lat == null || device!.lng == null) return;

    final url =
        'https://www.google.com/maps/search/?api=1&query=${device!.lat},${device!.lng}';
    Share.share(
      'Vehicle: ${device!.name}\nLocation: $url',
      subject: 'Vehicle Location - ${device!.name}',
    );
  }

  void _navigate() {
    if (device == null || device!.lat == null || device!.lng == null) return;

    final url =
        'https://www.google.com/maps/dir/?api=1&destination=${device!.lat},${device!.lng}';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _openStreetView() {
    if (device != null && device!.lat != null && device!.lng != null) {
      Get.to(() => StreetViewScreen(
            latitude: device!.lat!,
            longitude: device!.lng!,
          ));
    }
  }

  void _centerOnVehicle() {
    if (_currentCarPosition != null) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _currentCarPosition!, zoom: 17),
        ),
      );
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _todayKmTimer?.cancel();
    _todayDetailsTimer?.cancel();
    _carAnimationController?.dispose();
    _pulseController?.dispose();

    if (!_mapMarkerSC.isClosed) {
      _mapMarkerSC.close();
    }

    _isMapCreated = false;
    _mapController = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
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

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black87),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        widget.name ?? 'Track Device',
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        // Blinking status indicator in app bar
        AnimatedBuilder(
          animation: _pulseAnimation!,
          builder: (context, child) {
            final color = _getStatusColor();
            return Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: color.withValues(
                      alpha: 0.2 + (_pulseAnimation!.value * 0.3)),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        color.withValues(alpha: 0.1 * _pulseAnimation!.value),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(
                              alpha: 0.3 + (_pulseAnimation!.value * 0.4)),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _getStatusText(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        !isLoading
            ? _buildMap()
            : const Center(child: CircularProgressIndicator()),
        _buildMapControls(),
        _buildSimpleBottomSheet(),
      ],
    );
  }

  Widget _buildMap() {
    return StreamBuilder<List<Marker>>(
      stream: mapMarkerStream,
      builder: (context, snapshot) {
        return GoogleMap(
          mapType: _currentMapType,
          trafficEnabled: _trafficEnabled,
          initialCameraPosition: CameraPosition(
            target: LatLng(
              double.parse(widget.device!.lat!.toString()),
              double.parse(widget.device!.lng!.toString()),
            ),
            zoom: 16,
          ),
          onCameraMove: (position) {
            currentZoom = position.zoom;
          },
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          mapToolbarEnabled: false,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          buildingsEnabled: true,
          onMapCreated: (GoogleMapController controller) {
            _mapController = controller;
            _isMapCreated = true;
            if (_mapStyle != null) {
              controller.setMapStyle(_mapStyle);
            }
          },
          markers: Set<Marker>.of(snapshot.data ?? _markers),
          circles: _pulseCircles,
          // Blinking circles
          polylines: Set<Polyline>.of(polylines.values),
          padding: const EdgeInsets.only(bottom: 200),
        );
      },
    );
  }

  Widget _buildMapControls() {
    return Positioned(
      top: 10,
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
            icon: Icons.add,
            onTap: () => _safeAnimateCamera(CameraUpdate.zoomIn()),
          ),
          const SizedBox(height: 4),
          _MapButton(
            icon: Icons.remove,
            onTap: () => _safeAnimateCamera(CameraUpdate.zoomOut()),
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: Icons.my_location,
            onTap: _centerOnVehicle,
          ),
        ],
      ),
    );
  }

  // ============ SIMPLE BOTTOM SHEET (No Tap Toggle) ============
  Widget _buildSimpleBottomSheet() {
    _fetchAddress();

    return DraggableScrollableSheet(
      initialChildSize: 0.30,
      minChildSize: 0.12,
      maxChildSize: 0.80,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
              // Simple Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Speed Section
              _buildSpeedSection(),
              const Divider(height: 1),

              // Sensors Section
              _buildSensorsSection(),

              // Info Section
              _buildInfoSection(),
              const Divider(height: 1),

              // Quick Action Buttons
              _buildQuickActions(),
              const Divider(height: 1),

              // Summary Section
              _buildSummarySection(),

              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSpeedSection() {
    final speed = device?.speed ?? 0;
    final color = _getStatusColor();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Left sensors
          Expanded(
            flex: 2,
            child: Column(
              children: [
                _MiniSensor(
                  icon: Icons.route,
                  label: 'Today KM',
                  value: todaytotalDistance,
                ),
                const SizedBox(height: 8),
                _MiniSensor(
                  icon: Icons.engineering,
                  label: 'Engine',
                  value: todayData?.engineHours ?? todayEngineHours,
                ),
              ],
            ),
          ),

          // Speedometer
          Expanded(
            flex: 3,
            child: _Speedometer(speed: speed, statusColor: color),
          ),

          // Right sensors
          Expanded(
            flex: 2,
            child: Column(
              children: [
                _MiniSensor(
                  icon: Icons.local_gas_station,
                  label: 'Fuel',
                  value: fuelConsumption ?? '--',
                ),
                const SizedBox(height: 8),
                _MiniSensor(
                  icon: Icons.speed,
                  label: 'Top Speed',
                  value: todayData?.topSpeed ?? '--',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ActionButton(
                icon: Icons.description,
                label: 'Report',
                color: Colors.indigo,
                onTap: _openReport,
              ),
              _ActionButton(
                icon: Icons.play_circle_fill,
                label: 'Playback',
                color: Colors.orange,
                onTap: _openPlayback,
              ),
              _ActionButton(
                icon: Icons.phone,
                label: 'Call',
                color: _successColor,
                onTap: _callDevice,
              ),
              _ActionButton(
                icon: Icons.lock,
                label: 'Lock',
                color: _dangerColor,
                onTap: _openLock,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ActionButton(
                icon: Icons.share,
                label: 'Share',
                color: Colors.teal,
                onTap: _shareLocation,
              ),
              _ActionButton(
                icon: Icons.navigation,
                label: 'Navigate',
                color: Colors.purple,
                onTap: _navigate,
              ),
              _ActionButton(
                icon: Icons.streetview,
                label: 'Street View',
                color: _primaryColor,
                onTap: _openStreetView,
              ),
              _ActionButton(
                icon: Icons.gps_fixed,
                label: 'Center',
                color: _neutralColor,
                onTap: _centerOnVehicle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSensorsSection() {
    final sensors = device?.sensors ?? [];
    if (sensors.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Sensors',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: sensors.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final s = sensors[i];
              return _SensorChip(
                name: s['name'] ?? '',
                value: s['value']?.toString() ?? '--',
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildInfoSection() {
    if (device == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Blinking status dot
              AnimatedBuilder(
                animation: _pulseAnimation!,
                builder: (context, child) {
                  final color = _getStatusColor();
                  return Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(
                              alpha: 0.3 + (_pulseAnimation!.value * 0.4)),
                          blurRadius: 4,
                          spreadRadius: 1 + (_pulseAnimation!.value * 2),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  device?.name ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getStatusText(),
                  style: TextStyle(
                    fontSize: 12,
                    color: _getStatusColor(),
                    fontWeight: FontWeight.w500,
                  ),
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
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
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
              const Spacer(),
              GestureDetector(
                onTap: () {
                  getTodayKm();
                  getTodayDetails();
                },
                child: Icon(Icons.refresh, size: 18, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.5,
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

// ==================== WIDGET COMPONENTS ====================

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  const _MapButton({
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? CustomColor.primaryColor : Colors.white,
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
            color: selected ? Colors.white : CustomColor.primaryColor,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Speedometer extends StatelessWidget {
  final int speed;
  final Color statusColor;

  const _Speedometer({required this.speed, required this.statusColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      width: 110,
      child: CustomPaint(
        painter: SpeedometerPainter(
          speed: speed.toDouble(),
          maxSpeed: 200,
          statusColor: statusColor,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 55),
              Text(
                '$speed',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
              Text(
                'km/h',
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
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
  final Color statusColor;

  SpeedometerPainter({
    required this.speed,
    required this.maxSpeed,
    required this.statusColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = m.min(size.width, size.height) / 2 - 10;

    // Background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      m.pi * 0.75,
      m.pi * 1.5,
      false,
      Paint()
        ..color = Colors.grey[200]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );

    // Speed arc
    final speedAngle = (speed / maxSpeed) * m.pi * 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      m.pi * 0.75,
      speedAngle.clamp(0, m.pi * 1.5),
      false,
      Paint()
        ..color = statusColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );

    // Tick marks
    for (int i = 0; i <= 10; i++) {
      final angle = m.pi * 0.75 + (i / 10) * m.pi * 1.5;
      final outerPoint = Offset(
        center.dx + (radius + 5) * m.cos(angle),
        center.dy + (radius + 5) * m.sin(angle),
      );
      final innerPoint = Offset(
        center.dx + (radius - 5) * m.cos(angle),
        center.dy + (radius - 5) * m.sin(angle),
      );
      canvas.drawLine(
        innerPoint,
        outerPoint,
        Paint()
          ..color = Colors.grey[400]!
          ..strokeWidth = 1,
      );
    }

    // Needle
    final needleAngle =
        m.pi * 0.75 + (speed / maxSpeed).clamp(0, 1) * m.pi * 1.5;
    final needleEnd = Offset(
      center.dx + (radius - 15) * m.cos(needleAngle),
      center.dy + (radius - 15) * m.sin(needleAngle),
    );
    canvas.drawLine(
      center,
      needleEnd,
      Paint()
        ..color = statusColor
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // Center circles
    canvas.drawCircle(center, 6, Paint()..color = statusColor);
    canvas.drawCircle(center, 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant SpeedometerPainter oldDelegate) {
    return oldDelegate.speed != speed || oldDelegate.statusColor != statusColor;
  }
}

class _MiniSensor extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MiniSensor({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

class _SensorChip extends StatelessWidget {
  final String name;
  final String value;

  const _SensorChip({required this.name, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CustomColor.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$name: $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: CustomColor.primaryColor,
        ),
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
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
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
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
