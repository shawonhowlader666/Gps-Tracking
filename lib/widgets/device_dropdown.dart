import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/services/model/device_item.dart';
import 'package:smart_lock/widgets/common.dart';

class DeviceDropdown extends StatelessWidget {
  final DataController dataController;
  final String? selectedVehicle;
  final Function(String?) onChanged;

  const DeviceDropdown({
    super.key,
    required this.dataController,
    required this.selectedVehicle,
    required this.onChanged,
  });

  String _formatVehicleName(DeviceItem device) {
    return device.name ?? 'Unnamed Vehicle';
  }

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      title: 'selectVehicle'.tr,
      child: Obx(() {
        final devices = dataController.onlyDevices;
        if (devices.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        // if (devices.isEmpty) {
        //   return Center(child: Text("noVehicle".tr));
        // }
        return DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          initialValue: selectedVehicle,
          items: devices
              .map((device) => DropdownMenuItem<String>(
                    value: _formatVehicleName(device),
                    child: Text(_formatVehicleName(device)),
                  ))
              .toList(),
          onChanged: onChanged,
        );
      }),
    );
  }
}
