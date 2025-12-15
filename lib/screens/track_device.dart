import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:ui' as ui;
import 'dart:math' as m;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gpspro/config.dart';
import 'package:gpspro/arguments/device_args.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/flutter_flow/flutter_flow_widgets.dart';
import 'package:gpspro/screens/lock_unlock_screen.dart';
import 'package:gpspro/screens/report/get_today_report.dart';
import 'package:gpspro/screens/street_view_screen.dart';
import 'package:gpspro/services/admob_service.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/services/model/playback_route.dart';
import 'package:gpspro/services/model/share_perm.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/util/util.dart';
import 'package:gpspro/widgets/address.dart';
import 'package:gpspro/widgets/banner_ad_widget.dart';
import 'package:gpspro/widgets/bloc/custom_info_widget.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speedometer_chart/speedometer_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_math/vector_math.dart' as v;
import 'package:flutter/material.dart' as m;

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
  Animation<double>? _animation;

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
  bool showAddress = false;

  // PLAYBACK MODE VARIABLES
  bool _isPlaybackMode = false;
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

  AnimationController? _playbackAnimationController;
  double playbackRating = 0.0;
  int upperAnimatingPointsIndex = 1;
  int lowerAnimatingPointsIndex = 0;
  double baseTimeForMapAnimation = 0.0;
  double deltaTimeForMapAnimation = 5 / 60;
  bool cameraIdle = true;

  bool isPlay = false;
  String speedText = "1x";
  int speedStep = 1;
  int animationSpeed = 1000;

  DateTime playbackDateTimeFrom = DateTime.now();
  DateTime playbackDateTimeTo = DateTime.now();

  bool isPointActive = true;
  bool isAlertActive = true;

  Window? playbackWindow;
  bool showPlaybackWindow = false;
  LatLng previousLatLng = const LatLng(0.0, 0.0);
  LatLng currentLatLng = const LatLng(0.0, 0.0);

  // Draggable sheet controller
  final DraggableScrollableController _sheetController =
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
    });

    _initPlaybackAnimation();
    _initTrackingData();
  }

  void _initTrackingData() {
    drawPolyline();
    drawPolyline2();

    Timer startTimer(Function() callback) {
      callback();
      return Timer.periodic(const Duration(seconds: 20), (timer) => callback());
    }

    _todayKmTimer = startTimer(getTodayKm);
    _todayDetailsTimer = startTimer(getTodayDetails);
  }

  void _initPlaybackAnimation() {
    playbackDateTimeFrom = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    playbackDateTimeTo = DateTime.now();

    _playbackAnimationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: animationSpeed),
    );

    _playbackAnimationController!.addListener(_onPlaybackAnimationUpdate);
    _playbackAnimationController!.addStatusListener(_onPlaybackAnimationStatus);
  }

  void _onPlaybackAnimationUpdate() async {
    if (!mounted || _isDisposed) return;
    if (playbackRoutePoints.isEmpty) return;
    if (upperAnimatingPointsIndex >= playbackRoutePoints.length) return;
    if (lowerAnimatingPointsIndex >= playbackRoutePoints.length) return;

    baseTimeForMapAnimation = 0.0;

    LatLng start = playbackRoutePoints[lowerAnimatingPointsIndex];
    LatLng end = playbackRoutePoints[upperAnimatingPointsIndex];

    if (baseTimeForMapAnimation <= 1) {
      if (start.latitude != end.latitude && start.longitude != end.longitude) {
        double intermediateLat = (end.latitude - start.latitude) *
            (baseTimeForMapAnimation *
                baseTimeForMapAnimation *
                (3.0 - 2.0 * baseTimeForMapAnimation)) +
            start.latitude;
        double intermediateLon = (end.longitude - start.longitude) *
            (baseTimeForMapAnimation *
                baseTimeForMapAnimation *
                (3.0 - 2.0 * baseTimeForMapAnimation)) +
            start.longitude;

        MarkerId markerId = const MarkerId('playbackAnimatingMarker');
        LatLng intermediateLatLng = LatLng(intermediateLat, intermediateLon);
        double bearing = Geolocator.bearingBetween(
          intermediateLat,
          intermediateLon,
          end.latitude,
          end.longitude,
        );

        try {
          await Util.fetchAndCacheImages(
            "${UserRepository.getServerUrl()!}/${widget.device!.icon!.path!}",
          );

          BitmapDescriptor markerIcon = await Util.getMarkerIcon(
            widget.device!.icon!.path!,
          );

          if (!mounted || _isDisposed) return;

          Marker animatingMarker = Marker(
            markerId: markerId,
            anchor: const Offset(0.5, 0.5),
            position: intermediateLatLng,
            rotation: bearing,
            icon: markerIcon,
          );

          _playbackMarkers[markerId] = animatingMarker;
          playbackRating = upperAnimatingPointsIndex.toDouble();

          if (mounted && cameraIdle && _isMapCreated) {
            await _safeAnimateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: intermediateLatLng,
                  zoom: currentZoom,
                ),
              ),
            );

            if (mounted) {
              setState(() {
                cameraIdle = false;
              });
            }

            baseTimeForMapAnimation += deltaTimeForMapAnimation;
          }
        } catch (e) {
          debugPrint('Error in playback animation: $e');
        }
      }
    }
  }

  void _onPlaybackAnimationStatus(AnimationStatus status) {
    if (!mounted || _isDisposed) return;

    if (status == AnimationStatus.completed) {
      if (upperAnimatingPointsIndex >= playbackRoutePoints.length - 1) {
        _playbackAnimationController?.reset();
        upperAnimatingPointsIndex = 1;
        lowerAnimatingPointsIndex = 0;
        speedStep = 1;
        speedText = "1x";
        isPlay = false;
        if (mounted) setState(() {});
        return;
      } else {
        lowerAnimatingPointsIndex = upperAnimatingPointsIndex;
        upperAnimatingPointsIndex = upperAnimatingPointsIndex + speedStep;

        if (upperAnimatingPointsIndex >= playbackRoutePoints.length - 1) {
          upperAnimatingPointsIndex = playbackRoutePoints.length - 1;
        }

        _playbackAnimationController?.reset();
        _playbackAnimationController?.forward();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _todayKmTimer?.cancel();
    _todayDetailsTimer?.cancel();

    if (!_mapMarkerSC.isClosed) {
      _mapMarkerSC.close();
    }

    _playbackAnimationController?.dispose();
    _sheetController.dispose();
    _isMapCreated = false;
    _mapController = null;

    super.dispose();
  }

  // TRACKING DATA METHODS
  void getTodayKm() {
    if (!mounted || _isDisposed || _isPlaybackMode) return;

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
      if (value != null && mounted && !_isDisposed && !_isPlaybackMode) {
        setState(() {
          todaytotalDistance = value.distance_sum ?? "0";
          fuelConsumption = value.fuel_consumption ?? '0';
        });
      }
    }).whenComplete(() {
      if (mounted && !_isDisposed && !_isPlaybackMode) {
        _todayKmTimer = Timer(const Duration(seconds: 20), getTodayKm);
      }
    });
  }

  void getTodayDetails() async {
    if (!mounted || _isDisposed || _isPlaybackMode) return;

    try {
      final value = await ReportService.getTodayReportData(
        deviceId: widget.device?.id ?? 0,
      );

      if (mounted && !_isDisposed && !_isPlaybackMode) {
        setState(() {
          todayData = value;
        });
      }
    } catch (error) {
      log("Error fetching today's data: $error");
    } finally {
      if (mounted && !_isDisposed && !_isPlaybackMode) {
        _todayDetailsTimer =
            Timer(const Duration(seconds: 20), getTodayDetails);
      }
    }
  }

  void drawPolyline2() async {
    if (!mounted || _isDisposed) return;
    PolylineId id = const PolylineId("polyAnim");
    Polyline polyline = Polyline(
      width: 3,
      polylineId: id,
      color: Colors.blueAccent,
      points: newPolylinesData,
    );
    polylines[id] = polyline;
    if (mounted) setState(() {});
  }

  void drawPolyline() async {
    if (!mounted || _isDisposed) return;
    PolylineId id = const PolylineId("poly");
    Polyline polyline = Polyline(
      width: 3,
      polylineId: id,
      color: Colors.blue,
      points: polylineCoordinates,
    );
    polylines[id] = polyline;
    if (mounted) setState(() {});
  }

  void updateMarker(DeviceItem element) async {
    if (_isPlaybackMode || !mounted || _isDisposed) return;

    try {
      await Util.fetchAndCacheImages(
        UserRepository.getServerUrl()! + "/" + element.icon!.path!,
      );

      BitmapDescriptor markerIcon;
      bool rotation = true;

      if (element.iconType == "arrow") {
        rotation = true;
        markerIcon = await Util.getMarkerIcon(element.icon!.path!);
      } else if (element.icon!.path!.contains("v2")) {
        rotation = element.iconType == "rotating";
        markerIcon = await Util.getMarkerIcon(element.icon!.path!);
      } else {
        rotation = element.iconType == "rotating";
        markerIcon = await Util.getMarkerIcon(element.icon!.path!);
      }

      if (!mounted || _isDisposed) return;

      var pinPosition = LatLng(
        double.parse(element.lat.toString()),
        double.parse(element.lng.toString()),
      );

      if (first) {
        CameraPosition cPosition = CameraPosition(
          target: pinPosition,
          zoom: currentZoom,
        );

        final pickupMarker = Marker(
          markerId: const MarkerId("driverMarker"),
          position: pinPosition,
          rotation: rotation ? double.parse(element.course.toString()) : 0,
          icon: markerIcon,
        );

        await Future.delayed(const Duration(milliseconds: 500));

        if (!mounted || _isDisposed) return;

        _markers.add(pickupMarker);
        if (!_mapMarkerSC.isClosed) {
          _mapMarkerSink.add(_markers);
        }

        oldPin = pinPosition;

        await _safeMoveCamera(CameraUpdate.newCameraPosition(cPosition));

        isLoading = false;
        first = false;
      }

      if (!first && oldPin != null && oldPin != pinPosition) {
        Future.delayed(const Duration(seconds: 5)).then((value) {
          if (mounted &&
              !_isDisposed &&
              _mapController != null &&
              _isMapCreated) {
            animateCar(
              oldPin!.latitude,
              oldPin!.longitude,
              double.parse(element.lat.toString()),
              double.parse(element.lng.toString()),
              _mapMarkerSink,
              this,
              markerIcon,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Error updating marker: $e');
    }
  }

  // PLAYBACK METHODS
  void _enterPlaybackMode() {
    _todayKmTimer?.cancel();
    _todayDetailsTimer?.cancel();

    setState(() {
      _isPlaybackMode = true;
    });

    _showPlaybackDateDialog();
  }

  void _exitPlaybackMode() {
    _playbackAnimationController?.stop();
    _playbackAnimationController?.reset();

    _clearPlaybackData();

    setState(() {
      _isPlaybackMode = false;
      isPlay = false;
      speedStep = 1;
      speedText = "1x";
      playbackRating = 0.0;
    });

    _initTrackingData();
  }

  void _clearPlaybackData() {
    routeList.clear();
    playbackRoutePoints.clear();
    parkingPoints.clear();
    eventsPoints.clear();
    bottomRouteList.clear();
    _playbackMarkers.clear();
    _playbackPolyLines.clear();
    _parkingMarkers = null;
    _eventMarkers = null;
    playbackRating = 0;
    upperAnimatingPointsIndex = 1;
    lowerAnimatingPointsIndex = 0;
  }

  void _showPlaybackDateDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildDatePickerSheet(),
    );
  }

  Widget _buildDatePickerSheet() {
    return StatefulBuilder(
      builder: (context, setModalState) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'selectDateRange'.tr,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                      if (playbackRoutePoints.isEmpty) {
                        _exitPlaybackMode();
                      }
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'quickSelect'.tr,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildQuickSelectButton('today'.tr, Icons.today, Colors.blue,
                          () {
                        setModalState(() {
                          playbackDateTimeFrom = DateTime.now().subtract(Duration(
                            hours: DateTime.now().hour,
                            minutes: DateTime.now().minute,
                            seconds: DateTime.now().second,
                          ));
                          playbackDateTimeTo = DateTime.now();
                        });
                        Navigator.pop(context);
                        _fetchPlaybackData();
                      }),
                  const SizedBox(width: 10),
                  _buildQuickSelectButton(
                      'yesterday'.tr, Icons.history, Colors.orange, () {
                    setModalState(() {
                      playbackDateTimeFrom = DateTime.now().subtract(Duration(
                        days: 1,
                        hours: DateTime.now().hour,
                        minutes: DateTime.now().minute,
                        seconds: DateTime.now().second,
                      ));
                      playbackDateTimeTo = DateTime.now().subtract(Duration(
                        hours: DateTime.now().hour,
                        minutes: DateTime.now().minute,
                        seconds: DateTime.now().second,
                      ));
                    });
                    Navigator.pop(context);
                    _fetchPlaybackData();
                  }),
                  const SizedBox(width: 10),
                  _buildQuickSelectButton(
                      'thisWeek'.tr, Icons.date_range, Colors.green, () {
                    setModalState(() {
                      playbackDateTimeFrom = DateTime.now().subtract(Duration(
                        days: 7,
                        hours: DateTime.now().hour,
                        minutes: DateTime.now().minute,
                        seconds: DateTime.now().second,
                      ));
                      playbackDateTimeTo = DateTime.now();
                    });
                    Navigator.pop(context);
                    _fetchPlaybackData();
                  }),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),
              Text(
                'customRange'.tr,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 15),
              _buildDateTimeSelector(
                  'from'.tr, playbackDateTimeFrom, Icons.play_arrow,
                  Colors.green, () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: playbackDateTimeFrom,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(playbackDateTimeFrom),
                  );
                  if (time != null) {
                    setModalState(() {
                      playbackDateTimeFrom = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  }
                }
              }),
              const SizedBox(height: 15),
              _buildDateTimeSelector(
                  'to'.tr, playbackDateTimeTo, Icons.stop, Colors.red,
                      () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: playbackDateTimeTo,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(playbackDateTimeTo),
                      );
                      if (time != null) {
                        setModalState(() {
                          playbackDateTimeTo = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      }
                    }
                  }),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _fetchPlaybackData();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CustomColor.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_circle_outline, color: Colors.white),
                      const SizedBox(width: 10),
                      Text(
                        'loadPlayback'.tr,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickSelectButton(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateTimeSelector(String label, DateTime dateTime, IconData icon,
      Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('dd MMM yyyy, HH:mm').format(dateTime),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_calendar, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _fetchPlaybackData() {
    _clearPlaybackData();

    setState(() {
      _isPlaybackLoading = true;
    });

    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SpinKitRing(
                lineWidth: 3.0,
                color: CustomColor.primaryColor,
                size: 40.0,
              ),
              const SizedBox(height: 20),
              Text(
                'loadingPlayback'.tr,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    APIService.getHistory(
      widget.id.toString(),
      Util.formatReportDate(playbackDateTimeFrom),
      Util.formatReportTime(playbackDateTimeFrom),
      Util.formatReportDate(playbackDateTimeTo),
      Util.formatReportTime(playbackDateTimeTo),
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

            var element = el['items'].first;
            if (element['latitude'] != null) {
              rt.device_id = element['device_id'].toString();
              rt.longitude = element['longitude'].toString();
              rt.latitude = element['latitude'].toString();
              rt.speed = element['speed'];
              rt.course = element['course'].toString();
              rt.raw_time = element['raw_time'].toString();
              rt.speedType = "kph";
              rt.id = element["id"].toString();
            }
            bottomRouteList.add(rt);
          }

          if (el["status"] == 1) {
            parkingPoints.add(el['items']);
          }

          if (el["status"] == 5) {
            eventsPoints.add(el['items']);
          }

          el['items'].forEach((element) {
            if (element['latitude'] != null) {
              PlayBackRoute blackRoute = PlayBackRoute();
              blackRoute.device_id = element['device_id'].toString();
              blackRoute.longitude = element['longitude'].toString();
              blackRoute.latitude = element['latitude'].toString();
              blackRoute.speed = element['speed'];
              blackRoute.course = element['course'].toString();
              blackRoute.raw_time = element['raw_time'].toString();
              blackRoute.speedType = "kph";

              playbackRoutePoints.add(LatLng(
                double.parse(element['latitude'].toString()),
                double.parse(element['longitude'].toString()),
              ));
              routeList.add(blackRoute);
            }
          });
        }

        _playbackPolyLines.add(Polyline(
          polylineId: const PolylineId('playback_route'),
          visible: true,
          points: playbackRoutePoints,
          width: 4,
          color: const Color(0xFFF26611),
        ));

        await _addPlaybackMarkersAndFitBounds();
        _setPlaybackParkingMarkers();
        _setPlaybackEventsMarkers();

        if (mounted && !_isDisposed) {
          setState(() {
            _isPlaybackLoading = false;
          });
        }
      } else {
        if (mounted && !_isDisposed) {
          setState(() {
            _isPlaybackLoading = false;
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('noRecords'.tr),
            backgroundColor: Colors.orange,
          ),
        );

        _exitPlaybackMode();
      }
    }).catchError((error) {
      if (Navigator.canPop(context)) Navigator.pop(context);

      if (mounted && !_isDisposed) {
        setState(() {
          _isPlaybackLoading = false;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('errorLoadingData'.tr),
          backgroundColor: Colors.red,
        ),
      );

      _exitPlaybackMode();
    });
  }

  Future<void> _addPlaybackMarkersAndFitBounds() async {
    if (routeList.isEmpty || !mounted || _isDisposed) return;

    double? x0, x1, y0, y1;

    for (int i = 0; i < routeList.length; i++) {
      LatLng latLng = LatLng(
        double.parse(routeList[i].latitude!),
        double.parse(routeList[i].longitude!),
      );

      if (x0 == null) {
        x0 = x1 = latLng.latitude;
        y0 = y1 = latLng.longitude;
      } else {
        if (latLng.latitude > x1!) x1 = latLng.latitude;
        if (latLng.latitude < x0) x0 = latLng.latitude;
        if (latLng.longitude > y1!) y1 = latLng.longitude;
        if (latLng.longitude < y0!) y0 = latLng.longitude;
      }
    }

    LatLngBounds bounds = LatLngBounds(
      northeast: LatLng(x1 ?? 0, y1 ?? 0),
      southwest: LatLng(x0 ?? 0, y0 ?? 0),
    );

    await _setPlaybackStartEndMarkers(
      LatLng(double.parse(routeList.first.latitude!),
          double.parse(routeList.first.longitude!)),
      LatLng(double.parse(routeList.last.latitude!),
          double.parse(routeList.last.longitude!)),
      bounds,
    );
  }

  Future<void> _setPlaybackStartEndMarkers(
      LatLng start, LatLng end, LatLngBounds bounds) async {
    if (!mounted || _isDisposed) return;

    try {
      final Uint8List? startIcon = await Util.getBytesFromAsset(
        'assets/images/map-start-point.png',
        40,
      );
      final Uint8List? endIcon = await Util.getBytesFromAsset(
        'assets/images/map-end-point.png',
        40,
      );

      if (!mounted || _isDisposed) return;

      Marker startMarker = Marker(
        markerId: const MarkerId('playback_start'),
        position: start,
        icon: BitmapDescriptor.bytes(startIcon!),
        infoWindow: InfoWindow(title: 'startPoint'.tr),
      );

      Marker endMarker = Marker(
        markerId: const MarkerId('playback_end'),
        position: end,
        icon: BitmapDescriptor.bytes(endIcon!),
        infoWindow: InfoWindow(title: 'endPoint'.tr),
      );

      _playbackMarkers[const MarkerId('playback_start')] = startMarker;
      _playbackMarkers[const MarkerId('playback_end')] = endMarker;

      if (mounted && !_isDisposed && _isMapCreated) {
        await _safeAnimateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error setting start/end markers: $e');
    }
  }

  void _setPlaybackParkingMarkers() async {
    if (!mounted || _isDisposed) return;

    try {
      if (_parkingMarkers == null) {
        _parkingMarkers = <MarkerId, Marker>{};
        final Uint8List? parkingIcon = await Util.getBytesFromAsset(
          'assets/images/map-point.png',
          30,
        );

        if (!mounted || _isDisposed) return;

        for (var element in parkingPoints) {
          var markerId = MarkerId('stop${element[0]["id"]}');

          Map<String, String> data = {};
          data["Object"] = widget.name ?? "";
          data["Position"] =
          "${element[0]["latitude"]}, ${element[0]["longitude"]}";
          data["Duration"] = element[0]["time"] ?? "";

          Marker marker = Marker(
            markerId: markerId,
            onTap: () => _onPlaybackMarkerTap(
              LatLng(element[0]["latitude"], element[0]["longitude"]),
              data,
            ),
            position: LatLng(element[0]["latitude"], element[0]["longitude"]),
            icon: BitmapDescriptor.bytes(parkingIcon!),
          );

          _parkingMarkers![markerId] = marker;
          _playbackMarkers[markerId] = marker;
        }
      } else {
        _playbackMarkers.addAll(_parkingMarkers!);
      }

      if (mounted && !_isDisposed) setState(() {});
    } catch (e) {
      debugPrint('Error setting parking markers: $e');
    }
  }

  void _setPlaybackEventsMarkers() async {
    if (!mounted || _isDisposed) return;

    try {
      if (_eventMarkers == null) {
        _eventMarkers = <MarkerId, Marker>{};
        final Uint8List? eventIcon = await Util.getBytesFromAsset(
          'assets/images/map-alert-point.png',
          30,
        );

        if (!mounted || _isDisposed) return;

        for (var element in eventsPoints) {
          var markerId = MarkerId('event${element[0]["id"]}');

          Map<String, String> data = {};
          data["Object"] = widget.name ?? "";
          data["Event"] = element[0]["event"] ?? "";
          data["Speed"] = "${element[0]["speed"]} kph";
          data["Time"] = element[0]["time"] ?? "";

          var marker = Marker(
            markerId: markerId,
            onTap: () => _onPlaybackMarkerTap(
              LatLng(
                double.parse(element[0]["lat"].toString()),
                double.parse(element[0]["lng"].toString()),
              ),
              data,
            ),
            position: LatLng(
              double.parse(element[0]["lat"].toString()),
              double.parse(element[0]["lng"].toString()),
            ),
            icon: BitmapDescriptor.bytes(eventIcon!),
          );

          _eventMarkers![markerId] = marker;
          _playbackMarkers[markerId] = marker;
        }
      } else {
        _playbackMarkers.addAll(_eventMarkers!);
      }

      if (mounted && !_isDisposed) setState(() {});
    } catch (e) {
      debugPrint('Error setting event markers: $e');
    }
  }

  void _onPlaybackMarkerTap(LatLng location, Map<String, String> data) async {
    if (!mounted || _isDisposed) return;

    CameraPosition cameraPosition = CameraPosition(
      target: location,
      zoom: currentZoom,
    );

    await _safeAnimateCamera(CameraUpdate.newCameraPosition(cameraPosition));

    previousLatLng = currentLatLng;
    currentLatLng = location;

    playbackWindow = Window(offsetX: 65, offsetY: 220, data: data);

    if (mounted && !_isDisposed) {
      setState(() {
        if (currentLatLng == previousLatLng) {
          showPlaybackWindow = !showPlaybackWindow;
        } else {
          showPlaybackWindow = true;
        }
      });
    }
  }

  void _toggleParkingMarkers() {
    if (!mounted || _isDisposed) return;

    isPointActive = !isPointActive;

    if (!isPointActive) {
      for (var element in parkingPoints) {
        _playbackMarkers.remove(MarkerId('stop${element[0]["id"]}'));
      }
    } else {
      _setPlaybackParkingMarkers();
    }

    setState(() {});
  }

  void _toggleEventMarkers() {
    if (!mounted || _isDisposed) return;

    isAlertActive = !isAlertActive;

    if (!isAlertActive) {
      for (var element in eventsPoints) {
        _playbackMarkers.remove(MarkerId('event${element[0]["id"]}'));
      }
    } else {
      _setPlaybackEventsMarkers();
    }

    setState(() {});
  }

  void _playPausePlayback() {
    if (!mounted || _isDisposed) return;

    setState(() {
      isPlay = !isPlay;
    });

    if (_playbackAnimationController!.isAnimating) {
      _playbackAnimationController!.stop(canceled: true);
      return;
    }

    _playbackAnimationController!.forward();
  }

  void _changePlaybackSpeed() {
    if (!mounted || _isDisposed) return;

    setState(() {
      if (speedStep == 1) {
        speedStep = 3;
        speedText = "2x";
        animationSpeed = 700;
      } else if (speedStep == 3) {
        speedStep = 5;
        speedText = "3x";
        animationSpeed = 400;
      } else if (speedStep == 5) {
        speedStep = 8;
        speedText = "5x";
        animationSpeed = 200;
      } else {
        speedStep = 1;
        speedText = "1x";
        animationSpeed = 1000;
      }
    });

    _playbackAnimationController!.duration =
        Duration(milliseconds: animationSpeed);
  }

  // MAP CONTROLS
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

  // Show tracking info bottom sheet
  void _showTrackingInfoBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildTrackingInfoSheet(),
    );
  }

  Widget _buildTrackingInfoSheet() {
    Color? color;
    if (device?.iconColor == "green") {
      color = Colors.green;
    } else if (device?.iconColor == "yellow") {
      color = Colors.yellow.shade700;
    } else {
      color = Colors.red;
    }

    double fontWidth = MediaQuery.of(context).size.aspectRatio;
    double iconWidth = 30;
    List<Widget> sensors = [];

    try {
      for (var sensor in device!.sensors!) {
        if (sensor['value'] != null) {
          sensors.add(Card(
            elevation: 1,
            shadowColor: color,
            child: Container(
              padding: const EdgeInsets.all(5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    "assets/images/sensors/${sensor['type']}.png",
                    width: iconWidth,
                    height: iconWidth,
                  ),
                  const SizedBox(width: 4),
                  Column(
                    children: [
                      Text(sensor["name"],
                          style: TextStyle(fontSize: fontWidth * 19)),
                      const SizedBox(height: 2),
                      Text(
                        gsmCodeConvert(sensor['value']),
                        style: TextStyle(fontSize: fontWidth * 19),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ));
        }
      }
    } catch (e) {}

    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(15, 15, 15, 5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              device?.name ?? "",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: FutureBuilder<String>(
                      future: APIService.getGeocoderAddress(
                        device?.lat?.toString() ?? "0",
                        device?.lng?.toString() ?? "0",
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Row(
                            children: [
                              const Icon(Icons.location_on,
                                  color: Colors.blue, size: 16),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  snapshot.data!.replaceAll('"', ''),
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
                        }
                        return Text(
                          'loading'.tr,
                          style:
                          TextStyle(fontSize: 12, color: Colors.grey[400]),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.only(left: 15, top: 10),
                    child: Text(
                      "statistics".tr,
                      style: TextStyle(
                        color: CustomColor.cssBlack,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        _buildStatCard(
                          "assets/images/sensors/total-distance.png",
                          "totalDistance".tr,
                          device?.totalDistance?.toString() ?? "0",
                          color!,
                          iconWidth,
                          fontWidth,
                        ),
                        _buildStatCard(
                          "assets/icons/route-length.png",
                          "todayKM".tr,
                          todaytotalDistance,
                          color,
                          25,
                          fontWidth,
                        ),
                        _buildStatCard(
                          "assets/images/sensors/engine_hours.png",
                          "engineHours".tr,
                          todayData?.engineHours ?? 'loading'.tr,
                          color,
                          iconWidth,
                          fontWidth,
                        ),
                        _buildStatCard(
                          "assets/images/sensors/satellites.png",
                          "moveDuration".tr,
                          todayData?.moveDuration ?? 'loading'.tr,
                          color,
                          iconWidth,
                          fontWidth,
                        ),
                        _buildStatCard(
                          "assets/images/sensors/door.png",
                          "stopDuration".tr,
                          todayData?.stopDuration ?? 'loading'.tr,
                          color,
                          iconWidth,
                          fontWidth,
                        ),
                        _buildStatCard(
                          "assets/images/sensors/speed.png",
                          "topSpeed".tr,
                          todayData?.topSpeed ?? 'loading'.tr,
                          color,
                          iconWidth,
                          fontWidth,
                        ),
                        _buildStatCard(
                          "assets/images/sensors/fuel_tank.png",
                          "fuelConsumption".tr,
                          fuelConsumption ?? 'loading'.tr,
                          color,
                          22,
                          fontWidth,
                        ),
                        ...sensors,
                      ],
                    ),
                  ),
                  const Divider(),
                  Center(
                    child: BannerAdWidget(forceShow: ALWAYS_SHOW_BANNER_ADS),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.dark,
    ));

    return WillPopScope(
      onWillPop: () async {
        if (_isPlaybackMode) {
          _exitPlaybackMode();
          return false;
        }
        return true;
      },
      child: SafeArea(
        child: Scaffold(
          appBar: _buildAppBar(),
          body: GetX<DataController>(
            init: DataController(),
            builder: (controller) {
              if (!_isPlaybackMode) {
                for (var element in controller.onlyDevices) {
                  if (element.id == widget.id) {
                    device = element;
                    updateMarker(element);
                  }
                }
              }
              return _buildBody();
            },
          ),
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
        icon: Icon(
          _isPlaybackMode ? Icons.close : Icons.arrow_back,
          color: CustomColor.cssBlack,
        ),
        onPressed: () {
          if (_isPlaybackMode) {
            _exitPlaybackMode();
          } else {
            Navigator.pop(context);
          }
        },
      ),
      title: Row(
        children: [
          if (_isPlaybackMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle, color: Colors.orange, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'playback'.tr,
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: Text(
                widget.name ?? 'trackDevice'.tr,
                style: FlutterFlowTheme.of(context).headlineMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
      centerTitle: false,
      elevation: 0,
      actions: [
        if (_isPlaybackMode)
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _showPlaybackDateDialog,
            tooltip: 'changeDateRange'.tr,
          ),
      ],
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        // Map
        !isLoading
            ? _buildMap()
            : const Center(child: CircularProgressIndicator()),

        // Map Controls on Right Side
        _buildMapControls(),

        // Speed indicator (left side) - Only in tracking mode
        if (!_isPlaybackMode) _buildSpeedIndicator(),

        // Playback info window
        if (_isPlaybackMode && showPlaybackWindow && playbackWindow != null)
          playbackWindow!,

        // Playback markers toggle
        if (_isPlaybackMode && playbackRoutePoints.isNotEmpty)
          Positioned(
            bottom: 120,
            left: 10,
            child: _buildMarkerToggleButtons(),
          ),

        // Playback Draggable Bottom Sheet
        if (_isPlaybackMode) _buildPlaybackDraggableSheet(),
      ],
    );
  }

  Widget _buildSpeedIndicator() {
    Color? color;
    if (device?.iconColor == "green") {
      color = Colors.green;
    } else if (device?.iconColor == "yellow") {
      color = Colors.yellow.shade700;
    } else {
      color = Colors.red;
    }

    return Positioned(
      top: MediaQuery.of(context).size.aspectRatio > 0.55 ? 70 : 100,
      left: 10,
      child: Container(
        width: 60,
        height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: color ?? Colors.grey, width: 5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              device?.speed?.toString() ?? "0",
              style: TextStyle(
                color: CustomColor.cssBlack,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const Text(
              "Km/hr",
              style: TextStyle(color: Colors.black, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapControls() {
    // Use unique key based on mode to prevent hero tag conflicts
    String prefix = _isPlaybackMode ? 'pb_${widget.id}' : 'tr_${widget.id}';

    return Positioned(
      top: 10,
      right: 5,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Map Type Button
          _buildControlButton(
            key: '${prefix}_mapType',
            icon: Icons.map,
            backgroundColor: _mapTypeBackgroundColor,
            foregroundColor: _mapTypeForegroundColor,
            onPressed: _onMapTypeButtonPressed,
          ),
          const SizedBox(height: 8),

          // Traffic Button (only in tracking mode)
          if (!_isPlaybackMode) ...[
            _buildControlButton(
              key: '${prefix}_traffic',
              icon: Icons.traffic,
              backgroundColor: _trafficBackgroundButtonColor,
              foregroundColor: _trafficForegroundButtonColor,
              onPressed: _trafficEnabledPressed,
            ),
            const SizedBox(height: 8),
          ],

          // Zoom In
          _buildControlButton(
            key: '${prefix}_zoomIn',
            icon: Icons.add,
            backgroundColor: Colors.white,
            foregroundColor: CustomColor.primaryColor,
            onPressed: () => _safeAnimateCamera(CameraUpdate.zoomIn()),
          ),
          const SizedBox(height: 4),

          // Zoom Out
          _buildControlButton(
            key: '${prefix}_zoomOut',
            icon: Icons.remove,
            backgroundColor: Colors.white,
            foregroundColor: CustomColor.primaryColor,
            onPressed: () => _safeAnimateCamera(CameraUpdate.zoomOut()),
          ),

          // Tracking mode specific controls
          if (!_isPlaybackMode) ...[
            const SizedBox(height: 8),
            _buildControlButton(
              key: '${prefix}_lock',
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
              key: '${prefix}_playback',
              icon: Icons.play_arrow_sharp,
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              onPressed: () {
                AdMobService().showInterstitialAd(ignoreFrequency: true);
                _enterPlaybackMode();
              },
            ),
            const SizedBox(height: 4),
            _buildControlButton(
              key: '${prefix}_info',
              icon: Icons.info_outline,
              backgroundColor: Colors.white,
              foregroundColor: CustomColor.primaryColor,
              onPressed: _showTrackingInfoBottomSheet,
            ),
            const SizedBox(height: 4),
            _buildControlButton(
              key: '${prefix}_report',
              icon: Icons.insert_drive_file,
              backgroundColor: Colors.white,
              foregroundColor: CustomColor.primaryColor,
              onPressed: () {
                AdMobService().showInterstitialAd(ignoreFrequency: true);
                // Show report dialog
              },
            ),
            const SizedBox(height: 4),
            _buildControlButton(
              key: '${prefix}_streetView',
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
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required String key,
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

  Widget _buildMarkerToggleButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _toggleParkingMarkers,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isPointActive
                    ? Colors.blue.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                isPointActive
                    ? 'assets/images/map-point.png'
                    : 'assets/images/point-inactive.png',
                height: 22,
                width: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: _toggleEventMarkers,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isAlertActive
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                isAlertActive
                    ? 'assets/images/map-alert-point.png'
                    : 'assets/images/error-inactive.png',
                height: 22,
                width: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return GoogleMap(
      mapType: _currentMapType,
      trafficEnabled: _trafficEnabled,
      initialCameraPosition: CameraPosition(
        target: LatLng(
          double.parse(widget.device!.lat!.toString()),
          double.parse(widget.device!.lng!.toString()),
        ),
        zoom: _isPlaybackMode ? 14 : 16,
      ),
      onCameraMove: (position) {
        currentZoom = position.zoom;
      },
      onCameraIdle: () {
        cameraIdle = true;
      },
      onTap: (latLng) {
        if (_isPlaybackMode) {
          setState(() {
            showPlaybackWindow = false;
          });
        }
      },
      rotateGesturesEnabled: !_isPlaybackMode,
      tiltGesturesEnabled: !_isPlaybackMode,
      mapToolbarEnabled: false,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      onMapCreated: (GoogleMapController controller) {
        _mapController = controller;
        _isMapCreated = true;
      },
      markers: _isPlaybackMode
          ? Set<Marker>.of(_playbackMarkers.values)
          : Set<Marker>.of(_markers),
      polylines: _isPlaybackMode
          ? _playbackPolyLines
          : Set<Polyline>.of(polylines.values),
      padding: const EdgeInsets.all(8),
    );
  }

  // Draggable Scrollable Sheet for Playback
  Widget _buildPlaybackDraggableSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.15,
      minChildSize: 0.08,
      maxChildSize: 0.65,
      controller: _sheetController,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 10),
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // Playback Controls (Always Visible)
              _buildPlaybackControls(),

              const Divider(),

              // Statistics Row
              if (playbackRoutePoints.isNotEmpty) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      _buildPlaybackStatChip(
                          Icons.route, playbackTotalDistance, Colors.blue),
                      _buildPlaybackStatChip(
                          Icons.timer, playbackMoveDuration, Colors.green),
                      _buildPlaybackStatChip(Icons.pause_circle,
                          playbackStopDuration, Colors.orange),
                      _buildPlaybackStatChip(
                          Icons.speed, playbackMaxSpeed, Colors.red),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Timeline
              if (bottomRouteList.isNotEmpty)
                ...bottomRouteList.asMap().entries.map((entry) {
                  return _buildTimelineItem(entry.value, entry.key);
                }).toList()
              else
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      _isPlaybackLoading
                          ? 'loading'.tr
                          : 'selectDateToLoad'.tr,
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

  Widget _buildPlaybackControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Column(
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name ?? "",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "${DateFormat('dd/MM HH:mm').format(playbackDateTimeFrom)} - ${DateFormat('dd/MM HH:mm').format(playbackDateTimeTo)}",
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
              if (playbackRoutePoints.isNotEmpty &&
                  playbackRating.toInt() < routeList.length)
                Text(
                  "${routeList[playbackRating.toInt()].speed ?? 0} kph",
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // Slider and Controls
          if (playbackRoutePoints.isNotEmpty) ...[
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: CustomColor.primaryColor,
                inactiveTrackColor: Colors.grey[300],
                thumbColor: CustomColor.primaryColor,
              ),
              child: Slider(
                value: playbackRating.clamp(
                    0, (playbackRoutePoints.length - 1).toDouble()),
                onChanged: (newRating) {
                  if (newRating < playbackRoutePoints.length) {
                    setState(() {
                      playbackRating = newRating;
                      lowerAnimatingPointsIndex = playbackRating.toInt();
                      upperAnimatingPointsIndex =
                          (playbackRating.toInt() + speedStep)
                              .clamp(0, playbackRoutePoints.length - 1);
                    });
                  }
                },
                min: 0,
                max: (playbackRoutePoints.length - 1)
                    .toDouble()
                    .clamp(0, double.infinity),
              ),
            ),

            // Control Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      playbackRating = (playbackRating - 10).clamp(
                          0, (playbackRoutePoints.length - 1).toDouble());
                      lowerAnimatingPointsIndex = playbackRating.toInt();
                      upperAnimatingPointsIndex =
                          (playbackRating.toInt() + speedStep)
                              .clamp(0, playbackRoutePoints.length - 1);
                    });
                  },
                  icon: const Icon(Icons.replay_10),
                  iconSize: 28,
                  color: Colors.grey[700],
                ),
                const SizedBox(width: 15),
                GestureDetector(
                  onTap: _playPausePlayback,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: CustomColor.primaryColor,
                    ),
                    child: Icon(
                      isPlay ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                IconButton(
                  onPressed: () {
                    setState(() {
                      playbackRating = (playbackRating + 10).clamp(
                          0, (playbackRoutePoints.length - 1).toDouble());
                      lowerAnimatingPointsIndex = playbackRating.toInt();
                      upperAnimatingPointsIndex =
                          (playbackRating.toInt() + speedStep)
                              .clamp(0, playbackRoutePoints.length - 1);
                    });
                  },
                  icon: const Icon(Icons.forward_10),
                  iconSize: 28,
                  color: Colors.grey[700],
                ),
                const SizedBox(width: 15),
                GestureDetector(
                  onTap: _changePlaybackSpeed,
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Text(
                      speedText,
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlaybackStatChip(IconData icon, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(PlayBackRoute trip, int index) {
    // Fix: status == 1 means STOPPED (parking), not moving
    bool isStopped = trip.status == 1;

    return InkWell(
      onTap: () {
        if (trip.latitude != null && trip.longitude != null) {
          LatLng position = LatLng(
            double.parse(trip.latitude!),
            double.parse(trip.longitude!),
          );

          _safeAnimateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: position, zoom: 16),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 50,
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isStopped ? Colors.red : Colors.blue,
                    ),
                    child: Icon(
                      isStopped ? Icons.local_parking : Icons.directions_car,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  if (index < bottomRouteList.length - 1)
                    Container(
                      width: 2,
                      height: 40,
                      color: Colors.grey[300],
                    ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isStopped
                      ? Colors.red.withValues(alpha: 0.05)
                      : Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isStopped
                        ? Colors.red.withValues(alpha: 0.2)
                        : Colors.blue.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isStopped ? 'stopped'.tr : 'moving'.tr,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isStopped ? Colors.red : Colors.blue,
                          ),
                        ),
                        Text(
                          Util.formatOnlyTime(trip.show ?? ""),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildTimelineChip(Icons.timer, trip.time ?? "0"),
                        if (!isStopped) ...[
                          _buildTimelineChip(
                              Icons.route, "${trip.distance ?? 0} km"),
                          _buildTimelineChip(
                              Icons.speed, "${trip.top_speed ?? 0} km/h"),
                        ],
                      ],
                    ),

                    // Show address for STOPPED locations
                    if (isStopped && trip.latitude != null && trip.longitude != null) ...[
                      const SizedBox(height: 8),
                      FutureBuilder<String>(
                        future: APIService.getGeocoderAddress(
                          trip.latitude!,
                          trip.longitude!,
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 14,
                                  color: Colors.red[400],
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    snapshot.data!.replaceAll('"', ''),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.grey[400],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'loading'.tr,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineChip(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey[600]),
        const SizedBox(width: 3),
        Text(
          value,
          style: TextStyle(fontSize: 11, color: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String iconPath,
      String label,
      String value,
      Color shadowColor,
      double iconWidth,
      double fontWidth,
      ) {
    return Card(
      elevation: 1,
      shadowColor: shadowColor,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(iconPath, width: iconWidth, height: iconWidth),
            const SizedBox(width: 6),
            Column(
              children: [
                Text(label, style: TextStyle(fontSize: fontWidth * 19)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: fontWidth * 19)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // HELPER METHODS
  String gsmCodeConvert(value) {
    if (value == "71606") return "Movistar";
    if (value == "71610") return "Claro";
    if (value == "71617") return "Entel";
    if (value == "71615") return "Bitel";
    return value.toString();
  }

  Future<Uint8List> getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  }

  void animateCar(
      double fromLat,
      double fromLong,
      double toLat,
      double toLong,
      StreamSink<List<Marker>> mapMarkerSink,
      TickerProvider provider,
      BitmapDescriptor markerIcon,
      ) async {
    if (!mounted || _isDisposed || _mapMarkerSC.isClosed) return;

    final double bearing = getBearing(
      LatLng(fromLat, fromLong),
      LatLng(toLat, toLong),
    );

    _markers.clear();

    var carMarker = Marker(
      markerId: const MarkerId("driverMarker"),
      position: LatLng(fromLat, fromLong),
      icon: markerIcon,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      rotation: bearing,
      draggable: false,
    );

    _markers.add(carMarker);
    if (!_mapMarkerSC.isClosed) {
      mapMarkerSink.add(_markers);
    }

    final animationController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: provider,
    );

    Tween<double> tween = Tween(begin: 0, end: 1);

    _animation = tween.animate(animationController)
      ..addListener(() async {
        if (!mounted || _isDisposed || _mapMarkerSC.isClosed) {
          animationController.dispose();
          return;
        }

        final v = _animation!.value;
        double lng = v * toLong + (1 - v) * fromLong;
        double lat = v * toLat + (1 - v) * fromLat;
        LatLng newPos = LatLng(lat, lng);

        _markers.remove(carMarker);

        carMarker = Marker(
          markerId: const MarkerId("driverMarker"),
          position: newPos,
          icon: markerIcon,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          rotation: bearing,
          draggable: false,
        );

        _markers.add(carMarker);
        if (!_mapMarkerSC.isClosed) {
          mapMarkerSink.add(_markers);
        }
        newPolylinesData.add(carMarker.position);

        oldPin = newPos;
      });

    await _safeAnimateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: LatLng(toLat, toLong), zoom: currentZoom),
    ));

    if (oldPin != null) {
      polylineCoordinates.add(oldPin!);
    }
    animationController.forward();
    newPolylinesData.clear();
    if (polylineCoordinates.length > 20) {
      polylineCoordinates.removeRange(0, 10);
    }
  }

  double getBearing(LatLng begin, LatLng end) {
    double lat = (begin.latitude - end.latitude).abs();
    double lng = (begin.longitude - end.longitude).abs();

    if (begin.latitude < end.latitude && begin.longitude < end.longitude) {
      return v.degrees(m.atan(lng / lat));
    } else if (begin.latitude >= end.latitude &&
        begin.longitude < end.longitude) {
      return (90 - v.degrees(m.atan(lng / lat))) + 90;
    } else if (begin.latitude >= end.latitude &&
        begin.longitude >= end.longitude) {
      return v.degrees(m.atan(lng / lat)) + 180;
    } else if (begin.latitude < end.latitude &&
        begin.longitude >= end.longitude) {
      return (90 - v.degrees(m.atan(lng / lat))) + 270;
    }
    return -1;
  }
}