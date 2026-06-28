// ignore_for_file: file_names
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;
import 'package:smart_lock/util/util.dart';
import 'package:url_launcher/url_launcher.dart';

class LockUnlockScreen extends StatefulWidget {
  final DeviceItem device;

  const LockUnlockScreen({super.key, required this.device});

  @override
  _LockUnlockScreenState createState() => _LockUnlockScreenState();
}

class _LockUnlockScreenState extends State<LockUnlockScreen>
    with TickerProviderStateMixin {
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _dangerColor = Color(0xFFEF4444);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _greyText = Color(0xFF6B7280);

  bool _isLocked = true;
  bool _isEngineOn = false;
  bool _isLoading = false;
  String _debugCommandsText = "Loading GPRS commands...";

  // Selected tracker protocol
  String _selectedProtocol = 'SinoTrack';

  void _loadSelectedProtocol() {
    final devId = widget.device.id;
    if (devId != null) {
      final saved = GetStorage().read<String>('protocol_$devId');
      if (saved != null) {
        _selectedProtocol = saved;
      }
    }
  }

  void _saveSelectedProtocol(String protocol) {
    final devId = widget.device.id;
    if (devId != null) {
      GetStorage().write('protocol_$devId', protocol);
    }
  }

  // SOS
  final TextEditingController _sosController = TextEditingController();
  String? _sosError;

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

  // Animation controllers
  late AnimationController _lockPulseController;
  late AnimationController _unlockPulseController;
  late AnimationController _successController;
  late Animation<double> _lockPulse;
  late Animation<double> _unlockPulse;
  late Animation<double> _successScale;
  late Animation<double> _successOpacity;

  bool _showSuccessAnim = false;
  bool _lastActionWasLock = true;

  @override
  void initState() {
    super.initState();

    _lockPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _unlockPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _lockPulse = Tween<double>(begin: 1.0, end: 1.10).animate(
      CurvedAnimation(parent: _lockPulseController, curve: Curves.easeInOut),
    );
    _unlockPulse = Tween<double>(begin: 1.0, end: 1.10).animate(
      CurvedAnimation(parent: _unlockPulseController, curve: Curves.easeInOut),
    );
    _successScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.2), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 50),
    ]).animate(
        CurvedAnimation(parent: _successController, curve: Curves.easeOut));
    _successOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _successController, curve: const Interval(0, 0.4)),
    );

    _resolveInitialLockState();
    _loadSelectedProtocol();
    
    APIService.getSavedCommands(widget.device.id.toString()).then((res) {
      if (res != null) {
        setState(() {
          _debugCommandsText = res.body;
        });
      } else {
        setState(() {
          _debugCommandsText = "Error: Null response from server";
        });
      }
    }).catchError((err) {
      setState(() {
        _debugCommandsText = "Error loading: $err";
      });
    });
  }

  @override
  void dispose() {
    _sosController.dispose();
    _lockPulseController.dispose();
    _unlockPulseController.dispose();
    _successController.dispose();
    super.dispose();
  }

  void _resolveInitialLockState() {
    _isEngineOn = _checkEngineStatus(widget.device);
    _isLocked = _checkLockStatus(widget.device);
  }

  bool _checkLockStatus(DeviceItem d) {
    final devId = d.id;
    if (devId != null) {
      final lockOverride = DataController.getLocalLockOverride(devId);
      if (lockOverride != null) {
        return ['locked', '1', 'true', 'on'].contains(lockOverride.toLowerCase().trim());
      }
    }

    // 1. Check lockStatus field
    final lockStatus = d.deviceData?.lockStatus?.toLowerCase().trim();
    if (lockStatus != null && lockStatus.isNotEmpty) {
      return lockStatus == 'locked' || lockStatus == '1' || lockStatus == 'true' || lockStatus == 'on';
    }

    // 2. Check custom sensors for "lock" / "block" / "relay" / "immobilizer"
    if (d.sensors != null) {
      for (var sensor in d.sensors!) {
        try {
          if (sensor is! Map) continue;
          final sensorMap = Map<String, dynamic>.from(sensor);
          final type = (sensorMap['type'] ?? '').toString().toLowerCase();
          final name = (sensorMap['name'] ?? '').toString().toLowerCase();
          final value = sensorMap['value'];
          
          if (type.contains('lock') || name.contains('lock') || 
              type.contains('relay') || name.contains('relay') ||
              type.contains('block') || name.contains('block') ||
              type.contains('immobiliz') || name.contains('immobiliz')) {
            if (value == null) continue;
            if (value is bool) return value;
            if (value is int) return value == 1;
            if (value is String) {
              final v = value.toLowerCase().trim();
              if (['on', '1', 'true', 'locked', 'blocked', 'yes'].contains(v)) return true;
              if (['off', '0', 'false', 'unlocked', 'unblocked', 'no'].contains(v)) return false;
            }
          }
        } catch (_) {
          continue;
        }
      }
    }

    // Default fallback: Always assume UNLOCKED (false) if not explicitly locked!
    return false;
  }

  bool _isDeviceOnline(DeviceItem d) {
    final online = d.online?.toLowerCase().trim() ?? '';
    if (online.contains('offline')) return false;
    if (online.contains('online')) return true;
    final iconColor = d.iconColor?.toLowerCase() ?? '';
    if (iconColor == 'green' || iconColor == 'yellow') return true;
    final speed = double.tryParse(d.speed.toString()) ?? 0;
    if (speed > 0) return true;
    if (d.timestamp != null && d.timestamp! > 0) {
      try {
        final lastUpdate =
            DateTime.fromMillisecondsSinceEpoch(d.timestamp! * 1000);
        return DateTime.now().difference(lastUpdate).inMinutes < 5;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  bool _checkEngineStatus(DeviceItem d) {
    final devId = d.id;
    if (devId != null) {
      final engineOverride = DataController.getLocalEngineOverride(devId);
      if (engineOverride != null) {
        return ['on', '1', 'true', 'ign on', 'engine on', 'acc on']
            .contains(engineOverride.toLowerCase().trim());
      }
    }

    if (d.engineStatus != null) {
      final status = d.engineStatus;
      if (status is bool) return status;
      if (status is int) return status == 1;
      if (status is String) {
        final s = status.toLowerCase().trim();
        if (['on', '1', 'true', 'ign on', 'engine on', 'acc on'].contains(s))
          return true;
        if (['off', '0', 'false', 'ign off', 'engine off', 'acc off']
            .contains(s)) return false;
      }
    }
    final speed = double.tryParse(d.speed.toString()) ?? 0;
    if (speed > 0) return true;
    if (d.sensors != null) {
      for (var sensor in d.sensors!) {
        try {
          if (sensor is! Map) continue;
          final sensorMap = Map<String, dynamic>.from(sensor);
          final type = (sensorMap['type'] ?? '').toString().toLowerCase();
          final name = (sensorMap['name'] ?? '').toString().toLowerCase();
          final value = sensorMap['value'];
          if (type == 'acc' ||
              type == 'ignition' ||
              name.contains('acc') ||
              name.contains('ignition')) {
            if (value == null) continue;
            if (value is bool) return value;
            if (value is int) return value == 1;
            if (value is String) {
              final v = value.toLowerCase().trim();
              if (['on', '1', 'true'].contains(v)) return true;
              if (['off', '0', 'false'].contains(v)) return false;
            }
          }
        } catch (_) {
          continue;
        }
      }
    }
    return d.iconColor?.toLowerCase() == 'yellow' ||
        d.iconColor?.toLowerCase() == 'green';
  }

  void _syncStateToDevice() {
    widget.device.engineStatus = _isLocked ? 'off' : 'on';
    if (widget.device.deviceData != null) {
      widget.device.deviceData!.lockStatus = _isLocked ? 'locked' : 'unlocked';
    }
    // Also sync the sensor value locally so the UI updates immediately!
    if (widget.device.sensors != null) {
      for (var sensor in widget.device.sensors!) {
        try {
          if (sensor is! Map) continue;
          final name = (sensor['name'] ?? '').toString().toLowerCase();
          final type = (sensor['type'] ?? '').toString().toLowerCase();
          if (name.contains('lock') || type.contains('lock') || name.contains('relay') || type == 'relay') {
            sensor['value'] = _isLocked ? 'On' : 'Off';
          }
        } catch (_) {}
      }
    }
    final traccar = widget.device.deviceData?.traccar;
    if (traccar != null) {
      final now = DateTime.now().toUtc().toIso8601String();
      if (_isLocked) {
        traccar.engineOffAt = now;
      } else {
        traccar.engineOnAt = now;
      }
    }
  }

  void _goBack() {
    _syncStateToDevice();
    Get.back<DeviceItem>(result: widget.device);
  }

  Future<void> _showSuccessAnimation(bool locked) async {
    setState(() {
      _showSuccessAnim = true;
      _lastActionWasLock = locked;
    });
    _successController.reset();
    await _successController.forward();
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _showSuccessAnim = false);
  }

  Future<void> _sendCommand(String commandType,
      {required bool lockAfter}) async {
    setState(() => _isLoading = true);
    try {
      // Send raw SinoTrack GPRS commands to directly control the tracker hardware:
      // 9400000 = Cut off engine (Lock)
      // 9500000 = Restore engine (Unlock)
      final Map<String, String> requestBody = {
        'id': '',
        'device_id': widget.device.id.toString(),
        'type': 'custom',
        'command': lockAfter ? '9400000' : '9500000',
        'data': lockAfter ? '9400000' : '9500000',
      };
      final res = await APIService.sendCommands(requestBody);
      if (res.statusCode == 200) {
        Map<String, dynamic>? responseJson;
        try {
          responseJson = json.decode(res.body);
        } catch (_) {}

        if (responseJson != null && responseJson.containsKey('status') && responseJson['status'] == 0) {
          final errMsg = responseJson['message'] ?? 'Failed to control engine';
          Fluttertoast.showToast(
            msg: '❌ $errMsg',
            toastLength: Toast.LENGTH_LONG,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: _dangerColor,
            textColor: Colors.white,
          );
          return;
        }

        setState(() {
          _isLocked = lockAfter;
          _isEngineOn = !lockAfter;
        });

        // Set local overrides in DataController to avoid UI bouncing on rapid background polls
        final devId = widget.device.id;
        if (devId != null) {
          DataController.setLocalStatusOverride(
            devId,
            engineStatus: lockAfter ? 'off' : 'on',
            lockStatus: lockAfter ? 'locked' : 'unlocked',
          );
        }

        _syncStateToDevice();
        await _showSuccessAnimation(lockAfter);
        Fluttertoast.showToast(
          msg: lockAfter
              ? '🔒 Vehicle locked successfully'
              : '🔓 Vehicle unlocked successfully',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: lockAfter ? _dangerColor : _successColor,
          textColor: Colors.white,
        );
      } else {
        Fluttertoast.showToast(
          msg: 'Command failed (${res.statusCode}). Please try again.',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: _dangerColor,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Connection error. Check your network.',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: _dangerColor,
        textColor: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getCommandString(String commandType) {
    if (commandType == 'accalm') {
      if (_selectedProtocol == 'SinoTrack') return 'CALLSET,1#; ACCALM,ON,3,1#';
      if (_selectedProtocol == 'Concox / Jimi') return 'CALL,ON#';
      if (_selectedProtocol == 'Micodus') return 'CALLALM,ON#';
      if (_selectedProtocol == 'Coban') return 'callalarm123456 on';
    } else if (commandType == 'gmt') {
      if (_selectedProtocol == 'SinoTrack') return 'ZONE,GMT+6#';
      if (_selectedProtocol == 'Concox / Jimi') return 'GMT,E,6,0#';
      if (_selectedProtocol == 'Micodus') return 'TIMEZONE,6#';
      if (_selectedProtocol == 'Coban') return 'time zone123456 6';
    } else if (commandType == 'reset') {
      if (_selectedProtocol == 'SinoTrack') return 'RESET#';
      if (_selectedProtocol == 'Concox / Jimi') return 'REBOOT#';
      if (_selectedProtocol == 'Micodus') return 'RST#';
      if (_selectedProtocol == 'Coban') return 'reset123456';
    }
    return '';
  }

  Future<void> _sendSMS(String number, String message) async {
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: number,
      queryParameters: <String, String>{
        'body': message,
      },
    );
    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      } else {
        final fallbackUri = Uri.parse("sms:$number?body=${Uri.encodeComponent(message)}");
        await launchUrl(fallbackUri);
      }
      Fluttertoast.showToast(
        msg: "✉️ Opened SMS app. Please send the message to apply settings.",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: _successColor,
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(msg: "Could not launch SMS app: $e", backgroundColor: _dangerColor);
    }
  }

  void _showCommandMethodDialog({
    required String command,
    required String friendlyName,
    required VoidCallback onGPRSTap,
    required VoidCallback onServerSMSTap,
  }) {
    final simNumber = widget.device.deviceData?.simNumber;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              const m.Icon(Icons.message_rounded, color: Colors.blue, size: 22),
              const SizedBox(width: 8),
              Text(
                'Send $friendlyName',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Command String:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  command,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: Color(0xFF334155),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Note: SinoTrack/H02 trackers do not support configuration commands over GPRS (Internet). They only support Engine Lock/Unlock. For SOS number and settings, please use SMS.',
                style: TextStyle(fontSize: 11, height: 1.4, color: Color(0xFF475569)),
              ),
              if (simNumber == null || simNumber.isEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  '⚠️ Device SIM number is not configured in settings. You must configure the SIM number to send SMS commands.',
                  style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                onGPRSTap();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE2E8F0),
                foregroundColor: const Color(0xFF0F172A),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('GPRS (Free)'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                onServerSMSTap();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Server SMS'),
            ),
            if (simNumber != null && simNumber.isNotEmpty)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _sendSMS(simNumber, command);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _successColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Phone SMS'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _sendCustomCommand(String commandType) async {
    final command = _getCommandString(commandType);
    if (command.isEmpty) return;

    String friendlyName = commandType.toUpperCase();
    if (commandType == 'accalm') friendlyName = 'ACC Call Alarm';
    if (commandType == 'gmt') friendlyName = 'GMT+6 Timezone';
    if (commandType == 'reset') friendlyName = 'Device Restart';

    final onGprsTap = () async {
      setState(() => _isLoading = true);
      try {
        if (commandType == 'accalm' && _selectedProtocol == 'SinoTrack') {
          final res1 = await APIService.sendCommands({
            'id': '',
            'device_id': widget.device.id.toString(),
            'type': 'custom',
            'command': 'CALLSET,1#',
            'data': 'CALLSET,1#',
          });
          if (res1.statusCode != 200) {
            throw Exception('CALLSET failed: ${res1.statusCode}');
          }
          Map<String, dynamic>? res1Json;
          try { res1Json = json.decode(res1.body); } catch(_) {}
          if (res1Json != null && res1Json['status'] == 0) {
            throw Exception(res1Json['message'] ?? 'CALLSET rejected by server');
          }

          await Future.delayed(const Duration(milliseconds: 600));

          final res2 = await APIService.sendCommands({
            'id': '',
            'device_id': widget.device.id.toString(),
            'type': 'custom',
            'command': 'ACCALM,ON,3,1#',
            'data': 'ACCALM,ON,3,1#',
          });
          
          Map<String, dynamic>? res2Json;
          try { res2Json = json.decode(res2.body); } catch(_) {}
          final success = res2.statusCode == 200 && (res2Json == null || res2Json['status'] != 0);
          final msg = success ? '✅ ACC Call Alarm Enabled' : (res2Json?['message'] ?? 'ACCALM failed');
          Fluttertoast.showToast(
            msg: msg,
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: success ? _successColor : _dangerColor,
            textColor: Colors.white,
          );
          return;
        }

        final Map<String, String> requestBody = {
          'id': '',
          'device_id': widget.device.id.toString(),
          'type': 'custom',
          'command': command,
          'data': command,
        };
        final res = await APIService.sendCommands(requestBody);
        if (res.statusCode == 200) {
          Map<String, dynamic>? responseJson;
          try {
            responseJson = json.decode(res.body);
          } catch (_) {}

          if (responseJson != null && responseJson.containsKey('status') && responseJson['status'] == 0) {
            final errMsg = responseJson['message'] ?? 'Command rejected';
            Fluttertoast.showToast(
              msg: '❌ $errMsg',
              toastLength: Toast.LENGTH_LONG,
              gravity: ToastGravity.BOTTOM,
              backgroundColor: _dangerColor,
              textColor: Colors.white,
            );
            return;
          }

          Fluttertoast.showToast(
            msg: '✅ Command "$friendlyName" sent',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: _successColor,
            textColor: Colors.white,
          );
        } else {
          Fluttertoast.showToast(
            msg: 'Command failed (${res.statusCode})',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: _dangerColor,
            textColor: Colors.white,
          );
        }
      } catch (e) {
        Fluttertoast.showToast(
          msg: 'Error: $e',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: _dangerColor,
          textColor: Colors.white,
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    };

    final onServerSMSTap = () async {
      setState(() => _isLoading = true);
      try {
        if (commandType == 'accalm' && _selectedProtocol == 'SinoTrack') {
          final res1 = await APIService.sendCommands({
            'id': '',
            'device_id': widget.device.id.toString(),
            'type': 'sms',
            'command': 'CALLSET,1#',
            'data': 'CALLSET,1#',
          });
          if (res1.statusCode != 200) {
            throw Exception('CALLSET SMS failed: ${res1.statusCode}');
          }
          Map<String, dynamic>? res1Json;
          try { res1Json = json.decode(res1.body); } catch(_) {}
          if (res1Json != null && res1Json['status'] == 0) {
            throw Exception(res1Json['message'] ?? 'CALLSET SMS rejected by server');
          }

          await Future.delayed(const Duration(milliseconds: 600));

          final res2 = await APIService.sendCommands({
            'id': '',
            'device_id': widget.device.id.toString(),
            'type': 'sms',
            'command': 'ACCALM,ON,3,1#',
            'data': 'ACCALM,ON,3,1#',
          });
          
          Map<String, dynamic>? res2Json;
          try { res2Json = json.decode(res2.body); } catch(_) {}
          final success = res2.statusCode == 200 && (res2Json == null || res2Json['status'] != 0);
          final msg = success ? '✅ Server SMS: ACC Call Alarm Enabled' : (res2Json?['message'] ?? 'ACCALM SMS failed');
          Fluttertoast.showToast(
            msg: msg,
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: success ? _successColor : _dangerColor,
            textColor: Colors.white,
          );
          return;
        }

        final Map<String, String> requestBody = {
          'id': '',
          'device_id': widget.device.id.toString(),
          'type': 'sms',
          'command': command,
          'data': command,
        };
        final res = await APIService.sendCommands(requestBody);
        if (res.statusCode == 200) {
          Map<String, dynamic>? responseJson;
          try {
            responseJson = json.decode(res.body);
          } catch (_) {}

          if (responseJson != null && responseJson.containsKey('status') && responseJson['status'] == 0) {
            final errMsg = responseJson['message'] ?? 'SMS Command rejected';
            Fluttertoast.showToast(
              msg: '❌ $errMsg',
              toastLength: Toast.LENGTH_LONG,
              gravity: ToastGravity.BOTTOM,
              backgroundColor: _dangerColor,
              textColor: Colors.white,
            );
            return;
          }

          Fluttertoast.showToast(
            msg: '✅ Server SMS: "$friendlyName" sent',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: _successColor,
            textColor: Colors.white,
          );
        } else {
          Fluttertoast.showToast(
            msg: 'SMS Command failed (${res.statusCode})',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: _dangerColor,
            textColor: Colors.white,
          );
        }
      } catch (e) {
        Fluttertoast.showToast(
          msg: 'Error: $e',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: _dangerColor,
          textColor: Colors.white,
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    };

    _showCommandMethodDialog(
      command: command,
      friendlyName: friendlyName,
      onGPRSTap: onGprsTap,
      onServerSMSTap: onServerSMSTap,
    );
  }

  Future<void> _sendSOS() async {
    final number = _sosController.text.trim();
    final validationError = _validatePhone(number, isRequired: true);
    if (validationError != null) {
      setState(() {
        _sosError = validationError;
      });
      Fluttertoast.showToast(
        msg: 'Please fix validation errors first',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: _dangerColor,
        textColor: Colors.white,
      );
      return;
    }

    var cleanNumber = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanNumber.startsWith('880') && cleanNumber.length == 13) {
      cleanNumber = cleanNumber.substring(2);
    }

    String command = '';
    if (_selectedProtocol == 'SinoTrack' || _selectedProtocol == 'Concox / Jimi' || _selectedProtocol == 'Micodus') {
      command = 'SOS,A,${cleanNumber}#';
    } else if (_selectedProtocol == 'Coban') {
      command = 'admin123456 ${cleanNumber}';
    }

    if (command.isEmpty) return;

    final onGprsTap = () async {
      final isOnline = _isDeviceOnline(widget.device);
      if (!isOnline) {
        Fluttertoast.showToast(
          msg: '⚠️ Device is offline. GPRS commands will not be delivered.',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: _warningColor,
          textColor: Colors.white,
        );
      }

      setState(() => _isLoading = true);
      try {
        final Map<String, String> setAdminBody = {
          'id': '',
          'device_id': widget.device.id.toString(),
          'type': 'custom',
          'command': command,
          'data': command,
        };
        final res = await APIService.sendCommands(setAdminBody);

        if (res.statusCode == 200) {
          Map<String, dynamic>? responseJson;
          try {
            responseJson = json.decode(res.body);
          } catch (_) {}

          if (responseJson != null && responseJson.containsKey('status') && responseJson['status'] == 0) {
            final errMsg = responseJson['message'] ?? 'SOS configuration rejected';
            Fluttertoast.showToast(
              msg: '❌ $errMsg',
              toastLength: Toast.LENGTH_LONG,
              gravity: ToastGravity.BOTTOM,
              backgroundColor: _dangerColor,
              textColor: Colors.white,
            );
            return;
          }

          Fluttertoast.showToast(
            msg: '🆘 SOS Number Configured: $command',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: _successColor,
            textColor: Colors.white,
          );
        } else {
          Fluttertoast.showToast(
            msg: 'Failed to set SOS number (${res.statusCode})',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: _dangerColor,
            textColor: Colors.white,
          );
        }
      } catch (e) {
        Fluttertoast.showToast(
          msg: 'Connection error.',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: _dangerColor,
          textColor: Colors.white,
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    };

    final onServerSMSTap = () async {
      setState(() => _isLoading = true);
      try {
        final Map<String, String> setAdminBody = {
          'id': '',
          'device_id': widget.device.id.toString(),
          'type': 'sms',
          'command': command,
          'data': command,
        };
        final res = await APIService.sendCommands(setAdminBody);

        if (res.statusCode == 200) {
          Map<String, dynamic>? responseJson;
          try {
            responseJson = json.decode(res.body);
          } catch (_) {}

          if (responseJson != null && responseJson.containsKey('status') && responseJson['status'] == 0) {
            final errMsg = responseJson['message'] ?? 'SOS SMS rejected';
            Fluttertoast.showToast(
              msg: '❌ $errMsg',
              toastLength: Toast.LENGTH_LONG,
              gravity: ToastGravity.BOTTOM,
              backgroundColor: _dangerColor,
              textColor: Colors.white,
            );
            return;
          }

          Fluttertoast.showToast(
            msg: '🆘 Server SMS sent: $command',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: _successColor,
            textColor: Colors.white,
          );
        } else {
          Fluttertoast.showToast(
            msg: 'Failed to send Server SMS (${res.statusCode})',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: _dangerColor,
            textColor: Colors.white,
          );
        }
      } catch (e) {
        Fluttertoast.showToast(
          msg: 'Connection error.',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: _dangerColor,
          textColor: Colors.white,
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    };

    _showCommandMethodDialog(
      command: command,
      friendlyName: 'Configure SOS Number',
      onGPRSTap: onGprsTap,
      onServerSMSTap: onServerSMSTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          title: const Text(
            'Engine Control',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const m.Icon(Icons.arrow_back_ios_new_rounded,
                color: Color(0xFF0F172A)),
            onPressed: _goBack,
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFFAFAFA),
                Color(0xFFF1F5F9),
              ],
            ),
          ),
          child: Stack(
            children: [
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 110, 20, 30),
                child: Column(
                  children: [
                    _buildVehicleDashboard(),
                    const SizedBox(height: 28),
                    _buildCircularControlButtons(),
                    const SizedBox(height: 32),
                    _buildSOSSection(),
                    const SizedBox(height: 28),
                    _buildCustomCommandSection(),
                    const SizedBox(height: 28),
                    _buildSecurityCard(),
                    _buildDebugCommandsCard(),
                  ],
                ),
              ),
              if (_isLoading) _buildLoadingOverlay(),
              if (_showSuccessAnim) _buildSuccessOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHUDStatusRing() {
    return SizedBox(
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _lockPulseController,
            builder: (context, child) {
              final double val = _lockPulseController.value;
              return Container(
                width: 120 + (val * 12),
                height: 120 + (val * 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _isLocked
                          ? _dangerColor.withValues(alpha: 0.08 * (1 - val))
                          : _successColor.withValues(alpha: 0.08 * (1 - val)),
                      blurRadius: 18,
                      spreadRadius: 6 * val,
                    ),
                  ],
                  border: Border.all(
                    color: _isLocked
                        ? _dangerColor.withValues(
                            alpha: 0.15 + (0.35 * (1 - val)))
                        : _successColor.withValues(
                            alpha: 0.15 + (0.35 * (1 - val))),
                    width: 1.5,
                  ),
                ),
              );
            },
          ),
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _isLocked
                    ? _dangerColor.withValues(alpha: 0.1)
                    : _successColor.withValues(alpha: 0.1),
                width: 3,
              ),
            ),
          ),
          Container(
            width: 95,
            height: 95,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Colors.white, Color(0xFFF8FAFC)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: _isLocked
                    ? _dangerColor.withValues(alpha: 0.8)
                    : _successColor.withValues(alpha: 0.8),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                m.Icon(
                  _isLocked
                      ? Icons.lock_outline_rounded
                      : Icons.lock_open_rounded,
                  color: _isLocked ? _dangerColor : _successColor,
                  size: 32,
                ),
                const SizedBox(height: 2),
                Text(
                  _isLocked ? "SECURED" : "UNLOCKED",
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: _isLocked ? _dangerColor : _successColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleDashboard() {
    final isOnline = _isDeviceOnline(widget.device);
    final String statusStr = widget.device.iconColor?.toLowerCase() ?? 'red';
    Color statusColor = _dangerColor;
    if (statusStr == 'green') {
      statusColor = _successColor;
    } else if (statusStr == 'yellow') {
      statusColor = _warningColor;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Util.getVehicleIconWidget(
                    widget.device.icon?.path,
                    statusColor,
                    size: 22,
                    iconType: widget.device.icon?.type ?? widget.device.iconType,
                    deviceName: widget.device.name,
                    deviceId: widget.device.id,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.device.name ?? 'Unknown Device',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.device.deviceData?.plateNumber != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.device.deviceData!.plateNumber!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFF1F5F9), height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildQuickStat(
                'GPS SIGNAL',
                isOnline ? 'ONLINE' : 'OFFLINE',
                Icons.wifi_rounded,
                isOnline ? _successColor : _dangerColor,
              ),
              _buildQuickStat(
                'IGNITION',
                _isEngineOn ? 'ON' : 'OFF',
                Icons.power_rounded,
                _isEngineOn ? _successColor : _greyText,
              ),
              _buildQuickStat(
                'SECURITY',
                _isLocked ? 'ARMED' : 'READY',
                Icons.shield_rounded,
                _isLocked ? _warningColor : _successColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStat(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        m.Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Color(0xFF94A3B8),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCircularControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildCircularBtn(
          isLock: true,
          label: 'LOCK ENGINE',
          subtitle: 'Disable ignition',
          color: _dangerColor,
          icon: Icons.lock_outline_rounded,
          activeScale: _lockPulse,
        ),
        _buildCircularBtn(
          isLock: false,
          label: 'UNLOCK ENGINE',
          subtitle: 'Enable ignition',
          color: _successColor,
          icon: Icons.lock_open_rounded,
          activeScale: _unlockPulse,
        ),
      ],
    );
  }

  Widget _buildCircularBtn({
    required bool isLock,
    required String label,
    required String subtitle,
    required Color color,
    required IconData icon,
    required Animation<double> activeScale,
  }) {
    final bool isActionStateMatched = (isLock == _isLocked);

    // Build the exact visual button widget based on the user's uploaded images
    Widget buttonWidget;

    if (isLock) {
      // ── RED BUTTON (LOCK ENGINE) ──
      if (isActionStateMatched) {
        // Active Red Button (Image 2 style: solid red background, thin white ring inside, white lock icon, soft red glow)
        buttonWidget = Container(
          width: 115,
          height: 115,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color, // Solid red
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.55),
                blurRadius: 15,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Container(
            margin: const EdgeInsets.all(6.0), // Gap to the white ring
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white, // Thin white ring
                width: 2.2,
              ),
            ),
            child: Center(
              child: m.Icon(
                icon,
                color: Colors.white, // White lock icon
                size: 38,
              ),
            ),
          ),
        );
      } else {
        // Inactive Red Button (Translucent red background and red lock icon - bolder)
        buttonWidget = Container(
          width: 115,
          height: 115,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.22), // More saturated translucent background
            border: Border.all(
              color: color.withValues(alpha: 0.55), // Bolder red outer border
              width: 2.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Container(
            margin: const EdgeInsets.all(6.0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.35), // Bolder inner ring
                width: 1.5,
              ),
            ),
            child: Center(
              child: m.Icon(
                icon,
                color: color.withValues(alpha: 0.8), // Solid, rich red icon
                size: 34,
              ),
            ),
          ),
        );
      }
    } else {
      // ── GREEN BUTTON (UNLOCK ENGINE) ──
      if (isActionStateMatched) {
        // Active Green Button (Image 1 style: glossy green sphere with carbon-black border, white unlock icon, soft green glow)
        buttonWidget = Container(
          width: 115,
          height: 115,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF151515), // Carbon black border base
            border: Border.all(
              color: const Color(0xFF2C2C2C),
              width: 5.5, // Thick outer border
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: color.withValues(alpha: 0.5), // Green glow
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipOval(
            child: Stack(
              children: [
                // Glossy Green Sphere Gradient (radial offset)
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(-0.3, -0.3),
                      radius: 0.85,
                      colors: [
                        Color(0xFF86EFAC), // Bright neon green core
                        Color(0xFF22C55E), // Vibrant green middle
                        Color(0xFF15803D), // Deep dark green bottom-right
                      ],
                    ),
                  ),
                ),
                // Glossy Crescent/Lens Highlight at the top-left
                Positioned(
                  top: 5,
                  left: 9,
                  child: Container(
                    width: 65,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.55),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Icon in center
                Center(
                  child: m.Icon(
                    icon,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // Inactive Green Button (Translucent green background and green lock icon - matches inactive red button)
        buttonWidget = Container(
          width: 115,
          height: 115,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.22), // More saturated translucent background
            border: Border.all(
              color: color.withValues(alpha: 0.55), // Bolder green outer border
              width: 2.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Container(
            margin: const EdgeInsets.all(6.0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.35), // Bolder inner ring
                width: 1.5,
              ),
            ),
            child: Center(
              child: m.Icon(
                icon,
                color: color.withValues(alpha: 0.8), // Solid, rich green icon
                size: 34,
              ),
            ),
          ),
        );
      }
    }

    return GestureDetector(
      onTap: _isLoading || isActionStateMatched
          ? null
          : () => _sendCommand(isLock ? 'engineStop' : 'engineResume',
              lockAfter: isLock),
      child: Column(
        children: [
          ScaleTransition(
            scale: isActionStateMatched
                ? activeScale
                : const AlwaysStoppedAnimation(1.0),
            child: buttonWidget,
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: isActionStateMatched ? color : const Color(0xFF4B5563),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSOSSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _dangerColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const m.Icon(Icons.sos_rounded,
                    color: _dangerColor, size: 16),
              ),
              const SizedBox(width: 8),
              const Text(
                'SOS Config Command',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    _sosError != null ? _dangerColor : const Color(0xFFE2E8F0),
                width: _sosError != null ? 1.5 : 1.0,
              ),
            ),
            child: TextField(
              controller: _sosController,
              keyboardType: TextInputType.phone,
              onChanged: (val) {
                setState(() {
                  _sosError = _validatePhone(val, isRequired: true);
                });
              },
              decoration: const InputDecoration(
                hintText: 'Enter Authorized SOS Number',
                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          if (_sosError != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                _sosError!,
                style: const TextStyle(
                    color: _dangerColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _sendSOS,
              style: ElevatedButton.styleFrom(
                backgroundColor: _dangerColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text(
                'Configure SOS Number',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomCommandSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFC0392B).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const m.Icon(Icons.terminal_rounded,
                    color: Color(0xFFC0392B), size: 16),
              ),
              const SizedBox(width: 8),
              const Text(
                'Quick Commands Config',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Tracker Brand/Protocol Selector Dropdown
          const Text(
            'Select Tracker Model/Protocol:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedProtocol,
                isExpanded: true,
                icon: const m.Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                dropdownColor: Colors.white,
                style: const TextStyle(color: Color(0xFF1E293B), fontSize: 13, fontWeight: m.FontWeight.w600),
                items: ['SinoTrack', 'Concox / Jimi', 'Micodus', 'Coban']
                    .map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedProtocol = newValue;
                      _saveSelectedProtocol(newValue);
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildCustomCmdBtn('ACC CALL', 'accalm', Colors.orange),
              const SizedBox(width: 8),
              _buildCustomCmdBtn('ZONE GMT+6', 'gmt', Colors.blue),
              const SizedBox(width: 8),
              _buildCustomCmdBtn('REBOOT', 'reset', Colors.purple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomCmdBtn(String label, String commandType, Color tintColor) {
    return Expanded(
      child: GestureDetector(
        onTap: _isLoading ? null : () => _sendCustomCommand(commandType),
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: tintColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: tintColor.withValues(alpha: 0.25)),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: tintColor,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const m.Icon(Icons.shield_outlined,
              color: Color(0xFFF59E0B), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Encrypted Tunnel Active',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'GPRS commands are transmitted securely. For your safety, ensure the vehicle is stationary and in a safe area before cutting off the engine.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugCommandsCard() {
    return Container(
      margin: const EdgeInsets.only(top: 28),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DIAGNOSTICS: SERVER GPRS COMMANDS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _debugCommandsText,
            style: const TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08), blurRadius: 16),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFFC0392B),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sending GPRS command...',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    final color = _lastActionWasLock ? _dangerColor : _successColor;
    final icon = _lastActionWasLock ? Icons.lock : Icons.lock_open;
    final label = _lastActionWasLock ? 'Engine Locked!' : 'Engine Active!';

    return AnimatedBuilder(
      animation: _successController,
      builder: (context, child) {
        return Container(
          color: Colors.black.withValues(alpha: 0.35 * _successOpacity.value),
          child: Center(
            child: Transform.scale(
              scale: _successScale.value,
              child: Opacity(
                opacity: _successOpacity.value,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.25),
                        blurRadius: 20,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.1),
                          border: Border.all(color: color, width: 2),
                        ),
                        child: m.Icon(icon, color: color, size: 32),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
