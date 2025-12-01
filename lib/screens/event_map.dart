import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/services/model/event.dart';
import 'package:gpspro/screens/report/report_event.dart';
import 'package:gpspro/theme/custom_color.dart';

class EventMapPage extends StatefulWidget {
  @override
  _EventMapPageState createState() => _EventMapPageState();
}

class _EventMapPageState extends State<EventMapPage> {
  Completer<GoogleMapController> _controller = Completer();
  GoogleMapController? mapController;
  StreamController<int>? _postsController;
  MapType _currentMapType = MapType.normal;
  static ReportEventArgument? args;
  Set<Marker> _markers = Set<Marker>();
  Timer? _timer;
  Event? event;

  @override
  void initState() {
    _postsController = new StreamController();
    getPosition();
    super.initState();
  }

  void getPosition() {
    _timer = new Timer.periodic(Duration(seconds: 1), (timer) {
      if (args != null) _timer!.cancel();
      // APIService.getEventById(args.eventId.toString()).then((event) => {
      //       APIService.getPositionById(
      //               event.deviceId.toString(), event.positionId.toString())
      //           .then((value) => {addMarkers(value.single, event)})
      //     });
    });
  }

  void addMarkers(pos, Event e) async {
    // position = pos;
    // event = e;
    // _postsController.add(1);
    // CameraPosition cPosition = CameraPosition(
    //   target: LatLng(pos.latitude, pos.longitude),
    //   zoom: 16,
    // );
    // final GoogleMapController controller = await _controller.future;
    // controller.moveCamera(CameraUpdate.newCameraPosition(cPosition));
    // var iconPath;
    // if (event.type == "alarm") {
    //   iconPath = "images/alarm_event.png";
    // } else {
    //   iconPath = "images/normal_event.png";
    // }
    // final Uint8List markerIcon = await getBytesFromAsset(iconPath, 70);
    // _markers = Set<Marker>();
    // _markers.add(Marker(
    //   markerId: MarkerId(pos.deviceId.toString()),
    //   position: LatLng(pos.latitude, pos.longitude), // updated position
    //   icon: BitmapDescriptor.fromBytes(markerIcon),
    // ));
    // setState(() {});
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
    args = ModalRoute.of(context)!.settings.arguments as ReportEventArgument;
    return SafeArea(
        child: Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.white,
              iconTheme: IconThemeData(color: CustomColor.cssBlack),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    args!.name,
                    style: FlutterFlowTheme.of(context).headlineMedium,
                  ),
                ],
              ),
              centerTitle: false,
              elevation: 0,
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
        //position != null ? bottomWindow() : new Container()
      ],
    );
  }

  // Widget bottomWindow() {
  //   String result;
  //   if (event.attributes.containsKey("result")) {
  //     result = event.attributes["result"];
  //   } else {
  //     result = "";
  //   }
  //   return Positioned(
  //       bottom: 0,
  //       right: 0,
  //       left: 0,
  //       child: Align(
  //           alignment: Alignment.bottomCenter,
  //           child: Container(
  //               //margin: EdgeInsets.all(10),
  //               margin: EdgeInsets.fromLTRB(10, 0, 10, 30),
  //               padding: EdgeInsets.all(10),
  //               decoration: BoxDecoration(
  //                   color: Colors.white,
  //                   borderRadius: BorderRadius.all(Radius.circular(10)),
  //                   boxShadow: <BoxShadow>[
  //                     BoxShadow(
  //                         blurRadius: 20,
  //                         offset: Offset.zero,
  //                         color: Colors.grey.withOpacity(0.5))
  //                   ]),
  //               child: Column(
  //                 children: <Widget>[
  //                   position.address != null
  //                       ? Row(
  //                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //                           children: <Widget>[
  //                             Container(
  //                               padding: EdgeInsets.only(left: 5.0),
  //                               child: Icon(Icons.location_on_outlined,
  //                                   color: CustomColor.primaryColor,
  //                                   size: 20.0),
  //                             ),
  //                             Expanded(
  //                               child: Column(children: [
  //                                 Padding(
  //                                     padding: EdgeInsets.only(
  //                                         top: 10.0, left: 5.0, right: 0),
  //                                     child: Text(
  //                                       utf8.decode(
  //                                           utf8.encode(position.address)),
  //                                       maxLines: 2,
  //                                       overflow: TextOverflow.ellipsis,
  //                                     )),
  //                               ]),
  //                             )
  //                           ],
  //                         )
  //                       : new Container(),
  //                   Row(
  //                     children: [
  //                       Container(
  //                           padding: EdgeInsets.only(top: 3.0, left: 5.0),
  //                           child: Row(
  //                             children: <Widget>[
  //                               Container(
  //                                 padding: EdgeInsets.only(left: 3.0),
  //                                 child: Icon(Icons.event_note,
  //                                     color: CustomColor.primaryColor,
  //                                     size: 20.0),
  //                               ),
  //                             ],
  //                           )),
  //                       Container(
  //                           padding: EdgeInsets.only(
  //                               top: 5.0, left: 5.0, right: 10.0),
  //                           child: Text(AppLocalizations.of(context)
  //                               .translate(event.type))),
  //                     ],
  //                   ),
  //                   result.isNotEmpty
  //                       ? Row(
  //                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //                           children: <Widget>[
  //                             Container(
  //                               padding: EdgeInsets.only(left: 5.0),
  //                               child: Icon(Icons.comment,
  //                                   color: CustomColor.primaryColor,
  //                                   size: 20.0),
  //                             ),
  //                             Expanded(
  //                               child: Column(children: [
  //                                 Padding(
  //                                     padding: EdgeInsets.only(
  //                                         top: 10.0, left: 5.0, right: 0),
  //                                     child: Text(
  //                                       result,
  //                                       maxLines: 7,
  //                                       overflow: TextOverflow.ellipsis,
  //                                     )),
  //                               ]),
  //                             )
  //                           ],
  //                         )
  //                       : new Container(),
  //                   Row(
  //                     children: [
  //                       Container(
  //                           padding: EdgeInsets.only(top: 3.0, left: 5.0),
  //                           child: Row(
  //                             children: <Widget>[
  //                               Container(
  //                                 padding: EdgeInsets.only(left: 3.0),
  //                                 child: Icon(Icons.speed,
  //                                     color: CustomColor.primaryColor,
  //                                     size: 20.0),
  //                               ),
  //                             ],
  //                           )),
  //                       Container(
  //                           padding: EdgeInsets.only(
  //                               top: 5.0, left: 5.0, right: 10.0),
  //                           child: Text(convertSpeed(position.speed))),
  //                     ],
  //                   ),
  //                   Row(
  //                     children: [
  //                       Container(
  //                           padding: EdgeInsets.only(top: 3.0, left: 5.0),
  //                           child: Row(
  //                             children: <Widget>[
  //                               Container(
  //                                 padding: EdgeInsets.only(left: 5.0),
  //                                 child: Icon(Icons.access_time_outlined,
  //                                     color: CustomColor.primaryColor,
  //                                     size: 15.0),
  //                               ),
  //                             ],
  //                           )),
  //                       Container(
  //                           padding: EdgeInsets.only(
  //                               top: 5.0, left: 5.0, right: 10.0),
  //                           child: Text(
  //                             formatTime(position.serverTime),
  //                             style: TextStyle(fontSize: 11),
  //                           )),
  //                     ],
  //                   ),
  //                 ],
  //               ))));
  // }
}
