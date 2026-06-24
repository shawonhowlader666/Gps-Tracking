import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';
import 'package:smart_lock/arguments/device_args.dart';
import 'package:smart_lock/arguments/report_args.dart';
import 'package:smart_lock/flutter_flow/flutter_flow_theme.dart';
import 'package:smart_lock/flutter_flow/flutter_flow_widgets.dart';
import 'package:smart_lock/services/model/device.dart';
import 'package:smart_lock/services/model/device_item.dart';
import 'package:smart_lock/services/model/sensor_data.dart';
import 'package:smart_lock/screens/common_method.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/theme/custom_color.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart' as m;

class DeviceInfo extends StatefulWidget {
  const DeviceInfo({super.key});

  @override
  _DeviceInfoState createState() => _DeviceInfoState();
}

class _DeviceInfoState extends State<DeviceInfo> {
  static DeviceArguments? args;

  final TextEditingController _customCommand = TextEditingController();
  final List<String> _commands = <String>[];
  final List<String> _commandsValue = <String>[];
  int _selectedCommand = 0;
  String _commandSelected = "";
  int _selectedperiod = 0;
  double _dialogHeight = 300.0;
  double _dialogCommandHeight = 150.0;

  DateTime _selectedFromDate = DateTime.now();
  DateTime _selectedToDate = DateTime.now();
  TimeOfDay _selectedFromTime = TimeOfDay.now();
  TimeOfDay _selectedToTime = TimeOfDay.now();
  Device? device;
  var latLng;
  SharedPreferences? prefs;

  String totalDistance = "-";
  String maxSpeed = "-";
  String drivingHours = "-";
  String fuel = "-";

  List<SensorData> sensorValues = [];

  bool isLoading = true;

  List<LinearFuel> data = [];

  String? fromDate;
  String? toDate;
  String? fromTime;
  String? toTime;

  @override
  void initState() {
    checkPreference();
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void checkPreference() async {
    prefs = await SharedPreferences.getInstance();
    totalDistance = ("sharedLoading").tr;
    maxSpeed = ("sharedLoading").tr;
    drivingHours = ("sharedLoading").tr;
    fuel = ("sharedLoading").tr;
    if (prefs!.get("totalDistance-${args!.id}") != null) {
      totalDistance = prefs!.getString("totalDistance-${args!.id}")!;
      maxSpeed = prefs!.getString("maxSpeed-${args!.id}")!;
      drivingHours = prefs!.getString("drivingHours-${args!.id}")!;
      if (prefs!.getString("fuel-${args!.id}") != null) {
        fuel = prefs!.getString("fuel-${args!.id}")!;
      } else {
        fuel = "0";
      }
    }
    setState(() {});
    getTrip();
  }

  void getTrip() {
    DateTime current = DateTime.now();

    String month;
    String day;
    if (current.month < 10) {
      month = "0${current.month}";
    } else {
      month = current.month.toString();
    }

    int dayCon = current.day;
    if (current.day < 10) {
      day = "0$dayCon";
    } else {
      day = dayCon.toString();
    }
    var start = DateTime.parse("${current.year}-"
        "$month-"
        "$day "
        "00:00:00");

    var end = DateTime.parse("${current.year}-"
        "$month-"
        "$day "
        "24:00:00");

    fromDate = formatDateReport(start.toString());
    toDate = formatDateReport(end.toString());
    fromTime = formatTimeReport(start.toString());
    toTime = formatTimeReport(end.toString());

    APIService.getHistory(
            args!.id.toString(), fromDate!, fromTime!, toDate!, toTime!)
        .then((value) => {
              totalDistance = value!.distance_sum!,
              maxSpeed = value.top_speed!,
              drivingHours = value.move_duration!,
              if (value.fuel_consumption != null)
                {
                  fuel = value.fuel_consumption!,
                }
              else
                {fuel = "0"},
              print("------------------$totalDistance"),
              prefs!.setString("totalDistance-${args!.id}", totalDistance),
              prefs!.setString("maxSpeed-${args!.id}", maxSpeed),
              prefs!.setString("drivingHours-${args!.id}", drivingHours),
              setState(() {})
            });

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    args = ModalRoute.of(context)!.settings.arguments as DeviceArguments;

    return Scaffold(
      // appBar: AppBar(
      //   title: Text(args!.name,
      //       style: TextStyle(color: CustomColor.secondaryColor)),
      //   iconTheme: IconThemeData(
      //     color: CustomColor.secondaryColor, //change your color here
      //   ),
      // ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        iconTheme: IconThemeData(color: CustomColor.cssBlack),
        automaticallyImplyLeading: true,
        title: Row(
          children: [
            //Padding(padding: EdgeInsets.only(bottom: 5, right: 5),child:Image.asset("images/logo-icon.png", width: 40, height: 40)),
            Text(
              args!.name,
              style: FlutterFlowTheme.of(context).headlineMedium,
            ),
          ],
        ),
        // actions: [
        //   IconButton(onPressed: (){},
        //     icon:Icon(Icons.filter_list_outlined),
        //     color: Colors.black,)
        // ],
        centerTitle: false,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: loadDevice(),
      ),
    );
  }

  Widget loadDevice() {
    return Column(
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.all(10),
        ),
        Container(
            padding: const EdgeInsets.only(right: 15.0, left: 15.0, bottom: 15),
            child: tripDistance()),
        Container(
            padding: const EdgeInsets.only(right: 15.0, left: 15.0, bottom: 15),
            child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: Colors.white,
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.grey, spreadRadius: 1, blurRadius: 1.0),
                  ],
                ),
                child: Padding(
                    padding: const EdgeInsets.all(1.0), child: sensorInfo()))),
        Gap(10),
        Center(
            child: FFButtonWidget(
          onPressed: () async {
            Navigator.pushNamed(context, "/reportFuel",
                arguments: ReportArguments(args!.id, fromDate!, fromTime!,
                    toDate!, toTime!, args!.name, 10, args!.device));
          },
          text: 'fuelReport'.tr,
          icon: const m.Icon(Icons.local_gas_station_outlined),
          options: FFButtonOptions(
            width: 180.0,
            height: 37.0,
            padding: const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 0.0),
            iconPadding:
                const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 0.0),
            color: CustomColor.cssBlack.withValues(alpha: 0.1),
            textStyle: FlutterFlowTheme.of(context).titleSmall.override(
                  fontFamily: 'Outfit',
                  color: CustomColor.cssBlack,
                  fontWeight: FontWeight.w600,
                ),
            elevation: 0.0,
            borderSide: const BorderSide(
              color: Colors.transparent,
              width: 1.0,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
        )),
        Padding(padding: EdgeInsets.only(top: 20)),
        Container(color: CustomColor.primaryColor, child: bottomButton())
      ],
    );
  }

  Widget tripDistance() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: Colors.white,
        boxShadow: const [
          BoxShadow(color: Colors.grey, spreadRadius: 1, blurRadius: 1.0),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.0),
        child: Column(children: <Widget>[
          Container(
              padding: const EdgeInsets.all(10),
              child: const Text(
                "Today Summary",
                textAlign: TextAlign.start,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              )),
          Container(
              child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Container(
                  padding: const EdgeInsets.only(top: 3.0, left: 10.0),
                  child: Row(
                    children: <Widget>[
                      Container(
                          padding: const EdgeInsets.only(left: 3.0),
                          child: Text(('travelledDistance').tr)),
                    ],
                  )),
              Container(
                padding:
                    const EdgeInsets.only(top: 10.0, left: 5.0, right: 10.0),
                child: Text(totalDistance),
              )
            ],
          )),
          const SizedBox(height: 5.0),
          Container(
              child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Container(
                  padding: const EdgeInsets.only(top: 3.0, left: 10.0),
                  child: Row(
                    children: <Widget>[
                      Container(
                          padding: const EdgeInsets.only(left: 3.0),
                          child: Text(('maxSpeed').tr)),
                    ],
                  )),
              Container(
                padding:
                    const EdgeInsets.only(top: 10.0, left: 5.0, right: 10.0),
                child: Text(maxSpeed),
              )
            ],
          )),
          const SizedBox(height: 5.0),
          Container(
              child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Container(
                  padding: const EdgeInsets.only(top: 3.0, left: 10.0),
                  child: Row(
                    children: <Widget>[
                      Container(
                          padding: const EdgeInsets.only(left: 3.0),
                          child: Text(('fuel').tr)),
                    ],
                  )),
              Container(
                padding:
                    const EdgeInsets.only(top: 10.0, left: 5.0, right: 10.0),
                child: Text(fuel),
              )
            ],
          )),
          const SizedBox(height: 5.0),
          Container(
              child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Container(
                  padding: const EdgeInsets.only(top: 3.0, left: 10.0),
                  child: Row(
                    children: <Widget>[
                      Container(
                          padding: const EdgeInsets.only(left: 3.0),
                          child: Text("time".tr))
                    ],
                  )),
              Container(
                width: MediaQuery.of(context).size.width * 0.6,
                padding:
                    const EdgeInsets.only(top: 10.0, left: 5.0, right: 10.0),
                child: Text(
                  args!.device.time!,
                  textAlign: TextAlign.end,
                  style: const TextStyle(overflow: TextOverflow.ellipsis),
                ),
              )
            ],
          )),
          const SizedBox(height: 5.0),
          Container(
              child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Container(
                  padding: const EdgeInsets.only(top: 3.0, left: 10.0),
                  child: Row(
                    children: <Widget>[
                      Container(
                          padding: const EdgeInsets.only(left: 3.0),
                          child: Text(('stopDuration').tr))
                    ],
                  )),
              Container(
                padding:
                    const EdgeInsets.only(top: 10.0, left: 5.0, right: 10.0),
                child: Text(args!.device.stopDuration!),
              )
            ],
          )),
          Container(
              child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Container(
                  padding: const EdgeInsets.only(top: 3.0, left: 10.0),
                  child: Row(
                    children: <Widget>[
                      Container(
                          padding: const EdgeInsets.only(left: 3.0),
                          child: Text("driver".tr))
                    ],
                  )),
              Container(
                padding:
                    const EdgeInsets.only(top: 10.0, left: 5.0, right: 10.0),
                child: Text(args!.device.driver!),
              )
            ],
          )),
        ]),
      ),
    );
  }

  Widget bottomButton() {
    return Container(
        padding: const EdgeInsets.all(10),
        width: MediaQuery.of(context).size.width * 100,
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, "/playback",
                      arguments: ReportArguments(args!.id, "", "", "", "",
                          args!.name, 0, args!.device));
                },
                child: Column(children: [
                  Container(
                    child: const m.Icon(
                      Icons.play_circle_outline,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    ("playback").tr,
                    style: const TextStyle(color: Colors.white),
                  )
                ]),
              ),
              SizedBox(
                  height: 50,
                  child:
                      const VerticalDivider(thickness: 1, color: Colors.white)),
              GestureDetector(
                onTap: () {
                  showCommandDialog(context, args!.device);
                },
                child: Column(children: [
                  Container(
                    child: const m.Icon(
                      Icons.lock,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    ("command").tr,
                    style: const TextStyle(color: Colors.white),
                  )
                ]),
              ),
              SizedBox(
                  height: 50,
                  child:
                      const VerticalDivider(thickness: 1, color: Colors.white)),
              GestureDetector(
                onTap: () {
                  showReportDialog(context, ('report').tr);
                },
                child: Column(
                  children: [
                    Container(
                      child: const m.Icon(
                        Icons.analytics,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      ('report').tr,
                      style: const TextStyle(color: Colors.white),
                    )
                  ],
                ),
              )
            ]));
  }

  void showCommandDialog(BuildContext context, DeviceItem device) {
    _commands.clear();
    _commandsValue.clear();
    Dialog simpleDialog = Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
          Iterable list;
          APIService.getSendCommands(device.id.toString()).then((value) => {
                if (value != null)
                  {
                    list = json.decode(value.body)["commands"],
                    if (_commands.isEmpty)
                      {
                        list.forEach((element) {
                          _commands.add(element["title"]);
                          _commandsValue.add(element["id"]);
                        }),
                        setState(() {}),
                      }
                  },
              });

          return SizedBox(
            height: _dialogCommandHeight,
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(('commandTitle').tr),
                            ],
                          ),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                _commands.isNotEmpty
                                    ? DropdownButton<String>(
                                        hint: Text(('select_command').tr),
                                        value: _commands[_selectedCommand],
                                        items: _commands.map((String value) {
                                          return DropdownMenuItem<String>(
                                            value: value,
                                            child: Text(
                                              (value),
                                              style: TextStyle(),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (value) {
                                          print(value);
                                          setState(() {
                                            if (value == ("customCommand").tr) {
                                              _dialogCommandHeight = 200.0;
                                            } else {
                                              _dialogCommandHeight = 150.0;
                                            }
                                            _commandSelected = value!;
                                            _selectedCommand =
                                                _commands.indexOf(value);
                                            print(_selectedCommand);
                                          });
                                        },
                                      )
                                    : CircularProgressIndicator(),
                              ]),
                          _commandSelected == ("customCommand").tr
                              ? Container(
                                  child: TextField(
                                    controller: _customCommand,
                                    decoration: InputDecoration(
                                        labelText: ('commandCustom').tr),
                                  ),
                                )
                              : Container(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                                child: Text(
                                  ('cancel').tr,
                                  style: TextStyle(
                                      fontSize: 18.0, color: Colors.white),
                                ),
                              ),
                              SizedBox(
                                width: 20,
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: CustomColor.primaryColor,
                                ),
                                onPressed: () {
                                  sendCommand(args!.device);
                                },
                                child: Text(
                                  ('ok').tr,
                                  style: TextStyle(
                                      fontSize: 18.0, color: Colors.white),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ],
                )
              ],
            ),
          );
        }));
    showDialog(
        context: context, builder: (BuildContext context) => simpleDialog);
  }

  Widget sensorInfo() {
    double fontWidth = MediaQuery.of(context).size.aspectRatio;

    List<Widget> sensors = [];
    double iconWidth = 30;

    if (args!.device.sensors != []) {
      try {
        for (var sensor in args!.device.sensors!) {
          if (sensor['value'] != null) {
            sensors.add(Card(
                elevation: 1,
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
                              sensor['value'],
                              style: TextStyle(fontSize: fontWidth * 19),
                            )
                          ])
                        ]))));
          }

          if (sensor['type'] == "fuel_tank") {}
        }
      } catch (e) {}

      return Container(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Text(
                ('sensors').tr,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              )),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: sensors,
                  )),
              // const Padding(
              //   padding: EdgeInsets.all(10),
              // ),
              // Center(
              //   child: Column(
              //     mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              //     crossAxisAlignment: CrossAxisAlignment.center,
              //     children: [
              //       const Padding(
              //         padding: EdgeInsets.all(5),
              //       ),
              //       Text(
              //         AppLocalizations.of(context)!.translate("sharedMaintenance"),
              //         textAlign: TextAlign.center,
              //         style: TextStyle(fontWeight: FontWeight.bold),
              //       ),
              //       Row(
              //         children: [
              //           Image.asset("assets/images/sensors/main.png",
              //             width: iconWidth,
              //             height: iconWidth,),
              //           Container(
              //               width: 120,
              //               child:Text(maintenance, style: TextStyle(fontSize:12,overflow: TextOverflow.ellipsis), maxLines: 3,))
              //         ],
              //       ),
              //       Padding(padding: EdgeInsets.all(5)),
              //       Row(
              //         children: [
              //           Image.asset("assets/images/sensors/tier.png",  width: iconWidth,
              //             height: iconWidth,),
              //           Container(
              //               width: 120,
              //               child:Text(tires, style: TextStyle(fontSize:12,overflow: TextOverflow.ellipsis), maxLines: 3,))
              //         ],
              //       ),
              //     ],
              //   ),
              // )
            ],
          ));
    } else {
      return Container();
    }
  }

  void showSavedCommandDialog(BuildContext context) {
    _commands.clear();
    _commandsValue.clear();
    Dialog simpleDialog = Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
          Iterable list;
          APIService.getSavedCommands(args!.id.toString()).then((value) => {
                if (value != null)
                  {
                    list = json.decode(value.body),
                    if (_commands.isEmpty)
                      {
                        list.forEach((element) {
                          _commands.add(element["title"]);
                          _commandsValue.add(element["type"]);
                        }),
                        setState(() {}),
                      }
                    else
                      {
                        // Fluttertoast.showToast(
                        //     msg: AppLocalizations.of(context)
                        //         .translate("noData"),
                        //     toastLength: Toast.LENGTH_SHORT,
                        //     gravity: ToastGravity.CENTER,
                        //     timeInSecForIosWeb: 1,
                        //     backgroundColor: Colors.black54,
                        //     textColor: Colors.white,
                        //     fontSize: 16.0),
                        // Navigator.pop(context)
                      }
                  }
                else
                  {
                    // Fluttertoast.showToast(
                    //     msg: AppLocalizations.of(context)!.translate("noData"),
                    //     toastLength: Toast.LENGTH_SHORT,
                    //     gravity: ToastGravity.CENTER,
                    //     timeInSecForIosWeb: 1,
                    //     backgroundColor: Colors.black54,
                    //     textColor: Colors.white,
                    //     fontSize: 16.0),
                    // Navigator.pop(context)
                  }
              });

          return SizedBox(
            height: _dialogCommandHeight,
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(('commandTitle').tr),
                            ],
                          ),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                _commands.isNotEmpty
                                    ? DropdownButton<String>(
                                        hint: Text(('select_command').tr),
                                        value: _commands[_selectedCommand],
                                        items: _commands.map((String value) {
                                          return DropdownMenuItem<String>(
                                            value: value,
                                            child: SizedBox(
                                                width: MediaQuery.of(context)
                                                        .size
                                                        .width /
                                                    2,
                                                child: Text(
                                                  (value).tr,
                                                  style: const TextStyle(
                                                      fontSize: 12),
                                                  maxLines: 2,
                                                  softWrap: true,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                )),
                                          );
                                        }).toList(),
                                        onChanged: (value) {
                                          setState(() {
                                            if (value == "Custom Command") {
                                              _dialogCommandHeight = 200.0;
                                            } else {
                                              _dialogCommandHeight = 150.0;
                                            }
                                            _commandSelected = value!;
                                            _selectedCommand =
                                                _commands.indexOf(value);
                                          });
                                        },
                                      )
                                    : const CircularProgressIndicator(),
                              ]),
                          _commandSelected == "Custom Command"
                              ? Container(
                                  child: TextField(
                                    controller: _customCommand,
                                    decoration: InputDecoration(
                                        labelText: ('commandCustom').tr),
                                  ),
                                )
                              : Container(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                                child: Text(
                                  ('cancel').tr,
                                  style: const TextStyle(
                                      fontSize: 18.0, color: Colors.white),
                                ),
                              ),
                              const SizedBox(
                                width: 20,
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: CustomColor.primaryColor,
                                ),
                                onPressed: () {
                                  sendCommand(args!.device);
                                },
                                child: Text(
                                  ('ok').tr,
                                  style: const TextStyle(
                                      fontSize: 18.0, color: Colors.white),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ],
                )
              ],
            ),
          );
        }));
    showDialog(
        context: context, builder: (BuildContext context) => simpleDialog);
  }

  void sendCommand(DeviceItem device) {
    Map<String, String> requestBody;
    if (_commandSelected == ("customCommand").tr) {
      requestBody = <String, String>{
        'id': "",
        'device_id': device.id.toString(),
        'type': _commandsValue[_selectedCommand],
        'data': _customCommand.text
      };
    } else {
      requestBody = <String, String>{
        'id': "",
        'device_id': device.id.toString(),
        'type': _commandsValue[_selectedCommand]
      };
    }

    print(requestBody.toString());

    APIService.sendCommands(requestBody).then((res) => {
          if (res.statusCode == 200)
            {
              Fluttertoast.showToast(
                  msg: ('command_sent').tr,
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.CENTER,
                  timeInSecForIosWeb: 1,
                  backgroundColor: Colors.green,
                  textColor: Colors.white,
                  fontSize: 16.0),
              Navigator.of(context).pop()
            }
          else
            {
              Fluttertoast.showToast(
                  msg: ('errorMsg').tr,
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.CENTER,
                  timeInSecForIosWeb: 1,
                  backgroundColor: Colors.black54,
                  textColor: Colors.white,
                  fontSize: 16.0),
              Navigator.of(context).pop()
            }
        });
  }

  void sendSystemCommand(dynamic device) {
    Map<String, String> requestBody;
    if (_commandSelected == "Custom Command") {
      requestBody = <String, String>{
        'id': "",
        'device_id': device['id'].toString(),
        'type': _commandsValue[_selectedCommand],
        'data': _customCommand.text
      };
    } else {
      requestBody = <String, String>{
        'id': "",
        'device_id': device['id'].toString(),
        'type': _commandsValue[_selectedCommand]
      };
    }

    print(requestBody.toString());

    APIService.sendCommands(requestBody).then((res) => {
          if (res.statusCode == 200)
            {
              Fluttertoast.showToast(
                  msg: ('command_sent').tr,
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.CENTER,
                  timeInSecForIosWeb: 1,
                  backgroundColor: Colors.green,
                  textColor: Colors.white,
                  fontSize: 16.0),
              Navigator.of(context).pop()
            }
          else
            {
              Fluttertoast.showToast(
                  msg: ('errorMsg').tr,
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.CENTER,
                  timeInSecForIosWeb: 1,
                  backgroundColor: Colors.black54,
                  textColor: Colors.white,
                  fontSize: 16.0),
              Navigator.of(context).pop()
            }
        });
  }

  void showReportDialog(BuildContext context, String heading) {
    Dialog simpleDialog = Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return SizedBox(
            height: _dialogHeight,
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: <Widget>[
                              Radio(
                                value: 0,
                                groupValue: _selectedperiod,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedperiod =
                                        int.parse(value.toString());
                                    _dialogHeight = 300.0;
                                  });
                                },
                              ),
                              Text(
                                ('reportToday').tr,
                                style: const TextStyle(fontSize: 16.0),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: <Widget>[
                              Radio(
                                value: 1,
                                groupValue: _selectedperiod,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedperiod =
                                        int.parse(value.toString());
                                    _dialogHeight = 300.0;
                                  });
                                },
                              ),
                              Text(
                                ('reportYesterday').tr,
                                style: const TextStyle(fontSize: 16.0),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: <Widget>[
                              Radio(
                                value: 2,
                                groupValue: _selectedperiod,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedperiod =
                                        int.parse(value.toString());
                                    _dialogHeight = 300.0;
                                  });
                                },
                              ),
                              Text(
                                ('reportThisWeek').tr,
                                style: const TextStyle(fontSize: 16.0),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: <Widget>[
                              Radio(
                                value: 3,
                                groupValue: _selectedperiod,
                                onChanged: (value) {
                                  setState(() {
                                    _dialogHeight = 400.0;
                                    _selectedperiod =
                                        int.parse(value.toString());
                                  });
                                },
                              ),
                              Text(
                                ('reportCustom').tr,
                                style: const TextStyle(fontSize: 16.0),
                              ),
                            ],
                          ),
                          _selectedperiod == 3
                              ? Container(
                                  child: Column(
                                  children: <Widget>[
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: <Widget>[
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                CustomColor.primaryColor,
                                          ),
                                          onPressed: () => _selectFromDate(
                                              context, setState),
                                          child: Text(
                                              formatReportDate(
                                                  _selectedFromDate),
                                              style: const TextStyle(
                                                  color: Colors.white)),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                CustomColor.primaryColor,
                                          ),
                                          onPressed: () => _selectFromTime(
                                              context, setState),
                                          child: Text(
                                              formatReportTime(
                                                  _selectedFromTime),
                                              style: const TextStyle(
                                                  color: Colors.white)),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: <Widget>[
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                CustomColor.primaryColor,
                                          ),
                                          onPressed: () =>
                                              _selectToDate(context, setState),
                                          child: Text(
                                              formatReportDate(_selectedToDate),
                                              style: const TextStyle(
                                                  color: Colors.white)),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                CustomColor.primaryColor,
                                          ),
                                          onPressed: () =>
                                              _selectToTime(context, setState),
                                          child: Text(
                                              formatReportTime(_selectedToTime),
                                              style: const TextStyle(
                                                  color: Colors.white)),
                                        ),
                                      ],
                                    )
                                  ],
                                ))
                              : Container(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                                child: Text(
                                  ('cancel').tr,
                                  style: const TextStyle(
                                      fontSize: 18.0, color: Colors.white),
                                ),
                              ),
                              const SizedBox(
                                width: 20,
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: CustomColor.primaryColor,
                                ),
                                onPressed: () {
                                  showReport(heading);
                                },
                                child: Text(
                                  ('ok').tr,
                                  style: const TextStyle(
                                      fontSize: 18.0, color: Colors.white),
                                ),
                              ),
                            ],
                          )
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

  Future<void> _selectFromDate(
      BuildContext context, StateSetter setState) async {
    final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _selectedFromDate,
        firstDate: DateTime(2015, 8),
        lastDate: DateTime(2101));
    if (picked != null && picked != _selectedFromDate) {
      setState(() {
        _selectedFromDate = picked;
      });
    }
  }

  Future<void> _selectToDate(BuildContext context, StateSetter setState) async {
    final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _selectedToDate,
        firstDate: DateTime(2015, 8),
        lastDate: DateTime(2101));
    if (picked != null && picked != _selectedToDate) {
      setState(() {
        _selectedToDate = picked;
      });
    }
  }

  Future<void> _selectFromTime(
      BuildContext context, StateSetter setState) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? Container(),
        );
      },
    );
    if (picked != null && picked != _selectedFromTime) {
      setState(() {
        _selectedFromTime = picked;
      });
    }
  }

  Future<void> _selectToTime(BuildContext context, setState) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? Container(),
        );
      },
    );
    if (picked != null && picked != _selectedToTime) {
      setState(() {
        _selectedToTime = picked;
      });
    }
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
    if (heading == ('report').tr) {
      Navigator.pushNamed(context, "/reportList",
          arguments: ReportArguments(args!.device.id!, fromDate, fromTime,
              toDate, toTime, args!.name, 0, args!.device));
    } else {
      Navigator.pushNamed(context, "/playback",
          arguments: ReportArguments(args!.device.id!, fromDate, fromTime,
              toDate, toTime, args!.name, 0, args!.device));
    }
  }
}

/// Sample linear data type.
class LinearFuel {
  DateTime? time;
  int? val;

  LinearFuel({this.time, this.val});
}
