// ignore_for_file: file_names
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:smart_lock/screens/data_controller/data_controller.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;

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

    final devId = widget.device.id;
    if (devId != null) {
      final lockOverride = DataController.getLocalLockOverride(devId);
      if (lockOverride != null) {
        _isLocked =
            ['locked', '1', 'true'].contains(lockOverride.toLowerCase().trim());
        return;
      }
    }

    final lockStatus =
        widget.device.deviceData?.lockStatus?.toLowerCase().trim();
    if (lockStatus != null && lockStatus.isNotEmpty) {
      _isLocked =
          lockStatus == 'locked' || lockStatus == '1' || lockStatus == 'true';
    } else {
      _isLocked = !_isEngineOn;
    }
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
        'device_id': widget.device.id.toString(),
        'type': 'gprs',
        'command': lockAfter ? '9400000' : '9500000',
      };
      final res = await APIService.sendCommands(requestBody);
      if (res.statusCode == 200) {
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

  Future<void> _sendCustomCommand(String commandType) async {
    setState(() => _isLoading = true);
    try {
      Map<String, String> requestBody;
      String friendlyName = commandType.toUpperCase();

      if (commandType == 'accalm') {
        requestBody = {
          'device_id': widget.device.id.toString(),
          'type': 'gprs',
          'command': '8880000',
        };
        friendlyName = 'ACC Call Alarm Enable';
      } else if (commandType == 'gmt') {
        requestBody = {
          'device_id': widget.device.id.toString(),
          'type': 'gprs',
          'command': 'zone0000 6',
        };
        friendlyName = 'GMT+6 Timezone';
      } else if (commandType == 'reset') {
        requestBody = {
          'device_id': widget.device.id.toString(),
          'type': 'gprs',
          'command': 'RESET',
        };
        friendlyName = 'Device Restart';
      } else {
        requestBody = {
          'id': '',
          'device_id': widget.device.id.toString(),
          'type': commandType,
        };
      }

      final res = await APIService.sendCommands(requestBody);
      Fluttertoast.showToast(
        msg: res.statusCode == 200
            ? '✅ Command "$friendlyName" sent'
            : 'Command failed (${res.statusCode})',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: res.statusCode == 200 ? _successColor : _dangerColor,
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Connection error.',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: _dangerColor,
        textColor: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

    // Clean number: remove "+", spaces, dashes, parentheses
    var cleanNumber = number.replaceAll(RegExp(r'[^0-9]'), '');

    // Bangladesh country code handling: if starting with 880 (13 digits), strip "88" to make it 11-digit local format
    if (cleanNumber.startsWith('880') && cleanNumber.length == 13) {
      cleanNumber = cleanNumber.substring(2);
    }

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
        'device_id': widget.device.id.toString(),
        'type': 'gprs',
        'command': '${cleanNumber}0000 1',
      };
      final res = await APIService.sendCommands(setAdminBody);

      if (res.statusCode == 200) {
        final Map<String, String> smsModeBody = {
          'device_id': widget.device.id.toString(),
          'type': 'gprs',
          'command': '1510000',
        };
        await APIService.sendCommands(smsModeBody);

        final Map<String, String> disableAccCallBody = {
          'device_id': widget.device.id.toString(),
          'type': 'gprs',
          'command': '8890000',
        };
        await APIService.sendCommands(disableAccCallBody);

        Fluttertoast.showToast(
          msg: '🆘 SOS Set (Calls Disabled / SMS Mode)',
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
                    _buildHUDStatusRing(),
                    const SizedBox(height: 24),
                    _buildVehicleDashboard(),
                    const SizedBox(height: 28),
                    _buildCircularControlButtons(),
                    const SizedBox(height: 32),
                    _buildSOSSection(),
                    const SizedBox(height: 28),
                    _buildCustomCommandSection(),
                    const SizedBox(height: 28),
                    _buildSecurityCard(),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFC0392B).withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const m.Icon(
                  Icons.directions_car_filled_rounded,
                  color: Color(0xFFC0392B),
                  size: 20,
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

    // Color choices
    final Color bgColor =
        isActionStateMatched ? color : color.withValues(alpha: 0.15);
    final Color textIconColor = isActionStateMatched ? Colors.white : color;
    final Color borderCol =
        isActionStateMatched ? color : color.withValues(alpha: 0.3);

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
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bgColor,
                border: Border.all(color: borderCol, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: m.Icon(
                  icon,
                  color: textIconColor,
                  size: 36,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
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
        borderRadius: BorderRadius.circular(16),
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
        borderRadius: BorderRadius.circular(16),
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
                'SinoTrack Quick Commands',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
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
        borderRadius: BorderRadius.circular(16),
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
