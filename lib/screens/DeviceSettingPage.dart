import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
import 'package:smart_lock/services/model/single_device.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/storage/user_repository.dart';
import 'package:smart_lock/screens/common_method.dart';

class DeviceSettingPage extends StatefulWidget {
  const DeviceSettingPage({super.key});

  @override
  State<DeviceSettingPage> createState() => _DeviceSettingPageState();
}

class _DeviceSettingPageState extends State<DeviceSettingPage> {
  static const Color _primaryRed = Color(0xFFC0392B);
  static const Color _greyText = Color(0xFF6B7280);
  static const Color _darkText = Color(0xFF1F2937);

  DeviceItem? selectedDevice;
  SingleDevice? sd;
  int? selectedIconId;

  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSelectDeviceSheet() {
    final DataController controller = Get.find<DataController>();
    final devices = controller.onlyDevices;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _primaryRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.directions_car, color: _primaryRed),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Select Device',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Device List
                if (devices.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.devices, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text('No devices available', style: TextStyle(color: _greyText)),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: devices.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        final isSelected = selectedDevice?.id == device.id;

                        return InkWell(
                          onTap: () {
                            setState(() => selectedDevice = device);
                            Navigator.pop(context);
                            _showSnackBar('${device.name} selected');
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected ? _primaryRed.withValues(alpha: 0.05) : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? _primaryRed : Colors.grey.shade200,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Device Icon
                                if (device.icon?.path != null)
                                  CachedNetworkImage(
                                    imageUrl: "${UserRepository.getServerUrl()}/${device.icon!.path!}",
                                    width: 40,
                                    height: 40,
                                    errorWidget: (_, __, ___) => Icon(
                                      Icons.directions_car,
                                      size: 40,
                                      color: _greyText,
                                    ),
                                  )
                                else
                                  Icon(Icons.directions_car, size: 40, color: _greyText),

                                const SizedBox(width: 14),

                                // Device Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        device.name ?? 'Unknown Device',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected ? _primaryRed : _darkText,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'IMEI: ${device.imei ?? 'N/A'}',
                                        style: TextStyle(fontSize: 12, color: _greyText),
                                      ),
                                    ],
                                  ),
                                ),

                                // Selection Indicator
                                if (isSelected)
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: _primaryRed,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.check, color: Colors.white, size: 16),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEditSheet() {
    if (selectedDevice == null) {
      _showSnackBar('Please select a device first', isError: true);
      return;
    }

    // Load device data first
    showProgress(true, context);

    APIService.editDeviceData({'device_id': selectedDevice!.id.toString()}).then((value) {
      showProgress(false, context);

      sd = SingleDevice.fromJson(json.decode(value.body.replaceAll("ï»¿", "")));
      _nameController.text = sd!.item!["name"] ?? '';
      selectedIconId = sd!.item!["icon_id"];

      // Show the edit bottom sheet
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => _buildEditSheet(),
      );
    }).catchError((e) {
      showProgress(false, context);
      _showSnackBar('Failed to load device data', isError: true);
    });
  }

  Widget _buildEditSheet() {
    return StatefulBuilder(
      builder: (context, setSheetState) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _primaryRed.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.edit, color: _primaryRed),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Edit Device',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                selectedDevice!.name ?? 'Device',
                                style: TextStyle(fontSize: 13, color: _greyText),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Content
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Device Name
                        const Text(
                          'Device Name',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            hintText: 'Enter device name',
                            prefixIcon: Icon(Icons.label_outline, color: _primaryRed),
                            filled: true,
                            fillColor: const Color(0xFFF9FAFB),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _primaryRed, width: 2),
                            ),
                          ),
                        ),

                        // Icon Selection
                        if (sd?.device_icons != null && sd!.device_icons!.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          const Text(
                            'Select Icon',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 1,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: sd!.device_icons!.length,
                            itemBuilder: (context, index) {
                              final icon = sd!.device_icons![index];
                              final isSelected = selectedIconId == icon["id"];

                              return GestureDetector(
                                onTap: () {
                                  setSheetState(() {
                                    selectedIconId = icon["id"];
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected ? _primaryRed.withValues(alpha: 0.1) : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? _primaryRed : Colors.grey.shade300,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: CachedNetworkImage(
                                          imageUrl: "${APIService.serverURL ?? ''}/${icon["path"]}",
                                          width: 50,
                                          height: 50,
                                          fit: BoxFit.contain,
                                          errorWidget: (_, __, ___) => Icon(
                                            Icons.image,
                                            size: 50,
                                            color: _greyText,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: _primaryRed,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.check, color: Colors.white, size: 12),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],

                        const SizedBox(height: 80),
                      ],
                    ),
                  ),

                  // Save Button
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _greyText,
                                side: BorderSide(color: Colors.grey.shade300),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () => _updateDevice(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryRed,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updateDevice() async {
    if (_nameController.text.trim().isEmpty) {
      _showSnackBar('Please enter a device name', isError: true);
      return;
    }

    Navigator.pop(context); // Close edit sheet

    showProgress(true, context);

    Map<String, String> requestBody = {
      'name': _nameController.text.trim(),
      'fuel_measurement_id': sd!.item!["fuel_measurement_id"].toString(),
      'device_id': selectedDevice!.id.toString(),
      if (selectedIconId != null) 'icon_id': selectedIconId.toString(),
    };

    try {
      await APIService.editDevice(requestBody);

      if (mounted) {
        showProgress(false, context);
        _showSnackBar('Device updated successfully');

        // Refresh device data
        Get.find<DataController>().getDevices();

        // Reset selection
        setState(() {
          selectedDevice = null;
          sd = null;
          selectedIconId = null;
          _nameController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        showProgress(false, context);
        _showSnackBar('Failed to update device', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _primaryRed,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Device Settings',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          // Selected Device Display
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selectedDevice != null
                        ? _primaryRed.withValues(alpha: 0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.directions_car,
                    color: selectedDevice != null ? _primaryRed : _greyText,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selected Device',
                        style: TextStyle(fontSize: 12, color: _greyText),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selectedDevice?.name ?? 'No device selected',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: selectedDevice != null ? _darkText : _greyText,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _showSelectDeviceSheet,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('Select'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Options
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildOptionCard(
                  icon: Icons.edit_outlined,
                  title: 'Edit Device',
                  subtitle: 'Change name and icon',
                  onTap: _showEditSheet,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _primaryRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _primaryRed, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _darkText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: _greyText),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: _greyText),
          ],
        ),
      ),
    );
  }
}