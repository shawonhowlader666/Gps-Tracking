import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_lock/arguments/stop_args.dart';
import 'package:smart_lock/services/model/playback_route.dart';
import 'package:smart_lock/screens/common_method.dart';
import 'package:smart_lock/theme/custom_color.dart';

class StopMapPage extends StatefulWidget {
  const StopMapPage({super.key});

  @override
  _StopMapPageState createState() => _StopMapPageState();
}

class _StopMapPageState extends State<StopMapPage> {
  final Completer<GoogleMapController> _controller = Completer();
  GoogleMapController? mapController;
  StreamController<int>? _postsController;
  final MapType _currentMapType = MapType.normal;
  StopArguments? args;
  Set<Marker> _markers = <Marker>{};
  Timer? _timer;
  PlayBackRoute? pb;

  @override
  void initState() {
    _postsController = StreamController();
    _timer = Timer.periodic(Duration(milliseconds: 1000), (timer) {
      if (args != null) {
        _timer!.cancel();
        addMarkers(args!.route);
      }
    });
    super.initState();
  }

  void addMarkers(PlayBackRoute pos) async {
    pb = pos;
    _postsController!.add(1);
    CameraPosition cPosition = CameraPosition(
      target: LatLng(double.parse(pos.latitude!), double.parse(pos.longitude!)),
      zoom: 16,
    );
    final GoogleMapController controller = await _controller.future;
    controller.moveCamera(CameraUpdate.newCameraPosition(cPosition));
    var iconPath = "images/end.png";
    final Uint8List? markerIcon = await getBytesFromAsset(iconPath, 70);
    _markers = <Marker>{};
    _markers.add(Marker(
      markerId: MarkerId(pos.device_id!),
      position:
          LatLng(double.parse(pos.latitude!), double.parse(pos.longitude!)),
      icon: BitmapDescriptor.bytes(markerIcon!),
    ));
    setState(() {});
  }

  static final CameraPosition _initialRegion = CameraPosition(
    target: LatLng(0, 0),
    zoom: 0,
  );

  @override
  void dispose() {
    if (_timer!.isActive) {
      _timer!.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    args = ModalRoute.of(context)!.settings.arguments as StopArguments;
    return SafeArea(
        child: Scaffold(
            appBar: AppBar(
              title: Text(args!.name,
                  style: TextStyle(color: CustomColor.secondaryColor)),
              iconTheme: IconThemeData(
                color: CustomColor.secondaryColor, //change your color here
              ),
            ),
            body: streamLoad()));
  }

  Widget streamLoad() {
    return StreamBuilder<int>(
        stream: _postsController!.stream,
        builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
          if (snapshot.hasData) {
            return loadMap();
          } else if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(),
            );
          } else {
            return Center(
              child: Text(('noData').tr),
            );
          }
        });
  }

  Widget loadMap() {
    return Stack(
      children: <Widget>[
        GoogleMap(
          mapType: _currentMapType,
          initialCameraPosition: _initialRegion,
          myLocationButtonEnabled: false,
          myLocationEnabled: true,
          onMapCreated: (GoogleMapController controller) {
            _controller.complete(controller);
            mapController = controller;
          },
          markers: _markers,
          onTap: (LatLng latLng) {},
        ),
        // ignore: unnecessary_null_comparison
        pb != null ? bottomWindow() : Container()
      ],
    );
  }

  Widget bottomWindow() {
    return Positioned(
        bottom: 0,
        right: 0,
        left: 0,
        child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
                //margin: EdgeInsets.all(10),
                margin: EdgeInsets.fromLTRB(10, 0, 60, 30),
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                          blurRadius: 20,
                          offset: Offset.zero,
                          color: Colors.grey.withValues(alpha: 0.5))
                    ]),
                child: Column(
                  children: <Widget>[
                    // position.address != null
                    //     ? Row(
                    //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    //   children: <Widget>[
                    //     Container(
                    //       padding: EdgeInsets.only(left: 5.0),
                    //       child: Icon(Icons.location_on_outlined,
                    //           color: CustomColor.primaryColor,
                    //           size: 20.0),
                    //     ),
                    //     Expanded(
                    //       child: Column(children: [
                    //         Padding(
                    //             padding: EdgeInsets.only(
                    //                 top: 10.0, left: 5.0, right: 0),
                    //             child: Text(
                    //               utf8.decode(
                    //                   utf8.encode(position.address!)),
                    //               maxLines: 2,
                    //               overflow: TextOverflow.ellipsis,
                    //             )),
                    //       ]),
                    //     )
                    //   ],
                    // )
                    //     : new Container(),
                    Row(
                      children: [
                        Container(
                            padding: EdgeInsets.only(top: 3.0, left: 5.0),
                            child: Row(
                              children: <Widget>[
                                Container(
                                  padding: EdgeInsets.only(left: 3.0),
                                  child: Icon(Icons.speed,
                                      color: CustomColor.primaryColor,
                                      size: 20.0),
                                ),
                              ],
                            )),
                        Container(
                            padding: EdgeInsets.only(
                                top: 5.0, left: 5.0, right: 10.0),
                            child: Text("${pb!.speed} kph")),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                            padding: EdgeInsets.only(top: 3.0, left: 5.0),
                            child: Row(
                              children: <Widget>[
                                Container(
                                  padding: EdgeInsets.only(left: 5.0),
                                  child: Icon(Icons.access_time_outlined,
                                      color: CustomColor.primaryColor,
                                      size: 15.0),
                                ),
                              ],
                            )),
                        Container(
                            padding: EdgeInsets.only(
                                top: 5.0, left: 5.0, right: 10.0),
                            child: Text(
                              pb!.show!,
                              style: TextStyle(fontSize: 11),
                            )),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                            padding: EdgeInsets.only(top: 3.0, left: 5.0),
                            child: Row(
                              children: <Widget>[
                                Container(
                                  padding: EdgeInsets.only(left: 5.0),
                                  child: Icon(Icons.location_on,
                                      color: CustomColor.primaryColor,
                                      size: 15.0),
                                ),
                              ],
                            )),
                        Container(
                            padding: EdgeInsets.only(
                                top: 5.0, left: 5.0, right: 10.0),
                            child: Text(
                              "Lat: ${pb!.latitude} Lng:${pb!.longitude}",
                              style: TextStyle(fontSize: 11),
                            )),
                      ],
                    ),
                  ],
                ))));
  }
}
