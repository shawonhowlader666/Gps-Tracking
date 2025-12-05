import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/config.dart';
import 'package:gpspro/flutter_flow/flutter_flow_util.dart';
import 'package:gpspro/screens/common_method.dart';
import 'package:gpspro/screens/lock_unlock_screen.dart';
import 'package:gpspro/screens/track_device.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/admob_service.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/services/model/share_perm.dart';
import 'package:gpspro/services/model/single_device.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/widgets/address.dart';
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
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF3E6FB8),
                const Color(0xFF5C8ACF),
              ],
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.directions_car_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'vehicles'.tr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Obx(() => Text(
                          '${controller.allCount.value} ${'devices'.tr}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        )),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => controller.toggleSearchVisibility(),
                    child: Obx(() => Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: controller.isSearchVisible.value
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.search_rounded,
                        color: controller.isSearchVisible.value
                            ? const Color(0xFF898BEA)
                            : Colors.white,
                        size: 22,
                      ),
                    )),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      controller.filterDevicesByStatus("all");
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            const Gap(6),

            // Search Field
            if (controller.isSearchVisible.value)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Color(0xFF5C8ACF)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    focusNode: _searchFocusNode,
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'search'.tr,
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                        icon: Icon(Icons.close, color: Colors.grey[400]),
                        onPressed: () {
                          _searchController.clear();
                          controller.searchDevices('');
                        },
                      )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    onChanged: (text) => controller.searchDevices(text),
                  ),
                ),
              ),

            if (controller.isSearchVisible.value) const Gap(6),

            // Status Filter
            _buildStatusFilter(),
            const Gap(6),

            // Device List
            Expanded(
              child: Obx(() {
                final displayList = controller.searchText.isNotEmpty
                    ? controller.searchedDevices
                    : controller.filteredDevices;

                if (displayList.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.directions_car_outlined,
                          size: 60,
                          color: Colors.grey[300],
                        ),
                        const Gap(16),
                        Text(
                          ("noDeviceFound").tr,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  separatorBuilder: (context, index) => const Gap(10),
                  itemCount: displayList.length,
                  padding: const EdgeInsets.only(bottom: 20),
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
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildFilterCard(
              index: 0,
              icon: Icons.apps_rounded,
              label: 'all'.tr,
              count: controller.allCount.value,
              primaryColor: const Color(0xFF5C8ACF),
              isSelected: controller.selectedFilterIndex.value == 0,
              onTap: () => controller.filterDevicesByStatus("all"),
            ),
            _buildFilterCard(
              index: 1,
              icon: Icons.directions_car_filled_rounded,
              label: 'running'.tr,
              count: controller.movingCount.value,
              primaryColor: const Color(0xFF22C55E),
              isSelected: controller.selectedFilterIndex.value == 1,
              onTap: () => controller.filterDevicesByStatus("green"),
            ),
            _buildFilterCard(
              index: 2,
              icon: Icons.pause_circle_filled_rounded,
              label: 'idle'.tr,
              count: controller.idleCount.value,
              primaryColor: const Color(0xFFF59E0B),
              isSelected: controller.selectedFilterIndex.value == 2,
              onTap: () => controller.filterDevicesByStatus("yellow"),
            ),
            _buildFilterCard(
              index: 3,
              icon: Icons.power_off_rounded,
              label: 'offline'.tr,
              count: controller.offlineCount.value,
              primaryColor: const Color(0xFFEF4444),
              isSelected: controller.selectedFilterIndex.value == 3,
              onTap: () => controller.filterDevicesByStatus("red"),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildFilterCard({
    required int index,
    required IconData icon,
    required String label,
    required int count,
    required Color primaryColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 65,
        height: 80,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 20),
              width: 65,
              height: 60,
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
              decoration: BoxDecoration(
                color: isSelected ? primaryColor : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? primaryColor
                      : primaryColor.withValues(alpha: 0.2),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 2,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : primaryColor,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.95)
                          : Colors.grey[600],
                      height: 1,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isSelected
                        ? [primaryColor, primaryColor.withValues(alpha: 0.8)]
                        : [primaryColor.withValues(alpha: 0.9), primaryColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void showShareDialog(BuildContext context, dynamic device) {
    final List<Map<String, dynamic>> options = [
      {'value': 0, 'label': '10 min', 'time': 10},
      {'value': 1, 'label': '15 min', 'time': 15},
      {'value': 2, 'label': '30 min', 'time': 30},
      {'value': 3, 'label': '60 min', 'time': 60},
      {'value': 4, 'label': '120 min', 'time': 120},
      {'value': 5, 'label': '180 min', 'time': 180},
    ];

    int selectedIndex = 0;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.share_rounded,
                            color: Color(0xFF6366F1),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'shareLocation'.tr,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'selectDuration'.tr,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ...options.map((option) {
                      final isSelected = selectedIndex == option['value'];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedIndex = option['value'];
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF6366F1).withValues(alpha: 0.1)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF6366F1)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF6366F1)
                                        : Colors.grey[400]!,
                                    width: 2,
                                  ),
                                  color: isSelected
                                      ? const Color(0xFF6366F1)
                                      : Colors.transparent,
                                ),
                                child: isSelected
                                    ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                option['label'],
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? const Color(0xFF6366F1)
                                      : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              ('cancel').tr,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              expiryTime = options[selectedIndex]['time'];
                              shareLink(device);
                            },
                            child: Text(
                              ('share').tr,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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

  _StatusColors _getStatusColors(String? iconColor) {
    switch (iconColor) {
      case "green":
        return _StatusColors(
          primary: const Color(0xFF22C55E),
          bgGradientStart: const Color(0xFFDCFCE7),
          bgGradientEnd: const Color(0xFFF0FDF4),
          borderColor: const Color(0xFF86EFAC),
          iconBgColor: const Color(0xFF22C55E).withValues(alpha: 0.15),
          actionBarColor: const Color(0xFFF0FDF4),
          statusText: 'Running',
          statusIcon: Icons.directions_car,
        );
      case "yellow":
        return _StatusColors(
          primary: const Color(0xFFF59E0B),
          bgGradientStart: const Color(0xFFFEF3C7),
          bgGradientEnd: const Color(0xFFFFFBEB),
          borderColor: const Color(0xFFFCD34D),
          iconBgColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
          actionBarColor: const Color(0xFFFFFBEB),
          statusText: 'Idle',
          statusIcon: Icons.pause_circle_outline,
        );
      case "red":
        return _StatusColors(
          primary: const Color(0xFFEF4444),
          bgGradientStart: const Color(0xFFFEE2E2),
          bgGradientEnd: const Color(0xFFFEF2F2),
          borderColor: const Color(0xFFFCA5A5),
          iconBgColor: const Color(0xFFEF4444).withValues(alpha: 0.15),
          actionBarColor: const Color(0xFFFEF2F2),
          statusText: 'Offline',
          statusIcon: Icons.power_off,
        );
      default:
        return _StatusColors(
          primary: const Color(0xFF6B7280),
          bgGradientStart: const Color(0xFFF3F4F6),
          bgGradientEnd: const Color(0xFFF9FAFB),
          borderColor: const Color(0xFFD1D5DB),
          iconBgColor: const Color(0xFF6B7280).withValues(alpha: 0.15),
          actionBarColor: const Color(0xFFF9FAFB),
          statusText: 'Unknown',
          statusIcon: Icons.help_outline,
        );
    }
  }

  Widget deviceCard(
      DeviceItem device, BuildContext context, int index, int totalLength) {
    final statusColors = _getStatusColors(device.iconColor);
    final sensors = _buildSensorWidgets(device);
    final isLocked = false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            AdMobService().showInterstitialAd();
            Get.to(() => TrackDevicePage(device.id, device.name, device));
          },
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
              if (index.isEven) BannerAdWidget(),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      statusColors.bgGradientStart,
                      statusColors.bgGradientEnd,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            statusColors.primary,
                            statusColors.primary.withValues(alpha: 0),
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(28),
                          topRight: Radius.circular(16),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _buildVehicleIcon(device, statusColors),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildVehicleInfo(device, statusColors),
                              ),
                              _buildQuickActions(device, statusColors),
                            ],
                          ),
                          _buildAddressWidget(device),
                          if (sensors.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: sensors),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _buildBottomActionBar(device, statusColors, isLocked),
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
      ),
    );
  }

  Widget _buildVehicleIcon(DeviceItem device, _StatusColors statusColors) {
    return Stack(
      children: [
        Container(
          height: 68,
          width: 68,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                statusColors.primary.withValues(alpha: 0.6),
                statusColors.primary.withValues(alpha: 0.2),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: statusColors.primary.withValues(alpha: 0.4),
                blurRadius: 4,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: CachedNetworkImage(
              imageUrl:
              "${UserRepository.getServerUrl()}/${device.icon!.path!}",
              fit: BoxFit.contain,
              placeholder: (context, url) => Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Icon(
                Icons.directions_car,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: statusColors.bgGradientStart, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 2,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleInfo(DeviceItem device, _StatusColors statusColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          device.name ?? '',
          style: TextStyle(
            color: Colors.grey[800],
            fontWeight: FontWeight.w700,
            fontSize: 18,
            letterSpacing: -0.5,
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: statusColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    statusColors.statusIcon,
                    size: 12,
                    color: statusColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    statusColors.statusText,
                    style: TextStyle(
                      color: statusColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                device.stopDuration ?? '',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: statusColors.primary.withValues(alpha: 0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.speed, size: 16, color: statusColors.primary),
              const SizedBox(width: 6),
              Text(
                convertSpeed(device.speed, device.distanceUnitHour!),
                style: TextStyle(
                  color: statusColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(DeviceItem device, _StatusColors statusColors) {
    return Column(
      children: [
        _buildActionButton(
          icon: Icons.near_me,
          statusColors: statusColors,
          onTap: () async {
            String origin = "${device.lat},${device.lng}";
            if (Platform.isAndroid) {
              String query = Uri.encodeComponent(origin);
              String url =
                  "https://www.google.com/maps/search/?api=1&query=$query";
              await launchUrl(Uri.parse(url));
            } else {
              String urlAppleMaps = 'https://maps.apple.com/?q=$origin';
              String url =
                  "comgooglemaps://?saddr=&daddr=$origin&directionsmode=driving";
              if (await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(Uri.parse(url));
              } else if (await canLaunchUrl(Uri.parse(urlAppleMaps))) {
                await launchUrl(Uri.parse(urlAppleMaps));
              }
            }
          },
        ),
        const SizedBox(height: 2),
        _buildActionButton(
          icon: Icons.location_on_outlined,
          statusColors: statusColors,
          onTap: () => _showAddress(device.id ?? 0)
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required _StatusColors statusColors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: statusColors.primary.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 2,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: statusColors.primary,
          size: 20,
        ),
      ),
    );
  }

  // UPDATED: Removed Playback, Added Settings and More
  Widget _buildBottomActionBar(
      DeviceItem device, _StatusColors statusColors, bool isLocked) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border(
          top: BorderSide(
            color: Colors.black.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 2,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Report
          _buildBottomActionItem(
            icon: Icons.description_outlined,
            label: 'report'.tr,
            statusColors: statusColors,
            onTap: () {
              AdMobService().showInterstitialAd(ignoreFrequency: true);
              showReport(
                  ('report').tr, device.id ?? 1, device.name ?? '', device);
            },
          ),
          // Call
          _buildBottomActionItem(
            icon: Icons.phone_outlined,
            label: 'call'.tr,
            statusColors: statusColors,
            onTap: () {
              if (device.driverData?.phone != null &&
                  device.driverData!.phone.isNotEmpty) {
                launchUrl(Uri.parse('tel:${device.driverData?.phone}'));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('phoneNumberNotFound'.tr),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          // Lock/Unlock
          _buildBottomActionItem(
            icon: isLocked ? Icons.lock_open_outlined : Icons.lock_outlined,
            label: isLocked ? 'unlock'.tr : 'lock'.tr,
            statusColors: statusColors,
            onTap: () {
              AdMobService().showInterstitialAd(ignoreFrequency: true);
              Get.to(() => LockUnlockScreen(device: device));
            },
          ),
          // Settings (NEW)
          _buildBottomActionItem(
            icon: Icons.settings_outlined,
            label: 'settings'.tr,
            statusColors: statusColors,
            onTap: () {
              getEditDeviceData(device.id);
            },
          ),
          // More (NEW)
          _buildBottomActionItem(
            icon: Icons.more_horiz,
            label: 'more'.tr,
            statusColors: statusColors,
            onTap: () {
              _showMoreOptions(context, device);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionItem({
    required IconData icon,
    required String label,
    required _StatusColors statusColors,
    required VoidCallback onTap,
    bool isAddressButton = false,
  }) {
    final bool isAddressShowing =
        isAddressButton && _showingAddressForDeviceId != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      splashColor: statusColors.primary.withValues(alpha: 0.15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isAddressShowing
              ? statusColors.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: statusColors.primary.withValues(alpha: 0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: statusColors.primary.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: statusColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: statusColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // UPDATED: Enhanced Bottom Sheet with All Actions and Sensors
  void _showMoreOptions(BuildContext context, DeviceItem device) {
    final statusColors = _getStatusColors(device.iconColor);
    final isLocked = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                statusColors.bgGradientStart,
                statusColors.bgGradientEnd,
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle Bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: statusColors.primary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Device Header
                  Row(
                    children: [
                      Container(
                        height: 60,
                        width: 60,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: statusColors.primary,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: statusColors.primary.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: device.icon?.path != null
                            ? CachedNetworkImage(
                          imageUrl:
                          "${UserRepository.getServerUrl()}/${device.icon!.path!}",
                          fit: BoxFit.contain,
                          errorWidget: (context, url, error) => Icon(
                            Icons.directions_car,
                            color: Colors.white,
                            size: 28,
                          ),
                        )
                            : Icon(
                          Icons.directions_car,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.name ?? '',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColors.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        statusColors.statusIcon,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        statusColors.statusText,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  convertSpeed(
                                      device.speed, device.distanceUnitHour!),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Quick Actions Title
                  Text(
                    'quickActions'.tr,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Action Buttons Grid
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // First Row
                        Row(
                          children: [
                            _buildGridActionItem(
                              icon: Icons.description_outlined,
                              label: 'report'.tr,
                              color: const Color(0xFF6366F1),
                              onTap: () {
                                Navigator.pop(context);
                                AdMobService()
                                    .showInterstitialAd(ignoreFrequency: true);
                                showReport(('report').tr, device.id ?? 1,
                                    device.name ?? '', device);
                              },
                            ),
                            _buildGridActionItem(
                              icon: Icons.play_circle_outline,
                              label: 'playback'.tr,
                              color: const Color(0xFF8B5CF6),
                              onTap: () {
                                Navigator.pop(context);
                                AdMobService()
                                    .showInterstitialAd(ignoreFrequency: true);
                                Navigator.pushNamed(
                                  context,
                                  "/playback",
                                  arguments: ReportArguments(
                                    device.id!,
                                    "",
                                    "",
                                    "",
                                    "",
                                    device.name!,
                                    0,
                                    device,
                                  ),
                                );
                              },
                            ),
                            _buildGridActionItem(
                              icon: Icons.phone_outlined,
                              label: 'call'.tr,
                              color: const Color(0xFF22C55E),
                              onTap: () {
                                Navigator.pop(context);
                                if (device.driverData?.phone != null &&
                                    device.driverData!.phone.isNotEmpty) {
                                  launchUrl(Uri.parse(
                                      'tel:${device.driverData?.phone}'));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('phoneNumberNotFound'.tr),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                            ),
                            _buildGridActionItem(
                              icon: isLocked
                                  ? Icons.lock_open_outlined
                                  : Icons.lock_outlined,
                              label: isLocked ? 'unlock'.tr : 'lock'.tr,
                              color: const Color(0xFFF59E0B),
                              onTap: () {
                                Navigator.pop(context);
                                AdMobService()
                                    .showInterstitialAd(ignoreFrequency: true);
                                Get.to(() => LockUnlockScreen(device: device));
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Second Row
                        Row(
                          children: [
                            _buildGridActionItem(
                              icon: Icons.location_on_outlined,
                              label: 'address'.tr,
                              color: const Color(0xFFEF4444),
                              onTap: () {
                                Navigator.pop(context);
                                _showAddress(device.id ?? 0);
                              },
                            ),
                            _buildGridActionItem(
                              icon: Icons.share_outlined,
                              label: 'share'.tr,
                              color: const Color(0xFF0EA5E9),
                              onTap: () {
                                Navigator.pop(context);
                                showShareDialog(context, device);
                              },
                            ),
                            _buildGridActionItem(
                              icon: Icons.near_me_outlined,
                              label: 'navigate'.tr,
                              color: const Color(0xFF14B8A6),
                              onTap: () async {
                                Navigator.pop(context);
                                String origin = "${device.lat},${device.lng}";
                                if (Platform.isAndroid) {
                                  String query = Uri.encodeComponent(origin);
                                  String url =
                                      "https://www.google.com/maps/search/?api=1&query=$query";
                                  await launchUrl(Uri.parse(url));
                                } else {
                                  String urlAppleMaps =
                                      'https://maps.apple.com/?q=$origin';
                                  String url =
                                      "comgooglemaps://?saddr=&daddr=$origin&directionsmode=driving";
                                  if (await canLaunchUrl(Uri.parse(url))) {
                                    await launchUrl(Uri.parse(url));
                                  } else if (await canLaunchUrl(
                                      Uri.parse(urlAppleMaps))) {
                                    await launchUrl(Uri.parse(urlAppleMaps));
                                  }
                                }
                              },
                            ),
                            _buildGridActionItem(
                              icon: Icons.settings_outlined,
                              label: 'settings'.tr,
                              color: const Color(0xFF64748B),
                              onTap: () {
                                Navigator.pop(context);
                                getEditDeviceData(device.id);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Sensors Section
                  if (device.sensors != null && device.sensors!.isNotEmpty) ...[
                    Text(
                      'sensors'.tr,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: _buildSensorList(device, statusColors),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Grid Action Item for Bottom Sheet
  Widget _buildGridActionItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: color.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(
                icon,
                color: color,
                size: 26,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // Build Sensor List for Bottom Sheet
  List<Widget> _buildSensorList(DeviceItem device, _StatusColors statusColors) {
    List<Widget> sensorWidgets = [];

    try {
      for (int i = 0; i < device.sensors!.length; i++) {
        final sensor = device.sensors![i];
        if (sensor['value'] != null) {
          sensorWidgets.add(
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(
                border: i < device.sensors!.length - 1
                    ? Border(
                  bottom: BorderSide(
                    color: Colors.grey[200]!,
                    width: 1,
                  ),
                )
                    : null,
              ),
              child: Row(
                children: [
                  // Sensor Icon
                  Container(
                    width: 44,
                    height: 44,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.asset(
                      "assets/images/sensors/${sensor['type']}.png",
                      width: 24,
                      height: 24,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.sensors,
                        color: statusColors.primary,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Sensor Name & Type
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getSensorName(sensor['type'] ?? sensor['name'] ?? ''),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sensor['type'] ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Sensor Value
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: statusColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      _gsmCodeConvert(sensor['value']),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: statusColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error building sensor list: $e");
    }

    if (sensorWidgets.isEmpty) {
      sensorWidgets.add(
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                Icons.sensors_off,
                size: 48,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 12),
              Text(
                'noSensorsFound'.tr,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return sensorWidgets;
  }

  // Get Sensor Display Name
  String _getSensorName(String type) {
    final Map<String, String> sensorNames = {
      'fuel': 'Fuel Level',
      'temperature': 'Temperature',
      'battery': 'Battery',
      'gsm': 'GSM Signal',
      'ignition': 'Ignition',
      'door': 'Door',
      'acc': 'ACC',
      'speed': 'Speed',
      'odometer': 'Odometer',
      'engine': 'Engine',
      'alarm': 'Alarm',
      'power': 'Power',
      'voltage': 'Voltage',
      'rpm': 'RPM',
      'coolant': 'Coolant Temp',
      'oil': 'Oil Level',
      'seatbelt': 'Seatbelt',
      'harsh_acceleration': 'Harsh Acceleration',
      'harsh_braking': 'Harsh Braking',
      'harsh_cornering': 'Harsh Cornering',
    };

    return sensorNames[type.toLowerCase()] ?? type.toUpperCase();
  }

  List<Widget> _buildSensorWidgets(DeviceItem device) {
    final sensors = <Widget>[];
    final statusColors = _getStatusColors(device.iconColor);

    try {
      for (var sensor in device.sensors!) {
        if (sensor['value'] != null) {
          sensors.add(
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: statusColors.primary.withValues(alpha: 0.3),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      "assets/images/sensors/${sensor['type']}.png",
                      width: 18,
                      height: 18,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.sensors,
                        size: 18,
                        color: statusColors.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _gsmCodeConvert(sensor['value']),
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
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
        return value.toString();
    }
  }
}

class _StatusColors {
  final Color primary;
  final Color bgGradientStart;
  final Color bgGradientEnd;
  final Color borderColor;
  final Color iconBgColor;
  final Color actionBarColor;
  final String statusText;
  final IconData statusIcon;

  _StatusColors({
    required this.primary,
    required this.bgGradientStart,
    required this.bgGradientEnd,
    required this.borderColor,
    required this.iconBgColor,
    required this.actionBarColor,
    required this.statusText,
    required this.statusIcon,
  });
}

class Choice {
  const Choice({this.title, this.icon});

  final String? title;
  final IconData? icon;
}