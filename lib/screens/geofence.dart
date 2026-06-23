import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_lock/services/model/user.dart';
import 'package:smart_lock/theme/custom_color.dart';
import 'package:smart_lock/ui/custom_icon.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'geofence_list.dart';

class GeofencePage extends StatefulWidget {
  const GeofencePage({super.key});

  @override
  State<StatefulWidget> createState() => _GeofencePageState();
}

class _GeofencePageState extends State<GeofencePage> {
  static FenceArguments? args;
  final Completer<GoogleMapController> _controller = Completer();
  GoogleMapController? mapController;
  MapType _currentMapType = MapType.normal;
  bool _trafficEnabled = false;
  Color _trafficButtonColor = CustomColor.primaryColor;
  Set<Marker> _markers = <Marker>{};
  Set<Circle> _circles = <Circle>{};
  double _valRadius = 500;
  final double _valRadiusMax = 10000;
  bool addFenceVisible = false;
  bool deleteFenceVisible = false;
  bool addClicked = false;
  final TextEditingController _fenceName = TextEditingController();
  LatLng? _position;
  SharedPreferences? prefs;
  User? user;
  String? deleteFenceId;
  bool isLoading = false;

  Marker? newFenceMarker;
  List<LatLng> polylineCoordinates = [];
  Map<PolylineId, Polyline> polylines = {};

  @override
  initState() {
    super.initState();
    getFences();
  }

  void getFences() async {
    _markers = <Marker>{};
    _circles = <Circle>{};
  }

  void drawPolyline() async {
    PolylineId id = PolylineId("poly");
    Polyline polyline = Polyline(
        width: 6,
        polylineId: id,
        color: Colors.greenAccent,
        points: polylineCoordinates);
    polylines[id] = polyline;
    setState(() {});
  }

  Future<BitmapDescriptor> _myPainterToBitmap(String label, String icon) async {
    ui.PictureRecorder recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    CustomIcon myPainter = CustomIcon(label, icon);

    final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontSize: 30, color: Colors.black),
        ),
        textDirection: TextDirection.ltr);
    textPainter.layout();

    myPainter.paint(canvas,
        Size(textPainter.size.width + 30, textPainter.size.height + 25));
    final ui.Image image = await recorder.endRecording().toImage(
        textPainter.size.width.toInt() + 30,
        textPainter.size.height.toInt() + 25 + 50);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);

    Uint8List data = byteData!.buffer.asUint8List();
    setState(() {});
    return BitmapDescriptor.bytes(data);
  }

  void check(CameraUpdate u, GoogleMapController c) async {
    c.animateCamera(u);
    mapController!.animateCamera(u);
    LatLngBounds l1 = await c.getVisibleRegion();
    LatLngBounds l2 = await c.getVisibleRegion();
    mapController!.animateCamera(CameraUpdate.zoomTo(4));
    if (l1.southwest.latitude == -90 || l2.southwest.latitude == -90) {
      check(u, c);
    }
  }

  void _onMapTypeButtonPressed() {
    setState(() {
      _currentMapType = _currentMapType == MapType.normal
          ? MapType.satellite
          : MapType.normal;
    });
  }

  void _trafficEnabledPressed() {
    setState(() {
      _trafficEnabled = _trafficEnabled == false ? true : false;
      _trafficButtonColor =
          _trafficEnabled == false ? CustomColor.primaryColor : Colors.green;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void addFenceMarker() {
    if (addClicked) {
      setState(() {
        _myPainterToBitmap(('newFence').tr, "marker")
            .then((BitmapDescriptor bitmapDescriptor) {
          _markers.add(Marker(
            markerId: MarkerId("marker"),
            position: _position!,
            icon: bitmapDescriptor,
            anchor: Offset(0.5, 1),
            draggable: true,
            onDragEnd: (value) {},
          ));
          updateNewCircle(_valRadius);
          addFenceVisible = true;
          mapController!.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(target: _position!, zoom: 15)));
        });
      });
    }
  }

  void updateNewCircle(radius) {
    _circles = <Circle>{};
    setState(() {
      _circles.add(Circle(
          circleId: CircleId("circle"),
          fillColor: Color(0x40189ad3),
          strokeColor: Color(0x00000000),
          strokeWidth: 2,
          center: _position!,
          radius: radius));
    });
  }

  void deleteFence() {
    _showProgress(true);
  }

  void submitFence() {
    _showProgress(true);

    // GeofenceModel fence = new GeofenceModel();
    // fence.area = pos;
    // fence.name = _fenceName.text;

    // var fenceCon = json.encode(fence);
    // GeofenceModel fenceObj;
    // APIService.addGeofence(fenceCon.toString()).then((value) => {
    //       fenceObj = GeofenceModel.fromJson(json.decode(value.body)),
    //     });
  }

  static final CameraPosition _initialRegion = CameraPosition(
    target: LatLng(0, 0),
    zoom: 3,
  );

  @override
  Widget build(BuildContext context) {
    args = ModalRoute.of(context)!.settings.arguments as FenceArguments;
    return Scaffold(
      appBar: AppBar(
        title: Text(args!.fenceModel!.name!,
            style: TextStyle(color: CustomColor.secondaryColor)),
        iconTheme: IconThemeData(
          color: CustomColor.secondaryColor, //change your color here
        ),
      ),
      body: Stack(children: <Widget>[
        GoogleMap(
          mapType: _currentMapType,
          initialCameraPosition: _initialRegion,
          onTap: (pos) {
            _position = pos;
            addFenceMarker();
          },
          trafficEnabled: _trafficEnabled,
          myLocationButtonEnabled: false,
          myLocationEnabled: true,
          onMapCreated: (GoogleMapController controller) {
            _controller.complete(controller);
            mapController = controller;
            // CustomProgressIndicatorWidget().showProgressDialog(context,
            //     AppLocalizations.of(context)!.translate('sharedLoading'));
            isLoading = true;
            getFences();
          },
          markers: _markers,
          circles: _circles,
          polylines: Set<Polyline>.of(polylines.values),
        ),
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: Align(
            alignment: Alignment.topRight,
            child: Column(
              children: <Widget>[
                FloatingActionButton(
                  heroTag: "mapType",
                  onPressed: _onMapTypeButtonPressed,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  backgroundColor: CustomColor.primaryColor,
                  mini: true,
                  child: const Icon(Icons.map, size: 30.0),
                ),
                FloatingActionButton(
                  heroTag: "traffic",
                  onPressed: _trafficEnabledPressed,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  backgroundColor: _trafficButtonColor,
                  mini: true,
                  child: const Icon(Icons.traffic, size: 30.0),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget addFenceControls() {
    return Positioned(
      bottom: 0,
      right: 0,
      left: 0,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: EdgeInsets.all(15),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.all(Radius.circular(20)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                    blurRadius: 20,
                    offset: Offset.zero,
                    color: Colors.grey.withValues(alpha: 0.5))
              ]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                  width: MediaQuery.of(context).size.width * 0.95,
                  child: Row(
                    children: <Widget>[
                      Container(
                          width: MediaQuery.of(context).size.width * 0.90,
                          padding: EdgeInsets.all(5.0),
                          child: TextField(
                            controller: _fenceName,
                            decoration:
                                InputDecoration(labelText: ('fenceName').tr),
                          )),
                    ],
                  )),
              Container(
                  width: MediaQuery.of(context).size.width * 0.97,
                  padding: EdgeInsets.all(5.0),
                  child: Row(
                    children: <Widget>[
                      Text(('radius').tr),
                      SizedBox(
                          width: MediaQuery.of(context).size.width * 0.65,
                          child: Slider(
                            value: _valRadius,
                            onChanged: (newSliderValue) {
                              setState(() {
                                _valRadius = newSliderValue;
                                updateNewCircle(_valRadius);
                              });
                            },
                            min: 500,
                            max: _valRadiusMax,
                          )),
                      Text(
                        _valRadius.toStringAsFixed(0),
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  )),
              Container(
                  padding: EdgeInsets.all(10.0),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                          width: MediaQuery.of(context).size.width * 0.86,
                          child: ElevatedButton(
                            onPressed: () {
                              if (_fenceName.text.isNotEmpty) {
                                submitFence();
                              } else {
                                Fluttertoast.showToast(
                                    msg: ("enterFenceName").tr,
                                    toastLength: Toast.LENGTH_SHORT,
                                    gravity: ToastGravity.CENTER,
                                    timeInSecForIosWeb: 1,
                                    backgroundColor: Colors.green,
                                    textColor: Colors.white,
                                    fontSize: 16.0);
                              }
                            },
                            child: Text(('addGeofence').tr),
                          )),
                    ],
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showProgress(bool status) async {
    if (status) {
      return showDialog<void>(
        context: context,
        barrierDismissible: true, // user must tap button!
        builder: (BuildContext context) {
          return AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                Container(
                    margin: EdgeInsets.only(left: 5),
                    child: Text(('sharedLoading').tr)),
              ],
            ),
          );
        },
      );
    } else {
      Navigator.pop(context);
    }
  }
}

class Choice {
  const Choice({this.title, this.icon});

  final String? title;
  final IconData? icon;
}
