import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:gpspro/arguments/device_args.dart';
import 'package:gpspro/services/model/command.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/theme/custom_color.dart';

class CommandWindowPage extends StatefulWidget {
  const CommandWindowPage({super.key});

  @override
  State<StatefulWidget> createState() => _CommandPageState();
}

class _CommandPageState extends State<CommandWindowPage> {
  static DeviceArguments? args;

  List<Command> commands = [];
  Timer? _timer;

  @override
  initState() {
    super.initState();
    getCommands();
  }

  void getCommands() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (args != null) {
        _timer!.cancel();
        Iterable list;
        APIService.getSavedCommands(args!.id.toString()).then((value) => {
              {
                list = json.decode(value!.body),
                print(list.length),
                list.forEach((element) {
                  Command command = Command();
                  command.id = element["id"];
                  command.value = element["type"];
                  command.title = element["title"];
                  commands.add(command);
                }),
                setState(() {})
              }
            });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    args = ModalRoute.of(context)!.settings.arguments as DeviceArguments;
    return Scaffold(
        appBar: AppBar(
          // leading: IconButton(
          //   icon: Icon(Icons.close_outlined, color: Colors.white),
          //   onPressed: () => Navigator.of(context).pop(),
          // ),
          title: Text(('recentEvents').tr,
              style: TextStyle(color: CustomColor.secondaryColor)),
        ),
        body: loadCommands());
  }

  Widget loadCommands() {
    var size = MediaQuery.of(context).size;
    final double itemHeight = (size.height - kToolbarHeight - 150) / 5;
    final double itemWidth = size.width / 2;

    return GridView.count(
      // Create a grid with 2 columns. If you change the scrollDirection to
      // horizontal, this produces 2 rows.
      crossAxisCount: 2,
      shrinkWrap: true,
      childAspectRatio: (itemWidth / itemHeight),
      // Generate 100 widgets that display their index in the List.
      children: List.generate(commands.length, (index) {
        return Container(
            height: 30,
            padding: EdgeInsets.all(15),
            child: ElevatedButton(
              onPressed: () {
                sendCommand(commands[index].value);
              },
              child: Text(
                commands[index].title!,
                style: TextStyle(fontSize: 13),
              ),
            ));
      }),
    );

    // children: ListView.builder(
    //   itemCount:
    //   commands.length
    //   ,
    //   itemBuilder: (context, index) {
    //   final device = commands[index];
    //   return Container(
    //   height: 30,
    //   padding: EdgeInsets.all(15),
    //   child: ElevatedButton(
    //   onPressed: () {},
    //   child: Text("Item $index"),
    //   ));
    //   }
    // }));
  }

  void sendCommand(type) {
    Map<String, String> requestBody;

    requestBody = <String, String>{
      'id': "",
      'device_id': args!.id.toString(),
      'type': type
    };


    APIService.sendCommands(requestBody).then((res) => {
          if (res.statusCode == 200)
            {
              Fluttertoast.showToast(
                  msg: ('command_sent').tr,
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.CENTER,
                  timeInSecForIosWeb: 1,
                  backgroundColor: Colors.green,
                  textColor: Colors.white,
                  fontSize: 16.0),
              Navigator.of(context).pop()
            }
          else
            {
              Fluttertoast.showToast(
                  msg: ('errorMsg').tr,
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.CENTER,
                  timeInSecForIosWeb: 1,
                  backgroundColor: Colors.black54,
                  textColor: Colors.white,
                  fontSize: 16.0),
              Navigator.of(context).pop()
            }
        });
  }
}
