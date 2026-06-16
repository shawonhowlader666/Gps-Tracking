import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;
import 'package:gpspro/theme/custom_color.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:gpspro/config.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/widgets/banner_ad_widget.dart';

class LockUnlockScreen extends StatefulWidget {
  final DeviceItem device;

  const LockUnlockScreen({super.key, required this.device});

  @override
  _LockUnlockScreenState createState() => _LockUnlockScreenState();
}

class _LockUnlockScreenState extends State<LockUnlockScreen>
    with SingleTickerProviderStateMixin {
  final List<String> _commands = <String>[];
  final List<String> _commandsValue = <String>[];
  int _selectedCommand = 0;
  String _commandSelected = "";
  double _dialogCommandHeight = 150.0;
  final TextEditingController _customCommand = TextEditingController();
  bool _isLoading = false;
  bool _isEngineOn = false;
  bool _isLocked = false;
  String? _lockCommandType;
  String? _unlockCommandType;
  String? _lockCommandId;
  String? _unlockCommandId;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _checkEngineStatus();
    _loadLockUnlockCommands();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _customCommand.dispose();
    _animationController.dispose();
    super.dispose();
  }

  String? _getRawParameter(String key) {
    if (widget.device == null) return null;
    
    // 1. Try to search in device.sensors list
    final sensors = widget.device.sensors;
    if (sensors != null) {
      for (var s in sensors) {
        if (s is Map) {
          final name = (s['name'] ?? '').toString().toLowerCase();
          if (name.contains(key.toLowerCase())) {
            final val = s['value']?.toString();
            if (val != null && val.trim().isNotEmpty) {
              return val;
            }
          }
        }
      }
    }

    // 2. Try to search in deviceData.sensors
    final ddSensors = widget.device.deviceData?.sensors;
    if (ddSensors != null) {
      for (var s in ddSensors) {
        if (s is Map) {
          final name = (s['name'] ?? '').toString().toLowerCase();
          if (name.contains(key.toLowerCase())) {
            final val = s['value']?.toString();
            if (val != null && val.trim().isNotEmpty) {
              return val;
            }
          }
        }
      }
    }

    // 3. Try to extract from traccar.other (XML or JSON)
    final other = widget.device.deviceData?.traccar?.other;
    if (other != null && other.isNotEmpty) {
      final xmlMatch = RegExp('<$key>(.*?)</$key>', caseSensitive: false).firstMatch(other);
      if (xmlMatch != null && xmlMatch.group(1) != null) {
        final val = xmlMatch.group(1);
        if (val != null && val.trim().isNotEmpty) {
          return val;
        }
      }
      final jsonMatch = RegExp('["\']?$key["\']?\\s*:\\s*(true|false|"[^"]*"|\'[^\']*\'|\\d+\\.?\\d*)', caseSensitive: false).firstMatch(other);
      if (jsonMatch != null && jsonMatch.group(1) != null) {
        final val = jsonMatch.group(1)!.replaceAll('"', '').replaceAll("'", '');
        if (val.trim().isNotEmpty) {
          return val;
        }
      }
    }

    // 4. Try from deviceData.parameters or currents
    final params = widget.device.deviceData?.parameters;
    if (params != null && params.isNotEmpty) {
      final jsonMatch = RegExp('["\']?$key["\']?\\s*:\\s*(true|false|"[^"]*"|\'[^\']*\'|\\d+\\.?\\d*)', caseSensitive: false).firstMatch(params);
      if (jsonMatch != null && jsonMatch.group(1) != null) {
        final val = jsonMatch.group(1)!.replaceAll('"', '').replaceAll("'", '');
        if (val.trim().isNotEmpty) {
          return val;
        }
      }
    }

    return null;
  }

  void _checkEngineStatus() {
    // 1. Determine Locked/Secured Status
    final lockVal = _getRawParameter('blocked') ?? _getRawParameter('lock');
    if (lockVal != null) {
      final lv = lockVal.toLowerCase().trim();
      setState(() => _isLocked = (lv == 'true' || lv == '1' || lv == 'blocked' || lv == 'lock'));
    } else {
      setState(() => _isLocked = false);
    }

    // 2. Determine Engine/Ignition Status
    if (widget.device.engineStatus != null) {
      final status = widget.device.engineStatus;
      if (status is bool) {
        setState(() => _isEngineOn = status);
      } else if (status is int) {
        setState(() => _isEngineOn = status == 1);
      } else if (status is String) {
        final s = status.toLowerCase().trim();
        setState(() => _isEngineOn = s == 'on' || s == '1' || s == 'true');
      }
    } else {
      final traccar = widget.device.deviceData?.traccar;
      if (traccar != null) {
        final engineOnAt = traccar.engineOnAt;
        final engineOffAt = traccar.engineOffAt;
        if (engineOnAt != null && engineOffAt != null) {
          try {
            final onTime = DateTime.parse(engineOnAt);
            final offTime = DateTime.parse(engineOffAt);
            setState(() => _isEngineOn = onTime.isAfter(offTime));
          } catch (_) {}
        }
      }
    }
  }

  void _loadLockUnlockCommands() {
    APIService.getSavedCommands(widget.device.id.toString()).then((value) {
      if (value != null) {
        try {
          final List<dynamic> list = json.decode(value.body);
          for (var element in list) {
            if (element is Map) {
              final title = (element["title"] ?? "").toString().toLowerCase();
              final type = (element["type"] ?? "").toString();
              final id = (element["id"] ?? "").toString();
              if (title.contains("unlock")) {
                _unlockCommandType = type;
                _unlockCommandId = id;
              } else if (title.contains("lock")) {
                _lockCommandType = type;
                _lockCommandId = id;
              }
            }
          }
          debugPrint("Mapped Lock command: $_lockCommandType (ID: $_lockCommandId)");
          debugPrint("Mapped Unlock command: $_unlockCommandType (ID: $_unlockCommandId)");
        } catch (e) {
          debugPrint("Error loading saved commands: $e");
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          'Lock / Unlock',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w700,
            fontSize: 19,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const m.Icon(Icons.settings_suggest_rounded, color: Color(0xFF0F172A)),
            onPressed: () => showCommandDialog(context, widget.device),
          ),
        ],
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
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 110, 20, 20),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          // HUD Status Ring
                          _buildHUDStatusRing(),
                          const SizedBox(height: 28),
                          // Vehicle Dashboard Card
                          _buildVehicleDashboard(),
                          const SizedBox(height: 28),
                          // Action controls section
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: CustomColor.primary,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'COMMANDS',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF0F172A).withValues(alpha: 0.4),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Dual Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildCircularButton(
                                isUnlockButton: true,
                              ),
                              _buildCircularButton(
                                isUnlockButton: false,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Security Card
                          _buildSecurityCard(),
                        ],
                      ),
                    ),
                  ),
                ),
                BannerAdWidget(forceShow: ALWAYS_SHOW_BANNER_ADS),
              ],
            ),
            if (_isLoading) _buildLoadingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildHUDStatusRing() {
    return SizedBox(
      height: 170,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer breathing glowing ring
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final double value = _animationController.value;
              return Container(
                width: 135 + (value * 16),
                height: 135 + (value * 16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: !_isLocked
                          ? const Color(0xFF10B981).withValues(alpha: 0.08 * (1 - value))
                          : const Color(0xFFEF4444).withValues(alpha: 0.08 * (1 - value)),
                      blurRadius: 20,
                      spreadRadius: 8 * value,
                    ),
                  ],
                  border: Border.all(
                    color: !_isLocked
                        ? const Color(0xFF10B981).withValues(alpha: 0.15 + (0.35 * (1 - value)))
                        : const Color(0xFFEF4444).withValues(alpha: 0.15 + (0.35 * (1 - value))),
                    width: 1.5,
                  ),
                ),
              );
            },
          ),
          // Intermediate ring
          Container(
            width: 125,
            height: 125,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: !_isLocked
                    ? const Color(0xFF10B981).withValues(alpha: 0.1)
                    : const Color(0xFFEF4444).withValues(alpha: 0.1),
                width: 3,
              ),
            ),
          ),
          // Inner solid card HUD
          Container(
            width: 105,
            height: 105,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [
                  Colors.white,
                  Color(0xFFF8FAFC),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: !_isLocked
                    ? const Color(0xFF10B981).withValues(alpha: 0.8)
                    : const Color(0xFFEF4444).withValues(alpha: 0.8),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                m.Icon(
                  _isLocked ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                  color: !_isLocked ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  size: 34,
                ),
                const SizedBox(height: 2),
                Text(
                  _isLocked ? "SECURED" : "UNLOCKED",
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: !_isLocked ? const Color(0xFF10B981) : const Color(0xFFEF4444),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CustomColor.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: m.Icon(
                  Icons.directions_car_filled_rounded,
                  color: CustomColor.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.device.name ?? 'Unknown Device',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.device.deviceData?.plateNumber != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.device.deviceData!.plateNumber!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: Color(0xFFF1F5F9), height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildQuickStat('GPS SIGNAL', 'ONLINE', Icons.wifi_rounded, const Color(0xFF10B981)),
              _buildQuickStat('IGNITION', _isEngineOn ? 'ON' : 'OFF', Icons.power_rounded, _isEngineOn ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
              _buildQuickStat('SECURITY', _isLocked ? 'ARMED' : 'READY', Icons.shield_rounded, _isLocked ? const Color(0xFFF59E0B) : const Color(0xFF10B981)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStat(String label, String value, IconData icon, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        m.Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Color(0xFF94A3B8),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCircularButton({required bool isUnlockButton}) {
    final bool isActive = isUnlockButton ? !_isLocked : _isLocked;
    
    // Core color scheme definitions
    final Color themeColor = isUnlockButton ? const Color(0xFF16A34A) : const Color(0xFFDC2626); // green / red
    
    // Base light background and border colors
    final Color baseBgColor = isUnlockButton ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5); // light green / light red
    final Color baseBorderColor = isUnlockButton ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5);

    // Apply active/inactive colors
    final Color bgColor = isActive 
        ? (isUnlockButton ? const Color(0xFF16A34A) : const Color(0xFFDC2626)) 
        : baseBgColor;
        
    final Color borderColor = isActive 
        ? (isUnlockButton ? const Color(0xFF16A34A) : const Color(0xFFDC2626)) 
        : baseBorderColor;

    final Color textIconColor = isActive ? Colors.white : Colors.white.withValues(alpha: 0.65);

    final IconData iconData = isUnlockButton ? Icons.lock_open_rounded : Icons.lock_rounded;
    final String title = isUnlockButton ? 'UNLOCK' : 'LOCK';
    final String subtitle = isUnlockButton ? 'Unlock Vehicle' : 'Lock Vehicle';

    return GestureDetector(
      onTap: () {
        if (!_isLoading && !isActive) {
          sendEngineCommand(
            isUnlockButton ? (_unlockCommandType ?? 'engineResume') : (_lockCommandType ?? 'engineStop'),
            isUnlockButton ? _unlockCommandId : _lockCommandId,
            isUnlockButton,
          );
        }
      },
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: 125,
            height: 125,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
              border: Border.all(
                color: borderColor,
                width: 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  final double scale = isActive ? 1.0 + (_animationController.value * 0.05) : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: child,
                  );
                },
                child: m.Icon(
                  iconData,
                  color: textIconColor,
                  size: 42,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: themeColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const m.Icon(Icons.shield_outlined, color: Color(0xFFF59E0B), size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Encrypted Connection Active',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Commands are transmitted securely via encrypted channels. Make sure the vehicle is in a safe location before execution.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: const Color(0xFF475569),
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
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(CustomColor.primary),
              ),
              const SizedBox(height: 24),
              const Text(
                'Sending command...',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleEngine() {
    final commandType = _isLocked ? (_unlockCommandType ?? 'engineResume') : (_lockCommandType ?? 'engineStop');
    final commandId = _isLocked ? _unlockCommandId : _lockCommandId;
    sendEngineCommand(commandType, commandId, _isLocked);
  }

  void sendEngineCommand(String commandType, String? commandId, bool isUnlockAction) async {
    setState(() => _isLoading = true);

    try {
      Map<String, String> requestBody = <String, String>{
        'id': commandId ?? "",
        'device_id': widget.device.id.toString(),
        'type': commandType
      };

      final res = await APIService.sendCommands(requestBody);

      if (res.statusCode == 200) {
        // Parse the body to check for JSON status
        Map<String, dynamic>? responseJson;
        try {
          responseJson = json.decode(res.body);
        } catch (_) {}

        if (responseJson != null && responseJson.containsKey('status') && responseJson['status'] == 0) {
          Fluttertoast.showToast(
            msg: responseJson['message'] ?? 'Failed to send command',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: const Color(0xFFEF4444),
            textColor: Colors.white,
          );
          return;
        }

        setState(() {
          _isLocked = !isUnlockAction;
          _isEngineOn = isUnlockAction ? _isEngineOn : false;
        });

        Fluttertoast.showToast(
          msg: !isUnlockAction
              ? 'Vehicle locked successfully'
              : 'Vehicle unlocked successfully',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: const Color(0xFF22C55E),
          textColor: Colors.white,
        );
      } else {
        Fluttertoast.showToast(
          msg: 'Failed to send command',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: const Color(0xFFEF4444),
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Connection error',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: const Color(0xFFEF4444),
        textColor: Colors.white,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void showCommandDialog(BuildContext context, DeviceItem device) {
    _commands.clear();
    _commandsValue.clear();

    Dialog simpleDialog = Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          Iterable list;
          APIService.getSavedCommands(device.id.toString()).then((value) => {
            if (value != null)
              {
                list = json.decode(value.body),
                if (_commands.isEmpty)
                  {
                    list.forEach((element) {
                      _commands.add(element["title"]);
                      _commandsValue.add(element["type"]);
                    }),
                    setState(() {}),
                  }
              }
          });

          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: CustomColor.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.send,
                        color: CustomColor.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'sendCommand'.tr,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _commands.isNotEmpty
                      ? DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      hint: Text('select_command'.tr),
                      value: _commands.isNotEmpty
                          ? _commands[_selectedCommand]
                          : null,
                      items: _commands.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value,
                            style: const TextStyle(fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          if (value == "customCommand".tr) {
                            _dialogCommandHeight = 200.0;
                          } else {
                            _dialogCommandHeight = 150.0;
                          }
                          _commandSelected = value!;
                          _selectedCommand = _commands.indexOf(value);
                        });
                      },
                    ),
                  )
                      : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
                if (_commandSelected == "customCommand".tr)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: TextField(
                      controller: _customCommand,
                      decoration: InputDecoration(
                        labelText: 'commandCustom'.tr,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'cancel'.tr,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CustomColor.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => sendCommand(device),
                      child: Text(
                        'ok'.tr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
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

  void sendCommand(DeviceItem device) async {
    try {
      Map<String, String> requestBody;
      if (_commandSelected == "customCommand".tr) {
        requestBody = <String, String>{
          'id': "",
          'device_id': device.id.toString(),
          'type': _commandsValue[_selectedCommand],
          'data': _customCommand.text
        };
      } else {
        requestBody = <String, String>{
          'id': "",
          'device_id': device.id.toString(),
          'type': _commandsValue[_selectedCommand]
        };
      }

      final res = await APIService.sendCommands(requestBody);

      if (res.statusCode == 200) {
        Fluttertoast.showToast(
          msg: 'command_sent'.tr,
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: const Color(0xFF22C55E),
          textColor: Colors.white,
        );
        Navigator.of(context).pop();
        _checkEngineStatus();
      } else {
        Fluttertoast.showToast(
          msg: 'errorMsg'.tr,
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: const Color(0xFFEF4444),
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Connection error',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: const Color(0xFFEF4444),
        textColor: Colors.white,
      );
    }
  }
}