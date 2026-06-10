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
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

// ─── Background plugin singleton (initialized once, reused on every message) ─
FlutterLocalNotificationsPlugin? _bgPlugin;
bool _bgPluginReady = false;

// ─── Background message handler — MUST BE TOP-LEVEL ──────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Only initialize Firebase if it hasn't been initialized yet
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
    } catch (_) {}
  }
  await _showBackgroundNotification(message);
}

// ─── Background notification (plugin initialized once, not per message) ───────
Future<void> _showBackgroundNotification(RemoteMessage message) async {
  try {
    // Initialize background plugin only once
    if (!_bgPluginReady) {
      _bgPlugin = FlutterLocalNotificationsPlugin();

      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosSettings =
      DarwinInitializationSettings(
        requestSoundPermission: false,
        requestBadgePermission: false,
        requestAlertPermission: false,
      );

      await _bgPlugin!.initialize(
        const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
      );

      // Create channel once
      await _bgPlugin!
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'Used for important notifications',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ));

      _bgPluginReady = true;
    }

    final String title = message.notification?.title ??
        message.data['title'] as String? ??
        'New Notification';
    final String body = message.notification?.body ??
        message.data['body'] as String? ??
        'You have a new message';
    final String emoji = _getEmojiForMessage(body);

    await _bgPlugin!.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '$emoji $title',
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription: 'Important notifications',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data.toString(),
    );
  } catch (e) {
    debugPrint('Background notification error: $e');
    // Fallback: try a bare-minimum show with whatever plugin state we have
    try {
      await _bgPlugin?.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        message.notification?.title ?? 'Notification',
        message.notification?.body ?? 'New message',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel',
            'Default',
            importance: Importance.max,
            priority: Priority.max,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }
}

// ─── Emoji helper ─────────────────────────────────────────────────────────────
String _getEmojiForMessage(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('sos')) return '🆘';
  if (lower.contains('alarm') || lower.contains('alert')) return '🚨';
  if (lower.contains('speed')) return '⚡';
  if (lower.contains('geofence')) return '📍';
  if (lower.contains('ignition')) return '🔑';
  if (lower.contains('online')) return '✅';
  if (lower.contains('offline')) return '❌';
  if (lower.contains('fuel')) return '⛽';
  if (lower.contains('battery')) return '🔋';
  return '🔔';
}

// ─── Foreground notification ──────────────────────────────────────────────────
Future<void> showForegroundNotification(RemoteMessage message) async {
  final String title = message.notification?.title ??
      message.data['title'] as String? ??
      'New Notification';
  final String body = message.notification?.body ??
      message.data['body'] as String? ??
      'You have a new message';
  final String emoji = _getEmojiForMessage(body);

  final bool isAlert = body.toLowerCase().contains('sos') ||
      body.toLowerCase().contains('alert') ||
      body.toLowerCase().contains('alarm');

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    '$emoji $title',
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        isAlert ? 'alert_channel' : 'high_importance_channel',
        isAlert ? 'Alert Notifications' : 'High Importance Notifications',
        channelDescription: 'Important notifications',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: '$emoji $title',
          summaryText: 'Trust Me',
        ),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
    payload: message.data.toString(),
  );
}

// ─── Background tap handler ───────────────────────────────────────────────────
@pragma('vm:entry-point')
void onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  // Handle background notification tap if needed
}

// ─── main ─────────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize foreground notification plugin
    await _initializeLocalNotifications();

    // Create Android channels
    await _createNotificationChannels();

    // Request OS permissions
    await _requestNotificationPermissions();

    // Show notifications while app is in foreground
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground messages
    FirebaseMessaging.onMessage.listen(showForegroundNotification);

    // App opened from terminated state via notification tap
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        Future.delayed(const Duration(seconds: 2), () {
          try {
            Get.toNamed('/events');
          } catch (_) {}
        });
      }
    });

    // App opened from background state via notification tap
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      Future.delayed(const Duration(milliseconds: 500), () {
        try {
          Get.toNamed('/events');
        } catch (_) {}
      });
    });

    await NotificationService().initialize(flutterLocalNotificationsPlugin);

    // Initialize SharedPreferences once and store in UserRepository
    UserRepository.prefs = await SharedPreferences.getInstance();

    // Restore saved locale
    final String languageCode =
        UserRepository.prefs!.getString('language_code') ?? 'en_US';
    Get.updateLocale(Locale(languageCode));
  } catch (e) {
    debugPrint('Initialization error: $e');
  }

  runApp(Phoenix(child: const MyApp()));
}

// ─── Local notifications init ─────────────────────────────────────────────────
Future<void> _initializeLocalNotifications() async {
  const InitializationSettings initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    ),
  );

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          try {
            Get.toNamed('/events');
          } catch (_) {}
        });
      }
    },
    onDidReceiveBackgroundNotificationResponse:
    onDidReceiveBackgroundNotificationResponse,
  );
}

// ─── Create Android notification channels ─────────────────────────────────────
Future<void> _createNotificationChannels() async {
  if (!Platform.isAndroid) return;

  final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
  flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();

  if (androidPlugin == null) return;

  await Future.wait([
    androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'Used for important notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    )),
    androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'alert_channel',
      'Alert Notifications',
      description: 'Critical alerts and emergency notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    )),
    androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'default_channel',
      'Default Notifications',
      description: 'Default notification channel',
      importance: Importance.high,
      playSound: true,
    )),
  ]);
}

// ─── Request permissions ──────────────────────────────────────────────────────
Future<void> _requestNotificationPermissions() async {
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: true,
    provisional: false,
    sound: true,
  );

  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  if (Platform.isIOS) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
      critical: true,
    );
  }
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