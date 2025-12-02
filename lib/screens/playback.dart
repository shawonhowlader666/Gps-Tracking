// ignore_for_file: use_build_context_synchronously, unnecessary_null_comparison, duplicate_ignore

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/services/model/playback_route.dart';
import 'package:gpspro/screens/common_method.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/util/util.dart';
import 'package:gpspro/widgets/bloc/custom_info_widget.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:timelines/timelines.dart';

class PlaybackScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen>
    with TickerProviderStateMixin {
  static ReportArguments? args;

  bool filter = true;

  String selectStopDuration = ' > 1 min';

  final Completer<GoogleMapController> _controller = Completer();
  GoogleMapController? mapController;

  DateTime selectedDateFrom = DateTime.now();
  TimeOfDay selectedTimeFrom = TimeOfDay.now();
  DateTime selectedDateTo = DateTime.now();
  TimeOfDay selectedTimeTo = TimeOfDay.now();
  DateTime dateTimeFrom = DateTime.now();
  DateTime dateTimeTo = DateTime.now();

  String maxSpeed = "-";
  String totalDistance = "-";
  String moveDuration = "-";
  String stopDuration = "-";
  MapType _currentMapType = MapType.normal;

  final Color _mapTypeBackgroundColor = CustomColor.primaryColor;
  final Color _mapTypeForegroundColor = CustomColor.secondaryColor;

  bool stopEnabled = false;
  List<PlayBackRoute> routeList = [];
  final Map<MarkerId, Marker> _markers = <MarkerId, Marker>{};
  double currentZoom = 14.0;
  Timer? timerPlayBack;
  int playbackTime = 200;
  List<PlayBackRoute> bottomRouteList = [];
  List<LatLng> routePoints = [];
  Window? window;
  bool show = false;

  Map<MarkerId, Marker>? _eventMarkers;
  Map<MarkerId, Marker>? _parkingMarkers;
  Map<String, dynamic>? result;
  bool cameraIdle = true;

  AnimationController? animationController;
  int animationSpeed = 1000;

  LatLng previousLatLng = const LatLng(0.0, 0.0);
  LatLng currentLatLng = const LatLng(0.0, 0.0);
  final Set<Polyline> _polyLines = {};

  AnimationController? trafficAnimationController;
  AnimationController? playButtonAnimationController;
  AnimationController? fastButtonAnimationController;
  double rating = 0.0;

  double baseTimeForMapAnimation = 0.0;
  double deltaTimeForMapAnimation = 5 / 60;

  int upperAnimatingPointsIndex = 1;
  int lowerAnimatingPointsIndex = 0;
  BitmapDescriptor? customMarkerIcon;

  String speedText = "Slow";
  int speedStep = 1;
  bool isPlay = false;
  bool isAlertActive = true;
  List<dynamic> eventsPoints = [];
  List<dynamic> parkingPoints = [];

  bool isPointActive = true;
  String? _mapStyle;

  static const CameraPosition _initialRegion = CameraPosition(
    target: LatLng(0, 0),
    zoom: 14,
  );

  void _removeEventsMarkers() async {
    show = false;

    for (var element in eventsPoints) {
      _markers.remove(MarkerId('event${element[0]["id"]}'));
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _removeParkingMarkers() async {
    show = false;

    for (var element in parkingPoints) {
      _markers.remove(MarkerId('stop${element[0]["id"]}'));
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    rootBundle.loadString('assets/map_style.txt').then((string) {
      _mapStyle = string;
    });
    trafficAnimationController = AnimationController(
        duration: const Duration(milliseconds: 150), vsync: this);
    playButtonAnimationController = AnimationController(
        duration: const Duration(milliseconds: 150), vsync: this);
    fastButtonAnimationController = AnimationController(
        duration: const Duration(milliseconds: 150), vsync: this);
    super.initState();
    dateTimeFrom =
        DateTime(dateTimeFrom.year, dateTimeFrom.month, dateTimeFrom.day);
    animationController = AnimationController(
        vsync: this, duration: Duration(milliseconds: animationSpeed));
    animationController!.addListener(() async {
      baseTimeForMapAnimation = 0.0;
      LatLng start = LatLng(
              routePoints.elementAt(lowerAnimatingPointsIndex).latitude,
              routePoints.elementAt(lowerAnimatingPointsIndex).longitude),
          end = LatLng(
              routePoints.elementAt(upperAnimatingPointsIndex).latitude,
              routePoints.elementAt(upperAnimatingPointsIndex).longitude);

      if (baseTimeForMapAnimation <= 1) {
        if (start.latitude != end.latitude &&
            start.longitude != end.longitude) {
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
          MarkerId markerId = const MarkerId('animatingMarker');
          LatLng intermediateLatLng = LatLng(intermediateLat, intermediateLon);
          double bearing = Geolocator.bearingBetween(
              intermediateLat, intermediateLon, end.latitude, end.longitude);

          Util.fetchAndCacheImages(UserRepository.getServerUrl()! +
                  "/" +
                  args!.deviceItem.icon!.path!)
              .then((_) async {
            BitmapDescriptor markerIcon;
            if (args!.deviceItem.iconType == "arrow") {
              markerIcon =
                  await Util.getMarkerIcon(args!.deviceItem.icon!.path!);
            } else {
              markerIcon =
                  await Util.getMarkerIcon(args!.deviceItem.icon!.path!);
            }

            // customMarkerIcon =
            // await Util.getMarkerIcon("assets/markers/arrow-blue.png", bearing);
            Marker startMarker = Marker(
              markerId: markerId,
              anchor: const Offset(0.5, 0.5),
              position: intermediateLatLng,
              rotation: bearing,
              icon: markerIcon,
            );
            _markers.update(markerId, (value) => startMarker,
                ifAbsent: () => startMarker);
            rating = upperAnimatingPointsIndex.toDouble();
            if (mounted && this.cameraIdle) {
              _controller.future.then((value) => value.animateCamera(
                  CameraUpdate.newCameraPosition(CameraPosition(
                      target: LatLng(intermediateLat, intermediateLon),
                      zoom: currentZoom))));
              setState(() {
                this.cameraIdle = false;
              });
              baseTimeForMapAnimation += deltaTimeForMapAnimation;
            } else if (baseTimeForMapAnimation > 1) {
              return;
            }
          });
        }
      }
    });
    animationController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (upperAnimatingPointsIndex >= routePoints.length - 1) {
          animationController!.reset();
          upperAnimatingPointsIndex = 1;
          lowerAnimatingPointsIndex = 0;
          speedStep = 1;
          speedText = "Slow";
          isPlay = false;
          return;
        } else {
          lowerAnimatingPointsIndex = upperAnimatingPointsIndex;
          upperAnimatingPointsIndex = upperAnimatingPointsIndex + speedStep;
          if (upperAnimatingPointsIndex >= routePoints.length - 1) {
            upperAnimatingPointsIndex = routePoints.length - 1;
          }
          animationController!.reset();
          animationController!.forward();
        }
      } else if (status == AnimationStatus.dismissed) {
        // animationController.forward();
      }
    });
  }

  @override
  void dispose() {
    //timerPlayBack!.cancel();
    animationController!.dispose();
    trafficAnimationController!.dispose();
    playButtonAnimationController!.dispose();
    fastButtonAnimationController!.dispose();
    super.dispose();
  }

  void getReport() {
    routeList.clear();
    routePoints.clear();
    parkingPoints.clear();
    eventsPoints.clear();
    bottomRouteList.clear();
    _markers.clear();
    _polyLines.clear();
    _parkingMarkers = null;
    _eventMarkers = null;

    rating = 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
          barrierDismissible: false,
          context: context,
          builder: (context) => SpinKitRing(
              lineWidth: 3.0, color: CustomColor.primaryColor, size: 35.0));
    });
    APIService.getHistory(
            args!.id.toString(),
            Util.formatReportDate(dateTimeFrom),
            Util.formatReportTime(dateTimeFrom),
            Util.formatReportDate(dateTimeTo),
            Util.formatReportTime(dateTimeTo))
        .then((value) async {
      if (value!.items!.isNotEmpty) {
        if (value.distance_sum != null) {
          totalDistance = value.distance_sum!;
        } else {
          totalDistance = " 0 km";
        }

        if (value.top_speed != null) {
          maxSpeed = value.top_speed!;
        } else {
          maxSpeed = value.top_speed!;
        }

        if (value.move_duration != null) {
          moveDuration = value.move_duration!;
        } else {
          moveDuration = value.move_duration!;
        }

        if (value.stop_duration != null) {
          stopDuration = value.stop_duration!;
        } else {
          stopDuration = value.stop_duration!;
        }
        if (value.items!.isNotEmpty) {
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
              //rt.engine_idle = el['engine_idle'];
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
                routePoints.add(LatLng(
                    double.parse(element['latitude'].toString()),
                    double.parse(element['longitude'].toString())));
                routeList.add(blackRoute);
                routePoints.removeLast();
                _polyLines.add(Polyline(
                  polylineId: const PolylineId('polyline_one'),
                  visible: true,
                  points: routePoints,
                  width: 4,
                  color: const Color(0xFFF26611),
                ));
              }
            });
          }
        }
        await addToView();
        _setParkingMarkers();
        _setEventsMarkers();
      } else {
        setState(() {});
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No Records...!')));
        Navigator.pop(context);
      }
    });
  }

  Future<void> addToView() async {
    double? x0, x1, y0, y1;
    LatLngBounds? bounds;
    for (int i = 0; i < routeList.length; i++) {
      LatLng latLng = LatLng(
          double.parse(routeList.elementAt(i).latitude as String),
          double.parse(routeList.elementAt(i).longitude as String));
      if (x0 == null) {
        x0 = x1 = latLng.latitude;
        y0 = y1 = latLng.longitude;
      } else {
        if (latLng.latitude > x1!) x1 = latLng.latitude;
        if (latLng.latitude < x0) x0 = latLng.latitude;
        if (latLng.longitude > y1!) y1 = latLng.longitude;
        if (latLng.longitude < y0!) y0 = latLng.longitude;
      }
      if (i > 0 && routePoints.elementAt(routePoints.length - 1) == latLng) {
        continue;
      }
      routePoints.add(latLng);
      bounds = LatLngBounds(
          northeast: LatLng(x1 == null ? 0 : x1, y1 == null ? 0 : y1),
          southwest: LatLng(x0 == null ? 0 : x0, y0 == null ? 0 : y0));
    }
    _setStartEndMarkers(
        LatLng(double.parse(routeList.first.latitude!),
            double.parse(routeList.first.longitude!)),
        LatLng(double.parse(routeList.last.latitude!),
            double.parse(routeList.last.longitude!)),
        bounds!);

    setState(() {
      Navigator.pop(context);
    });
  }

  void _setParkingMarkers() async {
    if (_parkingMarkers == null) {
      _parkingMarkers = <MarkerId, Marker>{};
      final Uint8List? parkingIcon =
          await Util.getBytesFromAsset('assets/images/map-point.png', 30);
      for (var element in parkingPoints) {
        Map<String, String> data = <String, String>{};
        data.putIfAbsent("Object", () => args!.name);
        data.putIfAbsent("Position",
            () => "${element[0]["latitude"]}${element[0]["longitude"]}");
        data.putIfAbsent("Altitude", () => element[0]["altitude"].toString());
        data.putIfAbsent("Angle", () => element[0]["course"].toString());
        data.putIfAbsent("Came", () => "-");
        data.putIfAbsent("Left", () => "-");
        data.putIfAbsent("Duration", () => element[0]["time"]);
        var markerId = MarkerId('stop${element[0]["id"]}');
        Marker marker = Marker(
          markerId: markerId,
          onTap: () => _onTap(
              LatLng(element[0]["latitude"], element[0]["longitude"]), data),
          position: LatLng(element[0]["latitude"], element[0]["longitude"]),
          icon: BitmapDescriptor.bytes(
              parkingIcon!) /*BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue)*/,
        );
        _parkingMarkers!.putIfAbsent(markerId, () {
          return marker;
        });
        _markers.putIfAbsent(markerId, () {
          return marker;
        });
      }
    } else {
      _markers.addAll(_parkingMarkers!);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _setEventsMarkers() async {
    if (_eventMarkers == null) {
      _eventMarkers = <MarkerId, Marker>{};
      final Uint8List? eventIcon =
          await Util.getBytesFromAsset('assets/images/map-alert-point.png', 30);
      for (var element in eventsPoints) {
        var markerId = MarkerId('event${element[0]["id"]}');
        Map<String, String> data = Map<String, String>();
        data.putIfAbsent("Object", () => args!.name);
        data.putIfAbsent("Event", () => "");
        data.putIfAbsent(
            "Position", () => "${element[0]["lat"]}${element[0]["lng"]}");
        data.putIfAbsent("Altitude", () => element[0]["altitude"].toString());
        data.putIfAbsent("Angle", () => element[0]["course"].toString());
        data.putIfAbsent(
            "Speed", () => element[0]["speed"].toString() + " kph");
        data.putIfAbsent("Time", () => element[0]["time"]);
        var marker = Marker(
          markerId: markerId,
          onTap: () => _onTap(
              LatLng(double.parse(element[0]["lat"].toString()),
                  double.parse(element[0]["lng"].toString())),
              data),
          position: LatLng(double.parse(element[0]["lat"].toString()),
              double.parse(element[0]["lng"].toString())),
          icon: BitmapDescriptor.bytes(
              eventIcon!) /*BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue)*/,
        );
        _eventMarkers!.putIfAbsent(markerId, () {
          return marker;
        });
        _markers.putIfAbsent(markerId, () {
          return marker;
        });
      }
    } else {
      _markers.addAll(_eventMarkers!);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _setStartEndMarkers(
      LatLng start, LatLng end, LatLngBounds bounds) async {
    var stopIconPath = "assets/images/map-end-point.png";
    final Uint8List? stopIcon = await Util.getBytesFromAsset(stopIconPath, 30);

    var startIconPath = "assets/images/map-start-point.png";
    final Uint8List? startIcon =
        await Util.getBytesFromAsset(startIconPath, 30);

    Marker startMarker = Marker(
      markerId: const MarkerId('start'),
      position: start,
      icon: BitmapDescriptor.bytes(stopIcon!),
    );
    _markers.putIfAbsent(const MarkerId('start'), () => startMarker);
    Marker endMarker = Marker(
      markerId: const MarkerId('end'),
      position: end,
      icon: BitmapDescriptor.bytes(startIcon!),
    );
    _markers.putIfAbsent(const MarkerId('end'), () => endMarker);
    if (mounted) {
      _controller.future.then((value) =>
          value.animateCamera(CameraUpdate.newLatLngBounds(bounds, 120)));
      setState(() {});
    }
  }

  _onTap(LatLng location, Map<String, String> data) async {
    CameraPosition _kLake = CameraPosition(target: location, zoom: currentZoom);
    _controller.future.then(
        (value) => value.animateCamera(CameraUpdate.newCameraPosition(_kLake)));
    previousLatLng = currentLatLng;
    currentLatLng = location;
    //await _onChange();
    window = Window(offsetX: 65, offsetY: 220, data: data);
    setState(() {
      if (currentLatLng == previousLatLng) {
        show = !show;
      } else {
        show = true;
      }
    });
  }

  _onChange() async {
    // if (window == null) {
    //   return;
    // }
    // ScreenCoordinate coordinate = await _controller.future.then((
    //     value) => value.getScreenCoordinate(currentLatLng));
    // BlocProvider.of<WindowBloc>(context).add(
    //     ChangePositionEvent(context: context, screenCoordinate: coordinate));
    // ScreenCoordinate coordinate = await _controller.future.then((
    //     value) => value.getScreenCoordinate(currentLatLng));
    // window = Window(offsetX: coordinate.x.toDouble(), offsetY: coordinate.y.toDouble(), data: data);
  }

  pauseAnimation() {
    animationController!.stop(canceled: true);
  }

  // Select for From Date
  Future<DateTime> _selectFromDate(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: selectedDateFrom,
      firstDate: DateTime(2020),
      lastDate: DateTime(2050),
    );
    if (selected != null && selected != selectedDateFrom) {
      setState(() {
        selectedDateFrom = selected;
      });
    }
    return selectedDateFrom;
  }

  Future<TimeOfDay> _selectFromTime(BuildContext context) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: selectedTimeFrom,
    );
    if (selected != null && selected != selectedTimeFrom) {
      setState(() {
        selectedTimeFrom = selected;
      });
    }
    return selectedTimeFrom;
  }

  Future _selectFromDateTime(BuildContext context) async {
    final date = await _selectFromDate(context);
    if (date == null) return;

    final time = await _selectFromTime(context);

    if (time == null) return;
    setState(() {
      dateTimeFrom = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  // ignore: duplicate_ignore
  Future _selectToDateTime(BuildContext context) async {
    final date = await _selectFromDate(context);
    // ignore: unnecessary_null_comparison
    if (date == null) return;

    final time = await _selectFromTime(context);

    if (time == null) return;
    setState(() {
      dateTimeTo = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _onMapTypeButtonPressed() {
    setState(() {
      _currentMapType =
          _currentMapType == MapType.normal ? MapType.hybrid : MapType.normal;
    });
  }

  void showReportDialog(BuildContext context) {
    Dialog simpleDialog = Dialog(
      child: StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return SizedBox(
            height: 160,
            width: 300.0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: <Widget>[
                Column(
                  children: <Widget>[
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 10, right: 10, top: 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          InkWell(
                              onTap: () {
                                dateTimeFrom = DateTime.now().subtract(Duration(
                                  hours: DateTime.now().hour,
                                  minutes: DateTime.now().minute,
                                  seconds: DateTime.now().second,
                                  milliseconds: DateTime.now().millisecond,
                                  microseconds: DateTime.now().microsecond,
                                ));
                                dateTimeTo = DateTime.now();
                                getReport();
                                Navigator.pop(context);
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: <Widget>[
                                  Image.asset("assets/icons/today.png",
                                      width: 30),
                                  const Padding(
                                      padding: EdgeInsets.only(left: 20)),
                                  Text(
                                    ('reportToday').tr,
                                    style: const TextStyle(fontSize: 16.0),
                                  ),
                                ],
                              )),
                          const Divider(),
                          InkWell(
                              onTap: () {
                                dateTimeFrom = DateTime.now().subtract(Duration(
                                  days: 1,
                                  hours: DateTime.now().hour,
                                  minutes: DateTime.now().minute,
                                  seconds: DateTime.now().second,
                                  milliseconds: DateTime.now().millisecond,
                                  microseconds: DateTime.now().microsecond,
                                ));
                                dateTimeTo = DateTime.now().subtract(Duration(
                                  hours: DateTime.now().hour,
                                  minutes: DateTime.now().minute,
                                  seconds: DateTime.now().second,
                                  milliseconds: DateTime.now().millisecond,
                                  microseconds: DateTime.now().microsecond,
                                ));
                                getReport();
                                Navigator.pop(context);
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: <Widget>[
                                  Image.asset("assets/icons/yesterday.png",
                                      width: 30),
                                  const Padding(
                                      padding: EdgeInsets.only(left: 20)),
                                  Text(
                                    ('reportYesterday').tr,
                                    style: const TextStyle(fontSize: 16.0),
                                  ),
                                ],
                              )),
                          const Divider(),
                          InkWell(
                              onTap: () {
                                dateTimeFrom = DateTime.now().subtract(Duration(
                                  days: 7,
                                  hours: DateTime.now().hour,
                                  minutes: DateTime.now().minute,
                                  seconds: DateTime.now().second,
                                  milliseconds: DateTime.now().millisecond,
                                  microseconds: DateTime.now().microsecond,
                                ));
                                dateTimeTo = DateTime.now().subtract(Duration(
                                  hours: DateTime.now().hour,
                                  minutes: DateTime.now().minute,
                                  seconds: DateTime.now().second,
                                  milliseconds: DateTime.now().millisecond,
                                  microseconds: DateTime.now().microsecond,
                                ));
                                getReport();
                                Navigator.pop(context);
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: <Widget>[
                                  Image.asset("assets/icons/thisWeek.png",
                                      width: 30),
                                  const Padding(
                                      padding: EdgeInsets.only(left: 20)),
                                  Text(
                                    ('reportThisWeek').tr,
                                    style: const TextStyle(fontSize: 16.0),
                                  ),
                                ],
                              )),
                          const Divider(),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    showDialog(
        context: context, builder: (BuildContext context) => simpleDialog);
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.dark,
    ));

    args = ModalRoute.of(context)!.settings.arguments as ReportArguments;

    return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          automaticallyImplyLeading: true,
          iconTheme: IconThemeData(color: CustomColor.cssBlack),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'playback'.tr,
                style: FlutterFlowTheme.of(context).headlineMedium,
              ),
            ],
          ),
          centerTitle: false,
          elevation: 0,
          actions: [
            InkWell(
                onTap: () {
                  if (filter) {
                    setState(() {
                      filter = false;
                    });
                  } else {
                    setState(() {
                      filter = true;
                    });
                  }
                },
                child: const Padding(
                    padding: EdgeInsets.all(10), child: Icon(Icons.date_range)))
          ],
        ),
        body: slidingPanel());
  }

  Widget slidingPanel() {
    return SlidingUpPanel(
      minHeight: 170,
      parallaxEnabled: true,
      parallaxOffset: .0,
      maxHeight: 800,
      borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18.0), topRight: Radius.circular(18.0)),
      panel: bottomPanelView(),
      body: mainView(),
    );
  }

  Widget mainView() {
    return Stack(
      children: [
        mapView(),
        show
            ? window!
            : const SizedBox(
                height: 0,
                width: 0,
              ),
        Column(
          children: [
            filter ? topView() : Container(),
            Container(
                padding: const EdgeInsets.only(left: 10, bottom: 10),
                color: Colors.white,
                child: topDataView())
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 230, 7, 0),
          child: Align(
            alignment: Alignment.topRight,
            child: Column(
              children: <Widget>[
                FloatingActionButton(
                  heroTag: "mapLayer",
                  mini: true,
                  onPressed: _onMapTypeButtonPressed,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  backgroundColor: _mapTypeBackgroundColor,
                  foregroundColor: _mapTypeForegroundColor,
                  child: const Icon(Icons.layers, size: 25.0),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 290.0,
          left: 5.0,
          child: Container(
            padding: const EdgeInsets.only(
                top: 13.0, bottom: 10, left: 15, right: 15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(23.0),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(.3),
                    blurRadius: 3.0,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Row(
              children: [
                InkWell(
                    onTap: () {
                      isPointActive = !isPointActive;
                      if (!isPointActive) {
                        _removeParkingMarkers();
                      } else {
                        _setParkingMarkers();
                      }
                    },
                    child: Image.asset(
                      isPointActive
                          ? 'assets/images/map-point.png'
                          : 'assets/images/point-inactive.png',
                      height: 22,
                      width: 22,
                    )),
                const SizedBox(
                  width: 15,
                ),
                InkWell(
                    onTap: () {
                      isAlertActive = !isAlertActive;
                      if (!isAlertActive) {
                        _removeEventsMarkers();
                      } else {
                        _setEventsMarkers();
                      }
                    },
                    child: Image.asset(
                      isAlertActive
                          ? 'assets/images/map-alert-point.png'
                          : 'assets/images/error-inactive.png',
                      height: 22,
                      width: 22,
                    )),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget mapView() {
    return GoogleMap(
      mapType: _currentMapType,
      initialCameraPosition: _initialRegion,
      onMapCreated: (GoogleMapController controller) {
        _controller.complete(controller);
        mapController = controller;
        //mapController!.setMapStyle(_mapStyle);
        getReport();
      },
      onCameraMove: (cameraPosition) {
        currentZoom = cameraPosition.zoom;
        _onChange();
      },
      onCameraIdle: () {
        this.cameraIdle = true;
      },
      onTap: (latLng) {
        previousLatLng = currentLatLng;
        currentLatLng = latLng;
        setState(() {
          show = false;
        });
      },
      markers: Set<Marker>.of(_markers.values),
      polylines: _polyLines,
    );
  }

  Widget topView() {
    return Container(
        width: MediaQuery.of(context).size.width / 1,
        height: MediaQuery.of(context).size.height / 7.5,
        color: Colors.white,
        padding: const EdgeInsets.all(10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 5)),
                  Row(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                              onTap: () {
                                _selectFromDateTime(context);
                              },
                              child: Container(
                                  width: MediaQuery.of(context).size.width / 1.2,
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.grey, // Border color
                                      width: 1.0, // Border width
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Padding(
                                          padding: EdgeInsets.only(left: 10)),
                                      Image.asset(
                                          "assets/icons/hourglass-start.png",
                                          width: 25,
                                          height: 25),
                                      const Padding(
                                          padding: EdgeInsets.only(left: 20)),
                                      Text(
                                          "${Util.formatReportDate(dateTimeFrom)} ${Util.formatReportTime(dateTimeFrom)}"),
                                    ],
                                  ))),
                        ],
                      ),
                      const Padding(padding: EdgeInsets.only(left: 10)),
                      InkWell(
                          onTap: () {
                            showReportDialog(context);
                          },
                          child: Image.asset("assets/icons/funnel.png")),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.only(top: 10)),
                  Row(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                              onTap: () {
                                _selectToDateTime(context);
                              },
                              child: Container(
                                  width: MediaQuery.of(context).size.width / 1.2,
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.grey, // Border color
                                      width: 1.0, // Border width
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Padding(
                                          padding: EdgeInsets.only(left: 10)),
                                      Image.asset(
                                          "assets/icons/hourglass-start.png",
                                          width: 25,
                                          height: 25),
                                      const Padding(
                                          padding: EdgeInsets.only(left: 20)),
                                      Text(
                                          "${Util.formatReportDate(dateTimeTo)} ${Util.formatReportTime(dateTimeTo)}"),
                                    ],
                                  ))),
                        ],
                      ),
                      const Padding(padding: EdgeInsets.only(left: 10)),
                      InkWell(
                          onTap: () {
                            getReport();
                          },
                          child: Image.asset(
                            "assets/icons/send.png",
                            width: 30,
                          ))
                    ],
                  )
                ],
              ),
            ),
          ]),
        ));
  }

  Widget topDataView() {
    double width = 100;
    double height = 50;
    double fontSize = 12;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5.0), // Rounded corners
                color: Colors.blue.shade100, // Background color of the card
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ('routeLength').tr,
                      style: TextStyle(fontSize: fontSize),
                    ),
                    Text(
                      totalDistance,
                      style: TextStyle(fontSize: fontSize),
                    ),
                  ])),
          const Padding(padding: EdgeInsets.only(left: 5)),
          Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5.0), // Rounded corners
                color: Colors.green.shade100, // Background color of the card
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ('moveDuration').tr,
                      style: TextStyle(fontSize: fontSize),
                    ),
                    Text(
                      moveDuration,
                      style: TextStyle(fontSize: fontSize),
                    ),
                  ])),
          const Padding(padding: EdgeInsets.only(left: 5)),
          Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5.0), // Rounded corners
                color: Colors.blue.shade100, // Background color of the card
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ('stopsDuration').tr,
                      style: TextStyle(fontSize: fontSize),
                    ),
                    Text(
                      stopDuration,
                      style: TextStyle(fontSize: fontSize),
                    ),
                  ])),
          const Padding(padding: EdgeInsets.only(left: 5)),
          Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5.0), // Rounded corners
                color: Colors.red.shade100, // Background color of the card
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ('averageSpeed').tr,
                      style: TextStyle(fontSize: fontSize),
                    ),
                    Text(
                      '0 km',
                      style: TextStyle(fontSize: fontSize),
                    ),
                  ])),
          const Padding(padding: EdgeInsets.only(left: 5)),
          Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5.0), // Rounded corners
                color: Colors.green.shade100, // Background color of the card
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ('maxSpeed').tr,
                      style: TextStyle(fontSize: fontSize),
                    ),
                    Text(
                      maxSpeed,
                      style: TextStyle(fontSize: fontSize),
                    ),
                  ])),
          const Padding(padding: EdgeInsets.only(left: 5)),
        ],
      ),
    );
  }

  Widget bottomPanelView() {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: <Widget>[
          const Padding(padding: EdgeInsets.only(top: 10)),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: const BorderRadius.all(Radius.circular(12.0))),
          ),
          playerView()
        ],
      ),
    );
  }

  Widget playerView() {
    return Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                  width: MediaQuery.of(context).size.width / 2,
                  padding: const EdgeInsets.only(top: 5, bottom: 0, left: 5),
                  color: Colors.white,
                  child: Text(args!.name,
                      style: FlutterFlowTheme.of(context).headlineSmall)),
              SizedBox(
                  height: MediaQuery.of(context).size.height / 8,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            routePoints.length - 1 > rating.toInt()
                                ? Row(
                                    children: [
                                      Text(
                                          routeList[rating.toInt()]
                                              .speed
                                              .toString(),
                                          style: const TextStyle(
                                              fontSize: 40,
                                              fontWeight: FontWeight.bold)),
                                      const Text(
                                        "kph",
                                        style: TextStyle(fontSize: 15),
                                      ),
                                    ],
                                  )
                                : Container(),
                            routePoints.length - 1 > rating.toInt()
                                ? Column(
                                    children: [
                                      const Padding(
                                          padding: EdgeInsets.only(top: 7)),
                                      Text(
                                        Util.formatReportTime(DateTime.parse(
                                            routeList[rating.toInt()].raw_time!)),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12),
                                      ),
                                      Text(
                                        Util.formatReportDate(DateTime.parse(
                                            routeList[rating.toInt()].raw_time!)),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  )
                                : Container()
                          ],
                        ),
                        const IntrinsicHeight(
                          child: Row(
                            children: [
                              VerticalDivider(
                                color: Colors.black,
                                thickness: 2,
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            InkWell(
                                onTap: () {
                                  setState(() {
                                    isPlay = !isPlay;
                                    playButtonAnimationController!.forward();
                                  });
                                  if (animationController!.isAnimating) {
                                    pauseAnimation();
                                    return;
                                  }
                                  animationController!.forward();
                                },
                                child: ScaleTransition(
                                    scale: Tween(begin: 1.0, end: .8).animate(
                                        CurvedAnimation(
                                            parent:
                                                playButtonAnimationController!,
                                            curve: Curves.bounceIn))
                                      ..addStatusListener((status) {
                                        if (status == AnimationStatus.completed) {
                                          playButtonAnimationController!
                                              .reverse();
                                        }
                                      }),
                                    child: Icon(
                                      !isPlay
                                          ? Icons.play_circle
                                          : Icons.pause_circle,
                                      size: 50,
                                    ))),
                            Container(
                              width: MediaQuery.of(context).size.width / 2,
                              padding: const EdgeInsets.only(top: 3.0),
                              child: SliderTheme(
                                data: const SliderThemeData(
                                    trackHeight: 1,
                                    thumbShape: RoundSliderThumbShape(
                                        enabledThumbRadius: 6,
                                        disabledThumbRadius: 6)),
                                child: Slider(
                                  value: rating,
                                  onChanged: (newRating) {
                                    if (routePoints.length - 1 > newRating) {
                                      setState(() {
                                        rating = newRating;
                                        lowerAnimatingPointsIndex =
                                            rating.toInt();
                                        upperAnimatingPointsIndex =
                                            rating.toInt() + speedStep;
                                      });
                                    }
                                  },
                                  activeColor: CustomColor.primaryColor,
                                  inactiveColor: const Color(0xFFF1F1F1),
                                  min: 0,
                                  max: routePoints.length.toDouble(),
                                ),
                              ),
                            ),
                            InkWell(
                                onTap: () {
                                  setState(() {
                                    fastButtonAnimationController!.forward();
                                    if (speedStep == 1) {
                                      speedStep = 3;
                                      speedText = "Medium";
                                      animationSpeed = 700;
                                    } else if (speedStep == 3) {
                                      speedStep = 5;
                                      speedText = "Fast";
                                      animationSpeed = 200;
                                    } else if (speedStep == 5) {
                                      speedStep = 1;
                                      speedText = "Slow";
                                      animationSpeed = 1000;
                                    }
                                  });
                                  animationController!.duration =
                                      Duration(milliseconds: this.animationSpeed);
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ScaleTransition(
                                        scale: Tween(begin: 1.0, end: .8).animate(
                                            CurvedAnimation(
                                                parent:
                                                    fastButtonAnimationController!,
                                                curve: Curves.bounceIn))
                                          ..addStatusListener((status) {
                                            if (status ==
                                                AnimationStatus.completed) {
                                              fastButtonAnimationController!
                                                  .reverse();
                                            }
                                          }),
                                        child: Image.asset(
                                          'assets/images/double-right-arrow.png',
                                          height: 30.0,
                                        )),
                                    Text(
                                      speedText,
                                      style: const TextStyle(
                                          color: Color(0xFF0060A4), fontSize: 11),
                                    )
                                  ],
                                )),
                          ],
                        ),
                      ],
                    ),
                  )),
              Container(
                height: MediaQuery.of(context).size.height / 1.5,
                color: Colors.white,
                child: loadReport(),
              ),
            ]));
  }

  Widget loadReport() {
    return ListView.builder(
      itemCount: bottomRouteList.length,
      itemBuilder: (context, index) {
        final trip = bottomRouteList[index];
        return GestureDetector(
          onTap: () {
            // String fromDate = formatInvalidDate(trip.show.toString());
            // String toDate = formatInvalidDate(trip.left.toString());
            // String fromTime = formatInvalidTime(trip.show.toString());
            // String toTime = formatInvalidTime(trip.left.toString());
            //
            // Navigator.pushNamed(context, "/playback",
            //     arguments: ReportArguments(
            //         int.parse(trip.device_id),
            //         fromDate,
            //         fromTime,
            //         toDate,
            //         toTime,
            //         args.name,
            //         0));
            // setState(() {
            //   _markers.add(
            //       MonumentMarker(
            //         monument: Monument(
            //             name: "",
            //             imagePath:
            //             'assets/images/arrow-red.png',
            //             lat: double.parse(bottomRouteList[index].latitude.toString()),
            //             long:  double.parse(bottomRouteList[index].longitude.toString()),
            //             course: double.parse(bottomRouteList[index].course.toString()).toInt(),
            //             speed: bottomRouteList[index].speed.toString()+" kmp",
            //             message: addressLoad(bottomRouteList[index].latitude.toString(), bottomRouteList[index].longitude.toString()),
            //             altitude: "0",
            //             duration: bottomRouteList[index].raw_time.toString(),
            //             event: ''
            //         ),
            //       ));
            // });
          },
          child: reportRow(trip, index),
        );
      },
    );
  }

  Widget reportRow(PlayBackRoute t, int index) {
    return Card(
        child: Container(
            padding: const EdgeInsets.all(5),
            child: Column(
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const Padding(padding: EdgeInsets.only(left: 10)),
                    index == 0
                        ? const SizedBox(
                            height: 50.0,
                            child: TimelineNode(
                              indicator: Card(
                                color: Colors.grey,
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: EdgeInsets.all(11.0),
                                  child: Text(
                                    'P',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                ),
                              ),
                              endConnector: SolidLineConnector(
                                color: Colors.grey,
                              ),
                            ),
                          )
                        : t.status == 1
                            ? const SizedBox(
                                height: 50.0,
                                child: TimelineNode(
                                  indicator: Card(
                                    color: Colors.blue,
                                    margin: EdgeInsets.zero,
                                    child: Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Icon(
                                          Icons.route,
                                          size: 12,
                                          color: Colors.white,
                                        )),
                                  ),
                                  startConnector: SolidLineConnector(
                                    color: Colors.blue,
                                  ),
                                  endConnector: SolidLineConnector(
                                    color: Colors.blue,
                                  ),
                                ),
                              )
                            : const SizedBox(
                                height: 50.0,
                                child: TimelineNode(
                                  indicator: Card(
                                    color: Colors.grey,
                                    margin: EdgeInsets.zero,
                                    child: Padding(
                                      padding: EdgeInsets.all(11.0),
                                      child: Text(
                                        'P',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  startConnector: SolidLineConnector(
                                    color: Colors.grey,
                                  ),
                                  endConnector: SolidLineConnector(
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                    t.status == 1
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                      padding: EdgeInsets.only(left: 14)),
                                  Row(
                                    children: [
                                      Text(
                                        Util.formatOnlyTime(t.show!),
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      const Padding(
                                          padding: EdgeInsets.only(
                                              left: 10, bottom: 20)),
                                      //Text(t.latitude.toString()+" "+t.longitude.toString(), style: TextStyle(fontSize: 13,color: Colors.grey),)
                                    ],
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Padding(
                                      padding: EdgeInsets.only(left: 14)),
                                  const Icon(
                                    Icons.timelapse_sharp,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                  const Padding(
                                      padding: EdgeInsets.only(left: 5)),
                                  Text(
                                    t.time!,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                  const Padding(
                                      padding: EdgeInsets.only(left: 5)),
                                  const Icon(
                                    Icons.route,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                  const Padding(
                                      padding: EdgeInsets.only(left: 5)),
                                  Text(
                                    "${t.distance} km",
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                  const Padding(
                                      padding: EdgeInsets.only(left: 5)),
                                  const Icon(
                                    Icons.speed,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                  const Padding(
                                      padding: EdgeInsets.only(left: 5)),
                                  Text(
                                    "${t.top_speed} km/h",
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Padding(padding: EdgeInsets.only(left: 12)),
                                  Padding(padding: EdgeInsets.only(left: 5)),
                                  //Text(t.latitude.toString()+" "+t.longitude.toString(), style: TextStyle(color: Colors.grey, fontSize: 13),)
                                ],
                              ),
                              const Padding(padding: EdgeInsets.only(top: 10)),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                          padding: EdgeInsets.only(left: 14)),
                                      Row(
                                        children: [
                                          Text(
                                            Util.formatOnlyTime(t.show!),
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold),
                                          ),
                                          const Padding(
                                              padding: EdgeInsets.only(
                                                  left: 10, bottom: 20)),
                                          //Text(t.latitude.toString()+" "+t.longitude.toString(), style: TextStyle(fontSize: 13,color: Colors.grey),)
                                        ],
                                      ),
                                    ],
                                  ),
                                  const Padding(
                                      padding: EdgeInsets.only(left: 8)),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Icon(
                                        Icons.timelapse_sharp,
                                        size: 18,
                                        color: Colors.blue,
                                      ),
                                      const Padding(
                                          padding: EdgeInsets.only(left: 5)),
                                      Row(children: [
                                        Text(t.time!,
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold)),
                                      ]),
                                      const Padding(
                                          padding: EdgeInsets.only(left: 5)),
                                      const Icon(
                                        Icons.key,
                                        size: 18,
                                        color: Colors.blue,
                                      ),
                                      const Padding(
                                          padding: EdgeInsets.only(left: 5)),
                                      Row(children: [
                                        Text(t.engine_hours.toString(),
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold)),
                                        const Text(" min",
                                            style: TextStyle(fontSize: 13))
                                      ]),
                                    ],
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                      padding:
                                          EdgeInsets.only(left: 14, top: 1)),
                                  Row(
                                    children: [
                                      // Text(Util.formatOnlyTime(t.show!), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),),
                                      //Padding(padding: EdgeInsets.only(left: 10)),
                                      SizedBox(
                                          width: MediaQuery.of(context)
                                                  .size
                                                  .width /
                                              1.7,
                                          child: addressLoad(
                                              t.latitude!, t.longitude!))
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          )
                  ],
                )
              ],
            )));
  }

  Widget addressLoad(String lat, lng) {
    return FutureBuilder<String>(
        future: APIService.getGeocoderAddress(lat, lng),
        builder: (context, AsyncSnapshot<String> snapshot) {
          if (snapshot.hasData) {
            return Text(
              snapshot.data!.replaceAll('"', ''),
              style: const TextStyle(color: Colors.black, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            );
          } else {
            return const Text("...");
          }
        });
  }
}
