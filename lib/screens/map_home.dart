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
import 'package:gpspro/services/model/device_item.dart' hide Icon;
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
import 'package:gpspro/services/payment_service.dart';
import 'package:gpspro/services/model/billing_vehicle.dart';
import 'package:gpspro/screens/payment_list.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<StatefulWidget> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with AutomaticKeepAliveClientMixin {
  final Completer<GoogleMapController> _controller = Completer();
  final GlobalKey<ScaffoldState> _drawerKey = GlobalKey();
  final TextEditingController _searchController = TextEditingController();
  // final PanelController _pc = PanelController();

  GoogleMapController? mapController;
  Set<Marker> _markers = <Marker>{};
  final Map<int, String> _lastDeviceStates = {};
  MapType _currentMapType = MapType.normal;
  Map<String, BillingVehicle> _billingMap = {};
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
  int _currentMarkerSize = 38;
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
  StreamSubscription? _devicesSubscription;

  @override
  initState() {
    checkPreference();
    rootBundle.loadString('assets/map_style.txt').then((string) {
      _mapStyle = string;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadBillingInfo();
      }
    });

    _devicesSubscription = dataController.devices.listen((devices) {
      if (mounted && devices.isNotEmpty && mapController != null) {
        if (first) {
          addMarker(dataController);
          first = false;
        } else {
          updateMarker(dataController);
        }
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    if (_timer != null && _timer!.isActive) {
      _timer!.cancel();
    }
    super.dispose();
  }

  Future<void> _loadBillingInfo() async {
    try {
      final billingList = await PaymentService.getBillingVehicles();
      if (billingList != null && mounted) {
        setState(() {
          _billingMap = {for (var v in billingList) v.imei: v};
        });
      }
    } catch (e) {
      debugPrint('Error loading billing info in MapPage: $e');
    }
  }

  bool _isDeviceSuspended(DeviceItem device) {
    final imei = device.imei ?? device.deviceData?.imei;
    if (imei == null) return false;
    final billingInfo = _billingMap[imei];
    if (billingInfo == null) return false;

    if (!billingInfo.isActive) {
      return true;
    }

    if (billingInfo.expirationDate != null) {
      try {
        final expDate = DateTime.parse(billingInfo.expirationDate!);
        if (expDate.isBefore(DateTime.now())) {
          final daysPassed = DateTime.now().difference(expDate).inDays;
          if (daysPassed > 10) {
            return true;
          }
        }
      } catch (_) {}
    }
    return false;
  }

  void _showSuspendedDialog(DeviceItem device) {
    final imei = device.imei ?? device.deviceData?.imei;
    final billingInfo = imei != null ? _billingMap[imei] : null;
    final monthlyBillStr = billingInfo?.monthlyBill != null 
        ? " (মান্থলি বিল: ৳${billingInfo!.monthlyBill!.toStringAsFixed(0)})" 
        : "";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_clock_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('সেবা সাময়িকভাবে স্থগিত', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'আপনার "${device.name ?? 'ডিভাইস'}" গাড়িটির বিল বকেয়া থাকায় বা মেয়াদ শেষ হওয়ায় ট্র্যাকিং সাময়িকভাবে স্থগিত করা হয়েছে$monthlyBillStr। অবিলম্বে ট্র্যাকিং সচল করতে বকেয়া বিল পরিশোধ করুন।',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('বন্ধ করুন', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Get.to(() => const PaymentListScreen())?.then((_) {
                _loadBillingInfo();
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('বিল পরিশোধ করুন', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
    if (mounted) {
      setState(() {
        _location = LatLng(position.latitude, position.longitude);
      });
    }
  }

  void addMarker(DataController controller) {
    _markers = <Marker>{};
    List<Future> futures = [];
    _lastDeviceStates.clear();

    for (var element in controller.devices) {
      if (element.items!.isNotEmpty) {
        for (var subElement in element.items!) {
          if (subElement.deviceData!.active.toString() == "1") {
            final String path = subElement.icon!.path!;
            final String statusColor = Util.getDeviceStatusColorStr(subElement);
            final cachedIcon = Util.getCachedMarkerIcon(path, _currentMarkerSize,
                statusColor: statusColor,
                iconType: subElement.icon?.type ?? subElement.iconType,
                deviceName: subElement.name,
                deviceId: subElement.id);
            
            final double course = double.tryParse(subElement.course.toString()) ?? 0.0;

            final markerId = MarkerId(subElement.id.toString());
            final labelId = MarkerId("t_${subElement.id}");

            void buildAndAddMarker(BitmapDescriptor icon) {
              _markers.add(
                Marker(
                    markerId: markerId,
                    position: LatLng(double.parse(subElement.lat.toString()),
                        double.parse(subElement.lng.toString())),
                    rotation: course,
                    icon: icon,
                    anchor: const Offset(0.5, 0.5),
                    flat: true,
                    onTap: () {
                      device = subElement;
                      Get.to('/home',
                          arguments: DeviceArguments(
                              device!.id!, device!.name!, device!));

                      mapController!.getZoomLevel().then((value) => {
                            if (value < 15)
                              {
                                currentZoom = 15.5,
                              }
                          });
                      CameraPosition cPosition = CameraPosition(
                        target: LatLng(subElement.lat, subElement.lng),
                        zoom: currentZoom,
                      );
                      mapController!.moveCamera(
                          CameraUpdate.newCameraPosition(cPosition));
                      _selectedDeviceId = subElement.id!;
                      setState(() {
                        streetView = true;
                        polylines.clear();
                        polylineCoordinates.clear();

                        for (var tail in subElement.tail!) {
                          polylineCoordinates.add(LatLng(
                              double.parse(tail.lat.toString()),
                              double.parse(tail.lng.toString())));
                        }
                        drawPolyline();
                        device = subElement;
                        polylineCoordinates.add(LatLng(
                            double.parse(subElement.lat.toString()),
                            double.parse(subElement.lng.toString())));
                      });
                    },
                    infoWindow: const InfoWindow()),
              );

              if (isTextEnabled) {
                _markers.addLabelMarker(LabelMarker(
                  label: subElement.name!,
                  markerId: labelId,
                  position: LatLng(double.parse(subElement.lat.toString()),
                      double.parse(subElement.lng.toString())),
                ));
              }
            }

            if (cachedIcon != null) {
              buildAndAddMarker(cachedIcon);
            } else {
              final f = Util.getMarkerIcon(path,
                      size: _currentMarkerSize,
                      statusColor: statusColor,
                      iconType: subElement.icon?.type ?? subElement.iconType,
                      deviceName: subElement.name,
                      deviceId: subElement.id,
                      device: subElement)
                  .then((markerIcon) {
                if (mounted) {
                  setState(() {
                    buildAndAddMarker(markerIcon);
                  });
                }
              }).catchError((error) {
                print('Error fetching marker: $error');
              });
              futures.add(f);
            }
          }
        }
      }
    }

    if (futures.isNotEmpty) {
      Future.wait(futures).then((_) {
        _fitBounds();
      });
    } else {
      _fitBounds();
    }
  }

  void _fitBounds() {
    if (mounted && _markers.isNotEmpty && mapController != null) {
      try {
        LatLngBounds bound = boundsFromLatLngList(_markers);
        if (bound.southwest.latitude == bound.northeast.latitude &&
            bound.southwest.longitude == bound.northeast.longitude) {
          CameraPosition cPosition = CameraPosition(
            target: bound.southwest,
            zoom: 15,
          );
          mapController!.animateCamera(CameraUpdate.newCameraPosition(cPosition));
        } else {
          CameraUpdate u = CameraUpdate.newLatLngBounds(bound, 80);
          mapController!.animateCamera(u).then((void v) {
            check(u, mapController!);
          });
        }
      } catch (e) {
        print("Error fitting camera bounds: $e");
      }
    }
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
    List<Future> futures = [];
    bool hasChanges = false;

    for (var value in controller.devices) {
      if (value.items!.isNotEmpty) {
        for (var element in value.items!) {
          if (element.deviceData!.active.toString() == "0") {
            _markers.removeWhere((m) => m.markerId.value == element.id.toString());
            _markers.removeWhere((m) => m.markerId.value == "t_${element.id}");
            _lastDeviceStates.remove(element.id);
            hasChanges = true;
          }

          if (element.deviceData!.active.toString() == "1") {
            final String path = element.icon!.path!;
            final String? localAssetPath = Util.getLocalMappedAsset(
                path,
                iconType: element.icon?.type ?? element.iconType,
                deviceName: element.name,
                deviceId: element.id);
            final String statusColor = Util.getDeviceStatusColorStr(element);
            final cachedIcon = Util.getCachedMarkerIcon(path, _currentMarkerSize,
                statusColor: statusColor,
                iconType: element.icon?.type ?? element.iconType,
                deviceName: element.name,
                deviceId: element.id);
            
            final double course = double.tryParse(element.course.toString()) ?? 0.0;

            final double lat = double.parse(element.lat.toString());
            final double lng = double.parse(element.lng.toString());
            final String currentState = "$lat,$lng,$course,${element.name},$statusColor,$_currentMarkerSize,$path,$localAssetPath";
            if (_lastDeviceStates[element.id] == currentState) {
              continue;
            }
            _lastDeviceStates[element.id!] = currentState;
            hasChanges = true;

            final markerId = MarkerId(element.id.toString());
            final labelId = MarkerId("t_${element.id}");

            void buildAndAddMarker(BitmapDescriptor icon) {
              _markers.removeWhere((m) => m.markerId.value == element.id.toString());
              _markers.removeWhere((m) => m.markerId.value == "t_${element.id}");

              _markers.add(Marker(
                markerId: markerId,
                position: LatLng(double.parse(element.lat.toString()),
                    double.parse(element.lng.toString())),
                rotation: course,
                icon: icon,
                anchor: const Offset(0.5, 0.5),
                flat: true,
                onTap: () {
                  device = element;
                  if (_isDeviceSuspended(device!)) {
                    _showSuspendedDialog(device!);
                  } else {
                    Get.to(() => TrackDevicePage(device!.id, device!.name, device));
                  }
                  mapController!.getZoomLevel().then((value) => {
                        if (value < 15)
                          {
                            currentZoom = 15.5,
                          }
                      });

                  CameraPosition cPosition = CameraPosition(
                    target: LatLng(double.parse(element.lat.toString()),
                        double.parse(element.lng.toString())),
                    zoom: currentZoom,
                  );
                  mapController!
                      .moveCamera(CameraUpdate.newCameraPosition(cPosition));
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
                  markerId: labelId,
                  position: LatLng(double.parse(element.lat.toString()),
                      double.parse(element.lng.toString())),
                ));
              }

              if (_selectedDeviceId == element.id) {
                device = element;
                polylineCoordinates.clear();
                for (var tail in element.tail!) {
                  polylineCoordinates.add(LatLng(
                      double.parse(tail.lat.toString()),
                      double.parse(tail.lng.toString())));
                }
                polylineCoordinates.add(LatLng(
                    double.parse(element.lat.toString()),
                    double.parse(element.lng.toString())));
                
                // Re-draw the polyline
                PolylineId id = const PolylineId("poly");
                Polyline polyline = Polyline(
                    width: 3,
                    polylineId: id,
                    color: Colors.blue,
                    points: polylineCoordinates);
                polylines[id] = polyline;
              }
            }

            if (cachedIcon != null) {
              buildAndAddMarker(cachedIcon);
              hasChanges = true;
            } else {
              final f = Util.getMarkerIcon(path,
                      size: _currentMarkerSize,
                      statusColor: statusColor,
                      iconType: element.icon?.type ?? element.iconType,
                      deviceName: element.name,
                      deviceId: element.id,
                      device: element)
                  .then((markerIcon) {
                if (mounted) {
                  setState(() {
                    buildAndAddMarker(markerIcon);
                  });
                }
              });
              futures.add(f);
            }
          }
        }
      }
    }

    if (futures.isNotEmpty) {
      Future.wait(futures).then((_) {
        if (mounted) {
          setState(() {});
        }
      });
    } else if (hasChanges) {
      if (mounted) {
        setState(() {});
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
    polylines.clear();
    polylineCoordinates.clear();
    setState(() {});

    if (_markers.isNotEmpty) {
      LatLngBounds bound = boundsFromLatLngList(_markers);
      CameraUpdate u2 = CameraUpdate.newLatLngBounds(bound, 100);
      mapController!.animateCamera(u2).then((void v) {
        check(u2, mapController!);
      });
    }

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
      currentZoom = 15.5;
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
    target: LatLng(23.6850, 90.3563),
    zoom: 7,
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
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
        body: GetBuilder<DataController>(
            init: dataController,
            builder: (controller) {
              devicesList = controller.onlyDevices;

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
        color = const Color(0xFF00C853);
      } else if (d.iconColor == "yellow") {
        color = const Color(0xFFFF9100);
      } else if (d.iconColor == "red") {
        color = const Color(0xFFEF5350);
      }
    } else {
      color = const Color(0xFFEF5350);
    }

    return GestureDetector(
      onTap: () => {
        device = d,
        moveToMarker(),
        if (_isDeviceSuspended(d)) {
          _showSuspendedDialog(d)
        } else {
          Get.to(() => TrackDevicePage(d.id, d.name, d))
        }
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

  void _onZoomChanged(double zoom) {
    final int newSize = Util.getMarkerSizeForZoom(zoom);
    if (newSize != _currentMarkerSize) {
      if (mounted) {
        setState(() {
          _currentMarkerSize = newSize;
        });
        updateMarker(dataController);
      }
    }
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
            if (dataController.devices.isNotEmpty) {
              if (first) {
                addMarker(dataController);
                first = false;
              } else {
                updateMarker(dataController);
              }
            }
            // mapController!.setMapStyle(_mapStyle);
          },
          onCameraIdle: () {
            if (mapController != null) {
              mapController!.getZoomLevel().then((zoom) {
                _onZoomChanged(zoom);
              });
            }
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
                  foregroundColor: CustomColor.primary,
                  backgroundColor: CustomColor.secondaryColor,
                  child: const m.Icon(Icons.gps_fixed, size: 30.0, color: CustomColor.primary),
                ),
                FloatingActionButton(
                  heroTag: "mapTypeMenu",
                  mini: true,
                  onPressed: () {},
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  foregroundColor: CustomColor.primary,
                  backgroundColor: CustomColor.secondaryColor,
                  child: PopupMenuButton<Choice>(
                    onSelected: selectedMapType,
                    icon: const m.Icon(
                      Icons.map,
                      color: CustomColor.primary,
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
                  foregroundColor: CustomColor.primary,
                  child: const m.Icon(Icons.refresh, size: 30.0, color: CustomColor.primary),
                ),
                FloatingActionButton(
                    heroTag: "text",
                    mini: true,
                    onPressed: _removeMarkerName,
                    backgroundColor: CustomColor.secondaryColor,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    foregroundColor: CustomColor.primary,
                    child: const m.Icon(Icons.text_fields, size: 30.0, color: CustomColor.primary)),
                const Padding(padding: EdgeInsets.only(top: 10)),
                FloatingActionButton(
                  heroTag: "zoomIn",
                  mini: true,
                  onPressed: () {
                    mapController!.animateCamera(CameraUpdate.zoomIn());
                  },
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  backgroundColor: Colors.white,
                  foregroundColor: CustomColor.primary,
                  child: const m.Icon(Icons.add, size: 30.0, color: CustomColor.primary),
                ),
                const Padding(padding: EdgeInsets.only(top: 15)),
                FloatingActionButton(
                  heroTag: "zoomOut",
                  mini: true,
                  onPressed: () {
                    mapController!.animateCamera(CameraUpdate.zoomOut());
                  },
                  backgroundColor: Colors.white,
                  foregroundColor: CustomColor.primary,
                  child: const m.Icon(Icons.remove, size: 30.0, color: CustomColor.primary),
                ),
              ],
            ),
          ),
        ),
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
