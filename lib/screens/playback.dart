// lib/screens/playback/playback_screen.dart

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/services/model/playback_route.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/util/util.dart';
import 'package:intl/intl.dart';

class PlaybackScreen extends StatefulWidget {
  final int? id;
  final String? name;
  final DeviceItem? device;
  final DateTime? initialFromDate;
  final DateTime? initialToDate;

  const PlaybackScreen({
    super.key,
    required this.id,
    required this.name,
    this.device,
    this.initialFromDate,
    this.initialToDate,
  });

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen>
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  bool _isMapCreated = false;
  bool _isDisposed = false;

  MapType _currentMapType = MapType.normal;
  double currentZoom = 14.0;
  String? _mapStyle;

  // PLAYBACK VARIABLES
  bool _isPlaybackLoading = false;
  List<PlayBackRoute> routeList = [];
  List<PlayBackRoute> bottomRouteList = [];
  List<LatLng> playbackRoutePoints = [];
  List<dynamic> eventsPoints = [];
  List<dynamic> parkingPoints = [];

  String playbackMaxSpeed = "-";
  String playbackTotalDistance = "-";
  String playbackMoveDuration = "-";
  String playbackStopDuration = "-";

  Map<MarkerId, Marker> _playbackMarkers = <MarkerId, Marker>{};
  Map<MarkerId, Marker>? _eventMarkers;
  Map<MarkerId, Marker>? _parkingMarkers;

  final Set<Polyline> _playbackPolyLines = {};
  final Set<Polyline> _animatedPolyLines = {};

  // SMOOTH ANIMATION VARIABLES
  AnimationController? _animationController;
  Animation<double>? _animation;

  int _currentPointIndex = 0;
  bool _isPlaying = false;
  double _playbackProgress = 0.0;

  // Speed control
  int _speedMultiplier = 1;
  String _speedText = "1x";
  int _animationDurationMs = 800;

  // Cached marker icon
  BitmapDescriptor? _cachedCarIcon;
  LatLng? _currentCarPosition;
  double _currentCarBearing = 0.0;

  // Date range
  late DateTime _fromDate;
  late DateTime _toDate;

  // Marker toggles
  bool _showParkingMarkers = true;
  bool _showEventMarkers = true;

  final DraggableScrollableController _sheetController =
  DraggableScrollableController();

  // Camera update throttling
  DateTime? _lastCameraUpdate;
  static const int _cameraUpdateIntervalMs = 100;

  // Default position (Dhaka, Bangladesh - change as needed)
  static const LatLng _defaultPosition = LatLng(23.8103, 90.4125);

  // Helper to check initial dates
  bool get _hasInitialDates =>
      widget.initialFromDate != null && widget.initialToDate != null;

  // Get initial camera position safely
  LatLng get _initialCameraPosition {
    if (widget.device != null &&
        widget.device!.lat != null &&
        widget.device!.lng != null) {
      try {
        final lat = double.tryParse(widget.device!.lat.toString());
        final lng = double.tryParse(widget.device!.lng.toString());
        if (lat != null && lng != null) {
          return LatLng(lat, lng);
        }
      } catch (e) {
        debugPrint('Error parsing device position: $e');
      }
    }
    return _defaultPosition;
  }

  @override
  void initState() {
    super.initState();

    // Initialize dates from widget parameters or defaults
    _fromDate = widget.initialFromDate ??
        DateTime.now().subtract(const Duration(hours: 12));
    _toDate = widget.initialToDate ?? DateTime.now();

    rootBundle.loadString('assets/map_style.txt').then((string) {
      _mapStyle = string;
    }).catchError((error) {
      debugPrint('Error loading map style: $error');
    });

    _initAnimation();
    _cacheCarIcon();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hasInitialDates) {
        _loadPlaybackData();
      } else {
        _showDatePicker();
      }
    });
  }

  void _initAnimation() {
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _animationDurationMs),
    );

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController!,
        curve: Curves.linear,
      ),
    );

    _animation!.addListener(_onAnimationUpdate);
    _animationController!.addStatusListener(_onAnimationStatus);
  }

  Future<void> _cacheCarIcon() async {
    try {
      if (widget.device?.icon?.path != null) {
        await Util.fetchAndCacheImages(
          "${UserRepository.getServerUrl() ?? ''}/${widget.device!.icon!.path!}",
        );
        _cachedCarIcon = await Util.getMarkerIcon(widget.device!.icon!.path!);
      } else {
        // Use default car icon
        _cachedCarIcon = BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueAzure,
        );
      }
    } catch (e) {
      debugPrint('Error caching car icon: $e');
      _cachedCarIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueAzure,
      );
    }
  }

  void _onAnimationUpdate() {
    if (!mounted || _isDisposed || !_isPlaying) return;
    if (playbackRoutePoints.isEmpty) return;
    if (_currentPointIndex >= playbackRoutePoints.length - 1) return;

    final t = _animation!.value;
    final startIndex = _currentPointIndex;
    final endIndex = (_currentPointIndex + _speedMultiplier)
        .clamp(0, playbackRoutePoints.length - 1);

    final start = playbackRoutePoints[startIndex];
    final end = playbackRoutePoints[endIndex];

    final lat = _lerp(start.latitude, end.latitude, t);
    final lng = _lerp(start.longitude, end.longitude, t);
    final interpolatedPosition = LatLng(lat, lng);

    final bearing = Geolocator.bearingBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );

    _currentCarPosition = interpolatedPosition;
    _currentCarBearing = bearing;

    _updateCarMarker(interpolatedPosition, bearing);
    _playbackProgress = startIndex + t * (_speedMultiplier);
    _updateAnimatedPolyline(startIndex);
    _updateCameraThrottled(interpolatedPosition);

    if (mounted) setState(() {});
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (!mounted || _isDisposed) return;

    if (status == AnimationStatus.completed) {
      _currentPointIndex += _speedMultiplier;

      if (_currentPointIndex >= playbackRoutePoints.length - 1) {
        _stopPlayback();
        _currentPointIndex = 0;
        _playbackProgress = 0;
        if (mounted) setState(() {});
        return;
      }

      _animationController!.reset();
      _animationController!.forward();
    }
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  void _updateCarMarker(LatLng position, double bearing) {
    if (_cachedCarIcon == null) return;

    final marker = Marker(
      markerId: const MarkerId('playback_car'),
      position: position,
      rotation: bearing,
      icon: _cachedCarIcon!,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      zIndex: 10,
    );

    _playbackMarkers[const MarkerId('playback_car')] = marker;
  }

  void _updateAnimatedPolyline(int currentIndex) {
    if (currentIndex < 0 || playbackRoutePoints.isEmpty) return;

    final trailPoints = playbackRoutePoints.sublist(
      0,
      (currentIndex + 1).clamp(0, playbackRoutePoints.length),
    );

    _animatedPolyLines.clear();
    _animatedPolyLines.add(Polyline(
      polylineId: const PolylineId('animated_trail'),
      points: trailPoints,
      width: 5,
      color: Colors.green,
      geodesic: true,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    ));
  }

  void _updateCameraThrottled(LatLng position) {
    final now = DateTime.now();
    if (_lastCameraUpdate != null &&
        now.difference(_lastCameraUpdate!).inMilliseconds <
            _cameraUpdateIntervalMs) {
      return;
    }
    _lastCameraUpdate = now;

    _safeAnimateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: position, zoom: currentZoom),
      ),
    );
  }

  Future<void> _safeAnimateCamera(CameraUpdate update) async {
    if (!mounted || _isDisposed || _mapController == null || !_isMapCreated) {
      return;
    }
    try {
      await _mapController!.animateCamera(update);
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _animationController?.dispose();
    _sheetController.dispose();
    _isMapCreated = false;
    _mapController = null;
    super.dispose();
  }

  // ==================== DATE PICKER ====================

  void _showDatePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: playbackRoutePoints.isNotEmpty,
      enableDrag: playbackRoutePoints.isNotEmpty,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSimpleDatePicker(),
    );
  }

  Widget _buildSimpleDatePicker() {
    return StatefulBuilder(
      builder: (context, setModalState) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Date Range',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (playbackRoutePoints.isNotEmpty)
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _quickButton('Today', Colors.blue, () {
                    setModalState(() {
                      _fromDate = DateTime(
                        DateTime.now().year,
                        DateTime.now().month,
                        DateTime.now().day,
                      );
                      _toDate = DateTime.now();
                    });
                  }),
                  const SizedBox(width: 8),
                  _quickButton('Yesterday', Colors.orange, () {
                    setModalState(() {
                      final yesterday =
                      DateTime.now().subtract(const Duration(days: 1));
                      _fromDate = DateTime(
                          yesterday.year, yesterday.month, yesterday.day);
                      _toDate = DateTime(yesterday.year, yesterday.month,
                          yesterday.day, 23, 59, 59);
                    });
                  }),
                  const SizedBox(width: 8),
                  _quickButton('Week', Colors.green, () {
                    setModalState(() {
                      _fromDate =
                          DateTime.now().subtract(const Duration(days: 7));
                      _toDate = DateTime.now();
                    });
                  }),
                ],
              ),
              const SizedBox(height: 20),
              _dateField(
                label: 'From',
                date: _fromDate,
                color: Colors.green,
                onTap: () async {
                  final result = await _pickDateTime(_fromDate);
                  if (result != null) {
                    setModalState(() => _fromDate = result);
                  }
                },
              ),
              const SizedBox(height: 12),
              _dateField(
                label: 'To',
                date: _toDate,
                color: Colors.red,
                onTap: () async {
                  final result = await _pickDateTime(_toDate);
                  if (result != null) {
                    setModalState(() => _toDate = result);
                  }
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _loadPlaybackData();
                  },
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Load Playback',
                      style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CustomColor.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 10),
            ],
          ),
        );
      },
    );
  }

  Widget _quickButton(String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateField({
    required String label,
    required DateTime date,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                label == 'From' ? Icons.play_arrow : Icons.stop,
                color: color,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  Text(
                    DateFormat('dd MMM yyyy, HH:mm').format(date),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit, size: 18, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: CustomColor.primaryColor),
          ),
          child: child!,
        );
      },
    );

    if (date == null) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: CustomColor.primaryColor),
          ),
          child: child!,
        );
      },
    );

    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  // ==================== DATA LOADING ====================

  void _clearData() {
    routeList.clear();
    playbackRoutePoints.clear();
    bottomRouteList.clear();
    parkingPoints.clear();
    eventsPoints.clear();
    _playbackMarkers.clear();
    _playbackPolyLines.clear();
    _animatedPolyLines.clear();
    _parkingMarkers = null;
    _eventMarkers = null;
    _currentPointIndex = 0;
    _playbackProgress = 0;
    _isPlaying = false;
  }

  void _loadPlaybackData() {
    if (widget.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device ID is missing'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _clearData();
    setState(() => _isPlaybackLoading = true);

    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SpinKitRing(
                lineWidth: 3.0,
                color: CustomColor.primaryColor,
                size: 40.0,
              ),
              const SizedBox(height: 16),
              Text('Loading playback...', style: TextStyle(color: Colors.grey[700])),
              const SizedBox(height: 8),
              Text(
                '${DateFormat('dd MMM').format(_fromDate)} - ${DateFormat('dd MMM').format(_toDate)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );

    APIService.getHistory(
      widget.id.toString(),
      Util.formatReportDate(_fromDate),
      Util.formatReportTime(_fromDate),
      Util.formatReportDate(_toDate),
      Util.formatReportTime(_toDate),
    ).then((value) async {
      if (!mounted || _isDisposed) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        return;
      }

      Navigator.pop(context);

      if (value != null && value.items != null && value.items!.isNotEmpty) {
        playbackTotalDistance = value.distance_sum ?? "0 km";
        playbackMaxSpeed = value.top_speed ?? "0 km/h";
        playbackMoveDuration = value.move_duration ?? "0";
        playbackStopDuration = value.stop_duration ?? "0";

        for (var el in value.items!) {
          if (el['time'] != null) {
            PlayBackRoute rt = PlayBackRoute();
            rt.time = el['time'];
            rt.show = el['show'];
            rt.left = el['left'];
            rt.distance = el['distance'];
            rt.engine_hours = el['engine_hours'];
            rt.fuel_consumption = el['fuel_consumption'];
            rt.top_speed = el['top_speed'];
            rt.average_speed = el['average_speed'];
            rt.status = el['status'];

            if (el['items'] != null && (el['items'] as List).isNotEmpty) {
              var element = el['items'].first;
              if (element['latitude'] != null) {
                rt.device_id = element['device_id']?.toString();
                rt.longitude = element['longitude']?.toString();
                rt.latitude = element['latitude']?.toString();
                rt.speed = element['speed'];
                rt.course = element['course']?.toString();
                rt.raw_time = element['raw_time']?.toString();
                rt.speedType = "kph";
                rt.id = element["id"]?.toString();
              }
            }
            bottomRouteList.add(rt);
          }

          if (el["status"] == 1) parkingPoints.add(el['items']);
          if (el["status"] == 5) eventsPoints.add(el['items']);

          if (el['items'] != null) {
            for (var element in el['items']) {
              if (element['latitude'] != null) {
                PlayBackRoute blackRoute = PlayBackRoute();
                blackRoute.device_id = element['device_id']?.toString();
                blackRoute.longitude = element['longitude']?.toString();
                blackRoute.latitude = element['latitude']?.toString();
                blackRoute.speed = element['speed'];
                blackRoute.course = element['course']?.toString();
                blackRoute.raw_time = element['raw_time']?.toString();
                blackRoute.speedType = "kph";

                final lat = double.tryParse(element['latitude'].toString());
                final lng = double.tryParse(element['longitude'].toString());
                if (lat != null && lng != null) {
                  playbackRoutePoints.add(LatLng(lat, lng));
                  routeList.add(blackRoute);
                }
              }
            }
          }
        }

        if (playbackRoutePoints.isNotEmpty) {
          _playbackPolyLines.add(Polyline(
            polylineId: const PolylineId('playback_route'),
            visible: true,
            points: playbackRoutePoints,
            width: 4,
            color: Colors.orange.withOpacity(0.6),
            geodesic: true,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ));

          await _addStartEndMarkers();
          _addParkingMarkers();
          _addEventMarkers();

          _currentCarPosition = playbackRoutePoints.first;
          _updateCarMarker(playbackRoutePoints.first, 0);
        }

        setState(() => _isPlaybackLoading = false);
      } else {
        setState(() => _isPlaybackLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No records found for ${DateFormat('dd MMM').format(_fromDate)} - ${DateFormat('dd MMM').format(_toDate)}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }).catchError((error) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      setState(() => _isPlaybackLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Error: $error')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    });
  }

  Future<void> _addStartEndMarkers() async {
    if (playbackRoutePoints.isEmpty || !mounted) return;

    try {
      Uint8List? startIcon;
      Uint8List? endIcon;

      try {
        startIcon = await Util.getBytesFromAsset('assets/images/map-start-point.png', 40);
        endIcon = await Util.getBytesFromAsset('assets/images/map-end-point.png', 40);
      } catch (e) {
        debugPrint('Error loading marker assets: $e');
      }

      if (!mounted) return;

      final startPos = playbackRoutePoints.first;
      final endPos = playbackRoutePoints.last;

      _playbackMarkers[const MarkerId('start')] = Marker(
        markerId: const MarkerId('start'),
        position: startPos,
        icon: startIcon != null
            ? BitmapDescriptor.bytes(startIcon)
            : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Start'),
        zIndex: 1,
      );

      _playbackMarkers[const MarkerId('end')] = Marker(
        markerId: const MarkerId('end'),
        position: endPos,
        icon: endIcon != null
            ? BitmapDescriptor.bytes(endIcon)
            : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'End'),
        zIndex: 1,
      );

      double minLat = startPos.latitude, maxLat = startPos.latitude;
      double minLng = startPos.longitude, maxLng = startPos.longitude;

      for (var point in playbackRoutePoints) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }

      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      await _safeAnimateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
      setState(() {});
    } catch (e) {
      debugPrint('Error adding markers: $e');
    }
  }

  Future<BitmapDescriptor> _createCircleMarker(String text, Color color) async {
    const size = 40.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(size / 2, size / 2);

    canvas.drawCircle(
      Offset(center.dx + 1, center.dy + 1),
      size / 2 - 4,
      Paint()..color = Colors.black26,
    );

    canvas.drawCircle(center, size / 2 - 4, Paint()..color = color);

    canvas.drawCircle(
      center,
      size / 2 - 4,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );

    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  void _addParkingMarkers() async {
    if (!mounted || parkingPoints.isEmpty) return;

    _parkingMarkers = {};
    int index = 1;

    for (var element in parkingPoints) {
      if (!mounted) return;
      if (element == null || (element as List).isEmpty) continue;

      final id = MarkerId('parking_$index');
      final lat = double.tryParse(element[0]["latitude"]?.toString() ?? '') ?? 0;
      final lng = double.tryParse(element[0]["longitude"]?.toString() ?? '') ?? 0;

      if (lat == 0 && lng == 0) continue;

      final icon = await _createCircleMarker('P$index', Colors.blue);

      _parkingMarkers![id] = Marker(
        markerId: id,
        position: LatLng(lat, lng),
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        zIndex: 2,
      );

      if (_showParkingMarkers) {
        _playbackMarkers[id] = _parkingMarkers![id]!;
      }

      index++;
    }

    if (mounted) setState(() {});
  }

  void _addEventMarkers() async {
    if (!mounted || eventsPoints.isEmpty) return;

    _eventMarkers = {};
    int index = 1;

    for (var element in eventsPoints) {
      if (!mounted) return;
      if (element == null || (element as List).isEmpty) continue;

      final id = MarkerId('event_$index');
      final lat = double.tryParse(element[0]["lat"]?.toString() ?? '') ?? 0;
      final lng = double.tryParse(element[0]["lng"]?.toString() ?? '') ?? 0;

      if (lat == 0 && lng == 0) continue;

      final icon = await _createCircleMarker('A$index', Colors.red);

      _eventMarkers![id] = Marker(
        markerId: id,
        position: LatLng(lat, lng),
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        zIndex: 2,
      );

      if (_showEventMarkers) {
        _playbackMarkers[id] = _eventMarkers![id]!;
      }

      index++;
    }

    if (mounted) setState(() {});
  }

  // ==================== PLAYBACK CONTROLS ====================

  void _togglePlayPause() {
    if (playbackRoutePoints.isEmpty) return;

    setState(() => _isPlaying = !_isPlaying);

    if (_isPlaying) {
      if (_currentPointIndex >= playbackRoutePoints.length - 1) {
        _currentPointIndex = 0;
        _playbackProgress = 0;
      }
      _animationController!.forward();
    } else {
      _animationController!.stop();
    }
  }

  void _stopPlayback() {
    _animationController?.stop();
    _animationController?.reset();
    setState(() => _isPlaying = false);
  }

  void _changeSpeed() {
    setState(() {
      if (_speedMultiplier == 1) {
        _speedMultiplier = 2;
        _speedText = "2x";
        _animationDurationMs = 600;
      } else if (_speedMultiplier == 2) {
        _speedMultiplier = 4;
        _speedText = "4x";
        _animationDurationMs = 400;
      } else if (_speedMultiplier == 4) {
        _speedMultiplier = 8;
        _speedText = "8x";
        _animationDurationMs = 200;
      } else {
        _speedMultiplier = 1;
        _speedText = "1x";
        _animationDurationMs = 800;
      }
    });

    _animationController!.duration = Duration(milliseconds: _animationDurationMs);
  }

  void _seekTo(double value) {
    final index = value.toInt().clamp(0, playbackRoutePoints.length - 1);
    _currentPointIndex = index;
    _playbackProgress = value;

    if (index < playbackRoutePoints.length) {
      final pos = playbackRoutePoints[index];
      _currentCarPosition = pos;
      _updateCarMarker(pos, _currentCarBearing);
      _updateAnimatedPolyline(index);
      _safeAnimateCamera(CameraUpdate.newLatLng(pos));
    }

    setState(() {});
  }

  void _toggleParkingMarkers() {
    setState(() {
      _showParkingMarkers = !_showParkingMarkers;

      if (_showParkingMarkers && _parkingMarkers != null) {
        _playbackMarkers.addAll(_parkingMarkers!);
      } else {
        _parkingMarkers?.forEach((id, _) => _playbackMarkers.remove(id));
      }
    });
  }

  void _toggleEventMarkers() {
    setState(() {
      _showEventMarkers = !_showEventMarkers;

      if (_showEventMarkers && _eventMarkers != null) {
        _playbackMarkers.addAll(_eventMarkers!);
      } else {
        _eventMarkers?.forEach((id, _) => _playbackMarkers.remove(id));
      }
    });
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle, color: Colors.orange, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Playback',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.name ?? 'Unknown',
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (playbackRoutePoints.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    DateFormat('dd MMM').format(_fromDate),
                    style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.date_range, color: Colors.black54),
            onPressed: _showDatePicker,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map - USE SAFE INITIAL POSITION
          GoogleMap(
            mapType: _currentMapType,
            initialCameraPosition: CameraPosition(
              target: _initialCameraPosition, // FIXED: Using safe getter
              zoom: 14,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              _isMapCreated = true;
              if (_mapStyle != null) {
                controller.setMapStyle(_mapStyle);
              }
            },
            onCameraMove: (pos) => currentZoom = pos.zoom,
            markers: Set<Marker>.of(_playbackMarkers.values),
            polylines: {..._playbackPolyLines, ..._animatedPolyLines},
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            padding: const EdgeInsets.only(bottom: 120),
          ),

          // Map Controls
          Positioned(
            top: 10,
            right: 10,
            child: Column(
              children: [
                _mapButton(Icons.layers, () {
                  setState(() {
                    _currentMapType = _currentMapType == MapType.normal
                        ? MapType.hybrid
                        : MapType.normal;
                  });
                }),
                const SizedBox(height: 8),
                _mapButton(Icons.add, () => _safeAnimateCamera(CameraUpdate.zoomIn())),
                const SizedBox(height: 4),
                _mapButton(Icons.remove, () => _safeAnimateCamera(CameraUpdate.zoomOut())),
              ],
            ),
          ),

          // Marker Toggle Buttons
          if (playbackRoutePoints.isNotEmpty)
            Positioned(
              bottom: 140,
              left: 10,
              child: _buildMarkerToggles(),
            ),

          // Bottom Sheet
          _buildBottomSheet(),
        ],
      ),
    );
  }

  Widget _mapButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: Colors.grey[700]),
        ),
      ),
    );
  }

  Widget _buildMarkerToggles() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleChip('P', parkingPoints.length, Colors.blue, _showParkingMarkers, _toggleParkingMarkers),
          const SizedBox(width: 8),
          _toggleChip('A', eventsPoints.length, Colors.red, _showEventMarkers, _toggleEventMarkers),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, int count, Color color, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.15) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? color : Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(color: active ? color : Colors.grey, shape: BoxShape.circle),
              child: Center(
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 4),
            Text('$count', style: TextStyle(color: active ? color : Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.15,
      minChildSize: 0.08,
      maxChildSize: 0.6,
      controller: _sheetController,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              _buildControls(),
              if (playbackRoutePoints.isNotEmpty) ...[
                const Divider(),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _statChip(Icons.route, playbackTotalDistance, Colors.blue),
                      _statChip(Icons.timer, playbackMoveDuration, Colors.green),
                      _statChip(Icons.pause_circle, playbackStopDuration, Colors.orange),
                      _statChip(Icons.speed, playbackMaxSpeed, Colors.red),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (bottomRouteList.isNotEmpty)
                ...bottomRouteList.asMap().entries.map((e) => _buildTimelineItem(e.value, e.key))
              else
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      _isPlaybackLoading ? 'Loading...' : 'Select date range to load',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    final maxValue = (playbackRoutePoints.length - 1).toDouble().clamp(0.0, double.infinity);
    final currentValue = _playbackProgress.clamp(0.0, maxValue);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(DateFormat('dd/MM HH:mm').format(_fromDate), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              if (playbackRoutePoints.isNotEmpty && _playbackProgress.toInt() < routeList.length)
                Text(
                  '${routeList[_playbackProgress.toInt().clamp(0, routeList.length - 1)].speed ?? 0} kph',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              Text(DateFormat('dd/MM HH:mm').format(_toDate), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
          ),
          if (playbackRoutePoints.isNotEmpty) ...[
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                activeTrackColor: CustomColor.primaryColor,
                inactiveTrackColor: Colors.grey[300],
                thumbColor: CustomColor.primaryColor,
              ),
              child: Slider(
                value: currentValue,
                min: 0,
                max: maxValue > 0 ? maxValue : 1,
                onChanged: _seekTo,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => _seekTo((_playbackProgress - 10).clamp(0, maxValue)),
                  icon: const Icon(Icons.replay_10),
                  color: Colors.grey[700],
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: CustomColor.primaryColor),
                    child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 28),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _seekTo((_playbackProgress + 10).clamp(0, maxValue)),
                  icon: const Icon(Icons.forward_10),
                  color: Colors.grey[700],
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _changeSpeed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Text(_speedText, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(PlayBackRoute trip, int index) {
    final isStopped = trip.status == 1;
    int parkingNum = 0;
    if (isStopped) {
      for (int i = 0; i <= index; i++) {
        if (bottomRouteList[i].status == 1) parkingNum++;
      }
    }

    return InkWell(
      onTap: () {
        if (trip.latitude != null && trip.longitude != null) {
          final lat = double.tryParse(trip.latitude!);
          final lng = double.tryParse(trip.longitude!);
          if (lat != null && lng != null) {
            _safeAnimateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16));
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: isStopped ? Colors.blue : Colors.green),
                    child: Center(
                      child: isStopped
                          ? Text('P$parkingNum', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
                          : const Icon(Icons.directions_car, color: Colors.white, size: 14),
                    ),
                  ),
                  if (index < bottomRouteList.length - 1)
                    Container(width: 2, height: 30, color: Colors.grey[300]),
                ],
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isStopped ? Colors.blue : Colors.green).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (isStopped ? Colors.blue : Colors.green).withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isStopped ? 'P$parkingNum - Stopped' : 'Moving',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: isStopped ? Colors.blue : Colors.green),
                        ),
                        Text(Util.formatOnlyTime(trip.show ?? ""), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _infoChip(Icons.timer, trip.time ?? "0"),
                        if (!isStopped) ...[
                          _infoChip(Icons.route, "${trip.distance ?? 0} km"),
                          _infoChip(Icons.speed, "${trip.top_speed ?? 0} kph"),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: Colors.grey[600]),
        const SizedBox(width: 2),
        Text(value, style: TextStyle(fontSize: 10, color: Colors.grey[700])),
      ],
    );
  }
}