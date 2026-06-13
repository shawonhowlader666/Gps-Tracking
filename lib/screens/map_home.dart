import 'dart:async';
import 'dart:convert';
import 'dart:math' show cos, sqrt, asin;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gap/gap.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gpspro/arguments/device_args.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/services/model/device_item.dart';
import 'package:gpspro/services/model/geofence_model.dart';
import 'package:gpspro/preference.dart';
import 'package:gpspro/screens/common_method.dart';
import 'package:gpspro/screens/geofence.dart';
import 'package:gpspro/screens/track_device.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/util/util.dart';
import 'package:label_marker/label_marker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart' as m;

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<StatefulWidget> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final Completer<GoogleMapController> _controller = Completer();
  final GlobalKey<ScaffoldState> _drawerKey = GlobalKey();
  final TextEditingController _searchController = TextEditingController();
  // final PanelController _pc = PanelController();

  GoogleMapController? mapController;
  Set<Marker> _markers = <Marker>{};
  MapType _currentMapType = MapType.normal;
  final bool _trafficEnabled = false;
  int _selectedDeviceId = 0;
  bool deviceSelected = false;
  LatLng? _location;
  DeviceItem? device;

  var latLng;
  double currentZoom = 14;
  List<DeviceItem> devicesList = [];
  final List<dynamic> _searchResult = [];
  String selectedIndex = "all";
  Timer? _timer;
  List<LatLng> polylineCoordinates = [];
  Map<PolylineId, Polyline> polylines = {};

  bool first = true;
  bool streetView = false;

  bool isTextEnabled = true;
  int expiryTime = 10;
  SharedPreferences? prefs;

  List<Geofence> fenceList = [];

  bool geofenceEnabled = false;
  final Set<Circle> _circles = <Circle>{};
  Map<PolygonId, Polygon> polygons = {};

  List<Choice> menuChoices = [];
  List<Choice> choices = [];

  DataController dataController = Get.put(DataController());
  String? _mapStyle;

  @override
  initState() {
    checkPreference();
    rootBundle.loadString('assets/map_style.txt').then((string) {
      _mapStyle = string;
    });
    super.initState();
  }

  void checkPreference() async {
    prefs = await SharedPreferences.getInstance();
    menuChoices = <Choice>[
      Choice(title: ('normal').tr, icon: Icons.directions_car),
      Choice(title: ('hybrid').tr, icon: Icons.directions_car),
      Choice(title: ('satellite').tr, icon: Icons.directions_car),
    ];
    if (prefs!.getString(PREF_MAP_TYPE) != null) {
      setState(() {
        if (prefs!.getString(PREF_MAP_TYPE) == "1") {
          _currentMapType = MapType.normal;
        } else if (prefs!.getString(PREF_MAP_TYPE) == "2") {
          _currentMapType = MapType.hybrid;
        } else if (prefs!.getString(PREF_MAP_TYPE) == "3") {
          _currentMapType = MapType.satellite;
        }
      });
    }
  }

  void getFences() async {
    APIService.getGeoFences().then((value) => {
          // _timer.cancel(),
          fenceList = value!,
          {
            if (value.isNotEmpty)
              {
                value.forEach((element) {
                  if (element.type == "circle") {
                    _updateCircle(element.id, element.center['lat'].toString(),
                        element.center['lng'].toString(), element.radius);
                  }
                  if (element.type == "polygon") {
                    List<LatLng> polylineCoordinatesGeoFences = [];
                    json.decode(element.coordinates).forEach((element) {
                      polylineCoordinatesGeoFences
                          .add(LatLng(element["lat"], element["lng"]));
                    });
                    PolygonId id = PolygonId(element.id.toString());
                    Polygon polygon = Polygon(
                        strokeWidth: 2,
                        polygonId: id,
                        fillColor: Colors.blueAccent.withValues(alpha: 0.5),
                        geodesic: true,
                        points: polylineCoordinatesGeoFences);
                    polygons[id] = polygon;
                  }
                })
              },
          },
        });
  }

  void _updateCircle(id, lat, lng, radius) {
    setState(() {
      _circles.add(Circle(
          circleId: CircleId(id.toString()),
          fillColor: const Color(0x40189ad3),
          strokeColor: const Color(0x00000000),
          strokeWidth: 2,
          center: LatLng(double.parse(lat), double.parse(lng)),
          radius: double.parse(radius.toString())));
    });
  }

  void _onMapCreated() async {
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    //_pc.close();
    setState(() {
      _location = LatLng(position.latitude, position.longitude);
    });
  }

  void addMarker(DataController controller) {
    _markers = <Marker>{};
    LatLngBounds? bound;
    for (var element in controller.devices) {
      if (element.items!.isNotEmpty) {
        element.items!.forEach((element) async {
          if (element.deviceData!.active.toString() == "1") {
            Util.fetchAndCacheImages(
                    "${UserRepository.getServerUrl()!}/${element.icon!.path!}")
                .then((_) async {
              BitmapDescriptor markerIcon;
              bool rotation = true;
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
              _markers.add(
                Marker(
                    markerId: MarkerId(element.id.toString()),
                    position: LatLng(double.parse(element.lat.toString()),
                        double.parse(element.lng.toString())),
                    // updated position
                    rotation:
                        rotation ? double.parse(element.course.toString()) : 0,
                    icon: markerIcon,
                    onTap: () {
                      device = element;
                      // Navigator.pushNamed(context, "/trackDevice",
                      //     arguments:
                      //     DeviceArguments(device!.id!, device!.name!, device!));

                      Get.to('/home',
                          arguments: DeviceArguments(
                              device!.id!, device!.name!, device!));

                      mapController!.getZoomLevel().then((value) => {
                            if (value < 14)
                              {
                                currentZoom = 16,
                              }
                          });
                      CameraPosition cPosition = CameraPosition(
                        target: LatLng(element.lat, element.lng),
                        zoom: currentZoom,
                      );
                      mapController!.moveCamera(
                          CameraUpdate.newCameraPosition(cPosition));
                      _selectedDeviceId = element.id!;
                      setState(() {
                        //.open();
                        //slidingPanelHeight = 130;
                        streetView = true;
                        polylines.clear();
                        polylineCoordinates.clear();

                        for (var tail in element.tail!) {
                          polylineCoordinates.add(LatLng(
                              double.parse(tail.lat.toString()),
                              double.parse(tail.lng.toString())));
                        }
                        drawPolyline();
                        device = element;
                        polylineCoordinates.add(LatLng(
                            double.parse(element.lat.toString()),
                            double.parse(element.lng.toString())));
                      });
                    },
                    infoWindow: const InfoWindow(
                        // title: widget.model.devices[value.deviceId].name,
                        )),
              );

              if (isTextEnabled) {
                _markers.addLabelMarker(LabelMarker(
                  label: element.name!,
                  markerId: MarkerId("t_${element.id}"),
                  position: LatLng(double.parse(element.lat.toString()),
                      double.parse(element.lng.toString())),
                ));
              }
              bound = boundsFromLatLngList(_markers);
              // Perform additional actions if necessary.
            }).catchError((error) {
              print('Error fetching and caching images: $error');
            });
          }
        });
      }
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (bound != null) {
        CameraUpdate u2 = CameraUpdate.newLatLngBounds(bound!, 50);
        if (mapController != null) {
          mapController!.animateCamera(u2).then((void v) {
            check(u2, mapController!);
          });
          _timer!.cancel();
          setState(() {});
        }
      }
    });
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

  void check(CameraUpdate u, GoogleMapController c) async {
    c.animateCamera(u);
    mapController!.animateCamera(u);
    LatLngBounds l1 = await c.getVisibleRegion();
    LatLngBounds l2 = await c.getVisibleRegion();
    if (l1.southwest.latitude == -90 || l2.southwest.latitude == -90) {
      check(u, c);
    }
  }

  void updateMarker(DataController controller) async {
    for (var value in controller.devices) {
      if (value.items!.isNotEmpty) {
        value.items!.forEach((element) async {
          if (element.deviceData!.active.toString() == "0") {
            _markers
                .removeWhere((m) => m.markerId.value == element.id.toString());
            _markers.removeWhere((m) => m.markerId.value == "t_${element.id}");
          }

          if (element.deviceData!.active.toString() == "1") {
            Util.fetchAndCacheImages(
                    "${UserRepository.getServerUrl()!}/${element.icon!.path!}")
                .then((_) async {
              BitmapDescriptor markerIcon;
              if (element.iconType == "arrow") {
                markerIcon = await Util.getMarkerIcon(element.icon!.path!);
              } else if (element.icon!.path!.contains("v2")) {
                markerIcon = await Util.getMarkerIcon(element.icon!.path!);
              } else {
                markerIcon = await Util.getMarkerIcon(element.icon!.path!);
              }

              var pinPosition = LatLng(double.parse(element.lat.toString()),
                  double.parse(element.lng.toString()));

              _markers.removeWhere(
                  (m) => m.markerId.value == element.id.toString());

              _markers
                  .removeWhere((m) => m.markerId.value == "t_${element.id}");

              _markers.add(Marker(
                markerId: MarkerId(element.id.toString()),
                position: pinPosition,
                // updated position
                rotation: double.parse(element.course.toString()),
                icon: markerIcon,
                onTap: () {
                  device = element;
                  Get.to(
                      () => TrackDevicePage(device!.id, device!.name, device));
                  mapController!.getZoomLevel().then((value) => {
                        if (value < 14)
                          {
                            currentZoom = 16,
                          }
                      });

                  CameraPosition cPosition = CameraPosition(
                    target: LatLng(double.parse(element.lat.toString()),
                        double.parse(element.lng.toString())),
                    zoom: currentZoom,
                  );
                  mapController!
                      .moveCamera(CameraUpdate.newCameraPosition(cPosition));
                  //slidingPanelHeight = 130;
                  setState(() {
                    _selectedDeviceId = element.id!;
                    streetView = true;
                    polylines.clear();
                    polylineCoordinates.clear();

                    for (var tail in element.tail!) {
                      polylineCoordinates.add(LatLng(
                          double.parse(tail.lat.toString()),
                          double.parse(tail.lng.toString())));
                    }
                    drawPolyline();
                    device = element;
                    polylineCoordinates.add(LatLng(
                        double.parse(element.lat.toString()),
                        double.parse(element.lng.toString())));
                  });
                },
              ));

              if (isTextEnabled) {
                _markers.addLabelMarker(LabelMarker(
                  label: element.name!,
                  markerId: MarkerId("t_${element.id}"),
                  position: LatLng(double.parse(element.lat.toString()),
                      double.parse(element.lng.toString())),
                ));

                if (_selectedDeviceId == element.id) {
                  device = element;
                  polylineCoordinates.add(LatLng(
                      double.parse(element.lat.toString()),
                      double.parse(element.lng.toString())));
                }
              }
            });
          }
        });
      }
    }
  }

  void _removeMarkerName() {
    if (isTextEnabled) {
      for (var element in dataController.devices) {
        if (element.items!.isNotEmpty) {
          element.items!.forEach((element) async {
            if (element.deviceData!.active.toString() == "1") {
              _markers.removeWhere(
                  (m) => m.markerId.value == "t_${element.id}");
            }
          });
        }
      }
      setState(() {
        isTextEnabled = false;
      });
    } else {
      isTextEnabled = true;
      setState(() {
        updateMarker(dataController);
      });
    }
  }

  double calculateDistance(lat1, lon1, lat2, lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  void _reloadMap() {
    device = null;
    _selectedDeviceId = 0;
    setState(() {});
    // slidingPanelHeight = 0;
    // _pc.close();
    //widget.model.devices.forEach((key, value) {
    LatLngBounds bound = boundsFromLatLngList(_markers);

    polylines.clear();
    polylineCoordinates.clear();
    setState(() {});
    CameraUpdate u2 = CameraUpdate.newLatLngBounds(bound, 100);
    mapController!.animateCamera(u2).then((void v) {
      check(u2, mapController!);
    });

    Fluttertoast.showToast(
        msg: ("showingAllDevices").tr,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.CENTER,
        timeInSecForIosWeb: 1,
        backgroundColor: Colors.black54,
        textColor: Colors.white,
        fontSize: 16.0);
    // });
  }

  void removeMarker(val, device) async {
    _showProgress(true);
    if (val) {
      Map<String, String> requestBody = <String, String>{
        'id': device.id.toString(),
        'active': "1"
      };
      APIService.activateDevice(requestBody).then((value) => {
            dataController.getDevices().then((value) => {
                  setState(() {
                    _showProgress(false);
                  })
                })
          });
    } else {
      Map<String, String> requestBody = <String, String>{
        'id': device.id.toString(),
        'active': "0"
      };
      APIService.activateDevice(requestBody).then((value) => {
            dataController.getDevices().then((value) => {
                  _markers.removeWhere(
                      (m) => m.markerId.value == device.id.toString()),
                  _markers
                      .removeWhere((m) => m.markerId.value == "t_${device.id}"),
                  setState(() {
                    _showProgress(false);
                  })
                })
          });
    }
  }

  void moveToMarker() {
    if (device!.deviceData!.active.toString() == "1") {
      currentZoom = 16;
      if (device!.lat != null) {
        CameraPosition cPosition = CameraPosition(
          target: LatLng(double.parse(device!.lat.toString()),
              double.parse(device!.lng.toString())),
          zoom: currentZoom,
        );
        mapController!.animateCamera(CameraUpdate.newCameraPosition(cPosition));
        _selectedDeviceId = device!.id!;
        onSearchTextChanged(_searchController.text);
        setState(() {
          //slidingPanelHeight = 130;
          _selectedDeviceId = device!.id!;
          streetView = true;
          polylines.clear();
          polylineCoordinates.clear();
          for (var tail in device!.tail!) {
            polylineCoordinates.add(LatLng(double.parse(tail.lat.toString()),
                double.parse(tail.lng.toString())));
          }
          drawPolyline();
          device = device;
          polylineCoordinates.add(LatLng(double.parse(device!.lat.toString()),
              double.parse(device!.lng.toString())));
        });
        Navigator.pop(context);
      }
    }
  }

  static const CameraPosition _initialRegion = CameraPosition(
    target: LatLng(21.7679, 78.8718),
    zoom: 4,
  );

  Future<void> onSearchTextChanged(String text) async {
    _searchResult.clear();

    if (text.toLowerCase().isEmpty) {
      setState(() {});
      return;
    }

    for (var device in devicesList) {
      if (device.name!.toLowerCase().contains(text.toLowerCase())) {
        _searchResult.add(device);
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: GetX<DataController>(
            init: DataController(),
            builder: (controller) {
              devicesList = controller.onlyDevices;

              if (controller.devices.isNotEmpty) {
                if (first) {
                  addMarker(controller);
                  first = false;
                } else {
                  if (controller.devices.isNotEmpty) {
                    updateMarker(controller);
                  }
                }
              }

              if (!controller.isLoading.value) {
                return buildMap();
              } else {
                return const Center(child: CircularProgressIndicator());
              }
            }));
  }

  Widget navDrawer() {
    return Drawer(
        child: Column(children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
        child: Card(
          child: ListTile(
            leading: const m.Icon(Icons.search),
            title: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                  hintText: ('search').tr,
                  border: InputBorder.none,
                  hintStyle: const TextStyle(fontSize: 12)),
              onChanged: onSearchTextChanged,
            ),
            trailing: IconButton(
              icon: const m.Icon(Icons.cancel),
              onPressed: () {
                _searchController.clear();
                onSearchTextChanged('');
              },
            ),
          ),
        ),
      ),
      Expanded(
          child: _searchResult.isNotEmpty || _searchController.text.isNotEmpty
              ? ListView.builder(
                  itemCount: _searchResult.length,
                  itemBuilder: (context, index) {
                    final device = _searchResult[index];
                    return deviceCard(device, context);
                  },
                )
              : selectedIndex == "all"
                  ? ListView.builder(
                      itemCount: devicesList.length,
                      itemBuilder: (context, index) {
                        final device = devicesList[index];
                        return deviceCard(device, context);
                      })
                  : ListView.builder(
                      itemCount: 0,
                      itemBuilder: (context, index) {
                        return Text(("noDeviceFound").tr);
                      }))
    ]));
  }

  Widget deviceCard(DeviceItem d, BuildContext context) {
    Color? color;

    if (d.iconColor != null) {
      if (d.iconColor == "green") {
        color = Colors.green;
      } else if (d.iconColor == "yellow") {
        color = YELLOW_CUSTOM;
      } else if (d.iconColor == "red") {
        color = Colors.red;
      }
    } else {
      color = Colors.red;
    }

    return GestureDetector(
      onTap: () => {
        device = d,
        moveToMarker(),
        Get.to(() => TrackDevicePage(d.id, d.name, d))
      },
      child: Card(
          elevation: 2.0,
          shadowColor: color,
          child: Padding(
              padding: const EdgeInsets.only(
                  top: 5, bottom: 10, left: 10, right: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        padding: const EdgeInsets.only(right: 10),
                        child: Checkbox(
                            value: d.deviceData!.active.toString() == "1"
                                ? true
                                : false,
                            onChanged: (val) {
                              removeMarker(val, d);
                            }),
                      ),
                      Container(
                          width: MediaQuery.of(context).size.width / 2.15,
                          padding: const EdgeInsets.only(right: 10),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,

                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                SizedBox(
                                    width:
                                        MediaQuery.of(context).size.width / 3.5,
                                    child: Text(d.name!,
                                        style: const TextStyle(
                                            overflow: TextOverflow.ellipsis,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700))),
                                Container(
                                    padding:
                                        const EdgeInsets.fromLTRB(8, 2, 8, 2),
                                    decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: const BorderRadius.all(
                                            Radius.circular(4))),
                                    child: d.speed > 0
                                        ? Text(
                                            convertSpeed(
                                                double.parse(d.speed!.toString()),
                                                d.distanceUnitHour!),
                                            style: TextStyle(
                                                color: CustomColor.secondaryColor,
                                                fontSize: 13),
                                          )
                                        : Text(
                                            convertSpeed(
                                                double.parse(d.speed!.toString()),
                                                d.distanceUnitHour!),
                                            style: TextStyle(
                                                color: CustomColor.secondaryColor,
                                                fontSize: 13),
                                          ))
                              ],
                            ),
                          )),
                    ],
                  ),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                      child: Row(
                        children: [
                          const m.Icon(
                            Icons.access_time_outlined,
                            size: 20,
                          ),
                          const Padding(padding: EdgeInsets.only(left: 5)),
                          Text(
                            d.time!,
                            textAlign: TextAlign.start,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ))
                ],
              ))),
    );
  }

  void selectedMapType(Choice choice) {
    setState(() {
      if (choice.title == ("satellite").tr) {
        prefs!.setString(PREF_MAP_TYPE, "3");
        _currentMapType = MapType.satellite;
      } else if (choice.title == ("terrain").tr) {
        prefs!.setString(PREF_MAP_TYPE, "1");
        _currentMapType = MapType.terrain;
      } else if (choice.title == ("hybrid").tr) {
        prefs!.setString(PREF_MAP_TYPE, "2");
        _currentMapType = MapType.hybrid;
      } else if (choice.title == ("normal").tr) {
        prefs!.setString(PREF_MAP_TYPE, "1");
        _currentMapType = MapType.normal;
      }
    });
  }

  Widget buildMap() {
    return Stack(
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(5, 20, 5, 0),
        ),
        GoogleMap(
          mapType: _currentMapType,
          initialCameraPosition: _initialRegion,
          trafficEnabled: _trafficEnabled,
          myLocationButtonEnabled: false,
          myLocationEnabled: true,
          onMapCreated: (GoogleMapController controller) {
            _controller.complete(controller);
            mapController = controller;
            _onMapCreated();
            // mapController!.setMapStyle(_mapStyle);
          },
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
          markers: _markers,
          polylines: Set<Polyline>.of(polylines.values),
          onTap: (LatLng latLng) {
            setState(() {
              // _pc.close();
              // slidingPanelHeight = 0;
              streetView = false;
            });
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 100, 7, 0),
          child: Align(
            alignment: Alignment.topRight,
            child: Column(
              children: <Widget>[
                FloatingActionButton(
                  heroTag: "mapTypeLocation",
                  mini: true,
                  onPressed: () {
                    CameraPosition cPosition = CameraPosition(
                      target: _location!,
                      zoom: currentZoom,
                    );
                    mapController!.animateCamera(
                        CameraUpdate.newCameraPosition(cPosition));
                  },
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  foregroundColor: CustomColor.primaryColor,
                  backgroundColor: CustomColor.secondaryColor,
                  child: const m.Icon(Icons.gps_fixed, size: 30.0),
                ),
                FloatingActionButton(
                  heroTag: "mapTypeMenu",
                  mini: true,
                  onPressed: () {},
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  foregroundColor: CustomColor.primaryColor,
                  backgroundColor: CustomColor.secondaryColor,
                  child: PopupMenuButton<Choice>(
                    onSelected: selectedMapType,
                    icon: const m.Icon(
                      Icons.map,
                    ),
                    itemBuilder: (BuildContext context) {
                      return menuChoices.map((Choice choice) {
                        return PopupMenuItem<Choice>(
                          value: choice,
                          child: Text(choice.title!),
                        );
                      }).toList();
                    },
                  ),
                ),
                FloatingActionButton(
                  heroTag: "reloadMap",
                  mini: true,
                  onPressed: _reloadMap,
                  backgroundColor: CustomColor.secondaryColor,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  foregroundColor: CustomColor.primaryColor,
                  child: const m.Icon(Icons.refresh, size: 30.0),
                ),
                // Visibility(
                //   visible: streetView,
                //   child: FloatingActionButton(
                //       heroTag: "streetView",
                //       mini: true,
                //       onPressed: _streetView,
                //       backgroundColor: CustomColor.secondaryColor,
                //       materialTapTargetSize: MaterialTapTargetSize.padded,
                //       foregroundColor: CustomColor.primaryColor,
                //       child: const m.Icon(Icons.streetview, size: 30.0)),
                // ),
                FloatingActionButton(
                    heroTag: "text",
                    mini: true,
                    onPressed: _removeMarkerName,
                    backgroundColor: CustomColor.secondaryColor,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    foregroundColor: CustomColor.primaryColor,
                    child: const m.Icon(Icons.text_fields, size: 30.0)),
                const Padding(padding: EdgeInsets.only(top: 10)),
                FloatingActionButton(
                  heroTag: "zoomIn",
                  mini: true,
                  onPressed: () {
                    mapController!.animateCamera(CameraUpdate.zoomIn());
                  },
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  backgroundColor: Colors.white,
                  foregroundColor: CustomColor.primaryColor,
                  child: const m.Icon(Icons.add, size: 30.0),
                ),
                const Padding(padding: EdgeInsets.only(top: 15)),
                FloatingActionButton(
                  heroTag: "zoomOut",
                  mini: true,
                  onPressed: () {
                    mapController!.animateCamera(CameraUpdate.zoomOut());
                  },
                  backgroundColor: Colors.white,
                  foregroundColor: CustomColor.primaryColor,
                  child: const m.Icon(Icons.remove, size: 30.0),
                ),
                // const Padding(padding: EdgeInsets.only(top: 10)),
                // Visibility(
                //   visible: streetView,
                //   child: FloatingActionButton(
                //       heroTag: "commands",
                //       mini: true,
                //       onPressed: (){
                //         showSavedCommandDialog(context);
                //       },
                //       backgroundColor: CustomColor.secondaryColor,
                //       materialTapTargetSize: MaterialTapTargetSize.padded,
                //       foregroundColor: CustomColor.primaryColor,
                //       child: const m.Icon(Icons.send_to_mobile, size: 30.0)),
                // ),
                // Visibility(
                //     visible: streetView,
                //     child:FloatingActionButton(
                //       heroTag: "whatsapp",
                //       mini: true,
                //       backgroundColor: CustomColor.secondaryColor,
                //       materialTapTargetSize: MaterialTapTargetSize.padded,
                //       foregroundColor: CustomColor.primaryColor,
                //       child: const FaIcon(FontAwesomeIcons.whatsapp, size: 30.0),
                //       onPressed: () async{
                //         String origin = "${device!.lat},${device!.lng}"; // lat,long like 123.34,68.56
                //
                //         String query = Uri.encodeComponent(origin);
                //         await FlutterShare.share(
                //             title: 'Device Info',
                //             text: 'Object: ${device!.name} \n Imei: ${device!.deviceData!.traccar!.uniqueId}',
                //             linkUrl: "https://www.google.com/maps/search/?api=1&query=$query",
                //             chooserTitle: ''
                //         );
                //       },
                //     )),
                // Visibility(
                //     visible: streetView,
                //     child:FloatingActionButton(
                //       heroTag: "streetView",
                //       mini: true,
                //       backgroundColor: CustomColor.secondaryColor,
                //       materialTapTargetSize: MaterialTapTargetSize.padded,
                //       foregroundColor: CustomColor.primaryColor,
                //       child: const FaIcon(FontAwesomeIcons.streetView, size: 30.0),
                //       onPressed: () async{
                //         launchUrl(Uri.parse("https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${device!.lat},${device!.lng}&heading=0&pitch=0&fov=80"));
                //       },
                //     )),
              ],
            ),
          ),
        ),
        // Stack(
        //   children: [
        //     Positioned(
        //       left: 5,
        //       top: 10,
        //       child: FloatingActionButton(
        //         heroTag: "openDrawer",
        //         mini: true,
        //         onPressed: () {
        //           _drawerKey.currentState!.openDrawer();
        //           setState(() {});
        //         },
        //         materialTapTargetSize: MaterialTapTargetSize.padded,
        //         backgroundColor: CustomColor.secondaryColor,
        //         foregroundColor: CustomColor.primaryColor,
        //         child: const m.Icon(Icons.menu, size: 25.0),
        //       ),
        //     ),
        //   ],
        // )
      ],
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
                const CircularProgressIndicator(),
                Container(
                    margin: const EdgeInsets.only(left: 5),
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
