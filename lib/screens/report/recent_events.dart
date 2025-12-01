import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/services/model/event.dart';
import 'package:gpspro/services/model/user.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EventsPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<EventsPage> {
  User? user;
  SharedPreferences? prefs;
  List<Event> eventList = [];
  Map<int, dynamic> devices = HashMap();
  var deviceId = [];
  bool isLoading = true;
  bool isEventLoading = true;

  int online = 0, offline = 0, unknown = 0;

  @override
  initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              Text(
                'recentEvents'.tr,
                style: FlutterFlowTheme.of(context).headlineMedium,
              ),
            ],
          ),
          centerTitle: false,
          elevation: 0,
        ),
        body: GetX<DataController>(
          init: DataController(),
          builder: (controller) {
            return Scaffold(
              body: Column(
                children: <Widget>[Expanded(child: loadEvents(controller))],
              ),
            );
          },
        ));
  }

  Widget loadEvents(DataController controller) {
    if (controller.events.isNotEmpty) {
      return ListView.separated(
          scrollDirection: Axis.vertical,
          itemCount: controller.events.length,
          separatorBuilder: (BuildContext context, int) {
            return Gap(1);
          },
          itemBuilder: (context, index) {
            final eventItem = controller.events[index];
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
      return Container(
        child: Center(
            child: Text(
          'noEvents'.tr,
          style: TextStyle(fontSize: 17),
        )),
      );
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
