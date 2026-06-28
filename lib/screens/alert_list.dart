import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smart_lock/services/model/alert.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
import 'package:smart_lock/services/model/user.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../services/model/geofence_model.dart';

class AlertListPage extends StatefulWidget {
  const AlertListPage({super.key});

  @override
  State<StatefulWidget> createState() => _AlertListPageState();
}

class _AlertListPageState extends State<AlertListPage> {
  // ✅ RED COLOR SCHEME
  static const Color _primaryRed = Color(0xFFC0392B);
  static const Color _lightRed = Color(0xFFE74C3C);
  static const Color _greyText = Color(0xFF6B7280);
  static const Color _darkText = Color(0xFF1F2937);

  Timer? _timer;
  SharedPreferences? prefs;
  User? user;
  bool isLoading = false;
  List<Alert> alertList = [];
  List<DeviceItem> devicesList = [];
  List<Geofence> fenceList = [];

  late DataController dataController;
  StreamSubscription? _devicesSubscription;
  bool _hasFetchedAlerts = false;
  bool _isAutoChecking = false;

  // Add Alert Variables
  List<String> selectedDevices = [];
  List<String> selectedFenceList = [];
  String selectedType = "";
  final TextEditingController _nameCtl = TextEditingController();
  final TextEditingController _typeCtl = TextEditingController();

  // Alert Types Configuration
  final List<Map<String, dynamic>> alertTypes = [
    {"name": "Over Speed", "icon": Icons.speed, "value": "overspeed"},
    {
      "name": "Stop Duration",
      "icon": Icons.stop_circle_outlined,
      "value": "stop_duration"
    },
    {"name": "Offline", "icon": Icons.wifi_off, "value": "offline_duration"},
    {"name": "Ignition", "icon": Icons.key, "value": "ignition_duration"},
    {"name": "Idle", "icon": Icons.timer_outlined, "value": "idle_duration"},
    {"name": "Geofence In", "icon": Icons.login, "value": "geofence_in"},
    {"name": "Geofence Out", "icon": Icons.logout, "value": "geofence_out"},
    {"name": "In/Out", "icon": Icons.swap_horiz, "value": "geofence_inout"},
    {
      "name": "Movement",
      "icon": Icons.play_arrow,
      "value": "start_of_movement"
    },
    {"name": "SOS", "icon": Icons.sos, "value": "sos"},
    {
      "name": "Fuel",
      "icon": Icons.local_gas_station,
      "value": "fuel_fill_theft"
    },
    {
      "name": "Driver",
      "icon": Icons.person_off,
      "value": "driver_change_unauthorized"
    },
  ];

  @override
  void initState() {
    super.initState();
    _initController();
    _initialize();
    
    _devicesSubscription = dataController.onlyDevices.listen((devices) {
      if (mounted) {
        setState(() {
          devicesList = devices;
        });
        _autoCreateDefaultAlertsIfNeeded();
      }
    });
  }

  Future<void> _initialize() async {
    _loadDevices();
    await getUser();
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
      
      // Force default to ON (true) for local-only idle and offline alerts on first run of this version
      if (prefs?.getBool('local_defaults_set_v3') != true) {
        await prefs?.setBool('auto_alert_idle', true);
        await prefs?.setBool('auto_alert_offline', true);
        await prefs?.setBool('local_defaults_set_v3', true);
      }
      
      String? userJson = prefs?.getString("user");

      if (userJson == null || userJson.isEmpty) {
        await getAlerts();
        return;
      }

      final parsed = json.decode(userJson);
      if (parsed == null) {
        await getAlerts();
        return;
      }

      user = User.fromJson(parsed);
      await getAlerts();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Error getting user: $e");
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

  Future<void> getAlerts() async {
    if (!mounted) return;

    setState(() => isLoading = true);

    try {
      final value = await APIService.getAlertList();

      if (mounted) {
        setState(() {
          isLoading = false;
          _hasFetchedAlerts = true;
          if (value != null) {
            alertList.clear();
            alertList.addAll(value);
          }
        });
        _syncPrefsWithServerState();
        _autoCreateDefaultAlertsIfNeeded();
      }
    } catch (e) {
      debugPrint("Error getting alerts: $e");
      if (mounted) {
        setState(() => isLoading = false);
        _showSnackBar('Failed to load alerts', isError: true);
      }
    }
  }

  Future<void> _syncPrefsWithServerState() async {
    final activePrefs = prefs ?? await SharedPreferences.getInstance();
    
    bool isEngineActive = false;
    final List<String> activeTypes = [];
    
    for (var a in alertList) {
      final t = a.type?.toLowerCase();
      final active = a.active.toString() == "1";
      if (t == 'ignition_duration' || t == 'ignition') {
        isEngineActive = active;
      }
      if (active && t != null) {
        activeTypes.add(t);
      }
    }
    
    await activePrefs.setBool('auto_alert_engine', isEngineActive);
    await activePrefs.setStringList('active_server_alerts', activeTypes);
  }

  Future<void> _autoCreateDefaultAlertsIfNeeded() async {
    if (!_hasFetchedAlerts) return;
    if (_isAutoChecking) return;
    _isAutoChecking = true;
    
    try {
      final List<String> requiredKeys = ['engine'];
      bool changedAny = false;
      
      for (final key in requiredKeys) {
        final String targetType = 'ignition_duration';
                
        Alert? existing;
        for (var a in alertList) {
          final t = a.type?.toLowerCase();
          final bool isMatch = (t == 'ignition_duration' || t == 'ignition');
          if (isMatch) {
            existing = a;
            break;
          }
        }
        
        if (existing == null) {
          if (devicesList.isEmpty) continue;
          
          final String nameVal = 'Engine ON / OFF';
          final String name = Uri.encodeComponent(nameVal);
          final String devices = devicesList.map((d) => 'devices[]=${d.id}').join('&');
          final String paramVal = '0';
          
          final String request = '&name=$name&type=$targetType&$targetType=$paramVal&$devices&notifications[sound]=1&notifications[push]=1&notifications[mobile]=1';
          
          try {
            final resp = await APIService.addAlert(request);
            if (resp.statusCode == 200) {
              changedAny = true;
              final activePrefs = prefs ?? await SharedPreferences.getInstance();
              await activePrefs.setBool('auto_alert_$key', true);
            } else {
              debugPrint("Failed to create alert $key: ${resp.statusCode} - ${resp.body}");
            }
          } catch (e) {
            debugPrint("Auto-create default alert error: $e");
          }
        } else if (existing.active.toString() != "1") {
          // If it exists but is inactive, automatically activate it!
          Map<String, String> requestBody = {
            'id': existing.id.toString(),
            'active': "true"
          };
          try {
            final resp = await APIService.activateAlert(requestBody);
            if (resp.statusCode == 200) {
              changedAny = true;
              final activePrefs = prefs ?? await SharedPreferences.getInstance();
              await activePrefs.setBool('auto_alert_$key', true);
            }
          } catch (e) {
            debugPrint("Auto-activate default alert error: $e");
          }
        }
      }
      
      if (changedAny && mounted) {
        try {
          final value = await APIService.getAlertList();
          if (value != null && mounted) {
            setState(() {
              alertList.clear();
              alertList.addAll(value);
            });
            _syncPrefsWithServerState();
          }
        } catch (_) {}
      }
    } finally {
      _isAutoChecking = false;
    }
  }

  void activateAlert(Alert alert) {
    Map<String, String> requestBody = {
      'id': alert.id.toString(),
      'active': "true"
    };

    APIService.activateAlert(requestBody).then((value) {
      if (mounted && value.statusCode == 200) {
        _showSnackBar('Alert activated');

        // SinoTrack overspeed hardware enable
        if (alert.type == 'overspeed' && alert.devices != null) {
          String speedVal = '80'; // Fallback speed limit
          if (alert.overspeed != null &&
              alert.overspeed.toString().trim().isNotEmpty) {
            speedVal = alert.overspeed.toString().trim();
          } else if (alert.name != null) {
            final match = RegExp(r'\d+').firstMatch(alert.name!);
            if (match != null) {
              speedVal = match.group(0)!;
            }
          }
          final formattedSpeed = speedVal.padLeft(3, '0');
          for (var device in alert.devices!) {
            String? devId;
            if (device is Map) {
              devId = device['id']?.toString();
            } else {
              devId = device.toString();
            }
            if (devId != null) {
              final Map<String, String> commandBody = {
                'device_id': devId,
                'type': 'gprs',
                'command': '1220000 $formattedSpeed',
              };
              APIService.sendCommands(commandBody).catchError((e) {});
            }
          }
        }

        getAlerts();
      } else {
        _showSnackBar('Failed to activate', isError: true);
      }
    }).catchError((e) {
      _showSnackBar('Error: $e', isError: true);
    });
  }

  void removeAlert(Alert alert) {
    Map<String, String> requestBody = {
      'id': alert.id.toString(),
      'active': "false"
    };

    APIService.activateAlert(requestBody).then((value) {
      if (mounted && value.statusCode == 200) {
        _showSnackBar('Alert deactivated');

        // SinoTrack overspeed hardware disable
        if (alert.type == 'overspeed' && alert.devices != null) {
          for (var device in alert.devices!) {
            String? devId;
            if (device is Map) {
              devId = device['id']?.toString();
            } else {
              devId = device.toString();
            }
            if (devId != null) {
              final Map<String, String> commandBody = {
                'device_id': devId,
                'type': 'gprs',
                'command': '1220000 0',
              };
              APIService.sendCommands(commandBody).catchError((e) {});
            }
          }
        }

        getAlerts();
      } else {
        _showSnackBar('Failed to deactivate', isError: true);
      }
    }).catchError((e) {
      _showSnackBar('Error: $e', isError: true);
    });
  }

  void deleteAlert(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Alert?', style: TextStyle(fontSize: 18)),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: _greyText)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performDelete(id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryRed,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _performDelete(int id) {
    final Alert? alert = alertList.firstWhereOrNull((a) => a.id == id);
    APIService.destroyAlert(id).then((value) {
      if (mounted) {
        _showSnackBar('Alert deleted');

        // SinoTrack overspeed hardware disable
        if (alert != null &&
            alert.type == 'overspeed' &&
            alert.devices != null) {
          for (var device in alert.devices!) {
            String? devId;
            if (device is Map) {
              devId = device['id']?.toString();
            } else {
              devId = device.toString();
            }
            if (devId != null) {
              final Map<String, String> commandBody = {
                'device_id': devId,
                'type': 'gprs',
                'command': '1220000 0',
              };
              APIService.sendCommands(commandBody).catchError((e) {});
            }
          }
        }

        getAlerts();
      }
    }).catchError((e) {
      if (mounted) {
        _showSnackBar('Failed to delete', isError: true);
      }
    });
  }

  void _showValidationError(List<String> errors) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.orange.shade600, size: 24),
            const SizedBox(width: 12),
            const Text('Required Fields', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...errors.map((error) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 6, color: _primaryRed),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(error,
                              style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryRed,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void addAlert() {
    List<String> errors = [];

    if (_nameCtl.text.trim().isEmpty) errors.add('Alert Name is required');
    if (selectedType.isEmpty) errors.add('Alert Type must be selected');
    if (selectedDevices.isEmpty)
      errors.add('At least one Device must be selected');
    if (_needsValueInput() && _typeCtl.text.trim().isEmpty) {
      errors.add('${_getValueLabel()} is required');
    }
    if (_isGeofenceType() && selectedFenceList.isEmpty) {
      errors.add('At least one Geofence must be selected');
    }

    if (errors.isNotEmpty) {
      _showValidationError(errors);
      return;
    }

    Navigator.pop(context);

    String request = _buildAlertRequest();

    APIService.addAlert(request).then((value) {
      if (mounted) {
        if (value.statusCode == 200) {
          _showSnackBar('Alert created successfully');

          // SinoTrack overspeed hardware enable
          if (selectedType == 'overspeed') {
            final speedVal = _typeCtl.text.trim();
            final formattedSpeed = speedVal.padLeft(3, '0');
            for (var deviceStr in selectedDevices) {
              final idStr = deviceStr.replaceAll('devices[]=', '');
              final Map<String, String> commandBody = {
                'device_id': idStr,
                'type': 'gprs',
                'command': '1220000 $formattedSpeed',
              };
              APIService.sendCommands(commandBody).catchError((e) {
                debugPrint("Overspeed GPRS command error: $e");
              });
            }
          }

          _resetForm();
          getAlerts();
        } else {
          _showSnackBar('Failed to create alert', isError: true);
        }
      }
    }).catchError((e) {
      if (mounted) {
        _showSnackBar('Error: $e', isError: true);
      }
    });
  }

  String _buildAlertRequest() {
    String name = Uri.encodeComponent(_nameCtl.text.trim());
    String type = selectedType;
    String devices = selectedDevices.join("&");
    
    // Always enable push and sound notifications on the server for the alert
    const notifParams = "&notifications[sound]=1&notifications[push]=1&notifications[mobile]=1";

    if (_isSimpleType()) {
      return "&name=$name&type=$type&$devices$notifParams";
    }

    if (_isGeofenceType()) {
      String geofences = selectedFenceList.join("&");
      int zoneVal = (type == 'geofence_out') ? 2 : 1;
      return "&name=$name&type=$type&zone=$zoneVal&$geofences&$devices$notifParams";
    }

    String value = Uri.encodeComponent(_typeCtl.text.trim());
    String paramName = _getParameterName();
    return "&name=$name&type=$type&$paramName=$value&$devices$notifParams";
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
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
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
    _devicesSubscription?.cancel();
    _nameCtl.dispose();
    _typeCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButton: _buildFAB(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: _primaryRed,
      foregroundColor: Colors.white,
      centerTitle: true,
      title: const Text(
        'Alerts',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
      ),
      actions: [
        IconButton(
          onPressed: getAlerts,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  // Built-in auto-tracking alerts (always active, can't be deleted)
  static const List<Map<String, dynamic>> _autoAlerts = [
    {'icon': Icons.key, 'label': 'Engine ON / OFF', 'desc': 'Auto-detect ignition changes', 'key': 'engine'},
    {'icon': Icons.timer_outlined, 'label': 'Idle Detection', 'desc': 'Engine ON — speed ≤ 1 km/h', 'key': 'idle'},
    {'icon': Icons.wifi_off, 'label': 'Offline / Online', 'desc': 'Connection lost or restored', 'key': 'offline'},
  ];

  Widget _buildBody() {
    if (isLoading) {
      return Center(
        child: CircularProgressIndicator(color: _primaryRed),
      );
    }

    final filteredCustomAlerts = alertList.where((alert) {
      final t = alert.type?.toLowerCase() ?? '';
      return t != 'ignition_duration' && t != 'idle_duration' && t != 'offline_duration' &&
             t != 'ignition' && t != 'idle' && t != 'offline';
    }).toList();

    return RefreshIndicator(
      onRefresh: () async => getAlerts(),
      color: _primaryRed,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          // ── Auto Alerts Section ─────────────────────────────────────────
          _buildSectionHeader('Auto Tracking', Icons.auto_awesome, _primaryRed),
          const SizedBox(height: 6),
          ..._autoAlerts.map((a) => _buildAutoAlertCard(
                icon: a['icon'] as IconData,
                label: a['label'] as String,
                desc: a['desc'] as String,
                alertKey: a['key'] as String,
              )),
          const SizedBox(height: 10),

          // ── Server Alerts Section ───────────────────────────────────────
          if (filteredCustomAlerts.isNotEmpty) ...[
            _buildSectionHeader('Custom Alerts', Icons.notification_add, _primaryRed),
            const SizedBox(height: 6),
            ...filteredCustomAlerts.map((alert) => _buildAlertCard(alert)),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: color.withValues(alpha: 0.2), height: 1)),
      ],
    );
  }

  void toggleAutoAlert(String alertKey, bool turnOn) async {
    final activePrefs = prefs ?? await SharedPreferences.getInstance();

    if (alertKey == 'idle' || alertKey == 'offline') {
      await activePrefs.setBool('auto_alert_$alertKey', turnOn);
      setState(() {});
      _showSnackBar(turnOn ? 'Alert activated' : 'Alert deactivated');
      return;
    }

    setState(() => isLoading = true);
    
    final String targetType = 'ignition_duration';
            
    Alert? existing;
    for (var a in alertList) {
      final t = a.type?.toLowerCase();
      final bool isMatch = (t == 'ignition_duration' || t == 'ignition');
      if (isMatch) {
        existing = a;
        break;
      }
    }
        
    if (existing != null) {
      // Toggle existing alert on the server
      Map<String, String> requestBody = {
        'id': existing.id.toString(),
        'active': turnOn ? "true" : "false"
      };
      try {
        final resp = await APIService.activateAlert(requestBody);
        if (resp.statusCode == 200) {
          _showSnackBar(turnOn ? 'Alert activated' : 'Alert deactivated');
          await activePrefs.setBool('auto_alert_$alertKey', turnOn);
        } else {
          _showSnackBar('Failed to update alert', isError: true);
        }
      } catch (e) {
        _showSnackBar('Error: $e', isError: true);
      }
      await getAlerts();
    } else {
      if (turnOn) {
        // Create new alert on the server
        if (devicesList.isEmpty) {
          setState(() => isLoading = false);
          _showSnackBar('No devices available to assign alert', isError: true);
          return;
        }
        
        final String nameVal = 'Engine ON / OFF';
        final String name = Uri.encodeComponent(nameVal);
        final String devices = devicesList.map((d) => 'devices[]=${d.id}').join('&');
        final String paramVal = '0';
        final String request = '&name=$name&type=$targetType&$targetType=$paramVal&$devices&notifications[sound]=1&notifications[push]=1&notifications[mobile]=1';
        
        try {
          final resp = await APIService.addAlert(request);
          if (resp.statusCode == 200) {
            _showSnackBar('Alert created successfully');
            await activePrefs.setBool('auto_alert_$alertKey', turnOn);
          } else {
            _showSnackBar('Failed to create alert', isError: true);
          }
        } catch (e) {
          _showSnackBar('Error: $e', isError: true);
        }
        await getAlerts();
      } else {
        setState(() => isLoading = false);
      }
    }
  }

  Widget _buildAutoAlertCard({
    required IconData icon,
    required String label,
    required String desc,
    required String alertKey,
  }) {
    bool isEnabled = false;

    if (alertKey == 'idle' || alertKey == 'offline') {
      isEnabled = prefs?.getBool('auto_alert_$alertKey') ?? true;
    } else {
      Alert? existing;
      for (var a in alertList) {
        final t = a.type?.toLowerCase();
        final bool isMatch = (t == 'ignition_duration' || t == 'ignition');
        if (isMatch) {
          existing = a;
          break;
        }
      }
      isEnabled = existing != null && existing.active.toString() == "1";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _primaryRed.withValues(alpha: 0.15), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _primaryRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: _primaryRed, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
                  ),
                  Text(
                    desc,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _primaryRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'AUTO',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: _primaryRed, letterSpacing: 0.5),
              ),
            ),
            const SizedBox(width: 4),
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: isEnabled,
                activeColor: _primaryRed,
                activeTrackColor: _primaryRed.withValues(alpha: 0.2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (bool value) {
                  toggleAutoAlert(alertKey, value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: _primaryRed.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_off_outlined,
              size: 60,
              color: _primaryRed.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Alerts Yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first alert',
            style: TextStyle(color: _greyText),
          ),
        ],
      ),
    );
  }

  String? _getAlertParamDetail(Alert alert) {
    if (alert.type == 'overspeed') {
      final value = alert.overspeed ?? _parseValFromName(alert.name);
      return value != null ? '$value km/h' : null;
    }
    if (alert.type == 'stop_duration') {
      final value = alert.stop_duration ?? _parseValFromName(alert.name);
      return value != null ? '$value min' : null;
    }
    if (alert.type == 'offline_duration') {
      final value = alert.offline_duration ?? _parseValFromName(alert.name);
      return value != null ? '$value min' : null;
    }
    if (alert.type == 'ignition_duration') {
      final value = alert.ignition_duration ?? _parseValFromName(alert.name);
      return value != null ? '$value min' : null;
    }
    if (alert.type == 'idle_duration') {
      final value = alert.idle_duration ?? _parseValFromName(alert.name);
      return value != null ? '$value min' : null;
    }
    return null;
  }

  String? _parseValFromName(String? name) {
    if (name == null) return null;
    final match = RegExp(r'\d+').firstMatch(name);
    return match?.group(0);
  }

  Widget _buildAlertCard(Alert alert) {
    final bool isActive = alert.active.toString() == "1";

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isActive
                    ? _primaryRed.withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getAlertTypeIcon(alert.type ?? ""),
                color: isActive ? _primaryRed : _greyText,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.name ?? 'Unnamed Alert',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _primaryRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          _formatAlertType(alert.type ?? ""),
                          style: TextStyle(
                            fontSize: 9,
                            color: _primaryRed,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_getAlertParamDetail(alert) != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          _getAlertParamDetail(alert)!,
                          style: TextStyle(fontSize: 10, color: _greyText),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Icon(Icons.directions_car, size: 11, color: _greyText),
                      const SizedBox(width: 2),
                      Text(
                        '${alert.devices?.length ?? 0}',
                        style: TextStyle(fontSize: 10, color: _greyText),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    value: isActive,
                    onChanged: (value) {
                      value ? activateAlert(alert) : removeAlert(alert);
                    },
                    activeColor: _primaryRed,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                GestureDetector(
                  onTap: () => deleteAlert(alert.id!),
                  child: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 18),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ],
        ),
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
      backgroundColor: _primaryRed,
      icon: const Icon(Icons.add, color: Colors.white),
      label: const Text('Add Alert',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle Bar
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
                          child: Icon(Icons.add_alert, color: _primaryRed),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'Create Alert',
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

                  // Content
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Alert Name
                        const Text('Alert Name *',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: _nameCtl,
                          hint: 'Enter alert name',
                          icon: Icons.label_outline,
                        ),

                        const SizedBox(height: 20),

                        // Alert Type
                        const Text('Alert Type *',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        _buildAlertTypeGrid(setSheetState),

                        // Value Input
                        if (_needsValueInput()) ...[
                          const SizedBox(height: 20),
                          Text('${_getValueLabel()} *',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          _buildTextField(
                            controller: _typeCtl,
                            hint: _getValueHint(),
                            icon: Icons.numbers,
                            keyboardType: TextInputType.number,
                          ),
                        ],

                        // Geofence Selection
                        if (_isGeofenceType()) ...[
                          const SizedBox(height: 20),
                          Text('Geofences * (${selectedFenceList.length})',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          _buildGeofenceSelector(setSheetState),
                        ],

                        const SizedBox(height: 20),

                        // Device Selection
                        Text('Devices * (${selectedDevices.length})',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        _buildDeviceList(setSheetState),

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
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: addAlert,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryRed,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text('Save Alert',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: _greyText),
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
    );
  }

  Widget _buildAlertTypeGrid(StateSetter setSheetState) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
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
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? _primaryRed : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? _primaryRed : Colors.grey.shade300,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  type['icon'],
                  size: 26,
                  color: isSelected ? Colors.white : _greyText,
                ),
                const SizedBox(height: 6),
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
                      color: isSelected ? Colors.white : _darkText,
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text('No geofences available',
              style: TextStyle(color: _greyText)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: fenceList.map((fence) {
          final isSelected =
              selectedFenceList.contains("geofences[]=${fence.id}");

          return ListTile(
            leading: Icon(Icons.fence,
                color: isSelected ? _primaryRed : _greyText, size: 20),
            title: Text(fence.name ?? 'Unnamed Geofence',
                style: const TextStyle(fontSize: 14)),
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
              activeColor: _primaryRed,
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
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDeviceList(StateSetter setSheetState) {
    if (devicesList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child:
              Text('No devices available', style: TextStyle(color: _greyText)),
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
          // Select All
          ListTile(
            leading: const Icon(Icons.select_all, size: 20),
            title: const Text('Select All',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            trailing: Checkbox(
              value: selectedDevices.length == devicesList.length &&
                  devicesList.isNotEmpty,
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
              activeColor: _primaryRed,
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
          const Divider(height: 1),
          ...devicesList.map((device) {
            final isSelected =
                selectedDevices.contains("devices[]=${device.id}");

            return ListTile(
              leading: Icon(Icons.directions_car,
                  color: isSelected ? _primaryRed : _greyText, size: 20),
              title: Text(device.name ?? 'Unknown',
                  style: const TextStyle(fontSize: 14)),
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
                activeColor: _primaryRed,
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
            );
          }),
        ],
      ),
    );
  }

  bool _needsValueInput() {
    return selectedType.isNotEmpty && !_isSimpleType() && !_isGeofenceType();
  }

  bool _isGeofenceType() {
    return selectedType == "geofence_in" ||
        selectedType == "geofence_out" ||
        selectedType == "geofence_inout";
  }

  String _getValueLabel() {
    switch (selectedType) {
      case 'overspeed':
        return 'Speed (km/h)';
      case 'stop_duration':
        return 'Duration (min)';
      case 'offline_duration':
        return 'Duration (min)';
      case 'ignition_duration':
        return 'Duration (min)';
      case 'idle_duration':
        return 'Duration (min)';
      default:
        return 'Value';
    }
  }

  String _getValueHint() {
    switch (selectedType) {
      case 'overspeed':
        return 'e.g., 80';
      case 'stop_duration':
        return 'e.g., 15';
      case 'offline_duration':
        return 'e.g., 30';
      case 'ignition_duration':
        return 'e.g., 10';
      case 'idle_duration':
        return 'e.g., 20';
      default:
        return 'Enter value';
    }
  }
}
