import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gpspro/services/model/alert.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/services/model/user.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/widgets/scale_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../services/model/geofence_model.dart';

class AlertListPage extends StatefulWidget {
  const AlertListPage({super.key});

  @override
  State<StatefulWidget> createState() => _AlertListPageState();
}

class _AlertListPageState extends State<AlertListPage> with SingleTickerProviderStateMixin {
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
  final TextEditingController _deviceSearchCtl = TextEditingController();
  final TextEditingController _geofenceSearchCtl = TextEditingController();
  
  // Search queries
  String deviceSearchQuery = "";
  String geofenceSearchQuery = "";
  String statusFilter = "all";
  String alertSearchQuery = "";
  bool _argsChecked = false;

  // Device filtering for the main screen
  List<String> mainSelectedDevices = [];
  final TextEditingController _mainDeviceFilterCtl = TextEditingController();

  // Pulse animation controller for loading skeleton
  late AnimationController _pulseController;

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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _initController();
    _initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsChecked) {
      _argsChecked = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is int) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _resetForm();
          deviceSearchQuery = "";
          geofenceSearchQuery = "";
          _loadDevices();
          _loadFences();
          
          selectedDevices.clear();
          selectedDevices.add("devices[]=$args");

          setState(() {
            mainSelectedDevices.clear();
            mainSelectedDevices.add(args.toString());
          });

          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => _buildAddAlertSheet(),
          );
        });
      }
    }
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
      
      final email = UserRepository.getEmail();
      final userIdStr = UserRepository.getUserId();
      final name = UserRepository.getName() ?? email ?? 'Unknown User';

      if (userIdStr != null) {
        user = User(
          id: int.tryParse(userIdStr),
          email: email,
          username: name,
        );
      } else {
        final fetchedUser = await APIService.getUserData();
        if (fetchedUser != null) {
          user = fetchedUser;
          if (user!.id != null) {
            UserRepository.setUserId(user!.id.toString());
          }
          if (user!.email != null) {
            UserRepository.setEmail(user!.email!);
          }
          if (user!.username != null) {
            UserRepository.setName(user!.username!);
          }
        }
      }

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
    if (user == null) {
      return UserRepository.getName() ?? UserRepository.getEmail() ?? 'Unknown User';
    }
    if (user!.username != null && user!.username!.isNotEmpty) {
      return user!.username!;
    }
    if (user!.email != null && user!.email!.isNotEmpty) {
      return user!.email!;
    }
    return UserRepository.getName() ?? UserRepository.getEmail() ?? 'Unknown User';
  }

  String _getAlertUserName(Alert alert) {
    if (user != null && alert.user_id != null) {
      if (alert.user_id.toString() == user!.id.toString()) {
        return _getCurrentUserName();
      }
    }
    if (alert.user_id != null) {
      return 'User #${alert.user_id}';
    }
    return 'Unknown User';
  }

  bool _isAlertActive(Alert alert) {
    return alert.active.toString() == "1" ||
        alert.active == true ||
        alert.active.toString().toLowerCase() == "true";
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
            // Sort by ID descending so that newly created alerts show at the top
            alertList.sort((a, b) {
              final aId = int.tryParse(a.id.toString()) ?? 0;
              final bId = int.tryParse(b.id.toString()) ?? 0;
              return bId.compareTo(aId);
            });
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
      'alert_id': alert.id.toString(),
      'active': "0"
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
      'alert_id': alert.id.toString(),
      'active': "1"
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(5),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(5),
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
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
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
    _deviceSearchCtl.clear();
    _geofenceSearchCtl.clear();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        elevation: 5,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                ),
              ),
              const SizedBox(width: 20),
              const Text(
                'Please wait...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
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
    _deviceSearchCtl.dispose();
    _geofenceSearchCtl.dispose();
    _mainDeviceFilterCtl.dispose();
    _pulseController.dispose();
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
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person, size: 14, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 4),
                  Text(
                    _getCurrentUserName(),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  void _toggleQuickAlert(String type, bool turnOn) async {
    // 1. Find if an alert of this type already exists
    Alert? existing = alertList.firstWhereOrNull(
      (a) => a.type.toString().toLowerCase() == type.toLowerCase()
    );

    if (existing != null) {
      // If it exists, call activateAlert or removeAlert
      turnOn ? activateAlert(existing) : removeAlert(existing);
    } else {
      // If it does not exist and we want to turn it ON, we automatically create it!
      if (turnOn) {
        if (devicesList.isEmpty) {
          _showSnackBar('No devices available to assign to this alert', isError: true);
          return;
        }

        _showLoadingDialog();
        
        // Build the query parameters for creating a new alert for all devices by default
        String name = "Instant ${_formatAlertType(type)} Alert";
        
        // Select all device IDs
        List<String> deviceParams = [];
        for (var dev in devicesList) {
          deviceParams.add("devices[]=${dev.id}");
        }
        String devicesStr = deviceParams.join("&");
        
        String request = "";
        if (type == "sos") {
          request = "&name=${Uri.encodeComponent(name)}&type=$type&$devicesStr";
        } else if (type == "overspeed") {
          request = "&name=${Uri.encodeComponent(name)}&type=$type&overspeed=80&$devicesStr";
        } else if (type == "ignition_duration") {
          request = "&name=${Uri.encodeComponent(name)}&type=$type&ignition_duration=5&$devicesStr";
        } else if (type == "offline_duration") {
          request = "&name=${Uri.encodeComponent(name)}&type=$type&offline_duration=30&$devicesStr";
        } else if (type == "start_of_movement") {
          request = "&name=${Uri.encodeComponent(name)}&type=$type&$devicesStr";
        }
        
        APIService.addAlert(request).then((value) {
          if (mounted) {
            Navigator.pop(context);
            if (value.statusCode == 200) {
              _showSnackBar('$name created and activated successfully');
              getAlerts();
            } else {
              try {
                final responseBody = json.decode(value.body);
                String errorMsg = responseBody['message'] ?? 'Failed to create quick alert';
                _showSnackBar(errorMsg, isError: true);
              } catch (e) {
                _showSnackBar('Failed to create quick alert: ${value.statusCode}', isError: true);
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
    }
  }

  Widget _buildStatCards() {
    final deviceFilteredAlerts = alertList.where((alert) {
      if (mainSelectedDevices.isEmpty) return true;
      return alert.devices != null && alert.devices!.any((dev) {
        String devId = "";
        if (dev is Map) {
          devId = (dev['id'] ?? '').toString();
        } else {
          devId = dev.toString();
        }
        return mainSelectedDevices.contains(devId);
      });
    }).toList();

    final total = deviceFilteredAlerts.length;
    final active = deviceFilteredAlerts.where((a) => _isAlertActive(a)).length;
    final inactive = total - active;
    final primaryThemeColor = Theme.of(context).primaryColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              title: 'Total Rules',
              value: total.toString(),
              color: primaryThemeColor,
              icon: Icons.notifications_none_rounded,
              filterType: 'all',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              title: 'Active',
              value: active.toString(),
              color: const Color(0xFF10B981), // Emerald Green
              icon: Icons.check_circle_outline_rounded,
              filterType: 'active',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              title: 'Inactive',
              value: inactive.toString(),
              color: const Color(0xFFF59E0B), // Amber Orange
              icon: Icons.pause_circle_outline_rounded,
              filterType: 'inactive',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    required String filterType,
  }) {
    final bool isSelected = statusFilter == filterType;

    return ScaleButton(
      onTap: () {
        setState(() {
          statusFilter = filterType;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? null : color.withValues(alpha: 0.08),
          gradient: isSelected
              ? LinearGradient(
                  colors: [color, color.withValues(alpha: 0.82)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected 
                  ? color.withValues(alpha: 0.2)
                  : color.withValues(alpha: 0.03),
              blurRadius: isSelected ? 8 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : color,
                  ),
                ),
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? Colors.white : color,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 10.5,
                color: isSelected ? Colors.white.withValues(alpha: 0.9) : color.withValues(alpha: 0.8),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAlertsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Important Quick Alerts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _buildQuickAlertRow(
                title: 'Engine Status',
                subtitle: 'Ignition on/off notification',
                type: 'ignition_duration',
                icon: Icons.key_rounded,
              ),
              const SizedBox(height: 10),
              _buildQuickAlertRow(
                title: 'Over Speed',
                subtitle: 'Limit 80 km/h threshold',
                type: 'overspeed',
                icon: Icons.speed_rounded,
              ),
              const SizedBox(height: 10),
              _buildQuickAlertRow(
                title: 'SOS Alarm',
                subtitle: 'Emergency button triggering',
                type: 'sos',
                icon: Icons.sos_rounded,
              ),
              const SizedBox(height: 10),
              _buildQuickAlertRow(
                title: 'Offline Alert',
                subtitle: 'Disconnect duration 30m',
                type: 'offline_duration',
                icon: Icons.wifi_off_rounded,
              ),
              const SizedBox(height: 10),
              _buildQuickAlertRow(
                title: 'Movement Alert',
                subtitle: 'Start of movement notification',
                type: 'start_of_movement',
                icon: Icons.directions_run_rounded,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getQuickAlertColor(String type) {
    switch (type.toLowerCase()) {
      case 'ignition_duration':
        return const Color(0xFFD97706); // Amber
      case 'overspeed':
        return const Color(0xFFEA580C); // Deep Orange
      case 'sos':
        return const Color(0xFFDC2626); // Red
      case 'offline_duration':
        return const Color(0xFF6366F1); // Indigo
      case 'start_of_movement':
        return const Color(0xFF0D9488); // Teal
      case 'stop_duration':
        return const Color(0xFF8B5CF6); // Purple
      case 'idle_duration':
        return const Color(0xFF3B82F6); // Blue
      case 'geofence_in':
        return const Color(0xFF10B981); // Emerald
      case 'geofence_out':
        return const Color(0xFFEF4444); // Rose/Red
      case 'geofence_inout':
        return const Color(0xFF06B6D4); // Cyan
      case 'fuel_fill_theft':
      case 'fuel(fill/theft)':
        return const Color(0xFF22C55E); // Green
      case 'driver_change_unauthorized':
        return const Color(0xFFEC4899); // Pink
      default:
        return Theme.of(context).primaryColor;
    }
  }

  Gradient? _getQuickAlertGradient(String type, bool isActive) {
    if (!isActive) return null;
    final alertColor = _getQuickAlertColor(type);
    return LinearGradient(
      colors: [
        alertColor,
        alertColor.withValues(alpha: 0.8),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  Widget _buildQuickAlertRow({
    required String title,
    required String subtitle,
    required String type,
    required IconData icon,
  }) {
    final Alert? existing = alertList.firstWhereOrNull(
      (a) => a.type.toString().toLowerCase() == type.toLowerCase()
    );
    final bool isActive = existing != null && _isAlertActive(existing);
    final alertColor = _getQuickAlertColor(type);

    return Container(
      decoration: BoxDecoration(
        color: isActive ? null : Colors.white,
        gradient: _getQuickAlertGradient(type, isActive),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: isActive 
              ? alertColor 
              : alertColor.withValues(alpha: 0.18),
          width: isActive ? 1.5 : 1.0,
        ),
        boxShadow: [
          // 3D Bevel top highlight reflection
          const BoxShadow(
            color: Colors.white,
            blurRadius: 0,
            offset: Offset(0, -1),
          ),
          // Primary drop shadow (casts downward for 3D elevation)
          BoxShadow(
            color: isActive 
                ? alertColor.withValues(alpha: 0.22)
                : alertColor.withValues(alpha: 0.08),
            blurRadius: isActive ? 12 : 8,
            offset: const Offset(0, 4),
          ),
          // Ambient shadow
          BoxShadow(
            color: isActive 
                ? alertColor.withValues(alpha: 0.06)
                : alertColor.withValues(alpha: 0.02),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), // Slim padding
        child: Row(
          children: [
            // Icon Background
            Container(
              padding: const EdgeInsets.all(8), // Compact padding
              decoration: BoxDecoration(
                color: isActive 
                    ? Colors.white.withValues(alpha: 0.25) 
                    : alertColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isActive ? Colors.white : alertColor,
                size: 20, // Slim icon
              ),
            ),
            const SizedBox(width: 12),
            // Text Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isActive ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: isActive ? Colors.white.withValues(alpha: 0.8) : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            // Switch
            Transform.scale(
              scale: 0.8, // Slim switch
              child: Switch(
                value: isActive,
                onChanged: (val) {
                  _toggleQuickAlert(type, val);
                },
                activeColor: Colors.white,
                activeTrackColor: Colors.white.withValues(alpha: 0.45),
                inactiveThumbColor: Colors.grey.shade400,
                inactiveTrackColor: Colors.grey.shade200,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    String displayText = "";
    if (mainSelectedDevices.isNotEmpty) {
      if (mainSelectedDevices.length == 1) {
        String devId = mainSelectedDevices.first;
        var found = devicesList.firstWhereOrNull((d) => d.id.toString() == devId);
        displayText = found?.name ?? 'Device #$devId';
      } else {
        displayText = '${mainSelectedDevices.length} devices selected';
      }
    }
    _mainDeviceFilterCtl.text = displayText;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          readOnly: true,
          controller: _mainDeviceFilterCtl,
          onTap: _showMainDeviceSelectionSheet,
          decoration: InputDecoration(
            hintText: 'Search alert rules...',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
            suffixIcon: mainSelectedDevices.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      setState(() {
                        mainSelectedDevices.clear();
                      });
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ),
    );
  }

  void _showMainDeviceSelectionSheet() {
    String tempSearchQuery = "";
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final filteredDevices = devicesList.where((d) {
            final name = d.name?.toLowerCase() ?? '';
            final id = d.id.toString();
            final query = tempSearchQuery.toLowerCase();
            return name.contains(query) || id.contains(query);
          }).toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.8,
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
                    // Handle bar
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
                              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Icon(Icons.directions_car, color: Theme.of(context).primaryColor),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Select Vehicles',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${mainSelectedDevices.length} selected',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          if (mainSelectedDevices.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                setModalState(() {
                                  mainSelectedDevices.clear();
                                });
                              },
                              child: Text(
                                'Clear',
                                style: TextStyle(color: Colors.red.shade400, fontSize: 13),
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

                    // Search bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: TextField(
                          onChanged: (val) {
                            setModalState(() {
                              tempSearchQuery = val;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search devices...',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                            prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ),

                    // Devices list
                    Expanded(
                      child: filteredDevices.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.directions_car_filled, size: 48, color: Colors.grey.shade300),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No vehicles found',
                                    style: TextStyle(color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            )
                          : ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              children: [
                                // Select All Row
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade200),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Column(
                                    children: [
                                      ListTile(
                                        leading: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Icon(Icons.select_all, color: Theme.of(context).primaryColor, size: 20),
                                        ),
                                        title: const Text('Select All', style: TextStyle(fontWeight: FontWeight.w600)),
                                        trailing: Checkbox(
                                          value: filteredDevices.isNotEmpty &&
                                              filteredDevices.every((d) => mainSelectedDevices.contains(d.id.toString())),
                                          onChanged: (val) {
                                            setModalState(() {
                                              if (val!) {
                                                for (var device in filteredDevices) {
                                                  String item = device.id.toString();
                                                  if (!mainSelectedDevices.contains(item)) {
                                                    mainSelectedDevices.add(item);
                                                  }
                                                }
                                              } else {
                                                for (var device in filteredDevices) {
                                                  mainSelectedDevices.remove(device.id.toString());
                                                }
                                              }
                                            });
                                          },
                                          activeColor: Theme.of(context).primaryColor,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                        ),
                                        onTap: () {
                                          setModalState(() {
                                            bool allSelected = filteredDevices.isNotEmpty &&
                                                filteredDevices.every((d) => mainSelectedDevices.contains(d.id.toString()));

                                            if (allSelected) {
                                              for (var device in filteredDevices) {
                                                mainSelectedDevices.remove(device.id.toString());
                                              }
                                            } else {
                                              for (var device in filteredDevices) {
                                                String item = device.id.toString();
                                                if (!mainSelectedDevices.contains(item)) {
                                                  mainSelectedDevices.add(item);
                                                }
                                              }
                                            }
                                          });
                                        },
                                      ),
                                      const Divider(height: 1),
                                      // Device List
                                      ...filteredDevices.asMap().entries.map((entry) {
                                        int idx = entry.key;
                                        DeviceItem device = entry.value;
                                        final isSelected = mainSelectedDevices.contains(device.id.toString());

                                        return Column(
                                          children: [
                                            ListTile(
                                              leading: Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(5),
                                                ),
                                                child: Icon(
                                                  Icons.directions_car,
                                                  color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
                                                  size: 20,
                                                ),
                                              ),
                                              title: Text(device.name ?? 'Unknown Device'),
                                              subtitle: Text('ID: ${device.id}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                              trailing: Checkbox(
                                                value: isSelected,
                                                onChanged: (val) {
                                                  setModalState(() {
                                                    if (val!) {
                                                      mainSelectedDevices.add(device.id.toString());
                                                    } else {
                                                      mainSelectedDevices.remove(device.id.toString());
                                                    }
                                                  });
                                                },
                                                activeColor: Theme.of(context).primaryColor,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                              ),
                                              onTap: () {
                                                setModalState(() {
                                                  if (isSelected) {
                                                    mainSelectedDevices.remove(device.id.toString());
                                                  } else {
                                                    mainSelectedDevices.add(device.id.toString());
                                                  }
                                                });
                                              },
                                            ),
                                            if (idx != filteredDevices.length - 1)
                                              const Divider(height: 1, indent: 56),
                                          ],
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                    ),

                    // Apply Button
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() {}); // Trigger build to update the main page filter
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Apply Filter',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
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
      ),
    );
  }

  Widget _buildRulesHeader() {
    final primaryThemeColor = Theme.of(context).primaryColor;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'All Alert Rules',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          if (statusFilter != 'all')
            GestureDetector(
              onTap: () {
                setState(() {
                  statusFilter = 'all';
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: primaryThemeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: primaryThemeColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Filter: ${statusFilter.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 11,
                        color: primaryThemeColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.close, size: 12, color: primaryThemeColor),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final filteredAlerts = alertList.where((alert) {
      bool matchesDevice = true;
      if (mainSelectedDevices.isNotEmpty) {
        matchesDevice = alert.devices != null && alert.devices!.any((dev) {
          String devId = "";
          if (dev is Map) {
            devId = (dev['id'] ?? '').toString();
          } else {
            devId = dev.toString();
          }
          return mainSelectedDevices.contains(devId);
        });
      }

      bool matchesStatus = true;
      if (statusFilter == 'active') {
        matchesStatus = _isAlertActive(alert);
      } else if (statusFilter == 'inactive') {
        matchesStatus = !_isAlertActive(alert);
      }

      return matchesDevice && matchesStatus;
    }).toList();

    return RefreshIndicator(
      onRefresh: () async => getAlerts(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // 0. Search Bar
          _buildSearchBar(),

          // 1. Alert Stats Cards
          _buildStatCards(),

          // 2. Quick Alerts Section
          _buildQuickAlertsSection(),

          // 3. Custom Alerts List or Empty state
          _buildRulesHeader(),

          if (isLoading)
            _buildSkeletonLoader()
          else if (filteredAlerts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_off_outlined,
                      size: 48,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    alertList.isEmpty ? 'No Custom Alerts' : 'No matching rules found',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    alertList.isEmpty
                        ? 'Create a custom alert to monitor your vehicles'
                        : 'Try adjusting your search query or status filter',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filteredAlerts.length,
              itemBuilder: (context, index) => _buildCleanAlertCard(filteredAlerts[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Opacity(
          opacity: Tween<double>(begin: 0.35, end: 0.8).evaluate(_pulseController),
          child: child,
        );
      },
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 4,
        itemBuilder: (context, index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.grey.shade200, width: 1.5),
            ),
            child: Row(
              children: [
                // Icon skeleton
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 12),
                // Text skeletons
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 120,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            width: 60,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 30,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Switch/Delete skeleton
                Container(
                  width: 36,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }  // ✅ CLEAN ALERT CARD DESIGN
  Widget _buildCleanAlertCard(Alert alert) {
    final bool isActive = _isAlertActive(alert);
    final IconData typeIcon = _getAlertTypeIcon(alert.type ?? "");
    final alertColor = _getQuickAlertColor(alert.type ?? "");

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isActive ? null : Colors.white,
        gradient: _getQuickAlertGradient(alert.type ?? "", isActive),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: isActive ? alertColor.withValues(alpha: 0.6) : alertColor.withValues(alpha: 0.18),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isActive ? alertColor.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () => _showAlertDetails(alert),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.white.withValues(alpha: 0.25) : alertColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(
                    typeIcon,
                    color: isActive ? Colors.white : alertColor,
                    size: 18,
                  ),
                ),

                const SizedBox(width: 10),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Alert Name
                      Text(
                        alert.name ?? 'Unnamed Alert',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: isActive ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),

                      // Type and Status
                      Row(
                        children: [
                          // Type Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isActive ? Colors.white.withValues(alpha: 0.2) : alertColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _formatAlertType(alert.type ?? ""),
                              style: TextStyle(
                                fontSize: 9,
                                color: isActive ? Colors.white : alertColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // Status Indicator
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: isActive ? Colors.white : alertColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                              fontSize: 10,
                              color: isActive ? Colors.white.withValues(alpha: 0.9) : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 3),

                      // Devices Count
                      Row(
                        children: [
                          Icon(
                            Icons.directions_car, 
                            size: 11, 
                            color: isActive ? Colors.white.withValues(alpha: 0.8) : Colors.grey.shade500
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${alert.devices?.length ?? 0} devices',
                            style: TextStyle(
                              fontSize: 10,
                              color: isActive ? Colors.white.withValues(alpha: 0.8) : Colors.grey.shade600,
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Switch
                    Transform.scale(
                      scale: 0.75,
                      child: Switch(
                        value: isActive,
                        onChanged: (value) {
                          value ? activateAlert(alert) : removeAlert(alert);
                        },
                        activeThumbColor: Colors.white,
                        activeTrackColor: Colors.white.withValues(alpha: 0.45),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),

                    // Delete Button
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => deleteAlert(alert.id!),
                      icon: Icon(
                        Icons.delete_outline,
                        color: isActive ? Colors.white.withValues(alpha: 0.8) : Colors.grey.shade400,
                        size: 18,
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
    final bool isActive = _isAlertActive(alert);
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
                          color: isActive ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Icon(
                          _getAlertTypeIcon(alert.type ?? ""),
                          color: isActive ? Theme.of(context).primaryColor : Colors.grey,
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
                                foregroundColor: isActive ? Colors.orange : Theme.of(context).primaryColor,
                                side: BorderSide(color: isActive ? Colors.orange : Theme.of(context).primaryColor),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5),
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
                                  borderRadius: BorderRadius.circular(5),
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
        borderRadius: BorderRadius.circular(5),
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
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(icon, size: 18, color: Theme.of(context).primaryColor),
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
        borderRadius: BorderRadius.circular(5),
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

          final primaryThemeColor = Theme.of(context).primaryColor;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: primaryThemeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_car, size: 16, color: primaryThemeColor),
                const SizedBox(width: 6),
                Text(
                  deviceName,
                  style: TextStyle(
                    fontSize: 13,
                    color: primaryThemeColor,
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
        borderRadius: BorderRadius.circular(5),
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

          final primaryThemeColor = Theme.of(context).primaryColor;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: primaryThemeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fence, size: 16, color: primaryThemeColor),
                const SizedBox(width: 6),
                Text(
                  fenceName,
                  style: TextStyle(
                    fontSize: 13,
                    color: primaryThemeColor,
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
        borderRadius: BorderRadius.circular(5),
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
    final primaryThemeColor = Theme.of(context).primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? primaryThemeColor.withValues(alpha: 0.1) : Colors.red.shade50,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? primaryThemeColor : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isActive ? 'Active' : 'Inactive',
            style: TextStyle(
              fontSize: 11,
              color: isActive ? primaryThemeColor : Colors.red.shade700,
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
        return Icons.directions_run_rounded;
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
    return SizedBox(
      height: 38,
      child: FloatingActionButton.extended(
        onPressed: () => _showAddAlertBottomSheet(),
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
        ),
        icon: const Icon(Icons.add, color: Colors.white, size: 18),
        label: const Text(
          'ADD ALERT',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  void _showAddAlertBottomSheet() {
    _resetForm();
    deviceSearchQuery = "";
    geofenceSearchQuery = "";
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
                            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Icon(Icons.add_alert, color: Theme.of(context).primaryColor),
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
                          color: Colors.black.withValues(alpha: 0.05),
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
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
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
        borderRadius: BorderRadius.circular(5),
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
              color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade300,
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
          borderRadius: BorderRadius.circular(5),
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

    final filteredFences = fenceList.where((f) {
      final name = f.name?.toLowerCase() ?? '';
      final id = f.id.toString();
      final query = geofenceSearchQuery.toLowerCase();
      return name.contains(query) || id.contains(query);
    }).toList();

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _geofenceSearchCtl,
            onChanged: (val) {
              setSheetState(() {
                geofenceSearchQuery = val;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search geofences...',
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: geofenceSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        setSheetState(() {
                          _geofenceSearchCtl.clear();
                          geofenceSearchQuery = "";
                        });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Column(
            children: [
              if (filteredFences.isNotEmpty) ...[
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(Icons.select_all, color: Theme.of(context).primaryColor, size: 20),
                  ),
                  title: const Text('Select All', style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: Checkbox(
                    value: filteredFences.isNotEmpty &&
                        filteredFences.every((f) => selectedFenceList.contains("geofences[]=${f.id}")),
                    onChanged: (val) {
                      setSheetState(() {
                        if (val!) {
                          for (var fence in filteredFences) {
                            String item = "geofences[]=${fence.id}";
                            if (!selectedFenceList.contains(item)) {
                              selectedFenceList.add(item);
                            }
                          }
                        } else {
                          for (var fence in filteredFences) {
                            selectedFenceList.remove("geofences[]=${fence.id}");
                          }
                        }
                      });
                    },
                    activeColor: Theme.of(context).primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onTap: () {
                    setSheetState(() {
                      bool allSelected = filteredFences.isNotEmpty &&
                          filteredFences.every((f) => selectedFenceList.contains("geofences[]=${f.id}"));

                      if (allSelected) {
                        for (var fence in filteredFences) {
                          selectedFenceList.remove("geofences[]=${fence.id}");
                        }
                      } else {
                        for (var fence in filteredFences) {
                          String item = "geofences[]=${fence.id}";
                          if (!selectedFenceList.contains(item)) {
                            selectedFenceList.add(item);
                          }
                        }
                      }
                    });
                  },
                ),
                Divider(height: 1, color: Colors.grey.shade200),
              ],
              ...filteredFences.asMap().entries.map((entry) {
                int idx = entry.key;
                Geofence fence = entry.value;
                final isSelected = selectedFenceList.contains("geofences[]=${fence.id}");

                return Column(
                  children: [
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Icon(
                          Icons.fence,
                          color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
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
                        activeColor: Theme.of(context).primaryColor,
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
                    if (idx != filteredFences.length - 1)
                      Divider(height: 1, color: Colors.grey.shade200),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceList(StateSetter setSheetState) {
    if (devicesList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(5),
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

    final filteredDevices = devicesList.where((d) {
      final name = d.name?.toLowerCase() ?? '';
      final id = d.id.toString();
      final query = deviceSearchQuery.toLowerCase();
      return name.contains(query) || id.contains(query);
    }).toList();

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _deviceSearchCtl,
            onChanged: (val) {
              setSheetState(() {
                deviceSearchQuery = val;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search devices...',
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: deviceSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        setSheetState(() {
                          _deviceSearchCtl.clear();
                          deviceSearchQuery = "";
                        });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Column(
            children: [
              // Select All Header
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(Icons.select_all, color: Theme.of(context).primaryColor, size: 20),
                ),
                title: const Text('Select All', style: TextStyle(fontWeight: FontWeight.w600)),
                trailing: Checkbox(
                  value: filteredDevices.isNotEmpty &&
                      filteredDevices.every((d) => selectedDevices.contains("devices[]=${d.id}")),
                  onChanged: (val) {
                    setSheetState(() {
                      if (val!) {
                        for (var device in filteredDevices) {
                          String item = "devices[]=${device.id}";
                          if (!selectedDevices.contains(item)) {
                            selectedDevices.add(item);
                          }
                        }
                      } else {
                        for (var device in filteredDevices) {
                          selectedDevices.remove("devices[]=${device.id}");
                        }
                      }
                    });
                  },
                  activeColor: Theme.of(context).primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                onTap: () {
                  setSheetState(() {
                    bool allSelected = filteredDevices.isNotEmpty &&
                        filteredDevices.every((d) => selectedDevices.contains("devices[]=${d.id}"));

                    if (allSelected) {
                      for (var device in filteredDevices) {
                        selectedDevices.remove("devices[]=${device.id}");
                      }
                    } else {
                      for (var device in filteredDevices) {
                        String item = "devices[]=${device.id}";
                        if (!selectedDevices.contains(item)) {
                          selectedDevices.add(item);
                        }
                      }
                    }
                  });
                },
              ),
              Divider(height: 1, color: Colors.grey.shade200),
              // Device List
              ...filteredDevices.asMap().entries.map((entry) {
                int idx = entry.key;
                DeviceItem device = entry.value;
                final isSelected = selectedDevices.contains("devices[]=${device.id}");

                return Column(
                  children: [
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Icon(
                          Icons.directions_car,
                          color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
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
                        activeColor: Theme.of(context).primaryColor,
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
                    if (idx != filteredDevices.length - 1)
                      Divider(height: 1, indent: 56, color: Colors.grey.shade200),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
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

