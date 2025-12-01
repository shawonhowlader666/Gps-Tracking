import 'package:flutter/material.dart';
import 'package:gpspro/screens/add_alerts.dart';
import 'package:gpspro/screens/alert_list.dart';
import 'package:gpspro/screens/device_dashboard.dart';
import 'package:gpspro/screens/device_event.dart';
import 'package:gpspro/screens/device_info.dart';
import 'package:gpspro/screens/devices_selection.dart';
import 'package:gpspro/screens/engine_lock.dart';
import 'package:gpspro/screens/event_map.dart';
import 'package:gpspro/screens/geofence.dart';
import 'package:gpspro/screens/geofence_add.dart';
import 'package:gpspro/screens/geofence_list.dart';
import 'package:gpspro/screens/main_bottom_nav.dart';
import 'package:gpspro/screens/login.dart';
import 'package:gpspro/screens/notification_map.dart';
import 'package:gpspro/screens/notifications.dart';
import 'package:gpspro/screens/playback.dart';
import 'package:gpspro/screens/report/report_fuel.dart';
import 'package:gpspro/screens/report/report_route.dart';
import 'package:gpspro/screens/report/report_stop_view.dart';
import 'package:gpspro/screens/report/report_trip_view.dart';
import 'package:gpspro/screens/report/reports_list.dart';
import 'package:gpspro/screens/splash_screen.dart';
import 'package:gpspro/screens/stop_map.dart';

import 'screens/report/report_event.dart';
import 'screens/report/report_stop.dart';
import 'screens/report/report_summary.dart';
import 'screens/report/report_trip.dart';

final Map<String, WidgetBuilder> routes = {
  '/': (context) => SplashScreenPage(),
  '/login': (context) => LoginPage(),
  '/home': (context) => MainBottomNav(),
  '/deviceSelection': (context) => DeviceSelection(),
  '/deviceDashboard': (context) => DeviceDashboard(),
  '/deviceInfo': (context) => DeviceInfo(),
  '/reportList': (context) => ReportListPage(),
  '/reportRoute': (context) => ReportRoutePage(),
  '/reportEvent': (context) => ReportEventPage(),
  '/reportTrip': (context) => ReportTripPage(),
  '/reportFuel': (context) => ReportFuelPage(),
  '/reportTripView': (context) => ReportTripViewPage(),
  '/reportStopView': (context) => ReportStopViewPage(),
  '/reportStop': (context) => ReportStopPage(),
  '/reportSummary': (context) => ReportSummaryPage(),
  '/playback': (context) => PlaybackScreen(),
  '/notificationType': (context) => NotificationTypePage(),
  '/eventMap': (context) => EventMapPage(),
  '/notificationMap': (context) => NotificationMapPage(),
  '/geofence': (context) => GeofencePage(),
  '/geofenceList': (context) => GeofenceListPage(),
  '/geofenceAdd': (context) => GeofenceAddPage(),
  '/alertList': (context) => AlertListPage(),
  '/addAlert': (context) => AddAlertsPage(),
  '/notification': (context) => NotificationTypePage(),
  '/stopMap': (context) => StopMapPage(),
  '/deviceEvent': (context) => DeviceEventPage(),
  '/engineLock': (context) => const EngineLockScreen(),
};
