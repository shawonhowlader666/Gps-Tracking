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
  const DeviceEventPage({super.key});

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

  // ✅ UTC থেকে Local time-এ convert করার helper
  // Server "2024-01-15 13:44:00" এই format পাঠালে এটা local time-এ দেখাবে
  String _convertToLocalTime(String? serverTime) {
    if (serverTime == null || serverTime.isEmpty) return '';

    try {
      // ✅ DateTime.parse() UTC হিসেবে নেয় না — তাই আমরা manually UTC বলে দিচ্ছি
      DateTime utcTime;

      // Server যদি "2024-01-15T13:44:00Z" বা "2024-01-15T13:44:00.000Z" দেয়
      if (serverTime.contains('T') || serverTime.endsWith('Z')) {
        utcTime = DateTime.parse(serverTime).toUtc();
      }
      // Server যদি "2024-01-15 13:44:00" এই format দেয় (Z ছাড়া)
      else {
        // Z যোগ করে UTC বলে দাও
        utcTime = DateTime.parse('${serverTime}Z').toUtc();
      }

      // ✅ Device-এর local timezone-এ convert করো
      final DateTime localTime = utcTime.toLocal();

      // ✅ 12-hour format: "01:44 PM"
      final int hour = localTime.hour;
      final int minute = localTime.minute;
      final String period = hour >= 12 ? 'PM' : 'AM';
      final int displayHour = hour % 12 == 0 ? 12 : hour % 12;

      return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      // Parse করতে না পারলে original time দেখাও
      return serverTime ?? '';
    }
  }

  // ✅ Date ও Time দুটোই দেখাতে চাইলে এই function ব্যবহার করো
  String _convertToLocalDateTime(String? serverTime) {
    if (serverTime == null || serverTime.isEmpty) return '';

    try {
      DateTime utcTime;

      if (serverTime.contains('T') || serverTime.endsWith('Z')) {
        utcTime = DateTime.parse(serverTime).toUtc();
      } else {
        utcTime = DateTime.parse('${serverTime}Z').toUtc();
      }

      final DateTime localTime = utcTime.toLocal();

      final int hour = localTime.hour;
      final int minute = localTime.minute;
      final String period = hour >= 12 ? 'PM' : 'AM';
      final int displayHour = hour % 12 == 0 ? 12 : hour % 12;

      return '${localTime.day.toString().padLeft(2, '0')}/'
          '${localTime.month.toString().padLeft(2, '0')}/'
          '${localTime.year} '
          '${displayHour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return serverTime ?? '';
    }
  }

  void getReport() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
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
            Text('recentEvents'.tr),
          ],
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: StreamBuilder<int>(
          stream: _postsController.stream,
          builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
            if (snapshot.hasData) {
              return loadEvents();
            } else if (isLoading) {
              return const Center(child: CircularProgressIndicator());
            } else {
              return Center(child: Text(('noData').tr));
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

            // ✅ এখানে local time-এ convert করো
            final String localTime = _convertToLocalTime(eventItem.time);

            return InkWell(
                onTap: () {
                  Navigator.pushNamed(context, "/notificationMap",
                      arguments: ReportEventArgument(eventItem));
                },
                child: Container(
                  padding: const EdgeInsets.only(top: 10, bottom: 10),
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
                            Text(
                              eventItem.device_name!,
                              style: const TextStyle(
                                  fontSize: 16.0, fontWeight: FontWeight.bold),
                              softWrap: true,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        leading: const Icon(Icons.notifications),
                        trailing: SizedBox(
                          width: 80,
                          // ✅ converted local time দেখাও
                          child: Text(
                            localTime,
                            style: TextStyle(
                                fontSize: 12.0,
                                color: CustomColor.primaryColor),
                          ),
                        ),
                        subtitle: Text(
                          eventItem.message!.tr,
                          style: const TextStyle(fontSize: 14.0),
                        ),
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
