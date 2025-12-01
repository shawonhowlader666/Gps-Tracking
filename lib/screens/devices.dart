import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/config.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/flutter_flow/flutter_flow_util.dart';
import 'package:gpspro/screens/common_method.dart';
import 'package:gpspro/screens/lock_unlock_screen.dart';
import 'package:gpspro/screens/track_device.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/admob_service.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/services/model/device.dart';
import 'package:gpspro/services/model/device_item.dart';
import 'package:gpspro/services/model/share_perm.dart';
import 'package:gpspro/services/model/single_device.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/widgets/address.dart';
import 'package:flutter/material.dart' as m;
import 'package:gpspro/widgets/banner_ad_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  SingleDevice? sd;
  int expiryTime = 10;
  int _selectedperiod = 0;
  int? selectedIconId;

  final DataController controller = Get.find<DataController>();
  int? _showingAddressForDeviceId;
  Timer? _addressHideTimer;

  void _showAddress(int deviceId) {
    _hideAddress();

    setState(() {
      _showingAddressForDeviceId = deviceId;
    });

    _addressHideTimer = Timer(Duration(seconds: 15), () {
      _hideAddress();
    });
  }

  void _hideAddress() {
    if (_addressHideTimer != null) {
      _addressHideTimer!.cancel();
      _addressHideTimer = null;
    }
    setState(() {
      _showingAddressForDeviceId = null;
    });
  }

  Widget _buildAddressWidget(DeviceItem device) {
    final shouldShow = _showingAddressForDeviceId == device.id;

    return AnimatedCrossFade(
      duration: Duration(milliseconds: 300),
      crossFadeState:
          shouldShow ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      firstChild: SizedBox.shrink(),
      secondChild: Padding(
        padding: const EdgeInsets.only(left: 0, right: 20, bottom: 10),
        child: SizedBox(
          width: MediaQuery.of(context).size.width / 1.2,
          child: shouldShow
              ? addressLoadMarque(
                  double.parse(device.lat.toString()).toString(),
                  double.parse(device.lng.toString()).toString(),
                )
              : SizedBox.shrink(),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.filterDevicesByStatus("all");
    });
  }

  @override
  void dispose() {
    _hideAddress();

    _searchFocusNode.dispose();
    _searchController.dispose();
    _name.dispose();
    super.dispose();
  }

  void editDeviceDialog(BuildContext context, dynamic device) {
    Dialog simpleDialog = Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3.0),
      ),
      child: StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return SizedBox(
            height: 330,
            width: 300.0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(left: 10, right: 10, top: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        ("reportDeviceName").tr,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextField(
                        controller: _name,
                        decoration:
                            InputDecoration(labelText: ('sharedName').tr),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "selectIcon".tr,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 70,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: sd?.device_icons?.length ?? 0,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final icon = sd!.device_icons![index];
                            final isSelected = selectedIconId == icon["id"];
                            // log("${APIService.serverURL??''}/${icon["path"]}");
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  selectedIconId = icon["id"];
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color:
                                        isSelected ? Colors.blue : Colors.grey,
                                    width: isSelected ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                padding: const EdgeInsets.all(4),
                                child: Image(
                                  image: CachedNetworkImageProvider(
                                      "${APIService.serverURL ?? ''}/${icon["path"]}"),
                                  width: 46,
                                  height: 64,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              ('cancel').tr,
                              style: const TextStyle(
                                  fontSize: 18.0, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 20),
                          ElevatedButton(
                            onPressed: () => updateDevice(device["id"]),
                            child: Text(
                              ('ok').tr,
                              style: const TextStyle(
                                  fontSize: 18.0, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                )
              ],
            ),
          );
        },
      ),
    );

    showDialog(
      context: context,
      builder: (BuildContext context) => simpleDialog,
    );
  }

  void getEditDeviceData(deviceId) {
    selectedIconId = null;

    showProgress(true, context);
    Map<String, String> requestBody = <String, String>{
      'device_id': deviceId.toString()
    };
    APIService.editDeviceData(requestBody).then((value) => {
          showProgress(false, context),
          sd = SingleDevice.fromJson(
              json.decode(value.body.replaceAll("ï»¿", ""))),
          _name.text = sd!.item!["name"],
          editDeviceDialog(context, sd!.item)
        });
  }

  void updateDevice(deviceId) {
    showProgress(true, context);
    Map<String, String> requestBody = <String, String>{
      'name': _name.text,
      'fuel_measurement_id': sd!.item!["fuel_measurement_id"].toString(),
      'device_id': deviceId.toString(),
      if (selectedIconId != null) 'icon_id': selectedIconId.toString(),
    };

    APIService.editDevice(requestBody).then((value) => {
          showProgress(false, context),
          sd = SingleDevice.fromJson(
              json.decode(value.body.replaceAll("ï»¿", ""))),
          Navigator.pop(context),
          // editDeviceDialog(context, value),
        });
  }

  void showReport(String heading, int id, String name, DeviceItem device) {
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

    Navigator.pushNamed(context, "/reportList",
        arguments: ReportArguments(
            id, fromDate, fromTime, toDate, toTime, name, 0, device));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Text(
          'vehicles'.tr,
          style: const TextStyle(
            color: Colors.orange,
            fontSize: 32,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: IconButton(
              icon: const m.Icon(Icons.search, color: Colors.grey, size: 30),
              onPressed: () => controller.toggleSearchVisibility(),
            ),
          ),
        ],
        centerTitle: false,
        elevation: 0,
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            // Search Field
            if (controller.isSearchVisible.value)
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 10, right: 10),
                child: SizedBox(
                  height: 50,
                  child: TextFormField(
                    focusNode: _searchFocusNode,
                    controller: _searchController,
                    obscureText: false,
                    decoration: InputDecoration(
                      labelText: 'search'.tr,
                      labelStyle: FlutterFlowTheme.of(context).bodySmall,
                      hintStyle: FlutterFlowTheme.of(context).bodySmall,
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(
                          color: Color(0xFFDBE2E7),
                          width: 2.0,
                        ),
                        borderRadius: BorderRadius.circular(0),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsetsDirectional.fromSTEB(
                          16.0, 24.0, 0.0, 24.0),
                    ),
                    style: TextStyle(
                      color: FlutterFlowTheme.of(context).tertiary,
                    ),
                    onChanged: (text) => controller.searchDevices(text),
                  ),
                ),
              ),

            const Gap(15),

            // Replace the SizedBox with ListView of ChoiceChips with:
            _buildStatusFilter(),
            const Gap(10),

            // Device List
            Expanded(
              child: Obx(() {
                final displayList = controller.searchText.isNotEmpty
                    ? controller.searchedDevices
                    : controller.filteredDevices;

                if (displayList.isEmpty) {
                  return Center(child: Text(("noDeviceFound").tr));
                }

                return ListView.separated(
                  separatorBuilder: (context, index) => const Gap(10),
                  itemCount: displayList.length,
                  itemBuilder: (context, index) {
                    final device = displayList[index];
                    return deviceCard(
                        device, context, index, displayList.length);
                  },
                );
              }),
            )
          ],
        );
      }),
    );
  }

  Widget _buildStatusFilter() {
    return Obx(() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildFilterChip(
                      title: 'allVehicles'.tr,
                      isSelected: controller.selectedFilterIndex.value == 0,
                      onTap: () => controller.filterDevicesByStatus("all"),
                    ),
                    _buildFilterChip(
                      title: 'running'.tr,
                      isSelected: controller.selectedFilterIndex.value == 1,
                      onTap: () => controller.filterDevicesByStatus("green"),
                    ),
                    _buildFilterChip(
                      title: 'idle'.tr,
                      isSelected: controller.selectedFilterIndex.value == 2,
                      onTap: () => controller.filterDevicesByStatus("yellow"),
                    ),
                    _buildFilterChip(
                      title: 'offline'.tr,
                      isSelected: controller.selectedFilterIndex.value == 3,
                      onTap: () => controller.filterDevicesByStatus("red"),
                    ),
                  ],
                ),
              ),
            ),
            const Gap(10),
            Obx(() {
              String title = '';
              int count = 0;
              switch (controller.selectedFilterIndex.value) {
                case 0:
                  title = 'allVehicles'.tr;
                  count = controller.allCount.value ?? 0;
                  break;
                case 1:
                  title = 'running'.tr;
                  count = controller.movingCount.value ?? 0;
                  break;
                case 2:
                  title = 'idle'.tr;
                  count = controller.idleCount.value ?? 0;
                  break;
                case 3:
                  title = 'offline'.tr;
                  count = controller.offlineCount.value ?? 0;
                  break;
              }
              return Text(
                '$title: $count',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              );
            }),
          ],
        ),
      );
    });
  }

  Widget _buildFilterChip({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? CustomColor.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void showShareDialog(BuildContext context, dynamic device) {
    Dialog simpleDialog = Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return SizedBox(
            height: 400,
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
                                    expiryTime = 10;
                                  });
                                },
                              ),
                              const Text(
                                "10 min",
                                style: TextStyle(fontSize: 16.0),
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
                                    expiryTime = 15;
                                  });
                                },
                              ),
                              const Text(
                                "15 min",
                                style: TextStyle(fontSize: 16.0),
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
                                    expiryTime = 30;
                                  });
                                },
                              ),
                              const Text(
                                "30 min",
                                style: TextStyle(fontSize: 16.0),
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
                                    _selectedperiod =
                                        int.parse(value.toString());
                                    expiryTime = 60;
                                  });
                                },
                              ),
                              const Text(
                                "60 min",
                                style: TextStyle(fontSize: 16.0),
                              ),
                            ],
                          ),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: <Widget>[
                              Radio(
                                value: 4,
                                groupValue: _selectedperiod,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedperiod =
                                        int.parse(value.toString());
                                    expiryTime = 120;
                                  });
                                },
                              ),
                              const Text(
                                "120 min",
                                style: TextStyle(fontSize: 16.0),
                              ),
                            ],
                          ),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: <Widget>[
                              Radio(
                                value: 5,
                                groupValue: _selectedperiod,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedperiod =
                                        int.parse(value.toString());
                                    expiryTime = 180;
                                  });
                                },
                              ),
                              const Text(
                                "180 min",
                                style: TextStyle(fontSize: 16.0),
                              ),
                            ],
                          ),

                          // new Container(
                          //   child: new TextField(
                          //     controller: _shareEmail,
                          //     decoration: new InputDecoration(labelText: "Email"),
                          //   ),
                          // ),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.red, // foreground
                                ),
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
                                onPressed: () {
                                  shareLink(device);
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

  void shareLink(DeviceItem device) {
    DateTime currentDateTime = DateTime.now();
    Duration durationToAdd = Duration(minutes: expiryTime);
    DateTime newDateTime = currentDateTime.add(durationToAdd);
    APIService.generateShare(
            device.id.toString(),
            DateFormat('yyyy-MM-dd HH:mm:ss').format(newDateTime).toString(),
            device.name)
        .then((value) => {
              if (value is SharePerm)
                {
                  Navigator.pop(context),
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Check Permission")),
                  )
                }
              else
                {
                  Share.share(
                      "Device : ${value.name} \n ${UserRepository.getServerUrl()}/sharing/${value.hash}",
                      subject: "Device : ${value.name}")
                }
            });
  }

  Widget deviceCard(
      DeviceItem device, BuildContext context, int index, int totalLength) {
    final color = _getStatusColor(device.iconColor);
    final sensors = _buildSensorWidgets(device);
    final isLocked = false;

    return Padding(
      padding:
          const EdgeInsets.only(top: 5.0, left: 5.0, right: 7.0, bottom: 0),
      child: InkWell(
        onTap: () {
          AdMobService().showInterstitialAd();
          Get.to(() => TrackDevicePage(device.id, device.name, device));
        },
        child: Column(
          children: [
            if (index.isEven) BannerAdWidget(),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(5.0)),
                color: Colors.white,
                border: Border.all(width: 1.5, color: Colors.grey[350]!),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 3.0)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🔹 Top: icon + name + quick actions
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // vehicle icon
                        Container(
                          height: 60,
                          width: 60,
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            borderRadius:
                                const BorderRadius.all(Radius.circular(7)),
                            color: color.withOpacity(0.2),
                          ),
                          child: Image(
                            image: CachedNetworkImageProvider(
                              "${UserRepository.getServerUrl()}/${device.icon!.path!}",
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // name + status + actions
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      device.name ?? '',
                                      style: TextStyle(
                                          color: CustomColor.cssBlack,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 18),
                                    ),
                                  ),
                                  InkWell(
                                    child: m.Icon(Icons.directions_outlined,
                                        color: CustomColor.primaryColor,
                                        size: 22),
                                    onTap: () async {
                                      String origin =
                                          "${device.lat},${device.lng}";
                                      var url = '';
                                      var urlAppleMaps = '';
                                      if (Platform.isAndroid) {
                                        String query =
                                            Uri.encodeComponent(origin);
                                        url =
                                            "https://www.google.com/maps/search/?api=1&query=$query";
                                        await launchUrl(Uri.parse(url));
                                      } else {
                                        urlAppleMaps =
                                            'https://maps.apple.com/?q=$origin';
                                        url =
                                            "comgooglemaps://?saddr=&daddr=$origin&directionsmode=driving";
                                        if (await canLaunchUrl(
                                            Uri.parse(url))) {
                                          await launchUrl(Uri.parse(url));
                                        } else if (await canLaunchUrl(
                                            Uri.parse(urlAppleMaps))) {
                                          await launchUrl(
                                              Uri.parse(urlAppleMaps));
                                        } else {
                                          throw 'Could not launch $url';
                                        }
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    child: m.Icon(Icons.share,
                                        color: CustomColor.primaryColor,
                                        size: 22),
                                    onTap: () {
                                      showShareDialog(context, device);
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () {
                                      getEditDeviceData(device.id);
                                    },
                                    child: m.Icon(Icons.settings,
                                        color: CustomColor.primaryColor),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${device.iconColor == 'green' ? "Moving since:" : "Stopped since:"} ${device.stopDuration!}",
                                style: TextStyle(
                                  color: device.iconColor == 'green'
                                      ? Colors.green[600]
                                      : Colors.red[300],
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),

                  // Divider(thickness: 1.5, color: Colors.grey[350]),

                  // 🔹 Middle: speed + address
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Speed: ${convertSpeed(device.speed, device.distanceUnitHour!)}",
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildAddressWidget(device),
                      ],
                    ),
                  ),

                  // 🔹 Sensors
                  if (sensors.isNotEmpty) ...[
                    // Divider(thickness: 1.5, color: Colors.grey[350]),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ...sensors,
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // 🔹 Action buttons
                  // Divider(thickness: 1.5, color: Colors.grey[350]),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildActionButton(
                            icon: Icons.insert_drive_file,
                            label: 'report'.tr,
                            onTap: () {
                              AdMobService()
                                  .showInterstitialAd(ignoreFrequency: true);
                              showReport(('report').tr, device.id ?? 1,
                                  device.name ?? '', device);
                            },
                          ),
                          _buildActionButton(
                            icon: Icons.play_arrow,
                            label: 'playback'.tr,
                            onTap: () {
                              AdMobService()
                                  .showInterstitialAd(ignoreFrequency: true);
                              Navigator.pushNamed(
                                context,
                                "/playback",
                                arguments: ReportArguments(device.id!, "", "", "",
                                    "", device.name!, 0, device),
                              );
                            },
                          ),
                          _buildActionButton(
                            icon: Icons.call,
                            label: 'call'.tr,
                            onTap: () {
                              if (device.driverData?.phone != null &&
                                  device.driverData!.phone.isNotEmpty) {
                                launchUrl(
                                    Uri.parse('tel:${device.driverData?.phone}'));
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('phoneNumberNotFound'.tr),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                          ),
                          _buildActionButton(
                            icon: isLocked ? Icons.lock_open : Icons.lock,
                            label: isLocked ? 'unlock'.tr : 'lock'.tr,
                            onTap: () {
                              AdMobService()
                                  .showInterstitialAd(ignoreFrequency: true);
                              Get.to(() => LockUnlockScreen(device: device));
                            },
                          ),
                          _buildActionButton(
                            icon: Icons.location_on,
                            label: 'address'.tr,
                            onTap: () {
                              _showAddress(device.id ?? 0);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (ALWAYS_SHOW_BANNER_ADS && totalLength == 0 && index == 0)
              BannerAdWidget(forceShow: ALWAYS_SHOW_BANNER_ADS),
            if (ALWAYS_SHOW_BANNER_ADS && totalLength >= 1 && index == 1)
              BannerAdWidget(forceShow: ALWAYS_SHOW_BANNER_ADS),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isLock = false,
  }) {
    return SizedBox(
      height: 48,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24), // fully rounded
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                m.Icon(
                  icon,
                  size: 20,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getButtonColor(IconData icon) {
    switch (icon) {
      case Icons.play_arrow:
        return Colors.purple;
      case Icons.call:
        return Colors.green;
      case Icons.lock:
      case Icons.lock_open:
        return Colors.orange;
      case Icons.settings:
        return Colors.blue;
      default:
        return Colors.blue;
    }
  }

  Color _getStatusColor(String? iconColor) {
    if (iconColor == "green") return Colors.green[600]!;
    if (iconColor == "yellow") return Colors.yellow.shade800;
    if (iconColor == "red") return Colors.red[400]!;
    return Colors.yellow.shade700;
  }

  List<Widget> _buildSensorWidgets(DeviceItem device) {
    final sensors = <Widget>[];
    final color = _getStatusColor(device.iconColor);

    try {
      for (var sensor in device.sensors!) {
        if (sensor['value'] != null) {
          sensors.add(
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: color.withOpacity(0.3), width: 1),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      "assets/images/sensors/${sensor['type']}.png",
                      width: 20,
                      height: 20,
                    ),
                    const SizedBox(width: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          sensor["name"],
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _gsmCodeConvert(sensor['value']),
                          style: TextStyle(
                            fontSize: 10,
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
          sensors.add(const SizedBox(width: 4));
        }
      }
    } catch (e) {
      debugPrint("Error building sensor widgets: $e");
    }

    return sensors;
  }

  String _gsmCodeConvert(value) {
    switch (value) {
      case "71606":
        return "Movistar";
      case "71610":
        return "Claro";
      case "71617":
        return "Entel";
      case "71615":
        return "Bitel";
      default:
        return value;
    }
  }
}

class Choice {
  const Choice({this.title, this.icon});

  final String? title;
  final IconData? icon;
}
