import 'package:smart_lock/services/model/command.dart';

class GetCommands extends Object {
  Map<String, Command>? commands;

  GetCommands({this.commands});

  GetCommands.fromJson(Map<String, dynamic> json) {
    commands = json["commands"];
  }
}
