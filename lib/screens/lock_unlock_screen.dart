// ignore_for_file: file_names
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/services/model/device_item.dart' hide Icon;

class LockUnlockScreen extends StatefulWidget {
  final DeviceItem device;

  const LockUnlockScreen({Key? key, required this.device}) : super(key: key);

  @override
  _LockUnlockScreenState createState() => _LockUnlockScreenState();
}

class _LockUnlockScreenState extends State<LockUnlockScreen>
    with TickerProviderStateMixin {
  bool _isLocked = true;
  bool _isLoading = false;

  // SOS
  final TextEditingController _sosController = TextEditingController();

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
    ]).animate(CurvedAnimation(parent: _successController, curve: Curves.easeOut));
    _successOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: const Interval(0, 0.4)),
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
    final lockStatus =
    widget.device.deviceData?.lockStatus?.toLowerCase().trim();
    if (lockStatus != null && lockStatus.isNotEmpty) {
      final locked =
          lockStatus == 'locked' || lockStatus == '1' || lockStatus == 'true';
      setState(() => _isLocked = locked);
      return;
    }
    final status = widget.device.engineStatus;
    if (status != null) {
      bool engineOn = false;
      if (status is bool) engineOn = status;
      else if (status is int) engineOn = status == 1;
      else if (status is String) {
        final s = status.toLowerCase().trim();
        engineOn = s == 'on' || s == '1' || s == 'true';
      }
      setState(() => _isLocked = !engineOn);
      return;
    }
    setState(() => _isLocked = true);
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

  Future<void> _sendCommand(String commandType, {required bool lockAfter}) async {
    setState(() => _isLoading = true);
    try {
      final Map<String, String> requestBody = {
        'id': '',
        'device_id': widget.device.id.toString(),
        'type': commandType,
      };
      final res = await APIService.sendCommands(requestBody);
      if (res.statusCode == 200) {
        setState(() => _isLocked = lockAfter);
        _syncStateToDevice();
        await _showSuccessAnimation(lockAfter);
        Fluttertoast.showToast(
          msg: lockAfter ? '🔒 Vehicle locked successfully' : '🔓 Vehicle unlocked successfully',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: lockAfter ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
          textColor: Colors.white,
        );
      } else {
        Fluttertoast.showToast(
          msg: 'Command failed (${res.statusCode}). Please try again.',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: const Color(0xFFEF4444),
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Connection error. Check your network.',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: const Color(0xFFEF4444),
        textColor: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendCustomCommand(String commandType) async {
    setState(() => _isLoading = true);
    try {
      final Map<String, String> requestBody = {
        'id': '',
        'device_id': widget.device.id.toString(),
        'type': commandType,
      };
      final res = await APIService.sendCommands(requestBody);
      Fluttertoast.showToast(
        msg: res.statusCode == 200
            ? '✅ Command "$commandType" sent'
            : 'Command failed (${res.statusCode})',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: res.statusCode == 200
            ? const Color(0xFF22C55E)
            : const Color(0xFFEF4444),
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Connection error.',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: const Color(0xFFEF4444),
        textColor: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendSOS() async {
    final number = _sosController.text.trim();
    if (number.isEmpty) {
      Fluttertoast.showToast(
        msg: 'Please enter an SOS number',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: const Color(0xFFEF4444),
        textColor: Colors.white,
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final Map<String, String> requestBody = {
        'id': '',
        'device_id': widget.device.id.toString(),
        'type': 'sos',
        'data': number,
      };
      final res = await APIService.sendCommands(requestBody);
      Fluttertoast.showToast(
        msg: res.statusCode == 200
            ? '🆘 SOS number set successfully'
            : 'Failed to set SOS number',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: res.statusCode == 200
            ? const Color(0xFF22C55E)
            : const Color(0xFFEF4444),
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Connection error.',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: const Color(0xFFEF4444),
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
        backgroundColor: const Color(0xFFF0F0F0),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          title: const Text(
            'Lock Screen',
            style: TextStyle(
              color: Color(0xFF1E293B),
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const m.Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
            onPressed: _goBack,
          ),
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 32),

                  // ── SOS Section ──
                  const Text(
                    'SOS Number',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFD1D5DB)),
                    ),
                    child: TextField(
                      controller: _sosController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: 'Enter SOS Number',
                        hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                        border: InputBorder.none,
                        contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _sendSOS,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE53935),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Add',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Custom Command ──
                  const Text(
                    'Custom Command',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildCustomCmdBtn('ACCALM', 'accalm'),
                      const SizedBox(width: 10),
                      _buildCustomCmdBtn('GMT', 'gmt'),
                      const SizedBox(width: 10),
                      _buildCustomCmdBtn('RESET', 'reset'),
                    ],
                  ),
                  const SizedBox(height: 32),

                  _buildLockUnlockButtons(),
                ],
              ),
            ),

            // ── Loading overlay ──
            if (_isLoading) _buildLoadingOverlay(),

            // ── Success animation overlay ──
            if (_showSuccessAnim) _buildSuccessOverlay(),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Circular Lock / Unlock Buttons
  // ──────────────────────────────────────────────────────────────
  Widget _buildLockUnlockButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // LOCK BUTTON
        GestureDetector(
          onTap: _isLoading
              ? null
              : () => _sendCommand('engineStop', lockAfter: true),
          child: Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE53935),
              border: Border.all(color: Colors.white),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 4,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock,
                  color: Colors.white,
                  size: 32,
                ),
                SizedBox(height: 4),
                Text(
                  'Lock',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 32),

        // UNLOCK BUTTON
        GestureDetector(
          onTap: _isLoading
              ? null
              : () => _sendCommand('engineResume', lockAfter: false),
          child: Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green,
              border: Border.all(color: Colors.white),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 4,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_open,
                  color: Colors.white,
                  size: 32,
                ),
                SizedBox(height: 4),
                Text(
                  'Unlock',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Custom command chip button
  // ──────────────────────────────────────────────────────────────
  Widget _buildCustomCmdBtn(String label, String commandType) {
    return Expanded(
      child: GestureDetector(
        onTap: _isLoading ? null : () => _sendCustomCommand(commandType),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFE53935),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Loading overlay
  // ──────────────────────────────────────────────────────────────
  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.40),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFFE53935),
              ),
              const SizedBox(height: 16),
              Text(
                'Sending command...',
                style: TextStyle(
                    color: Colors.grey[800],
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Success animation overlay
  // ──────────────────────────────────────────────────────────────
  Widget _buildSuccessOverlay() {
    final color = _lastActionWasLock
        ? const Color(0xFFEF4444)
        : const Color(0xFF22C55E);
    final icon = _lastActionWasLock ? Icons.lock : Icons.lock_open;
    final label = _lastActionWasLock ? 'Locked!' : 'Unlocked!';

    return AnimatedBuilder(
      animation: _successController,
      builder: (context, child) {
        return Container(
          color: Colors.black.withOpacity(0.35 * _successOpacity.value),
          child: Center(
            child: Transform.scale(
              scale: _successScale.value,
              child: Opacity(
                opacity: _successOpacity.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.3),
                        blurRadius: 24,
                        spreadRadius: 4,
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withOpacity(0.12),
                          border: Border.all(color: color, width: 2.5),
                        ),
                        child: m.Icon(icon, color: color, size: 38),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 20,
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