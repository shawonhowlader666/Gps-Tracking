import 'dart:async';
import 'dart:developer';
import 'dart:math' as m;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/screens/lock_unlock_screen.dart';
import 'package:gpspro/screens/playback.dart';
import 'package:gpspro/screens/report/get_today_report.dart';
import 'package:gpspro/screens/street_view_screen.dart';
import 'package:gpspro/services/admob_service.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/util/util.dart';
import 'package:intl/intl.dart';
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
  String? fuelConsumption;

  Color _mapTypeBackgroundColor = CustomColor.primaryColor;
  Color _mapTypeForegroundColor = CustomColor.secondaryColor;
  Color _trafficBackgroundButtonColor = CustomColor.secondaryColor;
  Color _trafficForegroundButtonColor = CustomColor.primaryColor;

  bool first = true;
  LatLng? oldPin;
  String? _mapStyle;

  final _mapMarkerSC = StreamController<List<Marker>>.broadcast();
  StreamSink<List<Marker>> get _mapMarkerSink => _mapMarkerSC.sink;
  Stream<List<Marker>> get mapMarkerStream => _mapMarkerSC.stream;

  DeviceItem? device;
  Timer? _todayKmTimer;
  Timer? _todayDetailsTimer;
  String address = "Show Address";
  List<LatLng> polylineCoordinates = [];
  Map<PolylineId, Polyline> polylines = {};
  TodayReportData? todayData;
  List<LatLng> newPolylinesData = [];

  bool _isDisposed = false;
  String todaytotalDistance = "loading".tr;
  String todayEngineHours = "--";
  bool showAddress = false;

  // SMOOTH ANIMATION VARIABLES
  AnimationController? _carAnimationController;
  LatLng? _currentCarPosition;
  double _currentCarBearing = 0.0;
  bool _isAnimatingCar = false;

  // Pending position queue for smooth animation
  LatLng? _pendingPosition;
  double? _pendingBearing;
  BitmapDescriptor? _cachedMarkerIcon;

  // Debounce control
  DateTime? _lastUpdateTime;
  static const int _minUpdateIntervalMs = 800;

  // Animation frame counter for camera updates
  int _animationFrameCount = 0;
  static const int _cameraUpdateInterval = 5; // Update camera every N frames

  // Draggable sheet controller
  final DraggableScrollableController _trackingSheetController =
  DraggableScrollableController();

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

    rootBundle.loadString('assets/map_style.txt').then((string) {
      _mapStyle = string;
    }).catchError((error) {
      debugPrint('Error loading map style: $error');
    });

    _initTrackingData();
  }

  void _initTrackingData() {
    drawPolyline();
    drawPolyline2();

    // Start data fetching with initial call
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
      log("Fetching today details for device: ${widget.device?.id}");

      final value = await ReportService.getTodayReportData(
        deviceId: widget.device?.id ?? 0,
      );

      if (mounted && !_isDisposed) {
        log("Today data received: $value");
        log("Engine Hours: ${value?.engineHours}");
        log("Move Duration: ${value?.moveDuration}");
        log("Stop Duration: ${value?.stopDuration}");
        log("Top Speed: ${value?.topSpeed}");

        setState(() {
          todayData = value;
          // Also store engine hours separately for reliability
          if (value?.engineHours != null && value!.engineHours!.isNotEmpty) {
            todayEngineHours = value.engineHours!;
          }
        });
      }
    } catch (error) {
      log("Error fetching today's data: $error");
    } finally {
      if (mounted && !_isDisposed) {
        _todayDetailsTimer = Timer(const Duration(seconds: 10), getTodayDetails);
      }
    }
  }

  void drawPolyline2() {
    if (!mounted || _isDisposed) return;
    PolylineId id = const PolylineId("polyAnim");
    Polyline polyline = Polyline(
      width: 4,
      polylineId: id,
      color: Colors.blueAccent.withOpacity(0.7),
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
      color: Colors.blue,
      points: List.from(polylineCoordinates),
      geodesic: true,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    );
    polylines[id] = polyline;
  }

  void updateMarker(DeviceItem element) async {
    if (!mounted || _isDisposed) return;

    // Debounce updates - minimum interval between updates
    final now = DateTime.now();
    if (_lastUpdateTime != null &&
        now.difference(_lastUpdateTime!).inMilliseconds < _minUpdateIntervalMs) {
      return;
    }
    _lastUpdateTime = now;

    try {
      // Cache the marker icon (only load once)
      if (_cachedMarkerIcon == null) {
        await Util.fetchAndCacheImages(
          "${UserRepository.getServerUrl()!}/${element.icon!.path!}",
        );
        _cachedMarkerIcon = await Util.getMarkerIcon(element.icon!.path!);
      }

      if (!mounted || _isDisposed) return;

      bool rotation = element.iconType == "arrow" || element.iconType == "rotating";

      var newPosition = LatLng(
        double.parse(element.lat.toString()),
        double.parse(element.lng.toString()),
      );

      double targetBearing = rotation ? double.parse(element.course.toString()) : 0;

      if (first) {
        await _initializeFirstMarker(newPosition, targetBearing);
      } else if (_currentCarPosition != null) {
        double distance = _calculateDistance(_currentCarPosition!, newPosition);

        // Only animate if moved more than 2 meters
        if (distance > 2) {
          if (_isAnimatingCar) {
            // Store pending position for next animation
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

    oldPin = position;

    // Wait for map to be ready
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

    // Calculate distance for duration
    double distance = _calculateDistance(fromPosition, toPosition);

    // Smooth duration: 2-5 seconds based on distance
    // Faster for short distances, slower for long distances
    int durationMs = _calculateAnimationDuration(distance);

    // Dispose previous controller
    _carAnimationController?.dispose();

    _carAnimationController = AnimationController(
      duration: Duration(milliseconds: durationMs),
      vsync: this,
    );

    // Handle bearing wrap-around (shortest rotation path)
    double fromBearing = _normalizeBearing(_currentCarBearing);
    double toBearing = _normalizeBearing(targetBearing);

    double bearingDiff = toBearing - fromBearing;
    if (bearingDiff > 180) {
      bearingDiff -= 360;
    } else if (bearingDiff < -180) {
      bearingDiff += 360;
    }
    toBearing = fromBearing + bearingDiff;

    // Use smooth easing curve
    final Animation<double> animation = CurvedAnimation(
      parent: _carAnimationController!,
      curve: Curves.easeInOutSine,
    );

    animation.addListener(() {
      if (!mounted || _isDisposed || _mapMarkerSC.isClosed) {
        _carAnimationController?.stop();
        _isAnimatingCar = false;
        return;
      }

      final double t = animation.value;
      _animationFrameCount++;

      // Smooth interpolation using easing
      double lat = _lerp(fromPosition.latitude, toPosition.latitude, t);
      double lng = _lerp(fromPosition.longitude, toPosition.longitude, t);
      LatLng interpolatedPosition = LatLng(lat, lng);

      double interpolatedBearing = _lerp(fromBearing, toBearing, t);
      interpolatedBearing = _normalizeBearing(interpolatedBearing);

      _currentCarPosition = interpolatedPosition;
      _currentCarBearing = interpolatedBearing;

      // Update marker without calling setState
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

      // Add to polyline sparingly (every 10 meters)
      if (newPolylinesData.isEmpty ||
          _calculateDistance(newPolylinesData.last, interpolatedPosition) > 10) {
        newPolylinesData.add(interpolatedPosition);
      }

      // Smooth camera follow - update less frequently to reduce jitter
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
    // Base duration of 2 seconds
    // Add 100ms per 10 meters of distance
    // Cap at 5 seconds
    int duration = 2000 + (distanceMeters / 10 * 100).toInt();
    return duration.clamp(2000, 5000);
  }

  void _finishAnimation(LatLng finalPosition) {
    _isAnimatingCar = false;

    // Update polylines
    oldPin = finalPosition;
    polylineCoordinates.add(finalPosition);

    if (newPolylinesData.isNotEmpty) {
      polylineCoordinates.addAll(newPolylinesData);
      newPolylinesData.clear();
    }

    // Keep polyline manageable
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

    // Process pending position if any
    if (_pendingPosition != null && _cachedMarkerIcon != null) {
      LatLng pending = _pendingPosition!;
      double bearing = _pendingBearing ?? 0;
      _pendingPosition = null;
      _pendingBearing = null;

      // Small delay before starting next animation
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
    const double earthRadius = 6371000; // meters

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

  @override
  void dispose() {
    _isDisposed = true;
    _todayKmTimer?.cancel();
    _todayDetailsTimer?.cancel();

    _carAnimationController?.dispose();

    if (!_mapMarkerSC.isClosed) {
      _mapMarkerSC.close();
    }

    _trackingSheetController.dispose();
    _isMapCreated = false;
    _mapController = null;

    super.dispose();
  }

  void _onMapTypeButtonPressed() {
    setState(() {
      _currentMapType =
      _currentMapType == MapType.normal ? MapType.hybrid : MapType.normal;
      _mapTypeBackgroundColor = _currentMapType == MapType.normal
          ? CustomColor.secondaryColor
          : CustomColor.primaryColor;
      _mapTypeForegroundColor = _currentMapType == MapType.normal
          ? CustomColor.primaryColor
          : CustomColor.secondaryColor;
    });
  }

  void _trafficEnabledPressed() {
    setState(() {
      _trafficEnabled = !_trafficEnabled;
      _trafficBackgroundButtonColor = !_trafficEnabled
          ? CustomColor.secondaryColor
          : CustomColor.primaryColor;
      _trafficForegroundButtonColor = !_trafficEnabled
          ? CustomColor.primaryColor
          : CustomColor.secondaryColor;
    });
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.dark,
    ));

    return SafeArea(
      child: Scaffold(
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
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      automaticallyImplyLeading: false,
      iconTheme: IconThemeData(color: CustomColor.cssBlack),
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: CustomColor.cssBlack),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        widget.name ?? 'trackDevice'.tr,
        style: FlutterFlowTheme.of(context).headlineMedium,
        overflow: TextOverflow.ellipsis,
      ),
      centerTitle: false,
      elevation: 0,
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        !isLoading
            ? _buildMap()
            : const Center(child: CircularProgressIndicator()),
        _buildMapControls(),
        _buildTrackingDraggableSheet(),
      ],
    );
  }

  Widget _buildMapControls() {
    return Positioned(
      top: 10,
      right: 5,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildControlButton(
            icon: Icons.map,
            backgroundColor: _mapTypeBackgroundColor,
            foregroundColor: _mapTypeForegroundColor,
            onPressed: _onMapTypeButtonPressed,
          ),
          const SizedBox(height: 8),
          _buildControlButton(
            icon: Icons.traffic,
            backgroundColor: _trafficBackgroundButtonColor,
            foregroundColor: _trafficForegroundButtonColor,
            onPressed: _trafficEnabledPressed,
          ),
          const SizedBox(height: 8),
          _buildControlButton(
            icon: Icons.add,
            backgroundColor: Colors.white,
            foregroundColor: CustomColor.primaryColor,
            onPressed: () => _safeAnimateCamera(CameraUpdate.zoomIn()),
          ),
          const SizedBox(height: 4),
          _buildControlButton(
            icon: Icons.remove,
            backgroundColor: Colors.white,
            foregroundColor: CustomColor.primaryColor,
            onPressed: () => _safeAnimateCamera(CameraUpdate.zoomOut()),
          ),
          const SizedBox(height: 8),
          _buildControlButton(
            icon: Icons.lock,
            backgroundColor: Colors.white,
            foregroundColor: CustomColor.primaryColor,
            onPressed: () {
              AdMobService().showInterstitialAd(ignoreFrequency: true);
              Get.to(() => LockUnlockScreen(device: device!));
            },
          ),
          const SizedBox(height: 4),
          _buildControlButton(
            icon: Icons.play_arrow_sharp,
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            onPressed: () {
              AdMobService().showInterstitialAd(ignoreFrequency: true);
              Get.to(() => PlaybackScreen(
                id: widget.id,
                name: widget.name,
                device: device,
              ));
            },
          ),
          const SizedBox(height: 4),
          _buildControlButton(
            icon: Icons.share_location_rounded,
            backgroundColor: Colors.white,
            foregroundColor: CustomColor.primaryColor,
            onPressed: () {
              Get.to(() => StreetViewScreen(
                latitude: device?.lat ?? 0.0,
                longitude: device?.lng ?? 0.0,
              ));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: backgroundColor,
        elevation: 2,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Icon(icon, color: foregroundColor, size: 22),
        ),
      ),
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
          indoorViewEnabled: false,
          liteModeEnabled: false,
          onMapCreated: (GoogleMapController controller) {
            _mapController = controller;
            _isMapCreated = true;

            if (_mapStyle != null) {
              controller.setMapStyle(_mapStyle);
            }
          },
          markers: Set<Marker>.of(snapshot.data ?? _markers),
          polylines: Set<Polyline>.of(polylines.values),
          padding: const EdgeInsets.only(bottom: 150),
        );
      },
    );
  }

  Widget _buildTrackingDraggableSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.28,
      minChildSize: 0.12,
      maxChildSize: 0.55,
      controller: _trackingSheetController,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 5),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              _buildSpeedometerSection(),
              const Divider(height: 1),
              _buildOtherSensorsSection(),
              _buildDeviceDetailsSection(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSpeedometerSection() {
    Color statusColor = _getStatusColor();
    int currentSpeed = device?.speed ?? 0;

    List<Map<String, dynamic>> importantSensors = _getImportantSensors();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              children: [
                if (importantSensors.isNotEmpty)
                  _buildMiniSensorCard(
                    importantSensors[0]['icon'],
                    importantSensors[0]['name'],
                    importantSensors[0]['value'],
                  ),
                const SizedBox(height: 8),
                if (importantSensors.length > 1)
                  _buildMiniSensorCard(
                    importantSensors[1]['icon'],
                    importantSensors[1]['name'],
                    importantSensors[1]['value'],
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: _buildAnalogSpeedometer(currentSpeed, statusColor),
          ),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                if (importantSensors.length > 2)
                  _buildMiniSensorCard(
                    importantSensors[2]['icon'],
                    importantSensors[2]['name'],
                    importantSensors[2]['value'],
                  ),
                const SizedBox(height: 8),
                if (importantSensors.length > 3)
                  _buildMiniSensorCard(
                    importantSensors[3]['icon'],
                    importantSensors[3]['name'],
                    importantSensors[3]['value'],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalogSpeedometer(int speed, Color statusColor) {
    return SizedBox(
      height: 120,
      width: 120,
      child: CustomPaint(
        painter: SpeedometerPainter(
          speed: speed.toDouble(),
          maxSpeed: 200,
          statusColor: statusColor,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const SizedBox(height: 15),
              Text(
                speed.toString(),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
              Text(
                'km/h',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniSensorCard(String icon, String name, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            icon,
            width: 20,
            height: 20,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.sensors, size: 20, color: Colors.grey[600]),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

  List<Map<String, dynamic>> _getImportantSensors() {
    List<Map<String, dynamic>> sensors = [];

    // Today KM
    sensors.add({
      'icon': 'assets/images/sensors/total-distance.png',
      'name': 'Today KM',
      'value': todaytotalDistance,
    });

    // Engine Hours - Use multiple fallbacks
    String engineHoursValue = '--';
    if (todayData?.engineHours != null && todayData!.engineHours!.isNotEmpty) {
      engineHoursValue = todayData!.engineHours!;
    } else if (todayEngineHours != '--') {
      engineHoursValue = todayEngineHours;
    }

    sensors.add({
      'icon': 'assets/images/sensors/engine_hours.png',
      'name': 'Engine',
      'value': engineHoursValue,
    });

    // Fuel
    sensors.add({
      'icon': 'assets/images/sensors/fuel_tank.png',
      'name': 'Fuel',
      'value': fuelConsumption ?? '--',
    });

    // Top Speed
    sensors.add({
      'icon': 'assets/images/sensors/speed.png',
      'name': 'Top Speed',
      'value': todayData?.topSpeed ?? '--',
    });

    return sensors;
  }

  Widget _buildOtherSensorsSection() {
    List<Widget> sensorWidgets = [];

    try {
      if (device?.sensors != null) {
        for (var sensor in device!.sensors!) {
          if (sensor['value'] != null) {
            sensorWidgets.add(_buildSensorChip(
              'assets/images/sensors/${sensor['type']}.png',
              sensor['name'] ?? '',
              gsmCodeConvert(sensor['value']),
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('Error building sensors: $e');
    }

    if (sensorWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 10, 15, 8),
          child: Text(
            'Sensors',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: sensorWidgets),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildSensorChip(String icon, String name, String value) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CustomColor.primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CustomColor.primaryColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            icon,
            width: 18,
            height: 18,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.sensors, size: 18, color: CustomColor.primaryColor),
          ),
          const SizedBox(width: 6),
          Text(
            '$name: $value',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: CustomColor.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceDetailsSection() {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Device Info',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _getStatusColor(),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                device?.name ?? '',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                _getStatusText(),
                style: TextStyle(
                  fontSize: 12,
                  color: _getStatusColor(),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FutureBuilder<String>(
            future: APIService.getGeocoderAddress(
              device?.lat?.toString() ?? "0",
              device?.lng?.toString() ?? "0",
            ),
            builder: (context, snapshot) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      snapshot.hasData
                          ? snapshot.data!.replaceAll('"', '')
                          : 'Loading address...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildQuickStat('Move', todayData?.moveDuration ?? '--',
                  Icons.directions_car),
              _buildQuickStat(
                  'Stop', todayData?.stopDuration ?? '--', Icons.local_parking),
              _buildQuickStat('Distance',
                  device?.totalDistance?.toString() ?? '--', Icons.route),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: CustomColor.primaryColor),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }

  Color _getStatusColor() {
    if (device?.iconColor == "green") return Colors.green;
    if (device?.iconColor == "yellow") return Colors.orange;
    return Colors.red;
  }

  String _getStatusText() {
    if (device?.iconColor == "green") return "Moving";
    if (device?.iconColor == "yellow") return "Idle";
    return "Stopped";
  }

  String gsmCodeConvert(value) {
    if (value == "71606") return "Movistar";
    if (value == "71610") return "Claro";
    if (value == "71617") return "Entel";
    if (value == "71615") return "Bitel";
    return value.toString();
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

    final bgPaint = Paint()
      ..color = Colors.grey[200]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      m.pi * 0.75,
      m.pi * 1.5,
      false,
      bgPaint,
    );

    final speedPaint = Paint()
      ..color = statusColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final speedAngle = (speed / maxSpeed) * m.pi * 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      m.pi * 0.75,
      speedAngle.clamp(0, m.pi * 1.5),
      false,
      speedPaint,
    );

    final tickPaint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 1;

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
      canvas.drawLine(innerPoint, outerPoint, tickPaint);
    }

    final needleAngle =
        m.pi * 0.75 + (speed / maxSpeed).clamp(0, 1) * m.pi * 1.5;
    final needlePaint = Paint()
      ..color = statusColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final needleEnd = Offset(
      center.dx + (radius - 15) * m.cos(needleAngle),
      center.dy + (radius - 15) * m.sin(needleAngle),
    );

    canvas.drawLine(center, needleEnd, needlePaint);

    canvas.drawCircle(center, 6, Paint()..color = statusColor);
    canvas.drawCircle(center, 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant SpeedometerPainter oldDelegate) {
    return oldDelegate.speed != speed || oldDelegate.statusColor != statusColor;
  }
}