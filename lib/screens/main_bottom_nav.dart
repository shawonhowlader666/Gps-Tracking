import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:gpspro/screens/devices.dart';
import 'package:gpspro/screens/home_screen.dart';
import 'package:gpspro/screens/map_home.dart';
import 'package:gpspro/screens/report/recent_events.dart';
import 'package:gpspro/screens/settings.dart';
import 'package:gpspro/screens/data_controller/data_controller.dart';
import 'package:gpspro/services/admob_service.dart';
import 'package:gpspro/util/force_update.dart';
import 'package:line_icons/line_icons.dart';

class MainBottomNav extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _MainBottomNavState();
}

class _MainBottomNavState extends State<MainBottomNav> {
  int _selectedIndex = 0;
  bool first = true;
  String? email;
  String? password;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  AndroidNotificationChannel channel = const AndroidNotificationChannel(
    'high_importance_channel', // id
    'High Importance Notifications', // title
    description: 'This channel is used for important notifications.',
    importance: Importance.high,
  );

  @override
  void initState() {
    VersionUtils.checkForUpdate(context);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.dark,
    ));

    Future<bool> _onWillPop() async {
      return await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(("areYouSure").tr),
          content: Text(("doYouWantToExit").tr),
          actions: <Widget>[
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(("no").tr),
            ),
            ElevatedButton(
              onPressed: () => {SystemNavigator.pop()},
              child: Text(("yes").tr),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
          extendBody: true,
          body: GetX<DataController>(
            init: DataController(),
            builder: (controller) {
              return !controller.isLoading.value
                  ? IndexedStack(
                      index: _selectedIndex,
                      children: <Widget>[
                        HomeScreen(),
                        const DevicePage(),
                        const MapPage(),
                        EventsPage(),
                        SettingsPage(),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator());
            },
          ),
          bottomNavigationBar: Stack(
            children: [
              BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.white,
                elevation: 5,
                currentIndex: _selectedIndex,
                selectedItemColor: Colors.orange,
                unselectedItemColor: Colors.grey,
                selectedLabelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
                showUnselectedLabels: true,
                onTap: (index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                  AdMobService().showInterstitialAd();
                },
                items: [
                  BottomNavigationBarItem(
                    icon: Icon(LineIcons.home),
                    label: ('homePage').tr,
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(LineIcons.car),
                    label: ('vehicles').tr,
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(LineIcons.map),
                    label: ('map').tr,
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(LineIcons.bell),
                    label: ('events').tr,
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(LineIcons.cog),
                    label: ('settings').tr,
                  ),
                ],
              ),

              // Top indicator positioned at the top of the navigation bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 3,
                  child: Row(
                    children: List.generate(5, (index) {
                      final itemWidth = MediaQuery.of(context).size.width / 5;
                      return Container(
                        width: itemWidth,
                        alignment: Alignment.center,
                        child: Container(
                          height: 3,
                          width: 20,
                          decoration: BoxDecoration(
                            color: _selectedIndex == index
                                ? Colors.orange
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
