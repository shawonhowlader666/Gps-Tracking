import 'dart:collection';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;
import 'package:get/get.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/model/device.dart';
import 'package:gpspro/services/model/device_item.dart';
import 'package:gpspro/services/model/single_device.dart';
import 'package:gpspro/services/model/bottom_menu.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/widgets/address.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceSelection extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _DevicePageState();
}

class _DevicePageState extends State<DeviceSelection> {
  TextEditingController searchCtl = TextEditingController();
  List<DeviceItem> devicesList = [];
  List<dynamic> _searchResult = [];
  Locale? myLocale;

  String selectedIndex = "all";

  final Map<String, Widget> segmentMap = LinkedHashMap();

  List<BottomMenu> bottomMenu = [];
  SingleDevice? sd;
  String address = "Show Address";
  Map<String, String> addressMap = HashMap();
  int expiryTime = 10;
  SharedPreferences? prefs;
  int _expandedIndex = -1;
  List<Device> devicesListGroup = [];

  @override
  void initState() {
    super.initState();
    checkPreference();
  }

  void checkPreference() async {
    prefs = await SharedPreferences.getInstance();
  }

  @override
  Widget build(BuildContext context) {
    segmentMap.putIfAbsent(
        "all",
        () => Text(
              ("all").tr,
              style: const TextStyle(fontSize: 11),
            ));
    segmentMap.putIfAbsent(
        "green",
        () => Text(
              ("moving").tr,
              style: const TextStyle(fontSize: 11),
            ));
    segmentMap.putIfAbsent(
        "yellow",
        () => Text(
              ("stopped").tr,
              style: const TextStyle(fontSize: 11),
            ));
    segmentMap.putIfAbsent(
        "red",
        () => Text(
              ("offline").tr,
              style: const TextStyle(fontSize: 11),
            ));

    onSearchTextChanged(String text) async {
      _searchResult.clear();

      if (text.toLowerCase().isEmpty) {
        setState(() {});
        return;
      }

      devicesList.forEach((device) {
        if (device.name!.toLowerCase().contains(text.toLowerCase())) {
          _searchResult.add(device);
        }
      });
      setState(() {});
    }

    deviceListFilter(String filterVal) async {
      _searchResult.clear();

      if (filterVal == "all") {
        setState(() {});
        return;
      }

      for (var device in devicesList) {
        if (device.iconColor!.contains(filterVal)) {
          if (device.iconColor! == filterVal) {
            _searchResult.add(device);
          }
        }
      }

      setState(() {});
    }

    return Scaffold(
        appBar: AppBar(
          title: Text(('devices').tr,
              style: TextStyle(color: CustomColor.secondaryColor)),
        ),
        body: GetX<DataController>(
            init: DataController(),
            builder: (controller) {
              devicesList = controller.onlyDevices;

              return !controller.isLoading.value
                  ? Column(children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(1.0),
                        child: Card(
                          child: ListTile(
                            leading: const m.Icon(Icons.search),
                            title: TextField(
                              controller: searchCtl,
                              decoration: InputDecoration(
                                  hintText: ('search').tr,
                                  border: InputBorder.none),
                              onChanged: onSearchTextChanged,
                            ),
                          ),
                        ),
                      ),
                      const Padding(padding: EdgeInsets.all(3)),
                      SizedBox(
                        width: 500.0,
                        child: CupertinoSegmentedControl<String>(
                          children: segmentMap,
                          selectedColor: CustomColor.primaryColor,
                          unselectedColor: CustomColor.secondaryColor,
                          groupValue: selectedIndex,
                          onValueChanged: (String val) {
                            setState(() {
                              selectedIndex = val;
                              deviceListFilter(val);
                            });
                          },
                        ),
                      ),
                      const Padding(padding: EdgeInsets.all(3)),
                      devicesList.isNotEmpty
                          ? Expanded(
                              child: _searchResult.isNotEmpty ||
                                      searchCtl.text.isNotEmpty
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
                                            return const Text(
                                                ("noDeviceFound"));
                                          }))
                          : const CircularProgressIndicator()
                    ])
                  : const Center(child: CircularProgressIndicator());
            }));
  }

  Widget deviceGroupCard(Device device, BuildContext context, index) {
    return ExpansionPanelList(
      expansionCallback: (int panelIndex, bool isExpanded) {
        print(index);
        setState(() {
          _expandedIndex = isExpanded ? -1 : index;
        });
        //_onPanelTapped(index, isExpanded);
      },
      children: [
        ExpansionPanel(
          headerBuilder: (context, isExpanded) {
            return SizedBox(
                height: 20,
                child: Padding(
                    padding: const EdgeInsets.only(left: 20, top: 10),
                    child: Text(
                      device.title.toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )));
          },
          body: Column(children: <Widget>[
            for (var item in device.items!) deviceCard(item, context)
          ]),
          isExpanded: _expandedIndex == index,
          canTapOnHeader: true,
        ),
      ],
    );
  }

  Widget deviceCard(device, BuildContext context) {
    Color color;

    if (device.iconColor != null) {
      if (device.iconColor == "green") {
        color = Colors.green;
      } else if (device.iconColor == "yellow") {
        color = Colors.yellow.shade700;
      } else {
        color = Colors.red;
      }
    } else {
      color = Colors.yellow.shade700;
    }

    return Padding(
      padding:
          const EdgeInsets.only(top: 10.0, left: 5.0, right: 7.0, bottom: 0),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(context, "/geofenceList",
              arguments: ReportArguments(
                  device.id, "", "", "", "", device.name, 0, device));
        },
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 65, left: 20, right: 20),
              decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(10.0),
                      bottomRight: Radius.circular(10.0)),
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: color,
                      blurRadius: 3.0,
                    )
                  ]),
              child: Row(
                children: [
                  const m.Icon(
                    Icons.location_on,
                    size: 20,
                  ),
                  Container(
                    width: MediaQuery.of(context).size.width / 1.25,
                    padding: const EdgeInsets.all(10),
                    child: addressLoadMarque(
                        double.parse(device.lat.toString()).toString(),
                        double.parse(device.lng.toString()).toString()),
                  )
                ],
              ),
            ),
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(5.0)),
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 3.0,
                    )
                  ]),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    height: 65.0,
                    width: 8.0,
                    decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(5.0),
                            bottomLeft: Radius.circular(5.0))),
                  ),
                  Column(
                    children: [
                      Padding(
                          padding: const EdgeInsets.fromLTRB(5, 10, 5, 5),
                          child: Container(
                            height: 35,
                            width: 35,
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withValues(alpha: 0.3),
                            ),
                            child: Image(
                              image: CachedNetworkImageProvider(
                                  "${UserRepository.getServerUrl()}/${device.icon!.path!}"),
                              width: 35,
                              height: 35,
                            ),
                          )),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 10.0, left: 5),
                    child: SizedBox(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Text(
                                  device.name!,
                                  style: const TextStyle(
                                      fontFamily: "Sans",
                                      color: Colors.black,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14),
                                ),
                                Container(
                                    width: MediaQuery.of(context).size.width /
                                        1.25,
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            const m.Icon(
                                              Icons.access_time_sharp,
                                              size: 20,
                                            ),
                                            const Padding(
                                                padding:
                                                    EdgeInsets.only(left: 2)),
                                            Text(
                                              device.time!,
                                              style: const TextStyle(
                                                  fontFamily: "Sans",
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 11),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            const m.Icon(
                                              Icons.timelapse,
                                              size: 20,
                                            ),
                                            const Padding(
                                                padding:
                                                    EdgeInsets.only(left: 2)),
                                            Text(
                                              device.stopDuration!,
                                              style: const TextStyle(
                                                  fontFamily: "Sans",
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 11),
                                            )
                                          ],
                                        )
                                      ],
                                    ))
                              ]),
                          const Padding(padding: EdgeInsets.only(top: 3)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
