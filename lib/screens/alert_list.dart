import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gpspro/services/model/alert.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/services/model/user.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../services/model/geofence_model.dart';

class AlertListPage extends StatefulWidget {
  const AlertListPage({super.key});

  @override
  State<StatefulWidget> createState() => _AlertListPageState();
}

class _AlertListPageState extends State<AlertListPage> {
  Timer? _timer;
  SharedPreferences? prefs;
  User? user;
  bool isLoading = false;
  List<Alert> alertList = [];
  List<DeviceItem> devicesList = [];
  List<Geofence> fenceList = [];

  // Controller
  late DataController dataController;

  // Add Alert Variables
  List<String> selectedDevices = [];
  List<String> selectedFenceList = [];
  String selectedType = "";
  final TextEditingController _nameCtl = TextEditingController();
  final TextEditingController _typeCtl = TextEditingController();

  // Alert Types Configuration
  final List<Map<String, dynamic>> alertTypes = [
    {"name": "Over Speed", "icon": Icons.speed, "value": "overspeed"},
    {"name": "Stop Duration", "icon": Icons.stop_circle_outlined, "value": "stop_duration"},
    {"name": "Offline Duration", "icon": Icons.wifi_off, "value": "offline_duration"},
    {"name": "Ignition Duration", "icon": Icons.key, "value": "ignition_duration"},
    {"name": "Idle Duration", "icon": Icons.timer_outlined, "value": "idle_duration"},
    {"name": "Geofence In", "icon": Icons.login, "value": "geofence_in"},
    {"name": "Geofence Out", "icon": Icons.logout, "value": "geofence_out"},
    {"name": "Geofence In/Out", "icon": Icons.swap_horiz, "value": "geofence_inout"},
    {"name": "Start of Movement", "icon": Icons.play_arrow, "value": "start_of_movement"},
    {"name": "SOS", "icon": Icons.sos, "value": "sos"},
    {"name": "Fuel (Fill/Theft)", "icon": Icons.local_gas_station, "value": "fuel_fill_theft"},
    {"name": "Driver Change", "icon": Icons.person_off, "value": "driver_change_unauthorized"},
  ];

  @override
  void initState() {
    super.initState();
    _initController();
    _initialize();
  }

  Future<void> _initialize() async {
    await getUser();
    _loadDevices();
    _loadFences();
  }

  void _initController() {
    if (Get.isRegistered<DataController>()) {
      dataController = Get.find<DataController>();
    } else {
      dataController = Get.put(DataController());
    }
  }

  void _loadDevices() {
    try {
      devicesList = dataController.onlyDevices;
      setState(() {});
    } catch (e) {
      debugPrint("Error loading devices: $e");
    }
  }

  Future<void> _loadFences() async {
    try {
      final value = await APIService.getGeoFences();
      if (value != null && mounted) {
        setState(() {
          fenceList.clear();
          fenceList.addAll(value);
        });
      }
    } catch (e) {
      debugPrint("Error loading geofences: $e");
    }
  }

  Future<void> getUser() async {
    try {
      prefs = await SharedPreferences.getInstance();
      String? userJson = prefs?.getString("user");

      if (userJson == null || userJson.isEmpty) {
        debugPrint("User data not found in SharedPreferences");
        await getAlerts();
        return;
      }

      final parsed = json.decode(userJson);

      if (parsed == null) {
        debugPrint("Failed to parse user JSON");
        await getAlerts();
        return;
      }

      user = User.fromJson(parsed);

      debugPrint("User loaded successfully: ${_getCurrentUserName()}");

      await getAlerts();
      if (mounted) setState(() {});

    } catch (e, stackTrace) {
      debugPrint("Error getting user: $e");
      debugPrint("Stack trace: $stackTrace");
      await getAlerts();
    }
  }

  String _getCurrentUserName() {
    if (user == null) return 'Unknown User';
    if (user!.email != null && user!.email!.isNotEmpty) {
      return user!.email!;
    }
    return 'Unknown User';
  }

  String _getAlertUserName(Alert alert) {
    if (user != null && alert.user_id != null) {
      if (alert.user_id.toString() == user!.toString()) {
        return _getCurrentUserName();
      }
    }
    if (alert.user_id != null) {
      return 'User #${alert.user_id}';
    }
    return 'Unknown User';
  }

  Future<void> getAlerts() async {
    if (!mounted) return;

    setState(() => isLoading = true);

    try {
      final value = await APIService.getAlertList();

      if (mounted) {
        setState(() {
          isLoading = false;
          if (value != null) {
            alertList.clear();
            alertList.addAll(value);
            debugPrint("Loaded ${alertList.length} alerts");
          }
        });
      }
    } catch (e) {
      debugPrint("Error getting alerts: $e");
      if (mounted) {
        setState(() => isLoading = false);
        _showSnackBar('Failed to load alerts', isError: true);
      }
    }
  }

  void removeAlert(Alert alert) {
    _showLoadingDialog();
    Map<String, String> requestBody = {
      'id': alert.id.toString(),
      'active': "false"
    };

    APIService.activateAlert(requestBody).then((value) {
      if (mounted) {
        Navigator.pop(context);
        if (value.statusCode == 200) {
          _showSnackBar('Alert deactivated successfully');
          getAlerts();
        } else {
          _showSnackBar('Failed to deactivate alert', isError: true);
        }
      }
    }).catchError((e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Error: $e', isError: true);
      }
    });
  }

  void activateAlert(Alert alert) {
    _showLoadingDialog();
    Map<String, String> requestBody = {
      'id': alert.id.toString(),
      'active': "true"
    };

    APIService.activateAlert(requestBody).then((value) {
      if (mounted) {
        Navigator.pop(context);
        if (value.statusCode == 200) {
          _showSnackBar('Alert activated successfully');
          getAlerts();
        } else {
          _showSnackBar('Failed to activate alert', isError: true);
        }
      }
    }).catchError((e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Error: $e', isError: true);
      }
    });
  }

  void deleteAlert(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.delete_outline, color: Colors.red.shade400),
            ),
            const SizedBox(width: 12),
            const Text('Delete Alert'),
          ],
        ),
        content: const Text('Are you sure you want to delete this alert? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performDelete(id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _performDelete(int id) {
    _showLoadingDialog();
    APIService.destroyAlert(id).then((value) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Alert deleted successfully');
        getAlerts();
      }
    }).catchError((e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Failed to delete alert', isError: true);
      }
    });
  }

  // ✅ VALIDATION POPUP
  void _showValidationError(List<String> errors) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade400, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Required Fields',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please complete the following:',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ...errors.map((error) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade400,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5C8ACF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void addAlert() {
    // ✅ Validation with popup
    List<String> errors = [];

    if (_nameCtl.text.trim().isEmpty) {
      errors.add('Alert Name is required');
    }

    if (selectedType.isEmpty) {
      errors.add('Alert Type must be selected');
    }

    if (selectedDevices.isEmpty) {
      errors.add('At least one Device must be selected');
    }

    if (_needsValueInput() && _typeCtl.text.trim().isEmpty) {
      errors.add('${_getValueLabel()} is required for this alert type');
    }

    if (_isGeofenceType() && selectedFenceList.isEmpty) {
      errors.add('At least one Geofence must be selected for this alert type');
    }

    // Show validation popup if there are errors
    if (errors.isNotEmpty) {
      _showValidationError(errors);
      return;
    }

    Navigator.pop(context);
    _showLoadingDialog();

    String request = _buildAlertRequest();

    APIService.addAlert(request).then((value) {
      if (mounted) {
        Navigator.pop(context);

        if (value.statusCode == 200) {
          _showSnackBar('Alert created successfully');
          _resetForm();
          getAlerts();
        } else {
          try {
            final responseBody = json.decode(value.body);
            String errorMsg = responseBody['message'] ?? 'Failed to create alert';
            _showSnackBar(errorMsg, isError: true);
          } catch (e) {
            _showSnackBar('Failed to create alert', isError: true);
          }
        }
      }
    }).catchError((e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Error: $e', isError: true);
      }
    });
  }

  String _buildAlertRequest() {
    String name = Uri.encodeComponent(_nameCtl.text.trim());
    String type = selectedType;
    String devices = selectedDevices.join("&");

    if (_isSimpleType()) {
      return "&name=$name&type=$type&$devices";
    }

    if (_isGeofenceType()) {
      String geofences = selectedFenceList.join("&");
      return "&name=$name&type=$type&zone=0&$geofences&$devices";
    }

    String value = Uri.encodeComponent(_typeCtl.text.trim());
    String paramName = _getParameterName();
    return "&name=$name&type=$type&$paramName=$value&$devices";
  }

  bool _isSimpleType() {
    return selectedType == "start_of_movement" ||
        selectedType == "sos" ||
        selectedType == "fuel_fill_theft" ||
        selectedType == "driver_change_unauthorized";
  }

  String _getParameterName() {
    switch (selectedType) {
      case 'overspeed':
        return 'overspeed';
      case 'stop_duration':
        return 'stop_duration';
      case 'offline_duration':
        return 'offline_duration';
      case 'ignition_duration':
        return 'ignition_duration';
      case 'idle_duration':
        return 'idle_duration';
      default:
        return selectedType;
    }
  }

  void _resetForm() {
    _nameCtl.clear();
    _typeCtl.clear();
    selectedDevices.clear();
    selectedFenceList.clear();
    selectedType = "";
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

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
        backgroundColor: isError ? Colors.red.shade400 : Colors.green.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Please wait...'),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'N/A';

    try {
      DateTime date = DateTime.parse(dateString);
      return DateFormat('MMM dd, yyyy HH:mm').format(date);
    } catch (e) {
      return dateString;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nameCtl.dispose();
    _typeCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButton: _buildFAB(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('alerts'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          Text(
            '${alertList.length} alerts',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      actions: [
        if (user != null)
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person, size: 14, color: Colors.blue.shade700),
                  const SizedBox(width: 4),
                  Text(
                    _getCurrentUserName(),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        IconButton(
          onPressed: getAlerts,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading alerts...'),
          ],
        ),
      );
    }

    if (alertList.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () async => getAlerts(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: alertList.length,
        itemBuilder: (context, index) => _buildCleanAlertCard(alertList[index]),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_off_outlined,
              size: 64,
              color: Colors.blue.shade300,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Alerts Yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to create your first alert',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // ✅ CLEAN ALERT CARD DESIGN
  Widget _buildCleanAlertCard(Alert alert) {
    final bool isActive = alert.active.toString() == "1";
    final IconData typeIcon = _getAlertTypeIcon(alert.type ?? "");

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? Colors.green.shade100 : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showAlertDetails(alert),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    typeIcon,
                    color: isActive ? Colors.green.shade600 : Colors.grey.shade500,
                    size: 24,
                  ),
                ),

                const SizedBox(width: 14),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Alert Name
                      Text(
                        alert.name ?? 'Unnamed Alert',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),

                      // Type and Status
                      Row(
                        children: [
                          // Type Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _formatAlertType(alert.type ?? ""),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // Status Indicator
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isActive ? Colors.green : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      // Devices Count
                      Row(
                        children: [
                          Icon(Icons.directions_car, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            '${alert.devices?.length ?? 0} devices',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Actions
                Column(
                  children: [
                    // Switch
                    Transform.scale(
                      scale: 0.85,
                      child: Switch(
                        value: isActive,
                        onChanged: (value) {
                          value ? activateAlert(alert) : removeAlert(alert);
                        },
                        activeColor: Colors.green.shade600,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),

                    // Delete Button
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => deleteAlert(alert.id!),
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.red.shade400,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAlertDetails(Alert alert) {
    final bool isActive = alert.active.toString() == "1";
    final String userName = _getAlertUserName(alert);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Handle Bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
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
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.blue.shade50 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getAlertTypeIcon(alert.type ?? ""),
                          color: isActive ? const Color(0xFF5C8ACF) : Colors.grey,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alert.name ?? 'Alert Details',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            _buildStatusBadge(isActive),
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

                Divider(height: 1, color: Colors.grey.shade200),

                // Content
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Alert Information Section
                      _buildSectionHeader('Alert Information'),
                      const SizedBox(height: 12),
                      _buildDetailCard([
                        _buildDetailItem(Icons.badge_outlined, 'Alert ID', alert.id.toString()),
                        _buildDetailItem(Icons.category_outlined, 'Type', _formatAlertType(alert.type ?? '')),
                        _buildDetailItem(Icons.toggle_on_outlined, 'Status', isActive ? 'Active' : 'Inactive'),
                        if (alert.zone != null)
                          _buildDetailItem(Icons.map_outlined, 'Zone', alert.zone.toString()),
                      ]),

                      const SizedBox(height: 20),

                      // User Information Section
                      _buildSectionHeader('User Information'),
                      const SizedBox(height: 12),
                      _buildDetailCard([
                        _buildDetailItem(Icons.person_outline, 'Created By', userName),
                        _buildDetailItem(Icons.fingerprint, 'User ID', alert.user_id?.toString() ?? 'N/A'),
                      ]),

                      const SizedBox(height: 20),

                      // Devices Section
                      _buildSectionHeader('Devices (${alert.devices?.length ?? 0})'),
                      const SizedBox(height: 12),
                      _buildDevicesCard(alert),

                      // Geofences Section (if applicable)
                      if (_isGeofenceTypeValue(alert.type?.toString() ?? '')) ...[
                        const SizedBox(height: 20),
                        _buildSectionHeader('Geofences (${alert.geofences?.length ?? 0})'),
                        const SizedBox(height: 12),
                        _buildGeofencesCard(alert),
                      ],

                      const SizedBox(height: 20),

                      // Timestamps Section
                      _buildSectionHeader('Timestamps'),
                      const SizedBox(height: 12),
                      _buildDetailCard([
                        _buildDetailItem(Icons.calendar_today_outlined, 'Created At', _formatDate(alert.created_at)),
                        _buildDetailItem(Icons.update_outlined, 'Updated At', _formatDate(alert.updated_at)),
                      ]),

                      const SizedBox(height: 30),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                isActive ? removeAlert(alert) : activateAlert(alert);
                              },
                              icon: Icon(isActive ? Icons.pause : Icons.play_arrow),
                              label: Text(isActive ? 'Deactivate' : 'Activate'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isActive ? Colors.orange : Colors.green,
                                side: BorderSide(color: isActive ? Colors.orange : Colors.green),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                deleteAlert(alert.id);
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildDetailCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF5C8ACF)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesCard(Alert alert) {
    if (alert.devices == null || alert.devices!.isEmpty) {
      return _buildEmptyCard('No devices assigned', Icons.devices);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: alert.devices!.map((device) {
          String deviceName = 'Device';
          if (device is Map) {
            deviceName = device['name'] ?? 'Device #${device['id']}';
          } else {
            var found = devicesList.firstWhereOrNull((d) => d.id.toString() == device.toString());
            deviceName = found?.name ?? 'Device #$device';
          }

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_car, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 6),
                Text(
                  deviceName,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGeofencesCard(Alert alert) {
    if (alert.geofences == null || alert.geofences!.isEmpty) {
      return _buildEmptyCard('No geofences assigned', Icons.fence);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: alert.geofences!.map((fence) {
          String fenceName = 'Geofence';
          if (fence is Map) {
            fenceName = fence['name'] ?? 'Geofence #${fence['id']}';
          } else {
            var found = fenceList.firstWhereOrNull((f) => f.id.toString() == fence.toString());
            fenceName = found?.name ?? 'Geofence #$fence';
          }

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fence, size: 16, color: Colors.green.shade700),
                const SizedBox(width: 6),
                Text(
                  fenceName,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyCard(String message, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  bool _isGeofenceTypeValue(String type) {
    String normalizedType = type.toLowerCase().replaceAll(' ', '_');
    return normalizedType == "geofence_in" ||
        normalizedType == "geofence_out" ||
        normalizedType == "geofence_inout";
  }

  Widget _buildStatusBadge(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isActive ? 'Active' : 'Inactive',
            style: TextStyle(
              fontSize: 11,
              color: isActive ? Colors.green.shade700 : Colors.red.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getAlertTypeIcon(String type) {
    String normalizedType = type.toLowerCase().replaceAll(' ', '_');

    switch (normalizedType) {
      case 'overspeed':
      case 'over_speed':
        return Icons.speed;
      case 'stop_duration':
        return Icons.stop_circle_outlined;
      case 'offline_duration':
        return Icons.wifi_off;
      case 'ignition_duration':
        return Icons.key;
      case 'idle_duration':
        return Icons.timer_outlined;
      case 'geofence_in':
        return Icons.login;
      case 'geofence_out':
        return Icons.logout;
      case 'geofence_inout':
        return Icons.swap_horiz;
      case 'start_of_movement':
        return Icons.play_arrow;
      case 'sos':
        return Icons.sos;
      case 'fuel_fill_theft':
      case 'fuel(fill/theft)':
        return Icons.local_gas_station;
      case 'driver_change_unauthorized':
        return Icons.person_off;
      default:
        return Icons.notifications;
    }
  }

  String _formatAlertType(String type) {
    return type.replaceAll('_', ' ').split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: () => _showAddAlertBottomSheet(),
      backgroundColor: const Color(0xFF5C8ACF),
      icon: const Icon(Icons.add, color: Colors.white),
      label: const Text('Add Alert', style: TextStyle(color: Colors.white)),
    );
  }

  void _showAddAlertBottomSheet() {
    _resetForm();
    _loadDevices();
    _loadFences();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildAddAlertSheet(),
    );
  }

  Widget _buildAddAlertSheet() {
    return StatefulBuilder(
      builder: (context, setSheetState) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle Bar
                  Container(
                    margin: const EdgeInsets.only(top: 12),
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
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.add_alert, color: Color(0xFF5C8ACF)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Create New Alert',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'By: ${_getCurrentUserName()}',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
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
                        // Alert Name
                        _buildSectionTitle('Alert Name *'),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: _nameCtl,
                          hint: 'Enter alert name',
                          icon: Icons.label_outline,
                        ),

                        const SizedBox(height: 24),

                        // Alert Type
                        _buildSectionTitle('Alert Type *'),
                        const SizedBox(height: 12),
                        _buildAlertTypeGrid(setSheetState),

                        // Value Input (for certain types)
                        if (_needsValueInput()) ...[
                          const SizedBox(height: 24),
                          _buildSectionTitle('${_getValueLabel()} *'),
                          const SizedBox(height: 8),
                          _buildTextField(
                            controller: _typeCtl,
                            hint: _getValueHint(),
                            icon: Icons.numbers,
                            keyboardType: TextInputType.number,
                          ),
                        ],

                        // Geofence Selection (for geofence types)
                        if (_isGeofenceType()) ...[
                          const SizedBox(height: 24),
                          _buildSectionTitle('Select Geofences * (${selectedFenceList.length}/${fenceList.length})'),
                          const SizedBox(height: 12),
                          _buildGeofenceSelector(setSheetState),
                        ],

                        const SizedBox(height: 24),

                        // Device Selection
                        _buildSectionTitle('Select Devices * (${selectedDevices.length}/${devicesList.length})'),
                        const SizedBox(height: 12),
                        _buildDeviceList(setSheetState),

                        const SizedBox(height: 100),
                      ],
                    ),
                  ),

                  // Save Button
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: addAlert,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5C8ACF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save),
                              SizedBox(width: 8),
                              Text(
                                'Save Alert',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.grey.shade600),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildAlertTypeGrid(StateSetter setSheetState) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: alertTypes.length,
      itemBuilder: (context, index) {
        final type = alertTypes[index];
        final isSelected = selectedType == type['value'];

        return GestureDetector(
          onTap: () {
            setSheetState(() {
              selectedType = type['value'];
              _typeCtl.clear();
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF5C8ACF) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? const Color(0xFF5C8ACF) : Colors.grey.shade300,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  type['icon'],
                  size: 28,
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    type['name'],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGeofenceSelector(StateSetter setSheetState) {
    if (fenceList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Icon(Icons.fence, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No geofences available',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: fenceList.asMap().entries.map((entry) {
          int idx = entry.key;
          Geofence fence = entry.value;
          final isSelected = selectedFenceList.contains("geofences[]=${fence.id}");

          return Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.fence,
                    color: isSelected ? const Color(0xFF5C8ACF) : Colors.grey,
                    size: 20,
                  ),
                ),
                title: Text(fence.name ?? 'Unnamed Geofence'),
                trailing: Checkbox(
                  value: isSelected,
                  onChanged: (val) {
                    setSheetState(() {
                      if (val!) {
                        selectedFenceList.add("geofences[]=${fence.id}");
                      } else {
                        selectedFenceList.remove("geofences[]=${fence.id}");
                      }
                    });
                  },
                  activeColor: const Color(0xFF5C8ACF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                onTap: () {
                  setSheetState(() {
                    if (isSelected) {
                      selectedFenceList.remove("geofences[]=${fence.id}");
                    } else {
                      selectedFenceList.add("geofences[]=${fence.id}");
                    }
                  });
                },
              ),
              if (idx != fenceList.length - 1)
                Divider(height: 1, color: Colors.grey.shade200),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDeviceList(StateSetter setSheetState) {
    if (devicesList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Icon(Icons.devices, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No devices available',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Select All Header
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.select_all, color: Color(0xFF5C8ACF), size: 20),
            ),
            title: const Text('Select All', style: TextStyle(fontWeight: FontWeight.w600)),
            trailing: Checkbox(
              value: selectedDevices.length == devicesList.length && devicesList.isNotEmpty,
              onChanged: (val) {
                setSheetState(() {
                  if (val!) {
                    selectedDevices.clear();
                    for (var device in devicesList) {
                      selectedDevices.add("devices[]=${device.id}");
                    }
                  } else {
                    selectedDevices.clear();
                  }
                });
              },
              activeColor: const Color(0xFF5C8ACF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onTap: () {
              setSheetState(() {
                if (selectedDevices.length == devicesList.length) {
                  selectedDevices.clear();
                } else {
                  selectedDevices.clear();
                  for (var device in devicesList) {
                    selectedDevices.add("devices[]=${device.id}");
                  }
                }
              });
            },
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          // Device List
          ...devicesList.asMap().entries.map((entry) {
            int idx = entry.key;
            DeviceItem device = entry.value;
            final isSelected = selectedDevices.contains("devices[]=${device.id}");

            return Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.green.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.directions_car,
                      color: isSelected ? Colors.green : Colors.grey,
                      size: 20,
                    ),
                  ),
                  title: Text(device.name ?? 'Unknown Device'),
                  subtitle: Text('ID: ${device.id}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  trailing: Checkbox(
                    value: isSelected,
                    onChanged: (val) {
                      setSheetState(() {
                        if (val!) {
                          selectedDevices.add("devices[]=${device.id}");
                        } else {
                          selectedDevices.remove("devices[]=${device.id}");
                        }
                      });
                    },
                    activeColor: const Color(0xFF5C8ACF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onTap: () {
                    setSheetState(() {
                      if (isSelected) {
                        selectedDevices.remove("devices[]=${device.id}");
                      } else {
                        selectedDevices.add("devices[]=${device.id}");
                      }
                    });
                  },
                ),
                if (idx != devicesList.length - 1)
                  Divider(height: 1, indent: 56, color: Colors.grey.shade200),
              ],
            );
          }),
        ],
      ),
    );
  }

  bool _needsValueInput() {
    return selectedType.isNotEmpty &&
        !_isSimpleType() &&
        !_isGeofenceType();
  }

  bool _isGeofenceType() {
    return selectedType == "geofence_in" ||
        selectedType == "geofence_out" ||
        selectedType == "geofence_inout";
  }

  String _getValueLabel() {
    switch (selectedType) {
      case 'overspeed':
        return 'Speed Limit (km/h)';
      case 'stop_duration':
        return 'Stop Duration (minutes)';
      case 'offline_duration':
        return 'Offline Duration (minutes)';
      case 'ignition_duration':
        return 'Ignition Duration (minutes)';
      case 'idle_duration':
        return 'Idle Duration (minutes)';
      default:
        return 'Value';
    }
  }

  String _getValueHint() {
    switch (selectedType) {
      case 'overspeed':
        return 'Enter speed in km/h (e.g., 80)';
      case 'stop_duration':
        return 'Enter duration in minutes (e.g., 15)';
      case 'offline_duration':
        return 'Enter duration in minutes (e.g., 30)';
      case 'ignition_duration':
        return 'Enter duration in minutes (e.g., 10)';
      case 'idle_duration':
        return 'Enter duration in minutes (e.g., 20)';
      default:
        return 'Enter value';
    }
  }
}