import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as m;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
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
import 'package:gpspro/services/model/device_item.dart';
import 'package:gpspro/services/model/share_perm.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/util/util.dart';
import 'package:gpspro/widgets/address.dart';
import 'package:gpspro/widgets/banner_ad_widget.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:speedometer_chart/speedometer_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_math/vector_math.dart' as v;
import 'package:flutter/material.dart' as m;

import 'common_method.dart';

class TrackDevicePage extends StatefulWidget {
  final int? id;
  final String? name;
  final DeviceItem? device;

  const TrackDevicePage(this.id, this.name, this.device);

  @override
  State<StatefulWidget> createState() => _TrackDeviceState();
}

class _TrackDeviceState extends State<TrackDevicePage>
    with TickerProviderStateMixin {
  final List<Marker> _markers = <Marker>[];
  bool isLoading = false;
  MapType _currentMapType = MapType.normal;
  double currentZoom = 16.0;
  bool _trafficEnabled = false;
  final Completer<GoogleMapController> _controller = Completer();
  late GoogleMapController _mapController;
  double _dragStartPosition = 0;
  bool _isDragging = false;
  String? fuelConsumption;
  double _dialogHeight = 300.0;

  Widget _buildSpeedometer() {
    // Convert device speed to double (handle null/string cases)
    double speed = device?.speed != null
        ? double.tryParse(device!.speed.toString()) ?? 0.0
        : 0.0;

    return Container(
        // height: 80, // Adjust height as needed
        // width: 80,
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SpeedometerChart(
          dimension: 100,
          minValue: 0,
          maxValue: 150,
          value: speed,
          graphColor: [
            Colors.green,
            Colors.yellow,
            Colors.red,
          ],
          pointerColor: Colors.black,
        ));
  }

  DateTime _selectedFromDate = DateTime.now();
  DateTime _selectedToDate = DateTime.now();
  TimeOfDay _selectedFromTime = TimeOfDay.now();
  TimeOfDay _selectedToTime = TimeOfDay.now();
  Color _mapTypeBackgroundColor = CustomColor.primaryColor;
  Color _mapTypeForegroundColor = CustomColor.secondaryColor;

  Color _trafficBackgroundButtonColor = CustomColor.secondaryColor;
  Color _trafficForegroundButtonColor = CustomColor.primaryColor;
  int expiryTime = 10;

  bool first = true;

  LatLng? oldPin;
  String? _mapStyle;

  Animation<double>? _animation;

  final _mapMarkerSC = StreamController<List<Marker>>();

  StreamSink<List<Marker>> get _mapMarkerSink => _mapMarkerSC.sink;

  Stream<List<Marker>> get mapMarkerStream => _mapMarkerSC.stream;

  DeviceItem? device;
// Add these to your state class
  Timer? _todayKmTimer;
  Timer? _todayDetailsTimer;
  int _selectedperiod = 0;
  String address = "Show Address";
  List<LatLng> polylineCoordinates = [];
  Map<PolylineId, Polyline> polylines = {};
  TodayReportData? todayData;
  String? fromDate;
  String? toDate;
  String? fromTime;
  String? toTime;
  List<LatLng> newPolylinesData = [];

  bool _isPanelVisible = true;
  bool _isDisposed = false;

  String todaytotalDistance = "loading".tr;

// Function to get today's km data
  void getTodayKm() {
    if (!mounted) return;
    if (_isDisposed) return;
    final current = DateTime.now();
    final month = current.month.toString().padLeft(2, '0');
    final day = current.day.toString().padLeft(2, '0');

    final start = DateTime.parse(
      "${current.year}-$month-${day} 00:00:00",
    );
    final end = DateTime.parse(
      "${current.year}-$month-${day} 23:59:59",
    );

    final fromDate = formatDateReport(start.toString());
    final toDate = formatDateReport(end.toString());
    final fromTime = formatTimeReport(start.toString());
    final toTime = formatTimeReport(end.toString());

    APIService.getHistory(
      widget.device!.id.toString(),
      fromDate!,
      fromTime!,
      toDate!,
      toTime!,
    ).then((value) {
      if (value != null && mounted) {
        setState(() {
          todaytotalDistance = value.distance_sum ?? "0";
          fuelConsumption = value.fuel_consumption ?? '0';
        });
      }
    }).whenComplete(() {
      if (mounted) {
        _todayKmTimer = Timer(const Duration(seconds: 20), getTodayKm);
      }
    });
  }

  void getTodayDetails() async {
    if (!mounted) return;
    if (_isDisposed) return;
    try {
      final value = await ReportService.getTodayReportData(
        deviceId: widget.device?.id ?? 0,
      );

      if (mounted) {
        setState(() {
          todayData = value;
        });
      }

      log("${value.toJson()}");
    } catch (error) {
      log("Error fetching today's data: $error");
    } finally {
      if (mounted) {
        _todayDetailsTimer =
            Timer(const Duration(seconds: 20), getTodayDetails);
      }
    }
  }

  bool showAddress = false;
  @override
  initState() {
    rootBundle.loadString('assets/map_style.txt').then((string) {
      _mapStyle = string;
    });
    super.initState();
    drawPolyline();
    drawPolyline2();
    Timer startTimer(Function() callback) {
      callback();
      return Timer.periodic(const Duration(seconds: 20), (timer) => callback());
    }

    _todayKmTimer = startTimer(getTodayKm);
    _todayDetailsTimer = startTimer(getTodayDetails);
  }

  void drawPolyline2() async {
    PolylineId id = const PolylineId("polyAnim");
    Polyline polyline = Polyline(
        width: 3,
        polylineId: id,
        color: Colors.blueAccent,
        points: newPolylinesData);
    polylines[id] = polyline;
    setState(() {});
  }

  void drawPolyline() async {
    PolylineId id = const PolylineId("poly");
    Polyline polyline = Polyline(
        width: 3,
        polylineId: id,
        color: Colors.blue,
        points: polylineCoordinates);
    polylines[id] = polyline;
    setState(() {});
  }

  @override
  void dispose() {
    _todayKmTimer?.cancel();
    _todayDetailsTimer?.cancel();
    _mapMarkerSC.close();
    _mapMarkerSink.close();
    _mapController.dispose();
    _isDisposed = true;

    super.dispose();
  }

  void updateMarker(DeviceItem element) async {
    Util.fetchAndCacheImages(
            UserRepository.getServerUrl()! + "/" + element.icon!.path!)
        .then((_) async {
      BitmapDescriptor markerIcon;
      bool rotation = true;
      print(element.iconType);
      if (element.iconType == "arrow") {
        rotation = true;
        markerIcon = await Util.getMarkerIcon(element.icon!.path!);
      } else if (element.icon!.path!.contains("v2")) {
        if (element.iconType == "rotating") {
          rotation = true;
        } else {
          rotation = false;
        }
        markerIcon = await Util.getMarkerIcon(element.icon!.path!);
      } else {
        if (element.iconType == "rotating") {
          rotation = true;
        } else {
          rotation = false;
        }
        markerIcon = await Util.getMarkerIcon(element.icon!.path!);
      }

      var pinPosition = LatLng(double.parse(element.lat.toString()),
          double.parse(element.lng.toString()));

      if (first) {
        CameraPosition cPosition = CameraPosition(
          target: LatLng(double.parse(element.lat.toString()),
              double.parse(element.lng.toString())),
          zoom: currentZoom,
        );

        final pickupMarker = Marker(
            markerId: const MarkerId("driverMarker"),
            position: pinPosition,
            rotation: rotation ? double.parse(element.course.toString()) : 0,
            icon: markerIcon);

        //Adding a delay and then showing the marker on screen
        await Future.delayed(const Duration(milliseconds: 500));

        _markers.add(pickupMarker);
        _mapMarkerSink.add(_markers);

        oldPin = LatLng(double.parse(element.lat.toString()),
            double.parse(element.lng.toString()));

        final GoogleMapController controller = await _controller.future;
        controller.moveCamera(CameraUpdate.newCameraPosition(cPosition));
        isLoading = false;
        first = false;
      }

      if (!first) {
        Future.delayed(const Duration(seconds: 5)).then((value) {
          if (oldPin != pinPosition) {
            animateCar(
                oldPin!.latitude,
                oldPin!.longitude,
                double.parse(element.lat.toString()),
                double.parse(element.lng.toString()),
                _mapMarkerSink,
                this,
                _mapController,
                markerIcon);
            //polylineCoordinates.add(pinPosition);
          }
        });
      }
    });
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

  Future<Uint8List> getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
        targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  }

  currentMapStatus(CameraPosition position) {
    currentZoom = position.zoom;
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
            appBar: AppBar(
              backgroundColor: Colors.white,
              automaticallyImplyLeading: true,
              iconTheme: IconThemeData(color: CustomColor.cssBlack),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'trackDevice'.tr,
                    style: FlutterFlowTheme.of(context).headlineMedium,
                  ),
                ],
              ),
              centerTitle: false,
              elevation: 0,
            ),
            body: GetX<DataController>(
                init: DataController(),
                builder: (controller) {
                  for (var element in controller.onlyDevices) {
                    if (element.id == widget.id) {
                      device = element;
                      updateMarker(element);
                    }
                  }

                  return slidingPanel();
                })));
  }

  Widget slidingPanel() {
    return Stack(
      children: [
        // Full screen map
        !isLoading
            ? buildMap()
            : const Center(
                child: CircularProgressIndicator(),
              ),

        // Sliding panel
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          bottom: _isPanelVisible
              ? -MediaQuery.of(context).size.height * 0.095
              : -MediaQuery.of(context).size.height * 0.28,
          left: 0,
          right: 0,
          child: // Add these variables to your state class

// Replace your Container with this GestureDetector
              GestureDetector(
            onVerticalDragStart: (details) {
              _dragStartPosition = details.globalPosition.dy;
              _isDragging = true;
            },
            onVerticalDragUpdate: (details) {
              if (!_isDragging) return;

              final currentPosition = details.globalPosition.dy;
              final dragDistance = currentPosition - _dragStartPosition;

              // For immediate feedback while dragging (optional)
              // You can add visual feedback here if you want
            },
            onVerticalDragEnd: (details) {
              if (!_isDragging) return;
              _isDragging = false;

              final endPosition = details.globalPosition.dy;
              final dragDistance = endPosition - _dragStartPosition;
              final dragVelocity = details.primaryVelocity ?? 0;

              // Minimum swipe distance of 20 pixels
              if (dragDistance.abs() < 20) return;

              setState(() {
                // Swipe down (positive dragDistance)
                if (dragDistance > 0) {
                  _isPanelVisible = false;
                }
                // Swipe up (negative dragDistance)
                else {
                  _isPanelVisible = true;
                }
              });
            },
            child: Container(
              height: MediaQuery.of(context).size.height * 0.35,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(10.0),
                  topRight: Radius.circular(10.0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10.0,
                    spreadRadius: 1.0,
                  ),
                ],
              ),
              child: bottomPanelView(),
            ),
          ),
        ),
        Positioned(
            bottom: _isPanelVisible
                ? MediaQuery.of(context).size.height * 0.225
                : MediaQuery.of(context).size.height * 0.04,
            left: 0,
            right: 0,
            child: _buildSpeedometer()),
      ],
    );
  }

  Widget bottomPanelView() {
    Color? color;

    if (device!.iconColor != null) {
      if (device!.iconColor == "green") {
        color = Colors.green;
      } else if (device!.iconColor == "yellow") {
        color = Colors.yellow.shade700;
      } else {
        color = Colors.red;
      }
    } else {
      color = Colors.yellow.shade700;
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
                      children: <Widget>[
                        Image.asset(
                          "${"assets/images/sensors/" + sensor['type']}.png",
                          width: iconWidth,
                          height: iconWidth,
                        ),
                        const Padding(padding: EdgeInsets.only(left: 2)),
                        Column(children: [
                          Text(sensor["name"],
                              style: TextStyle(fontSize: fontWidth * 19)),
                          const Padding(padding: EdgeInsets.only(top: 2)),
                          Text(
                            gsmCodeConvert(sensor['value']),
                            style: TextStyle(fontSize: fontWidth * 19),
                          )
                        ])
                      ]))));
        }
      }
    } catch (e) {}

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.95,
      child: Column(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                  padding: const EdgeInsets.fromLTRB(10, 7, 0, 0),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Row(children: <Widget>[
                          Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: MediaQuery.of(context).size.width * 0.95,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          showAddress = true;
                                        });

                                        Future.delayed(Duration(seconds: 20),
                                            () {
                                          if (mounted) {
                                            setState(() {
                                              showAddress = false;
                                            });
                                          }
                                        });
                                      },
                                      child: Row(
                                        children: [
                                          m.Icon(Icons.location_on),
                                          Text(
                                            "showLocation".tr,
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: MediaQuery.of(context).size.width /
                                          2.5,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text(
                                            device!.name!,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 18),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Padding(padding: EdgeInsets.only(top: 2)),
                              if (showAddress)
                                Container(
                                  width:
                                      MediaQuery.of(context).size.width / 1.1,
                                  padding: const EdgeInsets.only(left: 5),
                                  child: addressLoadMarque(
                                      double.parse(device!.lat.toString())
                                          .toString(),
                                      double.parse(device!.lng.toString())
                                          .toString()),
                                ),
                              const Padding(padding: EdgeInsets.only(top: 2)),
                            ],
                          )
                        ]),
                      ])),
              const Divider(),
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  "statistics".tr,
                  style: TextStyle(
                      color: CustomColor.cssBlack,
                      fontWeight: FontWeight.w500,
                      fontSize: 13),
                ),
              ),
              const Padding(padding: EdgeInsets.only(top: 2)),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      SizedBox(
                        width: 6,
                      ),
                      Card(
                          elevation: 1,
                          shadowColor: color,
                          child: Container(
                              padding: const EdgeInsets.all(5),
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: <Widget>[
                                    Image.asset(
                                      "assets/images/sensors/total-distance.png",
                                      width: iconWidth,
                                      height: iconWidth,
                                    ),
                                    const Padding(
                                        padding: EdgeInsets.only(left: 2)),
                                    Column(
                                      children: [
                                        Text(("totalDistance").tr,
                                            style: TextStyle(
                                                fontSize: fontWidth * 19)),
                                        const Padding(
                                            padding: EdgeInsets.only(top: 2)),
                                        Text(
                                          device!.totalDistance.toString(),
                                          style: TextStyle(
                                              fontSize: fontWidth * 19),
                                        )
                                      ],
                                    )
                                  ]))),
                      Card(
                          elevation: 1,
                          shadowColor: color,
                          child: Container(
                              padding: const EdgeInsets.all(5),
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: <Widget>[
                                    Image.asset(
                                      "assets/icons/route-length.png",
                                      width: 25,
                                      height: 25,
                                    ),
                                    const Padding(
                                        padding: EdgeInsets.only(left: 2)),
                                    Column(
                                      children: [
                                        Text("todayKM".tr,
                                            style: TextStyle(
                                                fontSize: fontWidth * 19)),
                                        const Padding(
                                            padding: EdgeInsets.only(top: 2)),
                                        Text(
                                          todaytotalDistance,
                                          style: TextStyle(
                                              fontSize: fontWidth * 19),
                                        )
                                      ],
                                    )
                                  ]))),
                      Card(
                          elevation: 1,
                          shadowColor: color,
                          child: Container(
                              padding: const EdgeInsets.all(5),
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: <Widget>[
                                    Image.asset(
                                      "assets/images/sensors/engine_hours.png",
                                      width: iconWidth,
                                      height: iconWidth,
                                    ),
                                    const Padding(
                                        padding: EdgeInsets.only(left: 2)),
                                    Column(
                                      children: [
                                        Text("engineHours".tr,
                                            style: TextStyle(
                                                fontSize: fontWidth * 19)),
                                        const Padding(
                                            padding: EdgeInsets.only(top: 2)),
                                        Text(
                                          todayData?.engineHours ??
                                              'loading'.tr,
                                          style: TextStyle(
                                              fontSize: fontWidth * 19),
                                        )
                                      ],
                                    )
                                  ]))),
                      Card(
                          elevation: 1,
                          shadowColor: color,
                          child: Container(
                              padding: const EdgeInsets.all(5),
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: <Widget>[
                                    Image.asset(
                                      "assets/images/sensors/satellites.png",
                                      width: iconWidth,
                                      height: iconWidth,
                                    ),
                                    const Padding(
                                        padding: EdgeInsets.only(left: 2)),
                                    Column(
                                      children: [
                                        Text("moveDuration".tr,
                                            style: TextStyle(
                                                fontSize: fontWidth * 19)),
                                        const Padding(
                                            padding: EdgeInsets.only(top: 2)),
                                        Text(
                                          todayData?.moveDuration ??
                                              'loading'.tr,
                                          style: TextStyle(
                                              fontSize: fontWidth * 19),
                                        )
                                      ],
                                    )
                                  ]))),
                      Card(
                          elevation: 1,
                          shadowColor: color,
                          child: Container(
                              padding: const EdgeInsets.all(5),
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: <Widget>[
                                    Image.asset(
                                      "assets/images/sensors/door.png",
                                      width: iconWidth,
                                      height: iconWidth,
                                    ),
                                    const Padding(
                                        padding: EdgeInsets.only(left: 2)),
                                    Column(
                                      children: [
                                        Text("stopDuration".tr,
                                            style: TextStyle(
                                                fontSize: fontWidth * 19)),
                                        const Padding(
                                            padding: EdgeInsets.only(top: 2)),
                                        Text(
                                          todayData?.stopDuration ??
                                              'loading'.tr,
                                          style: TextStyle(
                                              fontSize: fontWidth * 19),
                                        )
                                      ],
                                    )
                                  ]))),
                      Card(
                          elevation: 1,
                          shadowColor: color,
                          child: Container(
                              padding: const EdgeInsets.all(5),
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: <Widget>[
                                    Image.asset(
                                      "assets/images/sensors/speed.png",
                                      width: iconWidth,
                                      height: iconWidth,
                                    ),
                                    const Padding(
                                        padding: EdgeInsets.only(left: 2)),
                                    Column(
                                      children: [
                                        Text("topSpeed".tr,
                                            style: TextStyle(
                                                fontSize: fontWidth * 19)),
                                        const Padding(
                                            padding: EdgeInsets.only(top: 2)),
                                        Text(
                                          todayData?.topSpeed ?? 'loading'.tr,
                                          style: TextStyle(
                                              fontSize: fontWidth * 19),
                                        )
                                      ],
                                    )
                                  ]))),
                      Card(
                          elevation: 1,
                          shadowColor: color,
                          child: Container(
                              padding: const EdgeInsets.all(5),
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: <Widget>[
                                    Image.asset(
                                      "assets/images/sensors/fuel_tank.png",
                                      width: 22,
                                      height: 22,
                                    ),
                                    const Padding(
                                        padding: EdgeInsets.only(left: 2)),
                                    Column(
                                      children: [
                                        Text("fuelConsumption".tr,
                                            style: TextStyle(
                                                fontSize: fontWidth * 19)),
                                        const Padding(
                                            padding: EdgeInsets.only(top: 2)),
                                        Text(
                                          fuelConsumption?.toString() ??
                                              'loading'.tr,
                                          style: TextStyle(
                                              fontSize: fontWidth * 19),
                                        )
                                      ],
                                    )
                                  ]))),
                      ...sensors
                    ],
                  )),
              Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  BannerAdWidget(
                    forceShow: ALWAYS_SHOW_BANNER_ADS,
                  ),
                ],
              )
            ],
          ),
        ],
      ),
    );
  }

  String gsmCodeConvert(value) {
    if (value == "71606") {
      return "Movistar";
    } else if (value == "71610") {
      return "Claro";
    } else if (value == "71617") {
      return "Entel";
    } else if (value == "71615") {
      return "Bitel";
    } else {
      return value;
    }
  }

  void _trafficEnabledPressed() {
    setState(() {
      _trafficEnabled = _trafficEnabled == false ? true : false;
      _trafficBackgroundButtonColor = _trafficEnabled == false
          ? CustomColor.secondaryColor
          : CustomColor.primaryColor;

      _trafficForegroundButtonColor = _trafficEnabled == false
          ? CustomColor.primaryColor
          : CustomColor.secondaryColor;
    });
  }

  Widget buildMap() {
    Color? color;

    if (device!.iconColor != null) {
      if (device!.iconColor == "green") {
        color = Colors.green;
      } else if (device!.iconColor == "yellow") {
        color = Colors.yellow.shade700;
      } else {
        color = Colors.red;
      }
    } else {
      color = Colors.yellow.shade700;
    }

    final googleMap = StreamBuilder<List<Marker>>(
        stream: mapMarkerStream,
        builder: (context, snapshot) {
          return GoogleMap(
            mapType: _currentMapType,
            trafficEnabled: _trafficEnabled,
            initialCameraPosition: CameraPosition(
              target: LatLng(double.parse(widget.device!.lat!.toString()),
                  double.parse(widget.device!.lng!.toString())),
              zoom: 16,
            ),
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            mapToolbarEnabled: false,
            myLocationEnabled: true,
            onCameraMove: currentMapStatus,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
              _mapController = controller;
              //_mapController.setMapStyle(_mapStyle);
            },
            polylines: Set<Polyline>.of(polylines.values),
            markers: Set<Marker>.of(snapshot.data ?? []),
            padding: const EdgeInsets.all(8),
          );
        });

    if (!isLoading) {
      return Stack(
        children: <Widget>[
          SizedBox(
              height: MediaQuery.of(context).size.height, child: googleMap),
          Align(
            alignment: Alignment.topRight,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 5, 0),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Column(
                      children: <Widget>[
                        FloatingActionButton(
                          heroTag: "mapTypeBtn",
                          onPressed: _onMapTypeButtonPressed,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          backgroundColor: _mapTypeBackgroundColor,
                          foregroundColor: _mapTypeForegroundColor,
                          mini: true,
                          child: const m.Icon(Icons.map, size: 30.0),
                        ),
                        FloatingActionButton(
                          heroTag: "trafficBtn",
                          mini: true,
                          onPressed: _trafficEnabledPressed,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          backgroundColor: _trafficBackgroundButtonColor,
                          foregroundColor: _trafficForegroundButtonColor,
                          child: const m.Icon(Icons.traffic, size: 30.0),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 5, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      children: <Widget>[
                        FloatingActionButton(
                          heroTag: "zoom_in",
                          mini: true,
                          onPressed: () {
                            _mapController.animateCamera(CameraUpdate.zoomIn());
                          },
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          backgroundColor: Colors.white,
                          foregroundColor: CustomColor.primaryColor,
                          child: const m.Icon(Icons.add, size: 30.0),
                        ),
                        const Padding(padding: EdgeInsets.only(top: 4)),
                        FloatingActionButton(
                          heroTag: "zoom_out",
                          mini: true,
                          onPressed: () {
                            _mapController
                                .animateCamera(CameraUpdate.zoomOut());
                          },
                          backgroundColor: Colors.white,
                          foregroundColor: CustomColor.primaryColor,
                          child: const m.Icon(Icons.remove, size: 30.0),
                        ),
                        const Padding(padding: EdgeInsets.only(top: 4)),
                        FloatingActionButton(
                          heroTag: "lock_device",
                          mini: true,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          backgroundColor: Colors.white,
                          foregroundColor: CustomColor.primaryColor,
                          child: const m.Icon(Icons.lock, size: 30.0),
                          onPressed: () async {
                            AdMobService()
                                .showInterstitialAd(ignoreFrequency: true);
                            Get.to(() => LockUnlockScreen(
                                  device: device!,
                                ));
                          },
                        ),
                        const Padding(padding: EdgeInsets.only(top: 4)),
                        FloatingActionButton(
                          heroTag: "playback_btn",
                          mini: true,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          backgroundColor: Colors.white,
                          foregroundColor: CustomColor.primaryColor,
                          child:
                              const m.Icon(Icons.play_arrow_sharp, size: 30.0),
                          onPressed: () async {
                            AdMobService()
                                .showInterstitialAd(ignoreFrequency: true);
                            Navigator.pushNamed(context, "/playback",
                                arguments: ReportArguments(widget.id!, "", "",
                                    "", "", widget.name!, 0, device!));
                          },
                        ),
                        const Padding(padding: EdgeInsets.only(top: 4)),
                        FloatingActionButton(
                          heroTag: "report_btn",
                          mini: true,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          backgroundColor: Colors.white,
                          foregroundColor: CustomColor.primaryColor,
                          child:
                              const m.Icon(Icons.insert_drive_file, size: 25.0),
                          onPressed: () async {
                            AdMobService()
                                .showInterstitialAd(ignoreFrequency: true);
                            showReportDialog(context, ('report').tr);
                          },
                        ),
                        const Padding(padding: EdgeInsets.only(top: 4)),
                        FloatingActionButton(
                          heroTag: "street_view",
                          mini: true,
                          onPressed: () {
                            Get.to(() => StreetViewScreen(
                                latitude: device?.lat ?? 0.0,
                                longitude: device?.lng ?? 0.0));
                          },
                          backgroundColor: Colors.white,
                          foregroundColor: CustomColor.primaryColor,
                          child: const m.Icon(Icons.share_location_rounded,
                              size: 30.0),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 180, 5, 0),
            child: Align(
              alignment: Alignment.topLeft,
              child: Column(
                children: <Widget>[
                  Padding(
                      padding: MediaQuery.of(context).size.aspectRatio > 0.55
                          ? const EdgeInsets.only(top: 60)
                          : const EdgeInsets.only(top: 150),
                      child: Container(
                          width: 60,
                          height: 60,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(
                                color: color,
                                width: 5,
                              )),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                device!.speed.toString(),
                                style: TextStyle(
                                    color: CustomColor.cssBlack,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17),
                              ),
                              const Text(
                                "Km/hr",
                                style: TextStyle(
                                    color: Colors.black, fontSize: 11),
                              )
                            ],
                          )))
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      return Center(
        child: Text("noData".tr),
      );
    }
  }

  void showReportDialog(BuildContext context, String heading) {
    // Always use today's values
    _selectedperiod = 0; // Today option
    showReport(heading);
  }

  void showReport(String heading) {
    String fromDate;
    String toDate;
    String fromTime;
    String toTime;

    DateTime current = DateTime.now();

    String month;
    if (current.month < 10) {
      month = "0${current.month}";
    } else {
      month = current.month.toString();
    }

    if (current.day < 10) {
    } else {}

    if (_selectedperiod == 0) {
      String today;

      int dayCon = current.day + 1;
      if (dayCon < 10) {
        today = "0$dayCon";
      } else {
        today = dayCon.toString();
      }

      var date = DateTime.parse("${current.year}-"
          "$month-"
          "$today "
          "00:00:00");
      fromDate = formatDateReport(DateTime.now().toString());
      toDate = formatDateReport(date.toString());
      fromTime = "00:00:00";
      toTime = "00:00:00";
    } else if (_selectedperiod == 1) {
      String yesterday;

      int dayCon = current.day - 1;
      if (current.day < 10) {
        yesterday = "0$dayCon";
      } else {
        yesterday = dayCon.toString();
      }

      var start = DateTime.parse("${current.year}-"
          "$month-"
          "$yesterday "
          "00:00:00");

      var end = DateTime.parse("${current.year}-"
          "$month-"
          "$yesterday "
          "24:00:00");

      fromDate = formatDateReport(start.toString());
      toDate = formatDateReport(end.toString());
      fromTime = "00:00:00";
      toTime = "00:00:00";
    } else if (_selectedperiod == 2) {
      String sevenDay, currentDayString;
      int dayCon = current.day - current.weekday;
      int currentDay = current.day;
      if (dayCon < 10) {
        sevenDay = "0${dayCon.abs()}";
      } else {
        sevenDay = dayCon.toString();
      }
      if (currentDay < 10) {
        currentDayString = "0$currentDay";
      } else {
        currentDayString = currentDay.toString();
      }

      var start = DateTime.parse("${current.year}-"
          "$month-"
          "$sevenDay "
          "00:00:00");

      var end = DateTime.parse("${current.year}-"
          "$month-"
          "$currentDayString "
          "24:00:00");

      fromDate = formatDateReport(start.toString());
      toDate = formatDateReport(end.toString());
      fromTime = "00:00:00";
      toTime = "00:00:00";
    } else {
      String startMonth, endMoth;
      if (_selectedFromDate.month < 10) {
        startMonth = "0${_selectedFromDate.month}";
      } else {
        startMonth = _selectedFromDate.month.toString();
      }

      if (_selectedToDate.month < 10) {
        endMoth = "0${_selectedToDate.month}";
      } else {
        endMoth = _selectedToDate.month.toString();
      }

      String startHour, endHour;
      if (_selectedFromTime.hour < 10) {
        startHour = "0${_selectedFromTime.hour}";
      } else {
        startHour = _selectedFromTime.hour.toString();
      }

      String startMin, endMin;
      if (_selectedFromTime.minute < 10) {
        startMin = "0${_selectedFromTime.minute}";
      } else {
        startMin = _selectedFromTime.minute.toString();
      }

      if (_selectedFromTime.minute < 10) {
        endMin = "0${_selectedToTime.minute}";
      } else {
        endMin = _selectedToTime.minute.toString();
      }

      if (_selectedToTime.hour < 10) {
        endHour = "0${_selectedToTime.hour}";
      } else {
        endHour = _selectedToTime.hour.toString();
      }

      String startDay, endDay;
      if (_selectedFromDate.day < 10) {
        if (_selectedFromDate.day == 10) {
          startDay = _selectedFromDate.day.toString();
        } else {
          startDay = "0${_selectedFromDate.day}";
        }
      } else {
        startDay = _selectedFromDate.day.toString();
      }

      if (_selectedToDate.day < 10) {
        if (_selectedToDate.day == 10) {
          endDay = _selectedToDate.day.toString();
        } else {
          endDay = "0${_selectedToDate.day}";
        }
      } else {
        endDay = _selectedToDate.day.toString();
      }

      var start = DateTime.parse("${_selectedFromDate.year}-"
          "$startMonth-"
          "$startDay "
          "$startHour:"
          "$startMin:"
          "00");

      var end = DateTime.parse("${_selectedToDate.year}-"
          "$endMoth-"
          "$endDay "
          "$endHour:"
          "$endMin:"
          "00");

      fromDate = formatDateReport(start.toString());
      toDate = formatDateReport(end.toString());
      fromTime = formatTimeReport(start.toString());
      toTime = formatTimeReport(end.toString());
    }

    Navigator.pop(context);
    Navigator.pushNamed(context, "/reportList",
        arguments: ReportArguments(widget.id!, fromDate, fromTime, toDate,
            toTime, widget.name!, 0, device!));
  }

  animateCar(
      double fromLat, //Starting latitude
      double fromLong, //Starting longitude
      double toLat, //Ending latitude
      double toLong, //Ending longitude
      StreamSink<List<Marker>>
          mapMarkerSink, //Stream build of map to update the UI
      TickerProvider
          provider, //Ticker provider of the widget. This is used for animation
      GoogleMapController controller,
      markerIcon //Google map controller of our widget
      ) async {
    final double bearing =
        getBearing(LatLng(fromLat, fromLong), LatLng(toLat, toLong));

    _markers.clear();

    var carMarker = Marker(
        markerId: const MarkerId("driverMarker"),
        position: LatLng(fromLat, fromLong),
        icon: markerIcon,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        rotation: bearing,
        draggable: false);

    //Adding initial marker to the start location.
    _markers.add(carMarker);
    mapMarkerSink.add(_markers);
    final animationController = AnimationController(
      duration: const Duration(seconds: 5), //Animation duration of marker
      vsync: provider, //From the widget
    );

    Tween<double> tween = Tween(begin: 0, end: 1);

    _animation = tween.animate(animationController)
      ..addListener(() async {
        //We are calculating new latitude and logitude for our marker
        final v = _animation!.value;
        double lng = v * toLong + (1 - v) * fromLong;
        double lat = v * toLat + (1 - v) * fromLat;
        LatLng newPos = LatLng(lat, lng);

        //Removing old marker if present in the marker array
        _markers.remove(carMarker);

        //New marker location
        carMarker = Marker(
            markerId: const MarkerId("driverMarker"),
            position: newPos,
            icon: markerIcon,
            anchor: const Offset(0.5, 0.5),
            flat: true,
            rotation: bearing,
            draggable: false);

        //Adding new marker to our list and updating the google map UI.
        _markers.add(carMarker);
        mapMarkerSink.add(_markers);
        newPolylinesData.add(carMarker.position);

        oldPin = newPos;
        //Moving the google camera to the new animated location.
      });
    controller.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(toLat, toLong), zoom: currentZoom)));
    polylineCoordinates.add(oldPin!);
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
