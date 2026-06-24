import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smart_lock/screens/report/report_screen.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;

class SelectDevicePage extends StatefulWidget {
  const SelectDevicePage({super.key});

  @override
  State<SelectDevicePage> createState() => _SelectDevicePageState();
}

class _SelectDevicePageState extends State<SelectDevicePage> {
  static const Color _primaryRed = Color(0xFFC0392B);
  static const Color _lightRed = Color(0xFFE74C3C);
  static const Color _greyText = Color(0xFF6B7280);
  static const Color _darkText = Color(0xFF1F2937);

  final TextEditingController _searchController = TextEditingController();
  DeviceItem? _selectedDevice;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _generateReport() {
    if (_selectedDevice == null) {
      Get.snackbar(
        'No Device Selected',
        'Please select a device to generate report',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.9),
        colorText: Colors.white,
        margin: const EdgeInsets.all(16),
        borderRadius: 8,
        icon: const Icon(Icons.error_outline, color: Colors.white),
      );
      return;
    }

    Get.to(() => ReportScreen(
          deviceId: _selectedDevice!.id ?? 0,
          deviceName: _selectedDevice!.name ?? '',
          device: _selectedDevice!,
        ));
  }

  List<DeviceItem> _filterDevices(List<DeviceItem> devices) {
    if (_searchQuery.isEmpty) return devices;

    return devices.where((device) {
      final name = device.name?.toLowerCase() ?? '';
      final imei = device.imei?.toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || imei.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Select Device',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: GetX<DataController>(
        init: DataController(),
        builder: (controller) {
          final allDevices = controller.onlyDevices;
          final filteredDevices = _filterDevices(allDevices);

          return Column(
            children: [
              // Search Bar Section
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Search Device',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _darkText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                      decoration: InputDecoration(
                        hintText: 'Search by name or IMEI...',
                        hintStyle: TextStyle(
                          color: _greyText.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: _primaryRed,
                          size: 22,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: _primaryRed,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Device Count
              if (allDevices.isNotEmpty)
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.car_crash_outlined,
                        size: 18,
                        color: _greyText,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${filteredDevices.length} ${filteredDevices.length == 1 ? 'Device' : 'Devices'} Found',
                        style: TextStyle(
                          fontSize: 13,
                          color: _greyText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_selectedDevice != null) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _primaryRed.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 14,
                                color: _primaryRed,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '1 Selected',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _primaryRed,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // Device List
              Expanded(
                child: filteredDevices.isEmpty
                    ? _buildEmptyState()
                    : Container(
                        color: Colors.white,
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: filteredDevices.length,
                          separatorBuilder: (context, index) => const Divider(
                            height: 1,
                            indent: 72,
                            color: Color(0xFFF0F0F0),
                          ),
                          itemBuilder: (context, index) {
                            final device = filteredDevices[index];
                            final isSelected = _selectedDevice?.id == device.id;

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedDevice = device;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                color: isSelected
                                    ? _primaryRed.withValues(alpha: 0.05)
                                    : Colors.transparent,
                                child: Row(
                                  children: [
                                    // Device Icon
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? _primaryRed.withValues(alpha: 0.1)
                                            : const Color(0xFFF3F4F6),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.directions_car,
                                        color: isSelected
                                            ? _primaryRed
                                            : _greyText,
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    // Device Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            device.name ?? "No Name",
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? _primaryRed
                                                  : _darkText,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.phonelink_lock,
                                                size: 13,
                                                color: _greyText,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                device.imei ?? "N/A",
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: _greyText,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Selection Indicator
                                    if (isSelected)
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: _primaryRed,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      )
                                    else
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: const Color(0xFFD1D5DB),
                                            width: 2,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),

              // Generate Report Button
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
                  top: false,
                  child: ElevatedButton(
                    onPressed: _generateReport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _selectedDevice != null ? _primaryRed : _greyText,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      minimumSize: const Size(double.infinity, 52),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.assessment, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Generate Report',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: _greyText.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _searchQuery.isEmpty
                    ? Icons.car_crash_outlined
                    : Icons.search_off,
                size: 60,
                color: _greyText,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _searchQuery.isEmpty
                  ? 'No Devices Available'
                  : 'No Devices Found',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _darkText,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _searchQuery.isEmpty
                    ? 'There are no devices registered in your account'
                    : 'Try searching with a different keyword',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: _greyText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
