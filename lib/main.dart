import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smart_lock/firebase_options.dart';
import 'package:smart_lock/routes.dart';
import 'package:smart_lock/storage/user_repository.dart';
import 'package:smart_lock/theme/custom_color.dart';
import 'package:smart_lock/services/notification_service.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'translation/translation_service.dart';

// ─── Global singleton notification plugin ────────────────────────────────────
// ─── Global singleton notification plugin ────────────────────────────────────
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

// ─── main ─────────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Register background messaging handler from notification_service.dart
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Initialize notification service (handles permissions, local notification init, and event listeners)
    await NotificationService().initialize(flutterLocalNotificationsPlugin);

    // Initialize SharedPreferences once and store in UserRepository
    UserRepository.prefs = await SharedPreferences.getInstance();

    // Restore saved locale
    String languageCode = UserRepository.prefs!.getString('language') ??
        UserRepository.prefs!.getString('language_code') ??
        'en';
    if (languageCode == 'en_US') {
      languageCode = 'en';
    } else if (languageCode == 'bn_BD') {
      languageCode = 'bn';
    }
    Get.updateLocale(Locale(languageCode));
  } catch (e) {
    debugPrint('Initialization error: $e');
  }

  runApp(Phoenix(child: const MyApp()));
}

// ─── App root ─────────────────────────────────────────────────────────────────
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<StatefulWidget> createState() => _MyAppPageState();
}

class _MyAppPageState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Set once here — never inside build()
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
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
    return OverlaySupport.global(
      child: GetMaterialApp(
        fallbackLocale: TranslationService.fallbackLocale,
        translations: TranslationService(),
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: ThemeData(
          useMaterial3: true,
          primarySwatch: CustomColor.primaryColor,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          textTheme: GoogleFonts.rethinkSansTextTheme(),
          appBarTheme: const AppBarTheme(
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarBrightness: Brightness.light,
              statusBarIconBrightness: Brightness.dark,
            ),
          ),
        ),
        initialRoute: '/',
        routes: routes,
      ),
    );
  }
}
