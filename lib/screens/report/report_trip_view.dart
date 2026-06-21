import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/services/model/playback_route.dart';
import 'package:gpspro/screens/common_method.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/theme/custom_color.dart';

class ReportTripViewPage extends StatefulWidget {
  const ReportTripViewPage({super.key});

  @override
  State<StatefulWidget> createState() => _ReportTripViewPageState();
}

class _ReportTripViewPageState extends State<ReportTripViewPage> {
  ReportArguments? args;
  StreamController<int>? _postsController;
  Timer? _timer;
  bool isLoading = true;

  String maxSpeed = "-";
  String totalDistance = "-";
  String moveDuration = "-";
  String stopDuration = "-";
  String fuelConsume = "-";
  List<PlayBackRoute> routeList = [];

  @override
  void initState() {
    _postsController = StreamController();
    getReport();
    super.initState();
  }

  void getReport() {
    _timer = Timer.periodic(Duration(milliseconds: 1000), (timer) {
      if (args != null) {
        _timer!.cancel();
        APIService.getHistory(args!.id.toString(), args!.fromDate,
                args!.fromTime, args!.toDate, args!.toTime)
            .then((value) => {
                  totalDistance = value!.distance_sum!,
                  maxSpeed = value.top_speed!,
                  moveDuration = value.move_duration!,
                  stopDuration = value.stop_duration!,
                  if (value.fuel_consumption != null)
                    {
                      fuelConsume = value.fuel_consumption!,
                    }
                  else
                    {
                      fuelConsume = "0",
                    },
                  value.items!.forEach((el) {
                    if (el['time'] != null &&
                        el['engine_work'] != 0 &&
                        el['idle'] != 0) {
                      PlayBackRoute rt = PlayBackRoute();
                      rt.time = el['time'];
                      rt.show = el['show'];
                      rt.left = el['left'];
                      rt.distance = el['distance'];
                      rt.engine_hours = el['engine_hours'];
                      rt.fuel_consumption = el['fuel_consumption'];
                      rt.top_speed = el['top_speed'];
                      rt.average_speed = el['average_speed'];

                      var element = el['items'].first;
                      if (element['latitude'] != null) {
                        rt.device_id = element['device_id'].toString();
                        rt.longitude = element['longitude'].toString();
                        rt.latitude = element['latitude'].toString();
                        rt.speed = element['speed'];
                        rt.course = element['course'].toString();
                        rt.raw_time = element['raw_time'].toString();
                        rt.speedType = "kph";
                      }
                      routeList.add(rt);
                    }
                  }),
                  _postsController!.add(1),
                  setState(() {})
                });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    args = ModalRoute.of(context)?.settings.arguments as ReportArguments;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        automaticallyImplyLeading: true,
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
      body: StreamBuilder<int>(
          stream: _postsController!.stream,
          builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
            if (snapshot.hasData) {
              return Stack(
                children: [
                  reportRowSummary(),
                  Padding(
                    padding: EdgeInsets.only(top: 160),
                    child: loadReport(),
                  ),
                ],
              );
            } else if (isLoading) {
              return Center(
                child: CircularProgressIndicator(),
              );
            } else {
              return Center(
                child: Text(('noData').tr),
              );
            }
          }),
    );
  }

  Widget loadReport() {
    return ListView.builder(
      itemCount: routeList.length,
      itemBuilder: (context, index) {
        final trip = routeList[index];
        return GestureDetector(
          onTap: () {
            String fromDate = formatInvalidDate(trip.show.toString());
            String toDate = formatInvalidDate(trip.left.toString());
            String fromTime = formatInvalidTime(trip.show.toString());
            String toTime = formatInvalidTime(trip.left.toString());

            Navigator.pushNamed(context, "/playback",
                arguments: ReportArguments(int.parse(trip.device_id!), fromDate,
                    fromTime, toDate, toTime, args!.name, 0, args!.deviceItem));
          },
          child: reportRow(trip),
        );
      },
    );
  }

  Widget reportRowSummary() {
    return Card(
        child: Container(
            padding: EdgeInsets.all(10),
            child: Column(
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                        child: Text(
                      ("positionDistance").tr,
                      style: TextStyle(
                          fontSize: 15, color: CustomColor.primaryColor),
                    )),
                    Expanded(
                        child: Text(
                      totalDistance,
                      style: TextStyle(fontSize: 15),
                    )),
                  ],
                ),
                Padding(padding: EdgeInsets.all(2)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                        child: Text(
                      ("topSpeed").tr,
                      style: TextStyle(
                          fontSize: 15, color: CustomColor.primaryColor),
                    )),
                    Expanded(
                        child: Text(
                      maxSpeed,
                      style: TextStyle(fontSize: 15),
                    )),
                  ],
                ),
                Padding(padding: EdgeInsets.all(2)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                        child: Text(
                      ("moveDuration").tr,
                      style: TextStyle(
                          fontSize: 15, color: CustomColor.primaryColor),
                    )),
                    Expanded(
                        child: Text(
                      moveDuration,
                      style: TextStyle(fontSize: 15),
                    )),
                  ],
                ),
                Padding(padding: EdgeInsets.all(2)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                        child: Text(
                      ("stopDuration").tr,
                      style: TextStyle(
                          fontSize: 15, color: CustomColor.primaryColor),
                    )),
                    Expanded(
                        child: Text(
                      stopDuration,
                      style: TextStyle(fontSize: 15),
                    )),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                        child: Text(
                      ("fuel").tr,
                      style: TextStyle(
                          fontSize: 15, color: CustomColor.primaryColor),
                    )),
                    Expanded(
                        child: Text(
                      fuelConsume ?? "-",
                      style: TextStyle(fontSize: 15),
                    )),
                  ],
                ),
              ],
            )));
  }

  Widget reportRow(PlayBackRoute t) {
    return Card(
        child: Container(
            padding: EdgeInsets.all(10),
            child: Column(
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(("reportStartTime").tr,
                        style: TextStyle(color: Colors.green)),
                    Text(("reportEndTime").tr,
                        style: TextStyle(color: Colors.red))
                  ],
                ),
                Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                        child: Text(
                      t.show!,
                      style: TextStyle(fontSize: 11),
                    )),
                    Expanded(
                        child: Text(
                      t.left!,
                      style: TextStyle(fontSize: 11),
                    )),
                  ],
                ),
                Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                        child: Text(
                      "${("positionDistance").tr}: ${t.distance} km",
                      style: TextStyle(fontSize: 11),
                    )),
                    Expanded(
                        child: Text(
                      "${("reportAverageSpeed").tr}: ${t.average_speed} kph",
                      style: TextStyle(fontSize: 11),
                    )),
                    Expanded(
                        child: Text(
                      "${("reportMaximumSpeed").tr}: ${t.top_speed} kph",
                      style: TextStyle(fontSize: 11),
                    )),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                        child: Text(
                      "${("reportDuration").tr}: ${t.time}",
                      style: TextStyle(fontSize: 11),
                    )),
                    Expanded(
                        child: Text(
                      "${("reportSpentFuel").tr}: ${t.fuel_consumption}",
                      style: TextStyle(fontSize: 11),
                    )),
                  ],
                ),
              ],
            )));
  }
}
