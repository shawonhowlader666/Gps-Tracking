import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:smart_lock/config.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;

class LockUnlockScreen extends StatefulWidget {
  final DeviceItem device;
  const LockUnlockScreen({Key? key, required this.device}) : super(key: key);

  @override
  _LockUnlockScreenState createState() => _LockUnlockScreenState();
}

class _LockUnlockScreenState extends State<LockUnlockScreen>
    with SingleTickerProviderStateMixin {
  List<String> _commands = <String>[];
  List<String> _commandsValue = <String>[];
  int _selectedCommand = 0;
  String _commandSelected = "";
  double _dialogCommandHeight = 150.0;
  TextEditingController _customCommand = TextEditingController();
  bool _isLoading = false;
  bool _isEngineOn = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _checkEngineStatus();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _customCommand.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _checkEngineStatus() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          widget.device.name ?? 'Engine Control',
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF64748B), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const m.Icon(Icons.tune_rounded, color: Color(0xFF64748B)),
            onPressed: () => showCommandDialog(context, widget.device),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  // ── Status Card ──
                  _buildStatusCard(),
                  const SizedBox(height: 40),

                  // ── Vehicle Icon ──
                  _buildVehicleIcon(),
                  const SizedBox(height: 48),

                  // ── Lock / Unlock Buttons ──
                  _buildActionButtons(),
                  const SizedBox(height: 24),

                  // ── Hint ──
                  Text(
                    'Use the buttons above to control engine remotely',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  // ── Status Card ──
  Widget _buildStatusCard() {
    final isOn = _isEngineOn;
    final statusColor = isOn ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final statusText = isOn ? 'UNLOCKED' : 'LOCKED';
    final statusIcon = isOn ? Icons.lock_open_rounded : Icons.lock_rounded;
    final statusBg = isOn
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFFFE4E4);

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isLoading ? 1.0 : _pulseAnimation.value,
          child: child,
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color: statusColor.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Column(
          children: [
            // Icon circle
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: statusBg,
                shape: BoxShape.circle,
              ),
              child: m.Icon(
                statusIcon,
                color: statusColor,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),

            // Status label
            Text(
              'ENGINE STATUS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey[400],
                letterSpacing: 2.5,
              ),
            ),
            const SizedBox(height: 8),

            // Status value
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: child,
              ),
              child: Text(
                statusText,
                key: ValueKey(statusText),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: statusColor,
                  letterSpacing: 3,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Status pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isOn ? 'Engine Running' : 'Engine Stopped',
                    style: TextStyle(
                      fontSize: 13,
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Vehicle Icon ──
  Widget _buildVehicleIcon() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: m.Icon(
        Icons.directions_car_rounded,
        size: 52,
        color: _isEngineOn
            ? const Color(0xFF22C55E)
            : const Color(0xFF94A3B8),
      ),
    );
  }

  // ── Two Action Buttons ──
  Widget _buildActionButtons() {
    return Row(
      children: [
        // LOCK Button
        Expanded(
          child: _buildControlButton(
            label: 'LOCK',
            icon: Icons.lock_rounded,
            color: const Color(0xFFEF4444),
            isActive: !_isEngineOn,
            onTap: _isLoading
                ? null
                : () {
              if (_isEngineOn) {
                _showConfirmDialog(
                  title: 'Lock Engine',
                  message:
                  'Are you sure you want to lock the engine?',
                  icon: Icons.lock_rounded,
                  color: const Color(0xFFEF4444),
                  onConfirm: () => sendEngineCommand('engineStop'),
                );
              } else {
                Fluttertoast.showToast(
                  msg: 'Engine is already locked',
                  backgroundColor: Colors.grey[700],
                  textColor: Colors.white,
                );
              }
            },
          ),
        ),
        const SizedBox(width: 16),

        // UNLOCK Button
        Expanded(
          child: _buildControlButton(
            label: 'UNLOCK',
            icon: Icons.lock_open_rounded,
            color: const Color(0xFF22C55E),
            isActive: _isEngineOn,
            onTap: _isLoading
                ? null
                : () {
              if (!_isEngineOn) {
                _showConfirmDialog(
                  title: 'Unlock Engine',
                  message:
                  'Are you sure you want to unlock the engine?',
                  icon: Icons.lock_open_rounded,
                  color: const Color(0xFF22C55E),
                  onConfirm: () => sendEngineCommand('engineResume'),
                );
              } else {
                Fluttertoast.showToast(
                  msg: 'Engine is already unlocked',
                  backgroundColor: Colors.grey[700],
                  textColor: Colors.white,
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isActive,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: isActive ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? color : color.withValues(alpha: 0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? color.withValues(alpha: 0.35)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: isActive ? 20 : 8,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            m.Icon(
              icon,
              size: 40,
              color: isActive ? Colors.white : color,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isActive ? Colors.white : color,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isActive ? 'Active' : 'Tap to activate',
              style: TextStyle(
                fontSize: 11,
                color: isActive
                    ? Colors.white.withValues(alpha: 0.8)
                    : Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Confirm Dialog ──
  void _showConfirmDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: m.Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Cancel',
                        style: TextStyle(color: Colors.grey[700])),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onConfirm();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Confirm',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(strokeWidth: 3),
              const SizedBox(height: 16),
              Text(
                'Sending command...',
                style: TextStyle(
                    color: Colors.grey[800],
                    fontSize: 15,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void sendEngineCommand(String commandType) async {
    setState(() => _isLoading = true);
    try {
      Map<String, String> requestBody = {
        'id': "",
        'device_id': widget.device.id.toString(),
        'type': commandType,
      };
      final res = await APIService.sendCommands(requestBody);
      if (res.statusCode == 200) {
        setState(() => _isEngineOn = commandType == 'engineResume');
        Fluttertoast.showToast(
          msg: commandType == 'engineStop'
              ? '🔒 Engine locked successfully'
              : '🔓 Engine unlocked successfully',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: commandType == 'engineStop'
              ? const Color(0xFFEF4444)
              : const Color(0xFF22C55E),
          textColor: Colors.white,
        );
      } else {
        Fluttertoast.showToast(
          msg: 'Failed to send command',
          backgroundColor: const Color(0xFFEF4444),
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Connection error',
        backgroundColor: const Color(0xFFEF4444),
        textColor: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Keep your existing showCommandDialog and sendCommand methods unchanged
  void showCommandDialog(BuildContext context, DeviceItem device) {
    _commands.clear();
    _commandsValue.clear();
    Dialog simpleDialog = Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75, // ✅ responsive
            ),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withOpacity(0.1), // fix API
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.send,
                            color: Color(0xFF2563EB), size: 20),
                      ),
                      const SizedBox(width: 12),

                      /// ✅ FIX overflow here
                      Expanded(
                        child: Text(
                          'sendCommand'.tr,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  /// 🔽 Dropdown
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

                        /// ✅ safe value
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
                            _commandSelected = value!;
                            _selectedCommand = _commands.indexOf(value);

                            /// ❌ REMOVE THIS (no need anymore)
                            // _dialogCommandHeight = ...
                          });
                        },
                      ),
                    )
                        : const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),

                  /// 🔽 Custom Field
                  if (_commandSelected == "customCommand".tr)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: TextField(
                        controller: _customCommand,
                        maxLines: 3, // ✅ prevents overflow
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

                  /// 🔽 Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            'cancel'.tr,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
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
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    showDialog(
        context: context,
        builder: (BuildContext context) => simpleDialog);
  }

  void sendCommand(DeviceItem device) async {
    try {
      Map<String, String> requestBody;
      if (_commandSelected == "customCommand".tr) {
        requestBody = {
          'id': "",
          'device_id': device.id.toString(),
          'type': _commandsValue[_selectedCommand],
          'data': _customCommand.text,
        };
      } else {
        requestBody = {
          'id': "",
          'device_id': device.id.toString(),
          'type': _commandsValue[_selectedCommand],
        };
      }
      final res = await APIService.sendCommands(requestBody);
      if (res.statusCode == 200) {
        Fluttertoast.showToast(
          msg: 'command_sent'.tr,
          backgroundColor: const Color(0xFF22C55E),
          textColor: Colors.white,
        );
        Navigator.of(context).pop();
        _checkEngineStatus();
      } else {
        Fluttertoast.showToast(
          msg: 'errorMsg'.tr,
          backgroundColor: const Color(0xFFEF4444),
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Connection error',
        backgroundColor: const Color(0xFFEF4444),
        textColor: Colors.white,
      );
    }
  }
}