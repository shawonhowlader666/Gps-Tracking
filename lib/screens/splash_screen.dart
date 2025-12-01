import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:gpspro/config.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/screens/server_maintenance_screen.dart';
import 'package:gpspro/services/admob_service.dart';
import 'package:gpspro/services/model/login.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreenPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _SplashScreenPageState();
}

class _SplashScreenPageState extends State<SplashScreenPage> {
  SharedPreferences? prefs;

  String _notificationToken = "";
  AndroidNotificationChannel channel = const AndroidNotificationChannel(
    'high_importance_channel', // id
    'High Importance Notifications', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.high,
  );

  int id = 0;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();

    Permission _permission = Permission.location;
    _permission.request();
    // initFirebase();
    fetchConfigAndProceed();
  }

  Future<void> fetchConfigAndProceed() async {
    try {
      prefs = await SharedPreferences.getInstance();
      var serverType = prefs!.getString('serverType') ?? 'free';

      final doc = await FirebaseFirestore.instance
          .collection('configs')
          .doc('urls')
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final spytrackConfig = data['spytrack'] as Map<String, dynamic>;
        SERVER_URL = spytrackConfig['url'] as List;
        SHOW_ADS = (spytrackConfig['ads'] as bool) && serverType == 'free';
        WHATS_APP = spytrackConfig['whatsapp'] as String;
        PHONE_NO = spytrackConfig['phone'] as String;
        EMAIL = spytrackConfig['email'] as String;
        adsFrequency = spytrackConfig['adsfrequency'] as int;
        APP_VERSION = spytrackConfig['version'] as String;
        BANNER_IMAGE = spytrackConfig['banners'] as List<dynamic>;
        fuelData = spytrackConfig['fuelData'];
      }

      // // Only update server URL from Firebase if no manual URL was set
      // if (SERVER_URL.isNotEmpty) {
      //   final prefs = await SharedPreferences.getInstance();
      //   if (prefs.getBool('isManualServerUrl') != true) {
      //     UserRepository.setServerUrl(SERVER_URL);
      //   }
      // }

      // 🔍 Match current server URL with server list
      String? currentServerUrl = UserRepository.getServerUrl();
      for (var server in SERVER_URL) {
        if (server['url'] == currentServerUrl) {
          ALWAYS_SHOW_BANNER_ADS = server['showBannerAds'];
          final message = server['message'] ?? '';
          if (message.isNotEmpty) {
            // 🚪 Close all routes and go to maintenance screen
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => ServerMaintenanceScreen(message: message),
                ),
                (route) => false,
              );
            });
            return;
          }
          break;
        }
      }

      if (SHOW_ADS) {
        await AdMobService().initialize();
      }

      checkPreference();
    } catch (e) {
      print('Error fetching Firebase config: $e');
      checkPreference();
    }
  }

  // Future<void> initFirebase() async {
  //   WidgetsFlutterBinding.ensureInitialized();

  //   FirebaseMessaging messaging = FirebaseMessaging.instance;
  //   await messaging.getToken().then((value) => {_notificationToken = value!});

  //   print("Notification Token:${_notificationToken}");

  //   FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
  //     print("object");

  //     _showNotification(message.notification!.title.toString(),
  //         message.notification!.body.toString());
  //   });

  //   await flutterLocalNotificationsPlugin
  //       .resolvePlatformSpecificImplementation<
  //           AndroidFlutterLocalNotificationsPlugin>()
  //       ?.createNotificationChannel(channel);

  //   await FirebaseMessaging.instance
  //       .setForegroundNotificationPresentationOptions(
  //     alert: true,
  //     badge: true,
  //     sound: true,
  //   );
  // }

  // Future<void> _showNotification(String title, String body) async {
  //   const AndroidNotificationDetails androidNotificationDetails =
  //       AndroidNotificationDetails('your channel id', 'your channel name',
  //           channelDescription: 'your channel description',
  //           importance: Importance.max,
  //           priority: Priority.high,
  //           icon: "logo",
  //           ticker: 'ticker');
  //   const NotificationDetails notificationDetails =
  //       NotificationDetails(android: androidNotificationDetails);
  //   await flutterLocalNotificationsPlugin
  //       .show(id++, title, body, notificationDetails, payload: 'item x');
  // }

  void checkPreference() async {
    // if (UserRepository.getServerUrl() == null) {
    //   UserRepository.setServerUrl(SERVER_URL);
    // }

    if (UserRepository.getHash() != null) {
      checkLogin();
    } else {
      Get.offAndToNamed('/login');
    }
  }

  void checkLogin() {
    //Future.delayed(const Duration(milliseconds: 3000), () {
    APIService.login(UserRepository.getServerUrl(), UserRepository.getEmail(),
            UserRepository.getPassword())
        .then((response) {
      if (response != null) {
        if (response.statusCode == 200) {
          UserLogin user = UserLogin.fromJson(
              jsonDecode(response.body.replaceAll("ï»¿", "")));
          UserRepository.setHash(user.userApiHash!);
          updateToken();
          Get.offAndToNamed('/home');
        } else {
          Get.offAndToNamed('/login');
        }
      } else {
        Get.offAndToNamed('/login');
      }
    });
    // });
  }

  void updateToken() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.getToken().then((value) => {_notificationToken = value!});
    print("Notification Token:${_notificationToken}");
    APIService.getUserData()
        .then((value) => {APIService.activateFCM(_notificationToken)});
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
    ));

    return Scaffold(
      // backgroundColor: FlutterFlowTheme.of(context).secondary,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Column(children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(36.0),
              child: Image.asset(
                'images/logo.png',
                height: 250.0,
                fit: BoxFit.contain,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(20),
            ),
            Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            )
          ]),
        ],
      ),
    );
  }
}
