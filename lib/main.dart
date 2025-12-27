import 'dart:developer';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gpspro/firebase_options.dart';
import 'package:gpspro/routes.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/services/notification_service.dart'; // ADD THIS
import 'package:overlay_support/overlay_support.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'translation/translation_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

// Notification channel setup
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: 'Used for important notifications',
  importance: Importance.max,
  playSound: true,
);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  showNotification(message);
}

Future<void> showNotification(RemoteMessage message) async {
  AndroidNotificationDetails androidPlatformChannelSpecifics =
  AndroidNotificationDetails(
    channel.id,
    channel.name,
    channelDescription: channel.description,
    importance: Importance.max,
    priority: Priority.high,
    icon: 'logo',
  );

  NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
  );

  log("Firebase notification ${message.notification?.title} ${message.notification?.body}");
  log("Firebase notification ${message.data}");

  await flutterLocalNotificationsPlugin.show(
    0,
    message.notification?.title ?? 'New Notification',
    message.notification?.body ?? 'You have a new message',
    platformChannelSpecifics,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);

    // Initialize notifications plugin
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('logo');

    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
        log('Notification tapped: ${response.payload}');
        if (response.payload != null) {
          Future.delayed(const Duration(milliseconds: 500), () {
            Get.toNamed('/events');
          });
        }
      },
    );

    // Create the notification channel
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Set up Firebase message handlers
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(showNotification);

    // Initialize NotificationService - ADD THIS
    await NotificationService().initialize(flutterLocalNotificationsPlugin);

    // Shared Preferences
    UserRepository.prefs = await SharedPreferences.getInstance();
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('language_code') ?? 'en_US';
    Get.updateLocale(Locale(languageCode));

    runApp(Phoenix(child: MyApp()));
  } catch (e, stackTrace) {
    log('Error during main initialization: $e');
    log('Stack trace: $stackTrace');
  }
}

Locale? _locale;

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<StatefulWidget> createState() => _MyAppPageState();
}

class _MyAppPageState extends State<MyApp> with WidgetsBindingObserver {
  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    return LayoutBuilder(builder: (context, constraints) {
      return OrientationBuilder(builder: (context, orientation) {
        return OverlaySupport.global(
            child: GetMaterialApp(
              locale: _locale,
              fallbackLocale: TranslationService.fallbackLocale,
              translations: TranslationService(),
              debugShowCheckedModeBanner: false,
              navigatorKey: navigatorKey,
              theme: ThemeData(
                useMaterial3: true,
                primarySwatch: CustomColor.primaryColor,
                visualDensity: VisualDensity.adaptivePlatformDensity,
                textTheme: GoogleFonts.rethinkSansTextTheme(),
                appBarTheme: AppBarTheme(
                  systemOverlayStyle: SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    statusBarBrightness: Brightness.light,
                    statusBarIconBrightness: Brightness.dark,
                  ),
                ),
              ),
              initialRoute: '/',
              routes: routes,
            ));
      });
    });
  }
}