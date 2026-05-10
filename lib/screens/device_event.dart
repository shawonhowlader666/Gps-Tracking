import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smart_lock/arguments/report_args.dart';
import 'package:smart_lock/services/model/event.dart';
import 'package:smart_lock/services/model/user.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/theme/custom_color.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceEventPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _DeviceEventPageState();
}

class _DeviceEventPageState extends State<DeviceEventPage> {
  User? user;
  SharedPreferences? prefs;
  List<Event>? eventList;
  ReportArguments? args;
  Map<int, dynamic> devices = HashMap();
  var deviceId = [];
  bool isLoading = true;
  bool isEventLoading = true;
  Locale? myLocale;
  late StreamController<int> _postsController;
  late Timer _timer;

  int online = 0, offline = 0, unknown = 0;

  @override
  initState() {
    _postsController = StreamController();
    getReport();
    super.initState();
  }

  getReport() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // ignore: unnecessary_null_comparison
      if (args != null) {
        _timer.cancel();
        APIService.getEventByID(args!.id.toString(), args!.fromDate,
                args!.fromTime, args!.toDate, args!.toTime)
            .then((value) => {
                  eventList = [],
                  eventList!.addAll(value!),
                  _postsController.add(1),
                  isLoading = false,
                  setState(() {})
                });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    args = ModalRoute.of(context)!.settings.arguments as ReportArguments;

    myLocale = Localizations.localeOf(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        automaticallyImplyLeading: true,
        iconTheme: IconThemeData(color: CustomColor.cssBlack),
        title: Row(
          children: [
            //Padding(padding: EdgeInsets.only(bottom: 5, right: 5),child:Image.asset("images/logo-icon.png", width: 40, height: 40)),
            Text(
              'recentEvents'.tr,
            ),
          ],
        ),
        // actions: [
        //   IconButton(onPressed: (){},
        //     icon:Icon(Icons.filter_list_outlined),
        //     color: Colors.black,)
        // ],
        centerTitle: false,
        elevation: 0,
      ),
      body: StreamBuilder<int>(
          stream: _postsController.stream,
          builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
            if (snapshot.hasData) {
              return loadEvents();
            } else if (isLoading) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            } else {
              return Center(
                child: Text(('noData').tr),
              );
            }
          }),
    );
  }

  Widget loadEvents() {
    if (eventList != null) {
      return ListView.builder(
          scrollDirection: Axis.vertical,
          itemCount: eventList!.length,
          itemBuilder: (context, index) {
            final eventItem = eventList![index];
            return InkWell(
                onTap: () {
                  Navigator.pushNamed(context, "/notificationMap",
                      arguments: ReportEventArgument(eventItem));
                },
                child: Container(
                  padding: EdgeInsets.only(top: 10, bottom: 10),
                  width: double.infinity,
                  decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(5.0)),
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 3.0,
                        )
                      ]),
                  child: Column(
                    children: <Widget>[
                      ListTile(
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(eventItem.device_name!,
                                style: const TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.bold),
                                softWrap: true,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                        leading: Icon(Icons.notifications),
                        trailing: Container(
                          width: 80,
                          child: Text(
                              eventItem.time != null ? eventItem.time! : "",
                              style: TextStyle(
                                  fontSize: 12.0,
                                  color: CustomColor.primaryColor)),
                        ),
                        subtitle: Text(eventItem.message!.tr,
                            style: const TextStyle(fontSize: 14.0)),
                      )
                    ],
                  ),
                ));
          });
    } else {
      return const Center(child: CircularProgressIndicator());
    }
  }
}

class Task {
  String task;
  int taskvalue;
  Color colorval;

  Task(this.task, this.taskvalue, this.colorval);
}

class ReportEventArgument {
  final Event event;
  ReportEventArgument(this.event);
}
