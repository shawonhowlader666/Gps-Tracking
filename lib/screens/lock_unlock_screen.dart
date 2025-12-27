import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:gpspro/config.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/services/model/device_item.dart' hide Icon;
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/widgets/banner_ad_widget.dart';

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
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _checkEngineStatus();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _customCommand.dispose();
    _animationController.dispose();
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
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          'Engine Control',
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF64748B)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const m.Icon(Icons.settings, color: Color(0xFF64748B)),
            onPressed: () => showCommandDialog(context, widget.device),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Vehicle Name
                          Text(
                            widget.device.name ?? 'Unknown Device',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                            textAlign: TextAlign.center,
                          ),

                          if (widget.device.deviceData?.plateNumber != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              widget.device.deviceData!.plateNumber!,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],

                          const SizedBox(height: 60),

                          // Engine Status Text
                          Text(
                            'ENGINE STATUS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[500],
                              letterSpacing: 2,
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Status Indicator
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: _isEngineOn
                                  ? const Color(0xFF22C55E).withOpacity(0.1)
                                  : const Color(0xFFEF4444).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _isEngineOn
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFFEF4444),
                                width: 2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _isEngineOn
                                        ? const Color(0xFF22C55E)
                                        : const Color(0xFFEF4444),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (_isEngineOn
                                            ? const Color(0xFF22C55E)
                                            : const Color(0xFFEF4444))
                                            .withOpacity(0.6),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _isEngineOn ? 'UNLOCKED' : 'LOCKED',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: _isEngineOn
                                        ? const Color(0xFF22C55E)
                                        : const Color(0xFFEF4444),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 80),

                          // Analog Button
                          _buildAnalogButton(),

                          const SizedBox(height: 40),

                          // Info Text
                          Text(
                            _isEngineOn
                                ? 'Tap to lock engine'
                                : 'Tap to unlock engine',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
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
    );
  }

  Widget _buildAnalogButton() {
    final isOn = _isEngineOn;
    final buttonColor = isOn ? const Color(0xFFEF4444) : const Color(0xFF22C55E);
    final buttonText = isOn ? 'OFF' : 'ON';

    return GestureDetector(
      onTapDown: (_) => _animationController.forward(),
      onTapUp: (_) {
        _animationController.reverse();
        if (!_isLoading) {
          _toggleEngine();
        }
      },
      onTapCancel: () => _animationController.reverse(),
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          final scale = 1.0 - (_animationController.value * 0.05);
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1E293B),
                    const Color(0xFF0F172A),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 30,
                    offset: Offset(0, _animationController.value * 10 + 15),
                    spreadRadius: -5,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF334155),
                        const Color(0xFF1E293B),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 10,
                        offset: const Offset(5, 5),
                        spreadRadius: -5,
                      ),
                      BoxShadow(
                        color: Colors.white.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(-5, -5),
                        spreadRadius: -5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: buttonColor,
                        boxShadow: [
                          BoxShadow(
                            color: buttonColor.withOpacity(0.7),
                            blurRadius: 40,
                            spreadRadius: 5,
                          ),
                          BoxShadow(
                            color: buttonColor.withOpacity(0.4),
                            blurRadius: 60,
                            spreadRadius: 15,
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Shine effect
                          Positioned(
                            top: 15,
                            left: 15,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.4),
                                    Colors.white.withOpacity(0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Text
                          Center(
                            child: Text(
                              buttonText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 3,
                                shadows: [
                                  Shadow(
                                    color: Colors.black26,
                                    offset: Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                strokeWidth: 3,
              ),
              const SizedBox(height: 20),
              Text(
                'Sending command...',
                style: TextStyle(
                  color: Colors.grey[800],
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleEngine() {
    final commandType = _isEngineOn ? 'engineStop' : 'engineResume';
    sendEngineCommand(commandType);
  }

  void sendEngineCommand(String commandType) async {
    setState(() => _isLoading = true);

    try {
      Map<String, String> requestBody = <String, String>{
        'id': "",
        'device_id': widget.device.id.toString(),
        'type': commandType
      };

      final res = await APIService.sendCommands(requestBody);

      if (res.statusCode == 200) {
        setState(() {
          _isEngineOn = commandType == 'engineResume';
        });

        Fluttertoast.showToast(
          msg: commandType == 'engineStop'
              ? 'Engine locked successfully'
              : 'Engine unlocked successfully',
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
            constraints: BoxConstraints(
              maxHeight: _dialogCommandHeight + 50,
            ),
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
                        color: const Color(0xFF2563EB).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.send,
                        color: Color(0xFF2563EB),
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
                        backgroundColor: const Color(0xFF2563EB),
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