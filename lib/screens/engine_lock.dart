// ignore_for_file: unused_local_variable, file_names

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smart_lock/arguments/device_args.dart';
import 'package:smart_lock/flutter_flow/flutter_flow_theme.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/theme/custom_color.dart';
import 'package:smart_lock/util/util.dart';

class EngineLockScreen extends StatefulWidget {
  const EngineLockScreen({super.key});

  @override
  State<StatefulWidget> createState() => _EngineLockScreenState();
}

class _EngineLockScreenState extends State<EngineLockScreen> {
  static DeviceArguments? args;

  late Timer _timer;
  bool commandSupported = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      _timer.cancel();
      if (args != null) {
        //getCommands();
      }
    });
  }

  // void getCommands() {
  //   APIService.getSendCommands(args!.device.id.toString()).then((value) {
  //     print(value);
  //     if (value != null) {
  //       for (var element in value.commands!) {
  //         if (element.title == "Engine resume") {
  //           commandSupported = true;
  //         }
  //
  //         if (element.title == "Engine stop") {
  //           commandSupported = true;
  //         }
  //
  //         if (element.title == "Apagar motor") {
  //           commandSupported = true;
  //         }
  //
  //         if (element.title == "Reanudar motor") {
  //           commandSupported = true;
  //         }
  //       }
  //       setState(() {
  //         isLoading = false;
  //       });
  //     } else {
  //       setState(() {
  //         isLoading = false;
  //       });
  //     }
  //   });
  // }

  void lock() {
    Map<String, String> requestBody;
    requestBody = <String, String>{
      'id': "",
      'device_id': args!.device.id.toString(),
      'type': "engineStop"
    };

    APIService.sendCommands(requestBody).then((res) => {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(('engineLocked').tr)))
        });
  }

  void unlock() {
    Map<String, String> requestBody;
    requestBody = <String, String>{
      'id': "",
      'device_id': args!.device.id.toString(),
      'type': "engineResume"
    };

    APIService.sendCommands(requestBody).then((res) => {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(('engineUnLocked').tr)))
        });
  }

  @override
  Widget build(BuildContext context) {
    args = ModalRoute.of(context)!.settings.arguments as DeviceArguments;

    return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          automaticallyImplyLeading: true,
          iconTheme: IconThemeData(color: CustomColor.cssBlack),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "engineLock".tr,
                style: FlutterFlowTheme.of(context).headlineMedium,
              ),
            ],
          ),
          centerTitle: false,
          elevation: 0,
        ),
        body: !isLoading
            ? Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  topView(),
                  commandSupported
                      ? Padding(
                          padding: const EdgeInsets.only(left: 20, right: 20),
                          child: centerView())
                      : Container(),
                  commandSupported ? bottomView() : Container()
                ],
              )
            : const Center(
                child: CircularProgressIndicator(),
              ));
  }

  Widget topView() {
    String status = ("moving").tr;
    Color statusColors = Colors.red;
    String statusDuration = "0s";

    String moving = args!.device.iconColors!.moving!;
    String stopped = args!.device.iconColors!.stopped!;
    String offline = args!.device.iconColors!.offline!;
    String engine = args!.device.iconColors!.engine!;

    Color gps = Colors.red;
    Color gsm = Colors.red;
    Color ignition = Colors.red;

    String jsonData = "";
    if (args!.device.deviceData!.traccar!.other != null) {
      jsonData = args!.device.deviceData!.traccar!.other!;
    } else {
      jsonData = "<info></info>";
    }

    Map<String, dynamic> parsedData = Util.convertXmlToJson(jsonData);

    if (parsedData.containsKey("sat")) {
      if (int.parse(parsedData["sat"]) > 0) {
        gps = Colors.green;
      } else {
        gps = Colors.red;
      }
    } else {
      gps = Colors.red;
    }

    if (parsedData.containsKey("rssi")) {
      if (int.parse(parsedData["rssi"]) > 0) {
        gsm = Colors.green;
      } else {
        gsm = Colors.red;
      }
    } else {
      gsm = Colors.red;
    }

    if (parsedData.containsKey("ignition")) {
      if (parsedData["ignition"].toString() == "true") {
        ignition = Colors.green;
      } else {
        ignition = Colors.red;
      }
    } else {
      ignition = Colors.red;
    }

    if (moving == args!.device.iconColor) {
      statusColors = Colors.green;
      status = ("stopped").tr;
    } else if (stopped == args!.device.iconColor) {
      statusColors = Colors.red;
      status = ("stopped").tr;
    } else if (offline == args!.device.iconColor) {
      statusColors = Colors.grey;
      status = ("stopped").tr;
    } else if (engine == args!.device.iconColor) {
      statusColors = Colors.yellow;
      status = ("stopped").tr;
    } else {
      statusColors = Colors.grey;
      status = ("stopped").tr;
    }

    if (args!.device.online == "offline") {
      statusColors = Colors.grey;
      status = ("stopped").tr;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            children: [
              Text(args!.device.name!),
              Text(args!.device.deviceData!.imei != null
                  ? args!.device.deviceData!.imei.toString()
                  : "-")
            ],
          ),
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                border: Border.all(width: 2, color: Colors.black)),
            child: Icon(
              Icons.drive_eta,
              color: statusColors,
            ),
          ),
          Column(
            children: [
              Text(commandSupported
                  ? ('deviceSupported').tr
                  : ('deviceNotSupported').tr),
              Text(args!.device.protocol!)
            ],
          ),
        ],
      ),
    );
  }

  Widget centerView() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        InkWell(
          onTap: () {},
          child: Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(50),
              ),
              child: InkWell(
                  onTap: () {
                    lock();
                  },
                  child: Row(children: [
                    const Icon(
                      Icons.lock,
                      color: Colors.white,
                      size: 30,
                    ),
                    const Padding(padding: EdgeInsets.only(left: 5)),
                    Text(
                      ('lock').tr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20.0,
                      ),
                    ),
                  ]))),
        ),
        InkWell(
          onTap: () {},
          child: Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(50),
              ),
              child: InkWell(
                  onTap: () {
                    unlock();
                  },
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_open,
                        color: Colors.white,
                        size: 30,
                      ),
                      Text(
                        ('unlock').tr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20.0,
                        ),
                      ),
                    ],
                  ))),
        )
      ],
    );
  }

  Widget bottomView() {
    return Padding(
        padding: const EdgeInsets.all(30),
        child: Container(
          padding: const EdgeInsets.all(10.0),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
              "Please do not use this feature when the GSM network connectivity is poor."),
        ));
  }
}
