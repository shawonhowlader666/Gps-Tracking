import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:gpspro/config.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/services/model/device_item.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/widgets/banner_ad_widget.dart';

class LockUnlockScreen extends StatefulWidget {
  final DeviceItem device;

  const LockUnlockScreen({Key? key, required this.device}) : super(key: key);

  @override
  _LockUnlockScreenState createState() => _LockUnlockScreenState();
}

class _LockUnlockScreenState extends State<LockUnlockScreen> {
  List<String> _commands = <String>[];
  List<String> _commandsValue = <String>[];
  int _selectedCommand = 0;
  String _commandSelected = "";
  double _dialogCommandHeight = 150.0;
  TextEditingController _customCommand = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('lockUnlockDevice'.tr),
        centerTitle: true,
        actions: [
          IconButton(
            icon: m.Icon(Icons.more_vert),
            onPressed: () {
              showCommandDialog(context, widget.device);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'deviceControl'.tr,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                            SizedBox(height: 20),
                            Text(
                              widget.device.name ?? '',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 30),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildControlButton(
                                  context,
                                  icon: Icons.lock_outline,
                                  label: 'lock'.tr.toUpperCase(),
                                  color: Colors.red,
                                  onPressed: () =>
                                      sendEngineCommand('engineStop'),
                                ),
                                _buildControlButton(
                                  context,
                                  icon: Icons.lock_open,
                                  label: 'unlock'.tr.toUpperCase(),
                                  color: Colors.green,
                                  onPressed: () =>
                                      sendEngineCommand('engineResume'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              BannerAdWidget(forceShow: ALWAYS_SHOW_BANNER_ADS),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        SizedBox(
          width: 100,
          height: 100,
          child: ElevatedButton(
            onPressed: _isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              shape: CircleBorder(),
              padding: EdgeInsets.all(20),
            ),
            child: m.Icon(
              icon,
              size: 40,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
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
        Fluttertoast.showToast(
          msg: 'commandSentSuccessfully'.tr,
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.CENTER,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      } else {
        Fluttertoast.showToast(
          msg: 'errorSendingCommand'.tr,
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.CENTER,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'connectionError'.tr,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.CENTER,
        backgroundColor: Colors.red,
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
        borderRadius: BorderRadius.circular(12.0),
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
            height: _dialogCommandHeight,
            width: 300.0,
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: <Widget>[
                Text(
                  'sendCommand'.tr,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _commands.isNotEmpty
                        ? DropdownButton<String>(
                            hint: Text(('select_command').tr),
                            value: _commands.isNotEmpty
                                ? _commands[_selectedCommand]
                                : null,
                            items: _commands.map((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(
                                  value,
                                  style: TextStyle(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                if (value == ("customCommand").tr) {
                                  _dialogCommandHeight = 200.0;
                                } else {
                                  _dialogCommandHeight = 150.0;
                                }
                                _commandSelected = value!;
                                _selectedCommand = _commands.indexOf(value);
                              });
                            },
                          )
                        : CircularProgressIndicator(),
                  ],
                ),
                if (_commandSelected == ("customCommand").tr)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextField(
                      controller: _customCommand,
                      decoration: InputDecoration(
                        labelText: ('commandCustom').tr,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        ('cancel').tr,
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CustomColor.primaryColor,
                      ),
                      onPressed: () => sendCommand(device),
                      child: Text(('ok').tr),
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
      if (_commandSelected == ("customCommand").tr) {
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
          msg: ('command_sent').tr,
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.CENTER,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
        Navigator.of(context).pop();
      } else {
        Fluttertoast.showToast(
          msg: ('errorMsg').tr,
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.CENTER,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Connection error',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.CENTER,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }
}
