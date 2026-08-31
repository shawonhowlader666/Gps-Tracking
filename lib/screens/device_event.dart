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
    super.initState();
  }

  // ✅ UTC থেকে Local time-এ convert করার helper
  // Server "2024-01-15 13:44:00" এই format পাঠালে এটা local time-এ দেখাবে
  String _convertToLocalTime(String? serverTime) {
    if (serverTime == null || serverTime.isEmpty) return '';

    try {
      if (serverTime.contains('AM') || serverTime.contains('PM') || serverTime.contains('am') || serverTime.contains('pm')) {
        final parts = serverTime.trim().split(RegExp(r'\s+'));
        for (var part in parts) {
          if (part.contains(':')) {
            final segs = part.split(':');
            if (segs.length >= 2) {
              final h = int.tryParse(segs[0]) ?? 12;
              final m = segs[1];
              final period = serverTime.toUpperCase().contains('PM') ? 'PM' : 'AM';
              final displayHour = h % 12 == 0 ? 12 : h % 12;
              return '${displayHour.toString().padLeft(2, '0')}:$m $period';
            }
          }
        }
        return serverTime;
      }

      final cleanTime = serverTime.replaceAll('Z', '').replaceAll('T', ' ');
      final DateTime dt = DateTime.parse(cleanTime);
      final int hour = dt.hour;
      final int minute = dt.minute;
      final String period = hour >= 12 ? 'PM' : 'AM';
      final int displayHour = hour % 12 == 0 ? 12 : hour % 12;

      return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return serverTime;
    }
  }

  String _convertToLocalDateTime(String? serverTime) {
    if (serverTime == null || serverTime.isEmpty) return '';

    try {
      if (serverTime.contains('AM') || serverTime.contains('PM') || serverTime.contains('am') || serverTime.contains('pm')) {
        return serverTime;
      }

      final cleanTime = serverTime.replaceAll('Z', '').replaceAll('T', ' ');
      final DateTime dt = DateTime.parse(cleanTime);

      final int hour = dt.hour;
      final int minute = dt.minute;
      final String period = hour >= 12 ? 'PM' : 'AM';
      final int displayHour = hour % 12 == 0 ? 12 : hour % 12;

      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year} '
          '${displayHour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return serverTime ?? '';
    }
  }

  bool _hasFetchedReport = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasFetchedReport) {
      final modalArgs = ModalRoute.of(context)?.settings.arguments as ReportArguments?;
      if (modalArgs != null) {
        args = modalArgs;
        _hasFetchedReport = true;
        APIService.getEventByID(args!.id.toString(), args!.fromDate,
                args!.fromTime, args!.toDate, args!.toTime)
            .then((value) {
          if (mounted) {
            setState(() {
              eventList = value ?? [];
              isLoading = false;
            });
            _postsController.add(1);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
