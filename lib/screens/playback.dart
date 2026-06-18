// lib/screens/playback/playback_screen.dart

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/services/model/playback_route.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/util/util.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

// ==================== SMOOTH CAR ANIMATOR FOR PLAYBACK ====================
class PlaybackCarAnimator {
  final TickerProvider vsync;
  final void Function(LatLng position, double bearing) onPositionUpdate;
  final void Function()? onAnimationComplete;

  Ticker? _ticker;

  LatLng _currentPosition;
  double _currentBearing;

  LatLng? _targetPosition;
  double _targetBearing = 0;

  bool _isRunning = false;
  int _lastTickTime = 0;

  double _speedMultiplier = 1.0;
  static const double _baseSpeed = 15.0;

  PlaybackCarAnimator({
    required this.vsync,
    required this.onPositionUpdate,
    required LatLng initialPosition,
    this.onAnimationComplete,
    double initialBearing = 0,
  })  : _currentPosition = initialPosition,
        _currentBearing = initialBearing {
    _ticker = vsync.createTicker(_onTick);
  }

  LatLng get currentPosition => _currentPosition;
  double get currentBearing => _currentBearing;
  bool get isAnimating => _isRunning;

  void setSpeedMultiplier(double multiplier) {
    _speedMultiplier = multiplier;
  }

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
    final deltaTime = (now - _lastTickTime) / 1000.0;
    _lastTickTime = now;

    final dt = deltaTime.clamp(0.001, 0.1);
    final distance = _calculateDistance(_currentPosition, _targetPosition!);

    if (distance < 0.5) {
      _currentPosition = _targetPosition!;
      _currentBearing = _normalizeBearing(_targetBearing);
      onPositionUpdate(_currentPosition, _currentBearing);
      _targetPosition = null;
      _stop();
      onAnimationComplete?.call();
      return;
    }

    final speed = _baseSpeed * _speedMultiplier;
    final moveDistance = speed * dt;
    final moveRatio = (moveDistance / distance).clamp(0.0, 1.0);

    final newLat = _currentPosition.latitude +
        (_targetPosition!.latitude - _currentPosition.latitude) * moveRatio;
    final newLng = _currentPosition.longitude +
        (_targetPosition!.longitude - _currentPosition.longitude) * moveRatio;

    _currentPosition = LatLng(newLat, newLng);
    _currentBearing = _interpolateBearing(_currentBearing, _targetBearing, 150.0 * dt);

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
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  void updatePosition(LatLng position, double bearing) {
    _currentPosition = position;
    _currentBearing = bearing;
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

// ==================== MAIN PLAYBACK SCREEN ====================
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

  final Map<MarkerId, Marker> _playbackMarkers = <MarkerId, Marker>{};
  Map<MarkerId, Marker>? _eventMarkers;
  Map<MarkerId, Marker>? _parkingMarkers;

  final Set<Polyline> _playbackPolyLines = {};
  final Set<Polyline> _animatedPolyLines = {};

  // High-performance ValueNotifiers to update overlays without rebuilding the entire screen at 60fps
  final ValueNotifier<Set<Marker>> _markersNotifier = ValueNotifier<Set<Marker>>({});
  final ValueNotifier<Set<Polyline>> _polylinesNotifier = ValueNotifier<Set<Polyline>>({});

  void _syncMarkers() {
    if (!_isDisposed) {
      _markersNotifier.value = Set<Marker>.of(_playbackMarkers.values);
    }
  }

  void _syncPolylines() {
    if (!_isDisposed) {
      _polylinesNotifier.value = {..._playbackPolyLines, ..._animatedPolyLines};
    }
  }

  // SMOOTH ANIMATION
  PlaybackCarAnimator? _carAnimator;
  Timer? _cameraFollowTimer;

  int _currentPointIndex = 0;
  bool _isPlaying = false;
  double _playbackProgress = 0.0;

  // Speed control
  int _speedMultiplier = 1;
  String _speedText = "1x";

  // Cached marker icon
  BitmapDescriptor? _cachedCarIcon;
  bool _isIconLoaded = false;

  // Date range
  late DateTime _fromDate;
  late DateTime _toDate;

  // Quick select button state
  int _selectedQuickButton = -1;

  // Marker toggles
  bool _showParkingMarkers = true;
  bool _showEventMarkers = true;

  final DraggableScrollableController _sheetController =
  DraggableScrollableController();

  static const LatLng _defaultPosition = LatLng(23.8103, 90.4125);

  bool get _hasInitialDates =>
      widget.initialFromDate != null && widget.initialToDate != null;

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

    _fromDate = widget.initialFromDate ??
        DateTime.now().subtract(const Duration(hours: 12));
    _toDate = widget.initialToDate ?? DateTime.now();

    rootBundle.loadString('assets/map_style.txt').then((string) {
      _mapStyle = string;
    }).catchError((error) {
      debugPrint('Error loading map style: $error');
    });

    // Load car icon first
    _loadCarIcon();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hasInitialDates) {
        _loadPlaybackData();
      } else {
        _showDatePicker();
      }
    });
  }

  // ==================== LOAD CAR ICON - FIXED ====================
  Future<void> _loadCarIcon() async {
    try {
      if (widget.device?.icon?.path != null) {
        final path = widget.device!.icon!.path!;
        _cachedCarIcon = await Util.getMarkerIcon(path);
      }

      _cachedCarIcon ??=
          BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure);

      _isIconLoaded = true;
      if (mounted) setState(() {});

    } catch (e) {
      debugPrint('Error loading car icon: $e');
      _cachedCarIcon =
          BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure);
      _isIconLoaded = true;
      if (mounted) setState(() {});
    }
  }


  void _initCarAnimator() {
    if (playbackRoutePoints.isEmpty) return;

    _carAnimator?.dispose();
    _carAnimator = PlaybackCarAnimator(
      vsync: this,
      onPositionUpdate: _onCarPositionUpdate,
      onAnimationComplete: _onCarReachedTarget,
      initialPosition: playbackRoutePoints.first,
      initialBearing: 0,
    );

    // IMPORTANT: Add initial car marker & animated polyline
    _addCarMarker(playbackRoutePoints.first, 0);
    _updateAnimatedPolyline(0);
  }

  void _onCarPositionUpdate(LatLng position, double bearing) {
    if (_isDisposed) return;
    _addCarMarker(position, bearing);
  }

  void _onCarReachedTarget() {
    if (!_isPlaying) return;

    _currentPointIndex++;
    _playbackProgress = _currentPointIndex.toDouble();
    _updateAnimatedPolyline(_currentPointIndex);

    if (_currentPointIndex >= playbackRoutePoints.length - 1) {
      _stopPlayback();
      _currentPointIndex = 0;
      _playbackProgress = 0;
      _updateAnimatedPolyline(0);
      if (mounted) setState(() {});
      return;
    }

    if (mounted) setState(() {});
    _moveToNextPoint();
  }

  void _moveToNextPoint() {
    if (_currentPointIndex >= playbackRoutePoints.length - 1) return;
    if (_carAnimator == null) return;

    final nextIndex = (_currentPointIndex + 1).clamp(0, playbackRoutePoints.length - 1);
    final currentPos = playbackRoutePoints[_currentPointIndex];
    final nextPos = playbackRoutePoints[nextIndex];

    final bearing = Geolocator.bearingBetween(
      currentPos.latitude,
      currentPos.longitude,
      nextPos.latitude,
      nextPos.longitude,
    );

    _carAnimator!.setSpeedMultiplier(_speedMultiplier.toDouble());
    _carAnimator!.moveTo(nextPos, bearing);
  }

  // ==================== ADD CAR MARKER - FIXED ====================
  void _addCarMarker(LatLng position, double bearing) {
    if (!_isIconLoaded || _cachedCarIcon == null) {
      // Use default marker if icon not loaded yet
      final marker = Marker(
        markerId: const MarkerId('playback_car'),
        position: position,
        rotation: bearing,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        flat: true,
        zIndex: 10,
      );
      _playbackMarkers[const MarkerId('playback_car')] = marker;
      _syncMarkers();
      return;
    }

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
    _syncMarkers();
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
    _syncPolylines();
  }

  void _startCameraFollowTimer() {
    _cameraFollowTimer?.cancel();
    _cameraFollowTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (_isPlaying && _carAnimator != null && _mapController != null) {
        _mapController!.moveCamera(
          CameraUpdate.newLatLng(_carAnimator!.currentPosition),
        );
      }
    });
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
    _cameraFollowTimer?.cancel();
    _carAnimator?.dispose();
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (playbackRoutePoints.isNotEmpty)
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _quickSelectButton(
                    label: 'Today',
                    index: 0,
                    isSelected: _selectedQuickButton == 0,
                    onTap: () {
                      setModalState(() {
                        _selectedQuickButton = 0;
                        _fromDate = DateTime(
                          DateTime.now().year,
                          DateTime.now().month,
                          DateTime.now().day,
                        );
                        _toDate = DateTime.now();
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  _quickSelectButton(
                    label: 'Yesterday',
                    index: 1,
                    isSelected: _selectedQuickButton == 1,
                    onTap: () {
                      setModalState(() {
                        _selectedQuickButton = 1;
                        final yesterday =
                        DateTime.now().subtract(const Duration(days: 1));
                        _fromDate = DateTime(
                            yesterday.year, yesterday.month, yesterday.day);
                        _toDate = DateTime(yesterday.year, yesterday.month,
                            yesterday.day, 23, 59, 59);
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  _quickSelectButton(
                    label: 'Week',
                    index: 2,
                    isSelected: _selectedQuickButton == 2,
                    onTap: () {
                      setModalState(() {
                        _selectedQuickButton = 2;
                        _fromDate =
                            DateTime.now().subtract(const Duration(days: 7));
                        _toDate = DateTime.now();
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _compactDateField(
                      label: 'From',
                      date: _fromDate,
                      color: Colors.green,
                      onTap: () async {
                        setModalState(() => _selectedQuickButton = -1);
                        final result = await _pickDateTime(_fromDate);
                        if (result != null) {
                          setModalState(() => _fromDate = result);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _compactDateField(
                      label: 'To',
                      date: _toDate,
                      color: Colors.red,
                      onTap: () async {
                        setModalState(() => _selectedQuickButton = -1);
                        final result = await _pickDateTime(_toDate);
                        if (result != null) {
                          setModalState(() => _toDate = result);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _loadPlaybackData();
                  },
                  icon: const Icon(Icons.play_circle_outline, size: 20),
                  label: const Text('Load Playback', style: TextStyle(fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CustomColor.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        );
      },
    );
  }

  Widget _quickSelectButton({
    required String label,
    required int index,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.green : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.grey[500]! : Colors.grey[300]!,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactDateField({
    required String label,
    required DateTime date,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  label == 'From' ? Icons.play_arrow : Icons.stop,
                  color: color,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('dd MMM, HH:mm').format(date),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
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
    _carAnimator?.dispose();
    _carAnimator = null;
    _syncMarkers();
    _syncPolylines();
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

    APIService.getHistory(
      widget.id.toString(),
      Util.formatReportDate(_fromDate),
      Util.formatReportTime(_fromDate),
      Util.formatReportDate(_toDate),
      Util.formatReportTime(_toDate),
    ).then((value) async {
      if (!mounted || _isDisposed) return;

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
            color: Colors.orange.withValues(alpha: 0.6),
            geodesic: true,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ));
          _syncPolylines();

          await _addStartEndMarkers();
          _addParkingMarkers();
          _addEventMarkers();

          // IMPORTANT: Initialize car animator and add car marker
          _initCarAnimator();
          _startCameraFollowTimer();

          debugPrint('Playback loaded: ${playbackRoutePoints.length} points');
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
        startIcon = await Util.getBytesFromAsset('assets/images/map-start-point.png', 36);
        endIcon = await Util.getBytesFromAsset('assets/images/map-end-point.png', 36);
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
      _syncMarkers();
      setState(() {});
    } catch (e) {
      debugPrint('Error adding markers: $e');
    }
  }

  Future<BitmapDescriptor> _createCircleMarker(String text, Color color) async {
    const size = 36.0;
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
          fontSize: 10,
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

    _syncMarkers();
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

    _syncMarkers();
    if (mounted) setState(() {});
  }

  // ==================== PLAYBACK CONTROLS ====================

  void _togglePlayPause() {
    if (playbackRoutePoints.isEmpty || _carAnimator == null) {
      debugPrint('Cannot play: no route points or animator');
      return;
    }

    setState(() => _isPlaying = !_isPlaying);

    if (_isPlaying) {
      if (_currentPointIndex >= playbackRoutePoints.length - 1) {
        _currentPointIndex = 0;
        _playbackProgress = 0;
        _carAnimator!.updatePosition(playbackRoutePoints.first, 0);
        _addCarMarker(playbackRoutePoints.first, 0);
      }
      _moveToNextPoint();
    }
  }

  void _stopPlayback() {
    setState(() => _isPlaying = false);
  }

  void _changeSpeed() {
    setState(() {
      if (_speedMultiplier == 1) {
        _speedMultiplier = 2;
        _speedText = "2x";
      } else if (_speedMultiplier == 2) {
        _speedMultiplier = 4;
        _speedText = "4x";
      } else if (_speedMultiplier == 4) {
        _speedMultiplier = 8;
        _speedText = "8x";
      } else {
        _speedMultiplier = 1;
        _speedText = "1x";
      }
    });

    if (_carAnimator != null) {
      _carAnimator!.setSpeedMultiplier(_speedMultiplier.toDouble());
    }
  }

  void _seekTo(double value) {
    final index = value.toInt().clamp(0, playbackRoutePoints.length - 1);
    _currentPointIndex = index;
    _playbackProgress = value;

    if (index < playbackRoutePoints.length) {
      final pos = playbackRoutePoints[index];
      if (_carAnimator != null) {
        _carAnimator!.updatePosition(pos, _carAnimator!.currentBearing);
      }
      _addCarMarker(pos, _carAnimator?.currentBearing ?? 0);
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
      _syncMarkers();
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
      _syncMarkers();
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle, color: Colors.orange, size: 14),
                  const SizedBox(width: 3),
                  Text(
                    'Playback',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontSize: 12,
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
                  fontSize: 15,
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
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    DateFormat('dd MMM').format(_fromDate),
                    style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.date_range, color: Colors.black54, size: 22),
            onPressed: _showDatePicker,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          ValueListenableBuilder<Set<Marker>>(
            valueListenable: _markersNotifier,
            builder: (context, markers, _) {
              return ValueListenableBuilder<Set<Polyline>>(
                valueListenable: _polylinesNotifier,
                builder: (context, polylines, _) {
                  return GoogleMap(
                    mapType: _currentMapType,
                    initialCameraPosition: CameraPosition(
                      target: _initialCameraPosition,
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
                    markers: markers,
                    polylines: polylines,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    buildingsEnabled: false,
                    padding: const EdgeInsets.only(bottom: 120),
                  );
                },
              );
            },
          ),

          if (_isPlaybackLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 3,
                        color: CustomColor.primaryColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Loading...',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Map Controls
          if (!_isPlaybackLoading)
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
                  const SizedBox(height: 6),
                  _mapButton(Icons.add, () => _safeAnimateCamera(CameraUpdate.zoomIn())),
                  const SizedBox(height: 4),
                  _mapButton(Icons.remove, () => _safeAnimateCamera(CameraUpdate.zoomOut())),
                  if (playbackRoutePoints.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _mapButton(Icons.gps_fixed, () {
                      if (_carAnimator != null) {
                        _safeAnimateCamera(
                          CameraUpdate.newLatLngZoom(_carAnimator!.currentPosition, 16),
                        );
                      } else if (playbackRoutePoints.isNotEmpty) {
                        _safeAnimateCamera(
                          CameraUpdate.newLatLngZoom(playbackRoutePoints.first, 16),
                        );
                      }
                    }),
                  ],
                ],
              ),
            ),

          // Marker Toggle Buttons
          if (playbackRoutePoints.isNotEmpty && !_isPlaybackLoading)
            Positioned(
              bottom: 130,
              left: 10,
              child: _buildMarkerToggles(),
            ),

          // Bottom Sheet
          if (!_isPlaybackLoading) _buildBottomSheet(),
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
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: CustomColor.primary),
        ),
      ),
    );
  }

  Widget _buildMarkerToggles() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleChip('P', parkingPoints.length, Colors.blue, _showParkingMarkers, _toggleParkingMarkers),
          const SizedBox(width: 6),
          _toggleChip('A', eventsPoints.length, Colors.red, _showEventMarkers, _toggleEventMarkers),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, int count, Color color, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? color : Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(color: active ? color : Colors.grey, shape: BoxShape.circle),
              child: Center(
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 3),
            Text('$count', style: TextStyle(color: active ? color : Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.14,
      minChildSize: 0.08,
      maxChildSize: 0.55,
      controller: _sheetController,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              _buildControls(),
              if (playbackRoutePoints.isNotEmpty) ...[
                const Divider(height: 1),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      _statChip(Icons.route, playbackTotalDistance, Colors.blue),
                      _statChip(Icons.timer, playbackMoveDuration, Colors.green),
                      _statChip(Icons.pause_circle, playbackStopDuration, Colors.orange),
                      _statChip(Icons.speed, playbackMaxSpeed, Colors.red),
                    ],
                  ),
                ),
              ],
              if (bottomRouteList.isNotEmpty)
                ...bottomRouteList.asMap().entries.map((e) => _buildTimelineItem(e.value, e.key))
              else
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'Select date range to load',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('dd/MM HH:mm').format(_fromDate),
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
              if (playbackRoutePoints.isNotEmpty && _playbackProgress.toInt() < routeList.length)
                Text(
                  '${routeList[_playbackProgress.toInt().clamp(0, routeList.length - 1)].speed ?? 0} kph',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              Text(
                DateFormat('dd/MM HH:mm').format(_toDate),
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ],
          ),
          if (playbackRoutePoints.isNotEmpty) ...[
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
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
                  icon: const Icon(Icons.replay_10, size: 22),
                  color: Colors.grey[700],
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: CustomColor.primaryColor,
                    ),
                    child: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () => _seekTo((_playbackProgress + 10).clamp(0, maxValue)),
                  icon: const Icon(Icons.forward_10, size: 22),
                  color: Colors.grey[700],
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _changeSpeed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Text(
                      _speedText,
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 3),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
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
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isStopped ? Colors.blue : Colors.green,
                    ),
                    child: Center(
                      child: isStopped
                          ? Text(
                        'P$parkingNum',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                          : const Icon(Icons.directions_car, color: Colors.white, size: 12),
                    ),
                  ),
                  if (index < bottomRouteList.length - 1)
                    Container(width: 2, height: 24, color: Colors.grey[300]),
                ],
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isStopped ? Colors.blue : Colors.green).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (isStopped ? Colors.blue : Colors.green).withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isStopped ? 'P$parkingNum - Stopped' : 'Moving',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            color: isStopped ? Colors.blue : Colors.green,
                          ),
                        ),
                        Text(
                          Util.formatOnlyTime(trip.show ?? ""),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 3,
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
        Icon(icon, size: 10, color: Colors.grey[600]),
        const SizedBox(width: 2),
        Text(value, style: TextStyle(fontSize: 9, color: Colors.grey[700])),
      ],
    );
  }
}