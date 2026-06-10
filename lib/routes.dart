import 'package:flutter/material.dart';
import 'package:smart_lock/screens/alert_list.dart';
import 'package:smart_lock/screens/device_event.dart';
import 'package:smart_lock/screens/device_info.dart';
import 'package:smart_lock/screens/devices_selection.dart';
import 'package:smart_lock/screens/engine_lock.dart';
import 'package:smart_lock/screens/event_map.dart';
import 'package:smart_lock/screens/geofence.dart';
import 'package:smart_lock/screens/geofence_add.dart';
import 'package:smart_lock/screens/geofence_list.dart';
import 'package:smart_lock/screens/main_bottom_nav.dart';
import 'package:smart_lock/screens/login.dart';
import 'package:smart_lock/screens/notification_map.dart';
import 'package:smart_lock/screens/notifications.dart';
import 'package:smart_lock/screens/report/recent_events.dart';
import 'package:smart_lock/screens/report/report_fuel.dart';
import 'package:smart_lock/screens/report/report_route.dart';
import 'package:smart_lock/screens/splash_screen.dart';
import 'package:smart_lock/screens/stop_map.dart';
import 'screens/report/report_event.dart';


final Map<String, WidgetBuilder> routes = {
  '/': (context) => SplashScreenPage(),
  '/login': (context) => LoginPage(),
  '/home': (context) => MainBottomNav(),
  '/deviceSelection': (context) => DeviceSelection(),
  '/deviceInfo': (context) => DeviceInfo(),
  '/reportRoute': (context) => ReportRoutePage(),
  '/reportEvent': (context) => ReportEventPage(),
  '/reportFuel': (context) => ReportFuelPage(),

  '/notificationType': (context) => NotificationTypePage(),
  '/eventMap': (context) => EventMapPage(),
  '/notificationMap': (context) => NotificationMapPage(),
  '/geofence': (context) => GeofencePage(),
  '/geofenceList': (context) => GeofenceListPage(),
  '/geofenceAdd': (context) => GeofenceAddPage(),
  '/alertList': (context) => AlertListPage(),
  '/notification': (context) => NotificationTypePage(),
  '/stopMap': (context) => StopMapPage(),
  '/deviceEvent': (context) => DeviceEventPage(),
  '/engineLock': (context) => const EngineLockScreen(),
  '/event': (context) => EventsPage(),
};
