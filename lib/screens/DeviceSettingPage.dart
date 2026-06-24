import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
import 'package:smart_lock/services/model/single_device.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/storage/user_repository.dart';
import 'package:smart_lock/screens/common_method.dart';
import 'package:smart_lock/util/util.dart';

class DeviceSettingPage extends StatefulWidget {
  final DeviceItem? device;
  const DeviceSettingPage({super.key, this.device});

  @override
  State<DeviceSettingPage> createState() => _DeviceSettingPageState();
}

class _DeviceSettingPageState extends State<DeviceSettingPage> {
  static const Color _primaryRed = Color(0xFFC0392B);
  static const Color _greyText = Color(0xFF6B7280);
  static const Color _darkText = Color(0xFF1F2937);
  static const Color _sosRed = Color(0xFFDC2626);

  DeviceItem? selectedDevice;
  SingleDevice? sd;
  int? selectedIconId;
  String? tempSelectedPath;

  final List<Map<String, dynamic>> localIconsList = [
    {
      "id": 87,
      "path": "assets/images/ambulance_toprunning.png",
      "name": "Ambulance"
    },
    {"id": 93, "path": "assets/images/bike_toprunning.png", "name": "Bike"},
    {"id": 92, "path": "assets/images/bus_toprunning.png", "name": "Bus"},
    {"id": 59, "path": "assets/images/car_toprunning.png", "name": "Car"},
    {"id": 56, "path": "assets/images/car_green.png", "name": "Green Car"},
    {"id": 43, "path": "assets/images/crane_toprunning.png", "name": "Crane"},
    {
      "id": 47,
      "path": "assets/images/garbage_toprunning.png",
      "name": "Garbage"
    },
    {"id": 45, "path": "assets/images/mixer_toprunning.png", "name": "Mixer"},
    {"id": 65, "path": "assets/images/muv_toprunning.png", "name": "MUV"},
    {"id": 67, "path": "assets/images/pickup_toprunning.png", "name": "Pickup"},
    {
      "id": 92,
      "path": "assets/images/school_toprunning.png",
      "name": "School Bus"
    },
    {"id": 93, "path": "assets/images/scotty_toprunning.png", "name": "Scotty"},
    {"id": 57, "path": "assets/images/suv_toprunning.png", "name": "SUV"},
    {"id": 47, "path": "assets/images/tanker_toprunning.png", "name": "Tanker"},
    {"id": 95, "path": "assets/images/tempotvr_toprunning.png", "name": "CNG"},
    {"id": 47, "path": "assets/images/truck_toprunning.png", "name": "Truck"},
  ];

  final TextEditingController _nameController = TextEditingController();

  // SOS Controllers
  final TextEditingController _sosPhone1Controller = TextEditingController();
  final TextEditingController _sosPhone2Controller = TextEditingController();
  final TextEditingController _sosPhone3Controller = TextEditingController();
  bool _isSosSending = false;
  String? _sosPhone1Error;
  String? _sosPhone2Error;
  String? _sosPhone3Error;

  Color _getDeviceStatusColor(DeviceItem? d) {
    if (d == null) return const Color(0xFF9CA3AF); // default grey

    // Check online status
    bool isOnline = false;
    final onlineStr = d.online?.toLowerCase().trim() ?? '';
    if (onlineStr.contains('online')) {
      isOnline = true;
    } else if (!onlineStr.contains('offline')) {
      final iconColor = d.iconColor?.toLowerCase() ?? '';
      if (iconColor == 'green' || iconColor == 'yellow') {
        isOnline = true;
      } else {
        final speed = double.tryParse(d.speed.toString()) ?? 0;
        isOnline = speed > 0;
      }
    }

    if (!isOnline) return const Color(0xFF9CA3AF); // offline grey

    // Check engine and speed status
    final speed = double.tryParse(d.speed.toString()) ?? 0;
    if (speed > 0) {
      return const Color(0xFF22C55E); // running green
    }

    bool isEngineOn = false;
    if (d.engineStatus != null) {
      final status = d.engineStatus;
      if (status is bool) isEngineOn = status;
      if (status is int) isEngineOn = (status == 1);
      if (status is String) {
        final s = status.toLowerCase();
        if (['on', '1', 'true'].contains(s)) isEngineOn = true;
      }
    }
    if (isEngineOn || d.iconColor?.toLowerCase() == 'yellow') {
      return const Color(0xFFF59E0B); // idle yellow
    }

    return const Color(0xFFEF4444); // stop red
  }

  @override
  void initState() {
    super.initState();
    if (widget.device != null) {
      selectedDevice = widget.device;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showEditSheet();
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sosPhone1Controller.dispose();
    _sosPhone2Controller.dispose();
    _sosPhone3Controller.dispose();
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

  String? _validatePhone(String value, {bool isRequired = false}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      if (isRequired) return 'This field is required';
      return null;
    }

    final clean = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.isEmpty) {
      return 'Invalid number format';
    }

    if (clean.startsWith('880') || clean.startsWith('01')) {
      if (clean.startsWith('880') && clean.length != 13) {
        return 'BD number with country code must be 13 digits';
      }
      if (clean.startsWith('01') && clean.length != 11) {
        return 'BD mobile number must be 11 digits';
      }
    } else {
      if (clean.length < 8 || clean.length > 15) {
        return 'Number must be between 8 and 15 digits';
      }
    }
    return null;
  }

  // ─── SOS Sheet ───────────────────────────────────────────────────────────────

  void _showSosSheet() {
    _sosPhone1Error = null;
    _sosPhone2Error = null;
    _sosPhone3Error = null;
    if (selectedDevice == null) {
      _showSnackBar('Please select a device first', isError: true);
      return;
    }

    final devId = selectedDevice!.id;
    _sosPhone1Controller.text =
        UserRepository.prefs?.getString("sos_phone_1_$devId") ?? '';
    _sosPhone2Controller.text =
        UserRepository.prefs?.getString("sos_phone_2_$devId") ?? '';
    _sosPhone3Controller.text =
        UserRepository.prefs?.getString("sos_phone_3_$devId") ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
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
                              color: _sosRed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child:
                                const Icon(Icons.sos, color: _sosRed, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'SOS Alert Setup',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  selectedDevice!.name ?? 'Device',
                                  style:
                                      TextStyle(fontSize: 13, color: _greyText),
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
                          // Info Banner
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _sosRed.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: _sosRed.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.info_outline,
                                    color: _sosRed, size: 20),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Enter up to 3 emergency contact numbers. When SOS is triggered, the device will send an SMS alert and you can call each contact directly.',
                                    style: TextStyle(fontSize: 13, height: 1.5),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Phone Number Fields
                          const Text(
                            'Emergency Contacts',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),

                          _buildPhoneField(
                            controller: _sosPhone1Controller,
                            label: 'Contact 1 (Primary)',
                            hint: '+880XXXXXXXXXX',
                            icon: Icons.phone,
                            isRequired: true,
                            errorText: _sosPhone1Error,
                            onChanged: (val) {
                              setSheetState(() {
                                _sosPhone1Error =
                                    _validatePhone(val, isRequired: true);
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildPhoneField(
                            controller: _sosPhone2Controller,
                            label: 'Contact 2 (Optional)',
                            hint: '+880XXXXXXXXXX',
                            icon: Icons.phone_outlined,
                            errorText: _sosPhone2Error,
                            onChanged: (val) {
                              setSheetState(() {
                                _sosPhone2Error =
                                    _validatePhone(val, isRequired: false);
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildPhoneField(
                            controller: _sosPhone3Controller,
                            label: 'Contact 3 (Optional)',
                            hint: '+880XXXXXXXXXX',
                            icon: Icons.phone_outlined,
                            errorText: _sosPhone3Error,
                            onChanged: (val) {
                              setSheetState(() {
                                _sosPhone3Error =
                                    _validatePhone(val, isRequired: false);
                              });
                            },
                          ),

                          const SizedBox(height: 28),

                          // Quick Call Section
                          if (_sosPhone1Controller.text.isNotEmpty ||
                              _sosPhone2Controller.text.isNotEmpty ||
                              _sosPhone3Controller.text.isNotEmpty) ...[
                            const Text(
                              'Quick Call',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 12),
                            _buildQuickCallRow(context, setSheetState),
                            const SizedBox(height: 28),
                          ],

                          // SOS Trigger Section
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Send SOS Command to Device',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'This will send a GPRS SOS command to the tracking device.',
                                  style:
                                      TextStyle(fontSize: 12, color: _greyText),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _isSosSending
                                        ? null
                                        : () => _sendSosCommand(setSheetState),
                                    icon: _isSosSending
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.warning_amber_rounded),
                                    label: Text(
                                      _isSosSending
                                          ? 'Sending...'
                                          : 'Send SOS Command',
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _sosRed,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          _sosRed.withValues(alpha: 0.5),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 80),
                        ],
                      ),
                    ),

                    // Save Contacts Button
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final devId = selectedDevice!.id;

                                  final p1Err = _validatePhone(
                                      _sosPhone1Controller.text,
                                      isRequired: true);
                                  final p2Err = _validatePhone(
                                      _sosPhone2Controller.text,
                                      isRequired: false);
                                  final p3Err = _validatePhone(
                                      _sosPhone3Controller.text,
                                      isRequired: false);

                                  if (p1Err != null ||
                                      p2Err != null ||
                                      p3Err != null) {
                                    setSheetState(() {
                                      _sosPhone1Error = p1Err;
                                      _sosPhone2Error = p2Err;
                                      _sosPhone3Error = p3Err;
                                    });
                                    _showSnackBar(
                                        'Please fix validation errors first',
                                        isError: true);
                                    return;
                                  }

                                  // Clean phone number helper
                                  String cleanPhone(String phone) {
                                    var clean =
                                        phone.replaceAll(RegExp(r'[^0-9]'), '');
                                    if (clean.startsWith('880') &&
                                        clean.length == 13) {
                                      clean = clean.substring(2);
                                    }
                                    return clean;
                                  }

                                  final p1 = cleanPhone(
                                      _sosPhone1Controller.text.trim());
                                  final p2 = cleanPhone(
                                      _sosPhone2Controller.text.trim());
                                  final p3 = cleanPhone(
                                      _sosPhone3Controller.text.trim());

                                  _sosPhone1Controller.text = p1;
                                  _sosPhone2Controller.text = p2;
                                  _sosPhone3Controller.text = p3;

                                  await UserRepository.prefs
                                      ?.setString("sos_phone_1_$devId", p1);
                                  await UserRepository.prefs
                                      ?.setString("sos_phone_2_$devId", p2);
                                  await UserRepository.prefs
                                      ?.setString("sos_phone_3_$devId", p3);
                                  if (!mounted) return;
                                  setSheetState(() {
                                    _sosPhone1Error = null;
                                    _sosPhone2Error = null;
                                    _sosPhone3Error = null;
                                  }); // refresh quick call & clear errors
                                  _showSnackBar(
                                      'SOS contacts saved successfully');
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryRed,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Save Contacts',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600),
                                ),
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
      ),
    );
  }

  Widget _buildPhoneField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isRequired = false,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            if (isRequired) ...[
              const SizedBox(width: 4),
              const Text('*', style: TextStyle(color: _sosRed)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))
          ],
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(icon, color: _greyText, size: 20),
            errorText: errorText,
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
              borderSide: const BorderSide(color: _sosRed, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickCallRow(BuildContext context, StateSetter setSheetState) {
    final contacts = [
      {'label': 'Contact 1', 'number': _sosPhone1Controller.text},
      {'label': 'Contact 2', 'number': _sosPhone2Controller.text},
      {'label': 'Contact 3', 'number': _sosPhone3Controller.text},
    ].where((c) => (c['number'] as String).isNotEmpty).toList();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: contacts.map((contact) {
        return GestureDetector(
          onTap: () => _makePhoneCall(contact['number']!),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call, color: Colors.green.shade700, size: 16),
                const SizedBox(width: 6),
                Text(
                  contact['number']!,
                  style: TextStyle(
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnackBar('Could not launch call to $phoneNumber', isError: true);
    }
  }

  Future<void> _sendSosCommand(StateSetter setSheetState) async {
    if (selectedDevice == null) return;

    final phone1 = _sosPhone1Controller.text.trim();
    final phone2 = _sosPhone2Controller.text.trim();
    final phone3 = _sosPhone3Controller.text.trim();

    final p1Err = _validatePhone(phone1, isRequired: true);
    final p2Err = _validatePhone(phone2, isRequired: false);
    final p3Err = _validatePhone(phone3, isRequired: false);

    if (p1Err != null || p2Err != null || p3Err != null) {
      setSheetState(() {
        _sosPhone1Error = p1Err;
        _sosPhone2Error = p2Err;
        _sosPhone3Error = p3Err;
      });
      _showSnackBar('Please fix validation errors first', isError: true);
      return;
    }

    // Clean phone number helper
    String cleanPhone(String phone) {
      var clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (clean.startsWith('880') && clean.length == 13) {
        clean = clean.substring(2);
      }
      return clean;
    }

    final cleanPhone1 = cleanPhone(phone1);
    final cleanPhone2 = phone2.isNotEmpty ? cleanPhone(phone2) : '';
    final cleanPhone3 = phone3.isNotEmpty ? cleanPhone(phone3) : '';

    final sosNumbers = [
      cleanPhone1,
      if (cleanPhone2.isNotEmpty) cleanPhone2,
      if (cleanPhone3.isNotEmpty) cleanPhone3
    ].join(',');

    // Check device online status
    bool isOnline = false;
    final onlineStr = selectedDevice!.online?.toLowerCase().trim() ?? '';
    if (onlineStr.contains('online')) {
      isOnline = true;
    } else if (!onlineStr.contains('offline')) {
      final iconColor = selectedDevice!.iconColor?.toLowerCase() ?? '';
      if (iconColor == 'green' || iconColor == 'yellow') {
        isOnline = true;
      } else {
        final speed = double.tryParse(selectedDevice!.speed.toString()) ?? 0;
        isOnline = speed > 0;
      }
    }

    if (!isOnline) {
      _showSnackBar(
          '⚠️ Device is offline. GPRS commands will not be delivered.',
          isError: true);
    }

    setSheetState(() => _isSosSending = true);

    try {
      // GPRS command body — adjust `command` key/value to match your server's expected format
      final Map<String, dynamic> body = {
        'device_id': selectedDevice!.id.toString(),
        'type': 'gprs',
        'command': 'SOS,$sosNumbers#',
      };

      final response = await APIService.sendCommands(body);

      setSheetState(() => _isSosSending = false);

      if (response.statusCode == 200) {
        _showSnackBar('SOS command sent to device successfully');
      } else {
        _showSnackBar('Failed to send SOS command (${response.statusCode})',
            isError: true);
      }
    } catch (e) {
      setSheetState(() => _isSosSending = false);
      _showSnackBar('Error sending SOS command', isError: true);
    }
  }

  // ─── Select Device Sheet ──────────────────────────────────────────────────────

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
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
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
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600),
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
                if (devices.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.devices,
                              size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text('No devices available',
                              style: TextStyle(color: _greyText)),
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
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
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
                              color: isSelected
                                  ? _primaryRed.withValues(alpha: 0.05)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? _primaryRed
                                    : Colors.grey.shade200,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Util.getVehicleIconWidget(
                                  device.icon?.path,
                                  _getDeviceStatusColor(device),
                                  size: 40,
                                  iconType:
                                      device.icon?.type ?? device.iconType,
                                  deviceName: device.name,
                                  deviceId: device.id,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        device.name ?? 'Unknown Device',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected
                                              ? _primaryRed
                                              : _darkText,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'IMEI: ${device.imei ?? 'N/A'}',
                                        style: TextStyle(
                                            fontSize: 12, color: _greyText),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: _primaryRed,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.check,
                                        color: Colors.white, size: 16),
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

  // ─── Edit Device Sheet ────────────────────────────────────────────────────────

  void _showEditSheet() {
    if (selectedDevice == null) {
      _showSnackBar('Please select a device first', isError: true);
      return;
    }

    showProgress(true, context);

    APIService.editDeviceData({'device_id': selectedDevice!.id.toString()})
        .then((value) {
      showProgress(false, context);

      sd = SingleDevice.fromJson(json.decode(value.body.replaceAll("ï»¿", "")));
      _nameController.text = sd!.item!["name"] ?? '';
      selectedIconId = sd!.item!["icon_id"];

      // Retrieve / resolve custom icon path
      final devId = selectedDevice!.id;
      tempSelectedPath =
          UserRepository.prefs?.getString("custom_icon_path_$devId");
      if (tempSelectedPath == null || tempSelectedPath!.isEmpty) {
        final currentIconPath = sd!.item!["icon"]?["path"];
        if (currentIconPath != null) {
          final mapped = Util.getLocalMappedAsset(currentIconPath,
              iconType: sd!.item!["icon"]?["type"] ?? sd!.item!["icon_type"],
              deviceName: sd!.item!["name"],
              deviceId: devId);
          if (mapped != null) {
            tempSelectedPath = mapped;
          }
        } else {
          final currentIconId = sd!.item!["icon_id"];
          if (currentIconId != null) {
            for (var item in localIconsList) {
              if (item["id"] == currentIconId) {
                tempSelectedPath = item["path"];
                break;
              }
            }
          }
        }
      }

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
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
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
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                selectedDevice!.name ?? 'Device',
                                style:
                                    TextStyle(fontSize: 13, color: _greyText),
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
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        const Text(
                          'Device Name',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            hintText: 'Enter device name',
                            prefixIcon:
                                Icon(Icons.label_outline, color: _primaryRed),
                            filled: true,
                            fillColor: const Color(0xFFF9FAFB),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: _primaryRed, width: 2),
                            ),
                          ),
                        ),
                        if (localIconsList.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          const Text(
                            'Select Icon',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 1,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: localIconsList.length,
                            itemBuilder: (context, index) {
                              final icon = localIconsList[index];
                              final isSelected =
                                  tempSelectedPath == icon["path"];

                              return GestureDetector(
                                onTap: () {
                                  setSheetState(() {
                                    tempSelectedPath = icon["path"];
                                    selectedIconId = icon["id"];
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? _primaryRed.withValues(alpha: 0.1)
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? _primaryRed
                                          : Colors.grey.shade300,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: Image.asset(
                                          icon["path"],
                                          width: 50,
                                          height: 50,
                                          fit: BoxFit.contain,
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
                                            child: const Icon(Icons.check,
                                                color: Colors.white, size: 12),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: const Text('Save Changes',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
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

    Navigator.pop(context);
    showProgress(true, context);

    final devId = selectedDevice!.id;
    if (tempSelectedPath != null) {
      await UserRepository.prefs
          ?.setString("custom_icon_path_$devId", tempSelectedPath!);
    }

    Map<String, String> requestBody = {
      'name': _nameController.text.trim(),
      'fuel_measurement_id': sd!.item!["fuel_measurement_id"].toString(),
      'device_id': devId.toString(),
      if (selectedIconId != null) 'icon_id': selectedIconId.toString(),
    };

    try {
      await APIService.editDevice(requestBody);

      if (mounted) {
        showProgress(false, context);
        _showSnackBar('Device updated successfully');
        Get.find<DataController>().getDevices();
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

  // ─── Build ────────────────────────────────────────────────────────────────────

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
                  child: Util.getVehicleIconWidget(
                    selectedDevice?.icon?.path,
                    _getDeviceStatusColor(selectedDevice),
                    size: 32,
                    iconType:
                        selectedDevice?.icon?.type ?? selectedDevice?.iconType,
                    deviceName: selectedDevice?.name,
                    deviceId: selectedDevice?.id,
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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

                const SizedBox(height: 12),

                // SOS Card — visually distinct
                _buildSosCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSosCard() {
    return InkWell(
      onTap: _showSosSheet,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _sosRed.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _sosRed.withValues(alpha: 0.08),
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
                color: _sosRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.sos, color: _sosRed, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SOS Alert',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _sosRed,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Set emergency contacts & send SOS command',
                    style: TextStyle(fontSize: 13, color: _greyText),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: _sosRed.withValues(alpha: 0.6)),
          ],
        ),
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
