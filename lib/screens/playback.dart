// lib/screens/playback/playback_screen.dart

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
import 'package:smart_lock/services/model/playback_route.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/util/util.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

// ==================== LOCALIZATION HELPER ====================
class PlaybackL10n {
  static bool isBangla = false;

  static String get fromDateTime => isBangla ? 'শুরুর তারিখ ও সময়' : 'From date & time';
  static String get toDateTime => isBangla ? 'শেষের তারিখ ও সময়' : 'To date & time';
  static String get apply => isBangla ? 'প্রয়োগ করুন' : 'Apply';
  static String get today => isBangla ? 'আজ' : 'Today';
  static String get yesterday => isBangla ? 'গতকাল' : 'Yesterday';
  static String get week => isBangla ? 'এই সপ্তাহ' : 'Week';
  static String get loadPlayback => isBangla ? 'প্লেব্যাক লোড করুন' : 'Load Playback';
  static String get selectDateRange => isBangla ? 'তারিখের সীমা নির্বাচন করুন' : 'Select Date Range';
  static String get from => isBangla ? 'শুরু' : 'From';
  static String get to => isBangla ? 'শেষ' : 'To';
  static String get loading => isBangla ? 'লোড হচ্ছে...' : 'Loading...';
  static String get noRecords => isBangla ? 'কোন রেকর্ড নেই' : 'No records';
  static String get tapDateToLoad => isBangla ? 'প্লেব্যাক লোড করতে একটি তারিখ ট্যাপ করুন' : 'Tap a date above to load playback';
  static String get moveTime => isBangla ? 'চলার সময়' : 'Move Time';
  static String get stopTime => isBangla ? 'থামার সময়' : 'Stop Time';
  static String get topSpeed => isBangla ? 'সর্বোচ্চ গতি' : 'Top Speed';
  static String get distance => isBangla ? 'দূরত্ব' : 'Distance';
  static String get moving => isBangla ? 'চলছে' : 'Moving';
  static String get stopped => isBangla ? 'থেমেছে' : 'Stopped';
}

// ==================== FAST CAR ANIMATOR FOR PLAYBACK ====================
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
  Duration _lastElapsed = Duration.zero;

  double _speedMultiplier = 1.0;
  static const double _baseSpeed = 400.0;

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
    _speedMultiplier = multiplier.clamp(1.0, 32.0);
  }

  void moveTo(LatLng target, double bearing) {
    _targetPosition = target;
    _targetBearing = bearing;
    if (!_isRunning) {
      _isRunning = true;
      _lastElapsed = Duration.zero;
      _ticker?.start();
    }
  }

  void _onTick(Duration elapsed) {
    if (_targetPosition == null) { _stop(); return; }
    final rawDt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    final dt = rawDt.clamp(0.001, 0.1);
    final distance = _haversineMetres(_currentPosition, _targetPosition!);
    if (distance < 0.3) {
      _currentPosition = _targetPosition!;
      _currentBearing = _normBearing(_targetBearing);
      onPositionUpdate(_currentPosition, _currentBearing);
      _targetPosition = null;
      _stop();
      onAnimationComplete?.call();
      return;
    }
    final speed = _baseSpeed * _speedMultiplier;
    final moveRatio = ((speed * dt) / distance).clamp(0.0, 1.0);
    final newLat = _currentPosition.latitude +
        (_targetPosition!.latitude - _currentPosition.latitude) * moveRatio;
    final newLng = _currentPosition.longitude +
        (_targetPosition!.longitude - _currentPosition.longitude) * moveRatio;
    _currentPosition = LatLng(newLat, newLng);
    _currentBearing = _normBearing(_targetBearing);
    onPositionUpdate(_currentPosition, _currentBearing);
  }

  double _normBearing(double b) { b = b % 360; return b < 0 ? b + 360 : b; }

  double _haversineMetres(LatLng a, LatLng b) {
    const R = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  void updatePosition(LatLng position, double bearing) {
    _currentPosition = position;
    _currentBearing = bearing;
  }

  void _stop() {
    _isRunning = false;
    _ticker?.stop();
    _lastElapsed = Duration.zero;
  }

  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
  }
}

// ==================== DATE SELECTOR WIDGET (matches screenshot 1 & 2 bottom) ====================
class PlaybackDateSelector extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  const PlaybackDateSelector({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  State<PlaybackDateSelector> createState() => _PlaybackDateSelectorState();
}

class _PlaybackDateSelectorState extends State<PlaybackDateSelector> {
  late ScrollController _scrollController;
  late List<DateTime> _dates;
  late int _selectedIndex;

  static const double _itemWidth = 62.0;
  static const double _itemSpacing = 8.0;

  @override
  void initState() {
    super.initState();
    _buildDateList();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected(animated: false));
  }

  @override
  void didUpdateWidget(PlaybackDateSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      _buildDateList();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected(animated: true));
    }
  }

  void _buildDateList() {
    final today = DateTime.now();
    List<DateTime> dates = [];
    for (int i = 59; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      dates.add(DateTime(d.year, d.month, d.day));
    }
    _dates = dates;
    _selectedIndex = _dates.indexWhere((d) =>
    d.year == widget.selectedDate.year &&
        d.month == widget.selectedDate.month &&
        d.day == widget.selectedDate.day);
    if (_selectedIndex < 0) _selectedIndex = _dates.length - 1;
  }

  void _scrollToSelected({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    final offset = (_selectedIndex * (_itemWidth + _itemSpacing)) - 16.0;
    final clamped = offset.clamp(0.0, _scrollController.position.maxScrollExtent);
    if (animated) {
      _scrollController.animateTo(clamped,
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    } else {
      _scrollController.jumpTo(clamped);
    }
  }

  bool _isSelected(DateTime date) =>
      date.year == widget.selectedDate.year &&
          date.month == widget.selectedDate.month &&
          date.day == widget.selectedDate.day;

  bool _isToday(DateTime date) {
    final t = DateTime.now();
    return date.year == t.year && date.month == t.month && date.day == t.day;
  }

  String _dayLabel(DateTime date) {
    if (_isToday(date)) return PlaybackL10n.today;
    return DateFormat('EEE').format(date);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      color: Colors.white,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _dates.length,
        itemBuilder: (context, index) {
          final date = _dates[index];
          final selected = _isSelected(date);
          final today = _isToday(date);
          final dayLabel = _dayLabel(date);

          return GestureDetector(
            onTap: () {
              setState(() => _selectedIndex = index);
              widget.onDateSelected(date);
              _scrollToSelected(animated: true);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _itemWidth,
              margin: EdgeInsets.only(right: _itemSpacing),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFE53935)
                    : today
                    ? const Color(0xFFFFEBEE)
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFB71C1C)
                      : today
                      ? const Color(0xFFEF9A9A)
                      : Colors.grey[200]!,
                  width: selected ? 1.5 : 1,
                ),
                boxShadow: selected
                    ? [BoxShadow(
                    color: Colors.red.withValues(alpha: 0.3),
                    blurRadius: 8, offset: const Offset(0, 3))]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dayLabel,
                    style: TextStyle(
                      fontSize: dayLabel == PlaybackL10n.today ? 8 : 10,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : today
                          ? const Color(0xFFE53935)
                          : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : today ? const Color(0xFFB71C1C) : Colors.black87,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    DateFormat('MMM').format(date),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? Colors.white.withValues(alpha: 0.85)
                          : today
                          ? const Color(0xFFEF9A9A)
                          : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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

  Map<MarkerId, Marker> _playbackMarkers = <MarkerId, Marker>{};
  Map<MarkerId, Marker>? _eventMarkers;
  Map<MarkerId, Marker>? _parkingMarkers;

  final Set<Polyline> _playbackPolyLines = {};
  final Set<Polyline> _animatedPolyLines = {};

  // SMOOTH ANIMATION
  PlaybackCarAnimator? _carAnimator;
  Timer? _cameraFollowTimer;

  int _currentPointIndex = 0;
  bool _isPlaying = false;
  double _playbackProgress = 0.0;

  int _speedMultiplier = 1;
  String _speedText = "1x";

  BitmapDescriptor? _cachedCarIcon;
  bool _isIconLoaded = false;

  late DateTime _selectedDate;
  late DateTime _fromDate;
  late DateTime _toDate;

  // Controls whether we are in "date picker" mode (showing modal) or playback mode
  // State: 0 = showing bottom date bar (screen 2), 1 = after loading (screen 3)
  bool _hasLoadedData = false;

  bool _showParkingMarkers = true;
  bool _showEventMarkers = true;

  static const LatLng _defaultPosition = LatLng(23.8103, 90.4125);

  bool get _hasInitialDates =>
      widget.initialFromDate != null && widget.initialToDate != null;

  LatLng get _initialCameraPosition {
    if (widget.device?.lat != null && widget.device?.lng != null) {
      final lat = double.tryParse(widget.device!.lat.toString());
      final lng = double.tryParse(widget.device!.lng.toString());
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    return _defaultPosition;
  }

  @override
  void initState() {
    super.initState();
    _fromDate = widget.initialFromDate ?? DateTime.now();
    _toDate = widget.initialToDate ?? DateTime.now();
    _selectedDate = DateTime(_toDate.year, _toDate.month, _toDate.day);

    rootBundle.loadString('assets/map_style.txt').then((s) {
      _mapStyle = s;
    }).catchError((_) {});

    _loadCarIcon();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hasInitialDates) _loadPlaybackData();
    });
  }

  Future<void> _loadCarIcon() async {
    try {
      if (widget.device?.icon?.path != null) {
        _cachedCarIcon = await Util.getMarkerIcon(widget.device!.icon!.path!);
      }
      _cachedCarIcon ??= BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
      _isIconLoaded = true;
      if (mounted) setState(() {});
    } catch (_) {
      _cachedCarIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
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
    );
    _addCarMarker(playbackRoutePoints.first, 0);
  }

  void _onCarPositionUpdate(LatLng position, double bearing) {
    if (_isDisposed) return;
    _addCarMarker(position, bearing);
    _updateAnimatedPolyline(_currentPointIndex);
    if (mounted) setState(() {});
  }

  void _onCarReachedTarget() {
    if (!_isPlaying) return;
    _currentPointIndex++;
    _playbackProgress = _currentPointIndex.toDouble();
    if (_currentPointIndex >= playbackRoutePoints.length - 1) {
      _stopPlayback();
      _currentPointIndex = 0;
      _playbackProgress = 0;
      if (mounted) setState(() {});
      return;
    }
    _moveToNextPoint();
  }

  void _moveToNextPoint() {
    if (_currentPointIndex >= playbackRoutePoints.length - 1) return;
    if (_carAnimator == null) return;
    final nextIndex = (_currentPointIndex + 1).clamp(0, playbackRoutePoints.length - 1);
    final cur = playbackRoutePoints[_currentPointIndex];
    final nxt = playbackRoutePoints[nextIndex];
    final bearing = Geolocator.bearingBetween(cur.latitude, cur.longitude, nxt.latitude, nxt.longitude);
    _carAnimator!.setSpeedMultiplier(_speedMultiplier.toDouble());
    _carAnimator!.moveTo(nxt, bearing);
  }

  void _addCarMarker(LatLng position, double bearing) {
    final icon = (_isIconLoaded && _cachedCarIcon != null)
        ? _cachedCarIcon!
        : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    _playbackMarkers[const MarkerId('playback_car')] = Marker(
      markerId: const MarkerId('playback_car'),
      position: position,
      rotation: bearing,
      icon: icon,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      zIndex: 10,
    );
  }

  void _updateAnimatedPolyline(int currentIndex) {
    if (currentIndex < 0 || playbackRoutePoints.isEmpty) return;
    final trail = playbackRoutePoints.sublist(0, (currentIndex + 1).clamp(0, playbackRoutePoints.length));
    _animatedPolyLines
      ..clear()
      ..add(Polyline(
        polylineId: const PolylineId('animated_trail'),
        points: trail,
        width: 5,
        color: Colors.green,
        geodesic: true,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ));
  }

  void _startCameraFollowTimer() {
    _cameraFollowTimer?.cancel();
    _cameraFollowTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_isPlaying && _carAnimator != null && _mapController != null) {
        _mapController!.moveCamera(CameraUpdate.newLatLng(_carAnimator!.currentPosition));
      }
    });
  }

  Future<void> _safeAnimateCamera(CameraUpdate update) async {
    if (!mounted || _isDisposed || _mapController == null || !_isMapCreated) return;
    try { await _mapController!.animateCamera(update); } catch (_) {}
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cameraFollowTimer?.cancel();
    _carAnimator?.dispose();
    _isMapCreated = false;
    _mapController = null;
    super.dispose();
  }

  // ==================== DATE PICKER MODAL (matches screenshot 1) ====================
  void _showDatePickerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildDatePickerModal(),
    );
  }

  Widget _buildDatePickerModal() {
    return StatefulBuilder(builder: (context, setModalState) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 16,
          left: 16, right: 16, top: 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // From date & time
            Text(
              PlaybackL10n.fromDateTime,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final result = await _pickDateTime(_fromDate);
                if (result != null) setModalState(() => _fromDate = result);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  DateFormat('dd-MM-yyyy HH:mm:ss').format(_fromDate),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // To date & time
            Text(
              PlaybackL10n.toDateTime,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final result = await _pickDateTime(_toDate);
                if (result != null) setModalState(() => _toDate = result);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  DateFormat('dd-MM-yyyy HH:mm:ss').format(_toDate),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Apply button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadPlaybackData();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: Text(
                  PlaybackL10n.apply,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFFE53935))),
        child: child!,
      ),
    );
    if (date == null) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFFE53935))),
        child: child!,
      ),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void _onDateBarSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _fromDate = DateTime(date.year, date.month, date.day, 0, 0, 0);
      _toDate = DateTime(date.year, date.month, date.day, 23, 59, 59);
    });
    _loadPlaybackData();
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
    _hasLoadedData = false;
    _carAnimator?.dispose();
    _carAnimator = null;
    playbackMaxSpeed = "-";
    playbackTotalDistance = "-";
    playbackMoveDuration = "-";
    playbackStopDuration = "-";
  }

  void _loadPlaybackData() {
    if (widget.id == null) return;
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
        playbackMaxSpeed = value.top_speed ?? "0 kph";
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
              final element = el['items'].first;
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
                PlayBackRoute br = PlayBackRoute();
                br.device_id = element['device_id']?.toString();
                br.longitude = element['longitude']?.toString();
                br.latitude = element['latitude']?.toString();
                br.speed = element['speed'];
                br.course = element['course']?.toString();
                br.raw_time = element['raw_time']?.toString();
                br.speedType = "kph";
                final lat = double.tryParse(element['latitude'].toString());
                final lng = double.tryParse(element['longitude'].toString());
                if (lat != null && lng != null) {
                  playbackRoutePoints.add(LatLng(lat, lng));
                  routeList.add(br);
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
            width: 5,
            color: Colors.red.withValues(alpha: 0.8),
            geodesic: true,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ));
          await _addStartEndMarkers();
          _addParkingMarkers();
          _addEventMarkers();
          _initCarAnimator();
          _startCameraFollowTimer();
          _hasLoadedData = true;
        }
        setState(() => _isPlaybackLoading = false);
      } else {
        setState(() => _isPlaybackLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.info_outline, color: Colors.white),
              const SizedBox(width: 8),
              Text('${PlaybackL10n.noRecords}: ${DateFormat('dd MMM').format(_fromDate)}'),
            ]),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
      }
    }).catchError((error) {
      setState(() => _isPlaybackLoading = false);
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
      } catch (_) {}
      if (!mounted) return;
      _playbackMarkers[const MarkerId('start')] = Marker(
        markerId: const MarkerId('start'),
        position: playbackRoutePoints.first,
        icon: startIcon != null
            ? BitmapDescriptor.bytes(startIcon)
            : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Start'),
        zIndex: 1,
      );
      _playbackMarkers[const MarkerId('end')] = Marker(
        markerId: const MarkerId('end'),
        position: playbackRoutePoints.last,
        icon: endIcon != null
            ? BitmapDescriptor.bytes(endIcon)
            : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'End'),
        zIndex: 1,
      );
      double minLat = playbackRoutePoints.first.latitude, maxLat = playbackRoutePoints.first.latitude;
      double minLng = playbackRoutePoints.first.longitude, maxLng = playbackRoutePoints.first.longitude;
      for (var p in playbackRoutePoints) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      await _safeAnimateCamera(CameraUpdate.newLatLngBounds(
          LatLngBounds(
              southwest: LatLng(minLat, minLng),
              northeast: LatLng(maxLat, maxLng)),
          80));
      setState(() {});
    } catch (_) {}
  }

  Future<BitmapDescriptor> _createCircleMarker(String text, Color color) async {
    const size = 36.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(size / 2, size / 2);
    canvas.drawCircle(Offset(center.dx + 1, center.dy + 1), size / 2 - 4, Paint()..color = Colors.black26);
    canvas.drawCircle(center, size / 2 - 4, Paint()..color = color);
    canvas.drawCircle(center, size / 2 - 4,
        Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
    final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
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
          markerId: id, position: LatLng(lat, lng), icon: icon,
          anchor: const Offset(0.5, 0.5), zIndex: 2);
      if (_showParkingMarkers) _playbackMarkers[id] = _parkingMarkers![id]!;
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
          markerId: id, position: LatLng(lat, lng), icon: icon,
          anchor: const Offset(0.5, 0.5), zIndex: 2);
      if (_showEventMarkers) _playbackMarkers[id] = _eventMarkers![id]!;
      index++;
    }
    if (mounted) setState(() {});
  }

  // ==================== PLAYBACK CONTROLS ====================
  void _togglePlayPause() {
    if (playbackRoutePoints.isEmpty || _carAnimator == null) return;
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

  void _stopPlayback() => setState(() => _isPlaying = false);

  void _changeSpeed() {
    setState(() {
      switch (_speedMultiplier) {
        case 1: _speedMultiplier = 2; _speedText = "2x"; break;
        case 2: _speedMultiplier = 4; _speedText = "4x"; break;
        case 4: _speedMultiplier = 8; _speedText = "8x"; break;
        case 8: _speedMultiplier = 16; _speedText = "16x"; break;
        default: _speedMultiplier = 1; _speedText = "1x";
      }
    });
    _carAnimator?.setSpeedMultiplier(_speedMultiplier.toDouble());
  }

  void _seekTo(double value) {
    final index = value.toInt().clamp(0, playbackRoutePoints.length - 1);
    _currentPointIndex = index;
    _playbackProgress = value;
    if (index < playbackRoutePoints.length) {
      final pos = playbackRoutePoints[index];
      _carAnimator?.updatePosition(pos, _carAnimator!.currentBearing);
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
        elevation: 0.5,
        shadowColor: Colors.black12,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.name ?? 'Unknown',
          style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Language toggle
          GestureDetector(
            onTap: () => setState(() => PlaybackL10n.isBangla = !PlaybackL10n.isBangla),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Text(
                PlaybackL10n.isBangla ? 'EN' : 'বাং',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black54),
              ),
            ),
          ),
          // Calendar icon button
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined, color: Colors.black54, size: 24),
            onPressed: _showDatePickerModal,
            tooltip: 'Date Range',
          ),
        ],
      ),
      body: Stack(children: [
        // MAP
        Positioned.fill(
          child: GoogleMap(
            mapType: _currentMapType,
            initialCameraPosition: CameraPosition(target: _initialCameraPosition, zoom: 14),
            onMapCreated: (controller) {
              _mapController = controller;
              _isMapCreated = true;
              if (_mapStyle != null) controller.setMapStyle(_mapStyle);
            },
            onCameraMove: (pos) => currentZoom = pos.zoom,
            markers: Set<Marker>.of(_playbackMarkers.values),
            polylines: {
              ..._playbackPolyLines,
              ..._animatedPolyLines,
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            buildingsEnabled: false,
            // Reserve space for bottom panel
            padding: EdgeInsets.only(bottom: _hasLoadedData ? 260 : 100),
          ),
        ),

        // Loading overlay
        if (_isPlaybackLoading)
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(strokeWidth: 3, color: Color(0xFFE53935)),
                  const SizedBox(height: 12),
                  Text(PlaybackL10n.loading, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                ]),
              ),
            ),
          ),

        // Map controls (top right)
        if (!_isPlaybackLoading)
          Positioned(
            top: 12,
            right: 12,
            child: Column(children: [
              _mapBtn(Icons.layers, () {
                setState(() {
                  _currentMapType = _currentMapType == MapType.normal ? MapType.hybrid : MapType.normal;
                });
              }),
              const SizedBox(height: 6),
              _mapBtn(Icons.add, () => _safeAnimateCamera(CameraUpdate.zoomIn())),
              const SizedBox(height: 4),
              _mapBtn(Icons.remove, () => _safeAnimateCamera(CameraUpdate.zoomOut())),
              if (playbackRoutePoints.isNotEmpty) ...[
                const SizedBox(height: 6),
                _mapBtn(Icons.my_location, () {
                  if (_carAnimator != null) {
                    _safeAnimateCamera(CameraUpdate.newLatLngZoom(_carAnimator!.currentPosition, 16));
                  }
                }),
              ],
            ]),
          ),

        // Marker toggles (bottom left, above bottom panel)
        if (playbackRoutePoints.isNotEmpty && !_isPlaybackLoading)
          Positioned(
            bottom: _hasLoadedData ? 270 : 110,
            left: 10,
            child: _buildMarkerToggles(),
          ),

        // BOTTOM PANEL
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _hasLoadedData ? _buildPlaybackBottomPanel() : _buildDateOnlyBottomPanel(),
        ),
      ]),
    );
  }

  Widget _mapBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 18, color: Colors.grey[700]),
        ),
      ),
    );
  }

  Widget _buildMarkerToggles() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _toggleChip('P', parkingPoints.length, Colors.blue, _showParkingMarkers, _toggleParkingMarkers),
        const SizedBox(width: 6),
        _toggleChip('A', eventsPoints.length, Colors.red, _showEventMarkers, _toggleEventMarkers),
      ]),
    );
  }

  Widget _toggleChip(String label, int count, Color color, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? color : Colors.grey[300]!),
        ),
        child: Row(children: [
          Container(
            width: 16, height: 16,
            decoration: BoxDecoration(color: active ? color : Colors.grey, shape: BoxShape.circle),
            child: Center(
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 4),
          Text('$count', style: TextStyle(color: active ? color : Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ==================== DATE ONLY BOTTOM (Screen 2) ====================
  Widget _buildDateOnlyBottomPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          PlaybackDateSelector(
            selectedDate: _selectedDate,
            onDateSelected: _onDateBarSelected,
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  // ==================== PLAYBACK BOTTOM PANEL (Screen 3) ====================
  Widget _buildPlaybackBottomPanel() {
    final maxValue = (playbackRoutePoints.length - 1).toDouble().clamp(0.0, double.infinity);
    final currentValue = _playbackProgress.clamp(0.0, maxValue);
    final currentSpeed = (routeList.isNotEmpty && _playbackProgress.toInt() < routeList.length)
        ? '${routeList[_playbackProgress.toInt().clamp(0, routeList.length - 1)].speed ?? 0}'
        : '0';
    final currentTime = (routeList.isNotEmpty && _playbackProgress.toInt() < routeList.length)
        ? routeList[_playbackProgress.toInt().clamp(0, routeList.length - 1)].raw_time ?? ''
        : '';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // Play controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // Play/pause + speed row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Play/Pause large red button (matches screenshot 3)
                    GestureDetector(
                      onTap: _togglePlayPause,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFE53935),
                        ),
                        child: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Slider (matches screenshot 3)
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                          activeTrackColor: const Color(0xFF1565C0),
                          inactiveTrackColor: Colors.grey[300],
                          thumbColor: const Color(0xFF1565C0),
                          overlayColor: const Color(0x201565C0),
                        ),
                        child: Slider(
                          value: currentValue,
                          min: 0,
                          max: maxValue > 0 ? maxValue : 1,
                          onChanged: _seekTo,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Speed button
                    GestureDetector(
                      onTap: _changeSpeed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Text(_speedText,
                            style: const TextStyle(
                                color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 2),

                // Current time display
                if (currentTime.isNotEmpty)
                  Text(
                    Util.formatOnlyTimeAMPM(currentTime),
                    style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w600),
                  ),

                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // Stats row (matches screenshot 3: time, speed, distance, move, stop, top speed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // _statCard এর পরিবর্তে সরাসরি Column দিন
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time_outlined, color: Colors.orange, size: 18),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd-MM-yy').format(_fromDate),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      // ✅ currentTime থেকে time নিন, _fromDate থেকে না
                      currentTime.isNotEmpty
                          ? Util.formatOnlyTimeAMPM(currentTime)
                          : DateFormat('HH:mm:ss').format(_fromDate),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                _statCard(
                  icon: Icons.speed_outlined,
                  iconColor: Colors.blue,
                  value: '$currentSpeed Km/h',
                  label: null,
                  fontSize: 13,
                ),
                _statCard(
                  icon: Icons.route_outlined,
                  iconColor: Colors.green,
                  value: playbackTotalDistance,
                  label: null,
                  fontSize: 13,
                ),
              ],
            ),
          ),


          const SizedBox(height: 8),
          const Divider(height: 1, indent: 12, endIndent: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statLabelCard(
                  icon: Icons.directions_walk,
                  iconColor: Colors.green,
                  value: playbackMoveDuration,
                  label: PlaybackL10n.moveTime,
                ),
                _statLabelCard(
                  icon: Icons.timer_off_outlined,
                  iconColor: Colors.red,
                  value: playbackStopDuration,
                  label: PlaybackL10n.stopTime,
                ),
                _statLabelCard(
                  icon: Icons.speed,
                  iconColor: Colors.blue,
                  value: playbackMaxSpeed,
                  label: PlaybackL10n.topSpeed,
                ),
              ],
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 4),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    String? label,
    double fontSize = 12,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        if (label != null) ...[
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
        ],
      ],
    );
  }

  Widget _statLabelCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
      ],
    );
  }
}