// import 'dart:async';
// import 'dart:convert';
//
// import 'package:flutter/material.dart';
// import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
// import 'package:fluttertoast/fluttertoast.dart';
// import 'package:get/get.dart';
// import 'package:smart_lock/arguments/device_args.dart';
// import 'package:smart_lock/arguments/report_args.dart';
// import 'package:smart_lock/services/model/command_list.dart';
// import 'package:smart_lock/services/model/user.dart';
// import 'package:smart_lock/screens/common_method.dart';
// import 'package:smart_lock/services/api_service.dart';
// import 'package:smart_lock/theme/custom_color.dart';
// import 'package:shared_preferences/shared_preferences.dart';
//
// class DeviceDashboard extends StatefulWidget {
//   @override
//   _DeviceDashboardState createState() => _DeviceDashboardState();
// }
//
// class _DeviceDashboardState extends State<DeviceDashboard> {
//   static DeviceArguments? args;
//   final TextEditingController _customCommand = new TextEditingController();
//   List<String> _commands = <String>[];
//   List<String> _commandsValue = <String>[];
//   int _selectedCommand = 0;
//   String _commandSelected = "";
//   int _selectedperiod = 0;
//   double _dialogHeight = 300.0;
//   double _dialogCommandHeight = 150.0;
//
//   DateTime _selectedFromDate = DateTime.now();
//   DateTime _selectedToDate = DateTime.now();
//   TimeOfDay _selectedFromTime = TimeOfDay.now();
//   TimeOfDay _selectedToTime = TimeOfDay.now();
//   SharedPreferences? prefs;
//   User? user;
//
//   Material Items(IconData icon, String heading, Color cColor) {
//     return Material(
//         color: Colors.white,
//         elevation: 14.0,
//         shadowColor: CustomColor.primaryColor,
//         borderRadius: BorderRadius.circular(24.0),
//         child: InkWell(
//           onTap: () {
//             if (heading == ('send_command').tr) {
//               //showCommandDialog(context);
//               showSavedCommandDialog(context);
//             } else if (heading == ('alarmGeofence').tr) {
//               Navigator.pushNamed(context, "/geofenceList",
//                   arguments: ReportArguments(
//                       args!.id, "", "", "", "", "", 0, args!.device));
//             } else if (heading == ('report').tr || heading == ('playback').tr) {
//               showReportDialog(context, heading);
//             } else if (heading == "Send Commands") {
//               showSavedCommandDialog(context);
//             }
//             //Navigator.pushNamed(context, "/deviceDashboard", arguments: DeviceArguments(device.id, device.name));
//           },
//           child: Center(
//             child: Padding(
//               padding: const EdgeInsets.all(8.0),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: <Widget>[
//                   Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: <Widget>[
//                       Expanded(
//                         child: Container(
//                           width: 140,
//                           padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
//                           child: Text(
//                             heading,
//                             softWrap: true,
//                             overflow: TextOverflow.ellipsis,
//                             maxLines: 2,
//                             textAlign: TextAlign.center,
//                             style: TextStyle(
//                               color: cColor,
//                               fontSize: 15.0,
//                             ),
//                           ),
//                         ),
//                       ),
//                       Material(
//                         color: cColor,
//                         borderRadius: BorderRadius.circular(24.0),
//                         child: Padding(
//                           padding: const EdgeInsets.all(15.0),
//                           child: Icon(
//                             icon,
//                             color: Colors.white,
//                             size: 30.0,
//                           ),
//                         ),
//                       )
//                     ],
//                   )
//                 ],
//               ),
//             ),
//           ),
//         ));
//   }
//
//   @override
//   void initState() {
//     checkPreference();
//     super.initState();
//   }
//
//   void checkPreference() async {
//     prefs = await SharedPreferences.getInstance();
//     String userJson = prefs!.getString("user")!;
//     final parsed = json.decode(userJson);
//     user = User.fromJson(parsed);
//     getCommands();
//     setState(() {});
//   }
//
//   void getCommands() {}
//
//   @override
//   Widget build(BuildContext context) {
//     args = ModalRoute.of(context)!.settings.arguments as DeviceArguments;
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(('device_dashboard').tr,
//             style: TextStyle(color: CustomColor.secondaryColor)),
//         iconTheme: IconThemeData(
//           color: CustomColor.secondaryColor, //change your color here
//         ),
//       ),
//       body: StaggeredGrid.count(
//         crossAxisCount: 2,
//         crossAxisSpacing: 12.0,
//         mainAxisSpacing: 12.0,
//         children: <Widget>[
//           Items(Icons.timeline, ('playback').tr, CustomColor.primaryColor),
//           Items(Icons.fence, ('alarmGeofence').tr, CustomColor.primaryColor),
//           Items(Icons.assessment, ('report').tr, CustomColor.primaryColor),
//           // Items(
//           //     Icons.send,
//           //     AppLocalizations.of(context)!.translate('send_command'),
//           //     CustomColor.primaryColor),
//           Items(Icons.send, ('send_command').tr, CustomColor.primaryColor)
//         ],
//       ),
//     );
//   }
//
//   void showReportDialog(BuildContext context, String heading) {
//     Dialog simpleDialog = Dialog(
//       shape: RoundedRectangleBorder(
//         borderRadius: BorderRadius.circular(12.0),
//       ),
//       child: StatefulBuilder(
//         builder: (BuildContext context, StateSetter setState) {
//           return new Container(
//             height: _dialogHeight,
//             width: 300.0,
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.start,
//               children: <Widget>[
//                 Column(
//                   children: <Widget>[
//                     Padding(
//                       padding:
//                           const EdgeInsets.only(left: 10, right: 10, top: 20),
//                       child: Column(
//                         mainAxisAlignment: MainAxisAlignment.start,
//                         crossAxisAlignment: CrossAxisAlignment.end,
//                         children: <Widget>[
//                           new Row(
//                             mainAxisAlignment: MainAxisAlignment.start,
//                             children: <Widget>[
//                               new Radio(
//                                 value: 0,
//                                 groupValue: _selectedperiod,
//                                 onChanged: (value) {
//                                   setState(() {
//                                     _selectedperiod =
//                                         int.parse(value.toString());
//                                     _dialogHeight = 300.0;
//                                   });
//                                 },
//                               ),
//                               new Text(
//                                 ('reportToday').tr,
//                                 style: new TextStyle(fontSize: 16.0),
//                               ),
//                             ],
//                           ),
//                           new Row(
//                             mainAxisAlignment: MainAxisAlignment.start,
//                             children: <Widget>[
//                               new Radio(
//                                 value: 1,
//                                 groupValue: _selectedperiod,
//                                 onChanged: (value) {
//                                   setState(() {
//                                     _selectedperiod =
//                                         int.parse(value.toString());
//                                     _dialogHeight = 300.0;
//                                   });
//                                 },
//                               ),
//                               new Text(
//                                 ('reportYesterday').tr,
//                                 style: new TextStyle(fontSize: 16.0),
//                               ),
//                             ],
//                           ),
//                           new Row(
//                             mainAxisAlignment: MainAxisAlignment.start,
//                             children: <Widget>[
//                               new Radio(
//                                 value: 2,
//                                 groupValue: _selectedperiod,
//                                 onChanged: (value) {
//                                   setState(() {
//                                     _selectedperiod =
//                                         int.parse(value.toString());
//                                     _dialogHeight = 300.0;
//                                   });
//                                 },
//                               ),
//                               new Text(
//                                 ('reportThisWeek').tr,
//                                 style: new TextStyle(fontSize: 16.0),
//                               ),
//                             ],
//                           ),
//                           new Row(
//                             mainAxisAlignment: MainAxisAlignment.start,
//                             children: <Widget>[
//                               new Radio(
//                                 value: 3,
//                                 groupValue: _selectedperiod,
//                                 onChanged: (value) {
//                                   setState(() {
//                                     _dialogHeight = 400.0;
//                                     _selectedperiod =
//                                         int.parse(value.toString());
//                                   });
//                                 },
//                               ),
//                               new Text(
//                                 ('reportCustom').tr,
//                                 style: new TextStyle(fontSize: 16.0),
//                               ),
//                             ],
//                           ),
//                           _selectedperiod == 3
//                               ? new Container(
//                                   child: new Column(
//                                   children: <Widget>[
//                                     Row(
//                                       mainAxisAlignment:
//                                           MainAxisAlignment.spaceBetween,
//                                       children: <Widget>[
//                                         ElevatedButton(
//                                           style: ElevatedButton.styleFrom(
//                                             backgroundColor:
//                                                 CustomColor.primaryColor,
//                                           ),
//                                           onPressed: () => _selectFromDate(
//                                               context, setState),
//                                           child: Text(
//                                               formatReportDate(
//                                                   _selectedFromDate),
//                                               style: TextStyle(
//                                                   color: Colors.white)),
//                                         ),
//                                         ElevatedButton(
//                                           style: ElevatedButton.styleFrom(
//                                             backgroundColor:
//                                                 CustomColor.primaryColor,
//                                           ),
//                                           onPressed: () => _selectFromTime(
//                                               context, setState),
//                                           child: Text(
//                                               formatReportTime(
//                                                   _selectedFromTime),
//                                               style: TextStyle(
//                                                   color: Colors.white)),
//                                         ),
//                                       ],
//                                     ),
//                                     Row(
//                                       mainAxisAlignment:
//                                           MainAxisAlignment.spaceBetween,
//                                       children: <Widget>[
//                                         ElevatedButton(
//                                           style: ElevatedButton.styleFrom(
//                                             backgroundColor:
//                                                 CustomColor.primaryColor,
//                                           ),
//                                           onPressed: () =>
//                                               _selectToDate(context, setState),
//                                           child: Text(
//                                               formatReportDate(_selectedToDate),
//                                               style: TextStyle(
//                                                   color: Colors.white)),
//                                         ),
//                                         ElevatedButton(
//                                           style: ElevatedButton.styleFrom(
//                                             backgroundColor:
//                                                 CustomColor.primaryColor,
//                                           ),
//                                           onPressed: () =>
//                                               _selectToTime(context, setState),
//                                           child: Text(
//                                               formatReportTime(_selectedToTime),
//                                               style: TextStyle(
//                                                   color: Colors.white)),
//                                         ),
//                                       ],
//                                     )
//                                   ],
//                                 ))
//                               : new Container(),
//                           new Row(
//                             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                             children: <Widget>[
//                               ElevatedButton(
//                                 style: ElevatedButton.styleFrom(
//                                     backgroundColor: Colors.red),
//                                 onPressed: () {
//                                   Navigator.of(context).pop();
//                                 },
//                                 child: Text(
//                                   ('cancel').tr,
//                                   style: TextStyle(
//                                       fontSize: 18.0, color: Colors.white),
//                                 ),
//                               ),
//                               SizedBox(
//                                 width: 20,
//                               ),
//                               ElevatedButton(
//                                 style: ElevatedButton.styleFrom(
//                                   backgroundColor: CustomColor.primaryColor,
//                                 ),
//                                 onPressed: () {
//                                   showReport(heading);
//                                 },
//                                 child: Text(
//                                   ('ok').tr,
//                                   style: TextStyle(
//                                       fontSize: 18.0, color: Colors.white),
//                                 ),
//                               ),
//                             ],
//                           )
//                         ],
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           );
//         },
//       ),
//     );
//     showDialog(
//         context: context, builder: (BuildContext context) => simpleDialog);
//   }
//
//   Future<void> _selectFromDate(
//       BuildContext context, StateSetter setState) async {
//     final DateTime? picked = await showDatePicker(
//         context: context,
//         initialDate: _selectedFromDate,
//         firstDate: DateTime(2015, 8),
//         lastDate: DateTime(2101));
//     if (picked != null && picked != _selectedFromDate)
//       setState(() {
//         _selectedFromDate = picked;
//       });
//   }
//
//   Future<void> _selectToDate(BuildContext context, StateSetter setState) async {
//     final DateTime? picked = await showDatePicker(
//         context: context,
//         initialDate: _selectedToDate,
//         firstDate: DateTime(2015, 8),
//         lastDate: DateTime(2101));
//     if (picked != null && picked != _selectedToDate)
//       setState(() {
//         _selectedToDate = picked;
//       });
//   }
//
//   Future<void> _selectFromTime(
//       BuildContext context, StateSetter setState) async {
//     final TimeOfDay? picked = await showTimePicker(
//       context: context,
//       initialTime: TimeOfDay.now(),
//       builder: (BuildContext context, Widget? child) {
//         return Directionality(
//           textDirection: TextDirection.rtl,
//           child: child != null ? child : new Container(),
//         );
//       },
//     );
//     if (picked != null && picked != _selectedFromTime)
//       setState(() {
//         _selectedFromTime = picked;
//       });
//   }
//
//   Future<void> _selectToTime(BuildContext context, setState) async {
//     final TimeOfDay? picked = await showTimePicker(
//       context: context,
//       initialTime: TimeOfDay.now(),
//       builder: (BuildContext context, Widget? child) {
//         return Directionality(
//           textDirection: TextDirection.rtl,
//           child: child != null ? child : new Container(),
//         );
//       },
//     );
//     if (picked != null && picked != _selectedToTime)
//       setState(() {
//         _selectedToTime = picked;
//       });
//   }
//
//   void showCommandDialog(BuildContext context) {
//     _commands.clear();
//     _commandsValue.clear();
//     Dialog simpleDialog = Dialog(
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(12.0),
//         ),
//         child: StatefulBuilder(
//             builder: (BuildContext context, StateSetter setState) {
//           List<Commands> list;
//           APIService.getSendCommands(args!.id.toString()).then((value) => {
//                 if (value != null)
//                   {
//                     list = json.decode(value.body)["commands"],
//                     if (_commands.length == 0)
//                       {
//                         list.forEach((element) {
//                           _commands.add(element.title!);
//                           _commandsValue.add(element.id!);
//                         }),
//                         setState(() {}),
//                       }
//                   },
//               });
//
//           return Container(
//             height: _dialogCommandHeight,
//             width: 300.0,
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.start,
//               children: <Widget>[
//                 Column(
//                   children: <Widget>[
//                     Padding(
//                       padding:
//                           const EdgeInsets.only(left: 10, right: 10, top: 20),
//                       child: Column(
//                         mainAxisAlignment: MainAxisAlignment.start,
//                         crossAxisAlignment: CrossAxisAlignment.end,
//                         children: <Widget>[
//                           new Row(
//                             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                             children: <Widget>[
//                               new Text(('commandTitle').tr),
//                             ],
//                           ),
//                           new Row(
//                               mainAxisAlignment: MainAxisAlignment.center,
//                               children: <Widget>[
//                                 _commands.length > 0
//                                     ? new DropdownButton<String>(
//                                         hint: new Text(('select_command').tr),
//                                         value: _commands[_selectedCommand],
//                                         items: _commands.map((String value) {
//                                           return new DropdownMenuItem<String>(
//                                             value: value,
//                                             child: new Text(
//                                               (value).tr,
//                                               style: TextStyle(),
//                                               overflow: TextOverflow.ellipsis,
//                                             ),
//                                           );
//                                         }).toList(),
//                                         onChanged: (value) {
//                                           print(value);
//                                           setState(() {
//                                             if (value == "Custom Command") {
//                                               _dialogCommandHeight = 200.0;
//                                             } else {
//                                               _dialogCommandHeight = 150.0;
//                                             }
//                                             _commandSelected = value!;
//                                             _selectedCommand =
//                                                 _commands.indexOf(value);
//                                             print(_selectedCommand);
//                                           });
//                                         },
//                                       )
//                                     : new CircularProgressIndicator(),
//                               ]),
//                           _commandSelected == "Custom Command"
//                               ? new Container(
//                                   child: new TextField(
//                                     controller: _customCommand,
//                                     decoration: new InputDecoration(
//                                         labelText: ('commandCustom').tr),
//                                   ),
//                                 )
//                               : new Container(),
//                           new Row(
//                             mainAxisAlignment: MainAxisAlignment.center,
//                             children: <Widget>[
//                               ElevatedButton(
//                                 style: ElevatedButton.styleFrom(
//                                     backgroundColor: Colors.red),
//                                 onPressed: () {
//                                   Navigator.of(context).pop();
//                                 },
//                                 child: Text(
//                                   ('cancel').tr,
//                                   style: TextStyle(
//                                       fontSize: 18.0, color: Colors.white),
//                                 ),
//                               ),
//                               SizedBox(
//                                 width: 20,
//                               ),
//                               ElevatedButton(
//                                 style: ElevatedButton.styleFrom(
//                                   backgroundColor: CustomColor.primaryColor,
//                                 ),
//                                 onPressed: () {
//                                   sendCommand();
//                                 },
//                                 child: Text(
//                                   ('ok').tr,
//                                   style: TextStyle(
//                                       fontSize: 18.0, color: Colors.white),
//                                 ),
//                               ),
//                             ],
//                           )
//                         ],
//                       ),
//                     ),
//                   ],
//                 )
//               ],
//             ),
//           );
//         }));
//     showDialog(
//         context: context, builder: (BuildContext context) => simpleDialog);
//   }
//
//   void showSavedCommandDialog(BuildContext context) {
//     _commands.clear();
//     _commandsValue.clear();
//     Dialog simpleDialog = Dialog(
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(12.0),
//         ),
//         child: StatefulBuilder(
//             builder: (BuildContext context, StateSetter setState) {
//           Iterable list;
//           APIService.getSavedCommands(args!.id.toString()).then((value) => {
//                 {
//                   list = json.decode(value!.body),
//                   if (_commands.length == 0)
//                     {
//                       list.forEach((element) {
//                         _commands.add(element["title"]);
//                         _commandsValue.add(element["type"]);
//                       }),
//                       setState(() {}),
//                     }
//                   else
//                     {
//                       // Fluttertoast.showToast(
//                       //     msg: AppLocalizations.of(context)
//                       //         .translate("noData"),
//                       //     toastLength: Toast.LENGTH_SHORT,
//                       //     gravity: ToastGravity.CENTER,
//                       //     timeInSecForIosWeb: 1,
//                       //     backgroundColor: Colors.black54,
//                       //     textColor: Colors.white,
//                       //     fontSize: 16.0),
//                       // Navigator.pop(context)
//                     }
//                 }
//               });
//
//           return Container(
//             height: _dialogCommandHeight,
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.start,
//               children: <Widget>[
//                 Column(
//                   children: <Widget>[
//                     Padding(
//                       padding:
//                           const EdgeInsets.only(left: 10, right: 10, top: 20),
//                       child: Column(
//                         mainAxisAlignment: MainAxisAlignment.start,
//                         crossAxisAlignment: CrossAxisAlignment.end,
//                         children: <Widget>[
//                           new Row(
//                             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                             children: <Widget>[
//                               new Text(('commandTitle').tr),
//                             ],
//                           ),
//                           new Row(
//                               mainAxisAlignment: MainAxisAlignment.center,
//                               children: <Widget>[
//                                 _commands.length > 0
//                                     ? new DropdownButton<String>(
//                                         hint: new Text(('select_command').tr),
//                                         value: _commands[_selectedCommand],
//                                         items: _commands.map((String value) {
//                                           return new DropdownMenuItem<String>(
//                                             value: value,
//                                             child: new Text(
//                                               (value).tr,
//                                               style: TextStyle(fontSize: 12),
//                                               maxLines: 2,
//                                               softWrap: true,
//                                               overflow: TextOverflow.ellipsis,
//                                             ),
//                                           );
//                                         }).toList(),
//                                         onChanged: (value) {
//                                           setState(() {
//                                             print(value);
//                                             if (value == "Custom Command") {
//                                               _dialogCommandHeight = 200.0;
//                                             } else {
//                                               _dialogCommandHeight = 150.0;
//                                             }
//                                             _commandSelected = value!;
//                                             _selectedCommand =
//                                                 _commands.indexOf(value);
//                                           });
//                                         },
//                                       )
//                                     : new CircularProgressIndicator(),
//                               ]),
//                           _commandSelected == "Custom Command"
//                               ? new Container(
//                                   child: new TextField(
//                                     controller: _customCommand,
//                                     decoration: new InputDecoration(
//                                         labelText: ('commandCustom').tr),
//                                   ),
//                                 )
//                               : new Container(),
//                           new Row(
//                             mainAxisAlignment: MainAxisAlignment.center,
//                             children: <Widget>[
//                               ElevatedButton(
//                                 style: ElevatedButton.styleFrom(
//                                     backgroundColor: Colors.red),
//                                 onPressed: () {
//                                   Navigator.of(context).pop();
//                                 },
//                                 child: Text(
//                                   ('cancel').tr,
//                                   style: TextStyle(
//                                       fontSize: 18.0, color: Colors.white),
//                                 ),
//                               ),
//                               SizedBox(
//                                 width: 20,
//                               ),
//                               ElevatedButton(
//                                 style: ElevatedButton.styleFrom(
//                                   backgroundColor: CustomColor.primaryColor,
//                                 ),
//                                 onPressed: () {
//                                   sendCommand();
//                                 },
//                                 child: Text(
//                                   ('ok').tr,
//                                   style: TextStyle(
//                                       fontSize: 18.0, color: Colors.white),
//                                 ),
//                               ),
//                             ],
//                           )
//                         ],
//                       ),
//                     ),
//                   ],
//                 )
//               ],
//             ),
//           );
//         }));
//     showDialog(
//         context: context, builder: (BuildContext context) => simpleDialog);
//   }
//
//   void sendCommand() {
//     Map<String, String> requestBody;
//     if (_commandSelected == "Custom Command") {
//       requestBody = <String, String>{
//         'id': "",
//         'device_id': args!.id.toString(),
//         'type': _commandsValue[_selectedCommand],
//         'data': _customCommand.text
//       };
//     } else {
//       requestBody = <String, String>{
//         'id': "",
//         'device_id': args!.id.toString(),
//         'type': _commandsValue[_selectedCommand]
//       };
//     }
//
//     print(requestBody.toString());
//
//     APIService.sendCommands(requestBody).then((res) => {
//           if (res.statusCode == 200)
//             {
//               Fluttertoast.showToast(
//                   msg: ('command_sent').tr,
//                   toastLength: Toast.LENGTH_SHORT,
//                   gravity: ToastGravity.CENTER,
//                   timeInSecForIosWeb: 1,
//                   backgroundColor: Colors.green,
//                   textColor: Colors.white,
//                   fontSize: 16.0),
//               Navigator.of(context).pop()
//             }
//           else
//             {
//               Fluttertoast.showToast(
//                   msg: ('errorMsg').tr,
//                   toastLength: Toast.LENGTH_SHORT,
//                   gravity: ToastGravity.CENTER,
//                   timeInSecForIosWeb: 1,
//                   backgroundColor: Colors.black54,
//                   textColor: Colors.white,
//                   fontSize: 16.0),
//               Navigator.of(context).pop()
//             }
//         });
//   }
//
//   void showReport(String heading) {
//     String fromDate;
//     String toDate;
//     String fromTime;
//     String toTime;
//
//     DateTime current = DateTime.now();
//
//     String month;
//     if (current.month < 10) {
//       month = "0" + current.month.toString();
//     } else {
//       month = current.month.toString();
//     }
//
//     if (current.day < 10) {
//     } else {}
//
//     if (_selectedperiod == 0) {
//       String today;
//
//       int dayCon = current.day + 1;
//       print(dayCon);
//       if (current.day < 10) {
//         if (dayCon < 10) {
//           today = "0" + dayCon.toString();
//         } else {
//           today = dayCon.toString();
//         }
//       } else {
//         today = dayCon.toString();
//       }
//
//       var date = DateTime.parse("${current.year}-"
//           "$month-"
//           "$today "
//           "00:00:00");
//       fromDate = formatDateReport(DateTime.now().toString());
//       toDate = formatDateReport(date.toString());
//       fromTime = "00:00:00";
//       toTime = "00:00:00";
//     } else if (_selectedperiod == 1) {
//       String yesterday;
//
//       int dayCon = current.day - 1;
//       if (current.day < 10) {
//         yesterday = "0" + dayCon.toString();
//       } else {
//         yesterday = dayCon.toString();
//       }
//
//       var start = DateTime.parse("${current.year}-"
//           "$month-"
//           "$yesterday "
//           "00:00:00");
//
//       var end = DateTime.parse("${current.year}-"
//           "$month-"
//           "$yesterday "
//           "24:00:00");
//
//       fromDate = formatDateReport(start.toString());
//       toDate = formatDateReport(end.toString());
//       fromTime = "00:00:00";
//       toTime = "00:00:00";
//     } else if (_selectedperiod == 2) {
//       String sevenDay, currentDayString;
//       int dayCon = current.day - current.weekday;
//       int currentDay = current.day;
//       if (dayCon < 10) {
//         sevenDay = "0" + dayCon.abs().toString();
//       } else {
//         sevenDay = dayCon.toString();
//       }
//       if (currentDay < 10) {
//         currentDayString = "0" + currentDay.toString();
//       } else {
//         currentDayString = currentDay.toString();
//       }
//
//       var start = DateTime.parse("${current.year}-"
//           "$month-"
//           "$sevenDay "
//           "00:00:00");
//
//       var end = DateTime.parse("${current.year}-"
//           "$month-"
//           "$currentDayString "
//           "24:00:00");
//
//       fromDate = formatDateReport(start.toString());
//       toDate = formatDateReport(end.toString());
//       fromTime = "00:00:00";
//       toTime = "00:00:00";
//     } else {
//       String startMonth, endMoth;
//       if (_selectedFromDate.month < 10) {
//         startMonth = "0" + _selectedFromDate.month.toString();
//       } else {
//         startMonth = _selectedFromDate.month.toString();
//       }
//
//       if (_selectedToDate.month < 10) {
//         endMoth = "0" + _selectedToDate.month.toString();
//       } else {
//         endMoth = _selectedToDate.month.toString();
//       }
//
//       String startHour, endHour;
//       if (_selectedFromTime.hour < 10) {
//         startHour = "0" + _selectedFromTime.hour.toString();
//       } else {
//         startHour = _selectedFromTime.hour.toString();
//       }
//
//       String startMin, endMin;
//       if (_selectedFromTime.minute < 10) {
//         startMin = "0" + _selectedFromTime.minute.toString();
//       } else {
//         startMin = _selectedFromTime.minute.toString();
//       }
//
//       if (_selectedFromTime.minute < 10) {
//         endMin = "0" + _selectedToTime.minute.toString();
//       } else {
//         endMin = _selectedToTime.minute.toString();
//       }
//
//       if (_selectedToTime.hour < 10) {
//         endHour = "0" + _selectedToTime.hour.toString();
//       } else {
//         endHour = _selectedToTime.hour.toString();
//       }
//
//       String startDay, endDay;
//       if (_selectedFromDate.day < 10) {
//         if (_selectedFromDate.day == 10) {
//           startDay = _selectedFromDate.day.toString();
//         } else {
//           startDay = "0" + _selectedFromDate.day.toString();
//         }
//       } else {
//         startDay = _selectedFromDate.day.toString();
//       }
//
//       if (_selectedToDate.day < 10) {
//         if (_selectedToDate.day == 10) {
//           endDay = _selectedToDate.day.toString();
//         } else {
//           endDay = "0" + _selectedToDate.day.toString();
//         }
//       } else {
//         endDay = _selectedToDate.day.toString();
//       }
//
//       var start = DateTime.parse("${_selectedFromDate.year}-"
//           "$startMonth-"
//           "$startDay "
//           "$startHour:"
//           "$startMin:"
//           "00");
//
//       var end = DateTime.parse("${_selectedToDate.year}-"
//           "$endMoth-"
//           "$endDay "
//           "$endHour:"
//           "$endMin:"
//           "00");
//
//       fromDate = formatDateReport(start.toString());
//       toDate = formatDateReport(end.toString());
//       fromTime = formatTimeReport(start.toString());
//       toTime = formatTimeReport(end.toString());
//     }
//
//     print(fromDate);
//     print(toDate);
//
//     Navigator.pop(context);
//     if (heading == ('report').tr) {
//       Navigator.pushNamed(context, "/reportList",
//           arguments: ReportArguments(args!.device.id!, fromDate, fromTime,
//               toDate, toTime, args!.name, 0, args!.device));
//     } else {}
//   }
// }
// //
// // class ReportArguments {
// //   final int id;
// //   final String fromDate;
// //   final String fromTime;
// //   final String toDate;
// //   final String toTime;
// //   final String name;
// //   final int type;
// //   ReportArguments(this.id, this.fromDate, this.fromTime, this.toDate,
// //       this.toTime, this.name, this.type);
// // }
