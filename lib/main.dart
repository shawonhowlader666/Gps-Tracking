import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gpspro/firebase_options.dart';
import 'package:gpspro/routes.dart';
import 'package:gpspro/storage/user_repository.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:gpspro/services/notification_service.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'translation/translation_service.dart';

/// Ultra-liquid scroll: iOS-quality spring physics on all platforms
class _PremiumScrollBehavior extends ScrollBehavior {
  const _PremiumScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const _LiquidScrollPhysics();
  }

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child; // No glow — clean premium look
  }
}

/// Custom scroll physics with tight spring — feels like water
class _LiquidScrollPhysics extends BouncingScrollPhysics {
  const _LiquidScrollPhysics({super.parent});

  @override
  _LiquidScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _LiquidScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => const SpringDescription(
        mass: 0.04,       // lighter = snappier response
        stiffness: 100,   // higher = tighter spring
        damping: 0.8,     // <1 = slight elastic overshoot
      );
}

/// Smooth page transition: fade + micro-slide, 280ms easeOutExpo
class _SmoothPageTransitionBuilder extends PageTransitionsBuilder {
  const _SmoothPageTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const curve = Curves.easeOutExpo;
    final curvedAnimation = CurvedAnimation(parent: animation, curve: curve);
    final fadeCurved = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );

    return FadeTransition(
      opacity: fadeCurved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.0, 0.025), // 2.5% upward — barely perceptible
          end: Offset.zero,
        ).animate(curvedAnimation),
        child: child,
      ),
    );
  }
}

// Global notification plugin instance (for foreground use only)
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

// Background message handler - MUST BE TOP-LEVEL FUNCTION
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}

  await _showBackgroundNotification(message);
}

// Show notification for background messages
Future<void> _showBackgroundNotification(RemoteMessage message) async {
  final FlutterLocalNotificationsPlugin backgroundPlugin =
  FlutterLocalNotificationsPlugin();

  try {
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
    DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,
    );

    await backgroundPlugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    const AndroidNotificationChannel backgroundChannel =
    AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'Used for important notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await backgroundPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(backgroundChannel);

    String title = message.notification?.title ??
        message.data['title'] ??
        'New Notification';
    String body = message.notification?.body ??
        message.data['body'] ??
        'You have a new message';

    String emoji = _getEmojiForMessage(body);

    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'Important notifications',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await backgroundPlugin.show(
      notificationId,
      '$emoji $title',
      body,
      notificationDetails,
      payload: message.data.toString(),
    );
  } catch (_) {
    await _showUltraSimpleNotification(backgroundPlugin, message);
  }
}

// Ultra simple fallback notification
Future<void> _showUltraSimpleNotification(
    FlutterLocalNotificationsPlugin plugin, RemoteMessage message) async {
  try {
    String title =
        message.notification?.title ?? message.data['title'] ?? 'Notification';
    String body =
        message.notification?.body ?? message.data['body'] ?? 'New message';

    await plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
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

// Get emoji for message type
String _getEmojiForMessage(String message) {
  message = message.toLowerCase();
  if (message.contains('sos')) return '🆘';
  if (message.contains('alarm') || message.contains('alert')) return '🚨';
  if (message.contains('speed')) return '⚡';
  if (message.contains('geofence')) return '📍';
  if (message.contains('ignition')) return '🔑';
  if (message.contains('online')) return '✅';
  if (message.contains('offline')) return '❌';
  if (message.contains('fuel')) return '⛽';
  if (message.contains('battery')) return '🔋';
  return '🔔';
}

// Show notification for foreground messages
Future<void> showForegroundNotification(RemoteMessage message) async {
  String title = message.notification?.title ??
      message.data['title'] ??
      'New Notification';
  String body = message.notification?.body ??
      message.data['body'] ??
      'You have a new message';

  String emoji = _getEmojiForMessage(body);

  bool isAlert = body.toLowerCase().contains('sos') ||
      body.toLowerCase().contains('alert') ||
      body.toLowerCase().contains('alarm');

  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
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
      summaryText: 'ONFLEET GPS',
    ),
  );

  const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  NotificationDetails notificationDetails = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    '$emoji $title',
    body,
    notificationDetails,
    payload: message.data.toString(),
  );
}

// Background notification response handler
@pragma('vm:entry-point')
void onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  // Handle background notification tap
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SharedPreferences first so they are always found
  try {
    UserRepository.prefs = await SharedPreferences.getInstance();
    final languageCode = UserRepository.prefs!.getString('language_code') ?? 'en_US';
    Get.updateLocale(Locale(languageCode));
  } catch (_) {}

  try {
    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize local notifications
    await _initializeLocalNotifications();

    // Create notification channels
    await _createNotificationChannels();

    // Request permissions
    await _requestNotificationPermissions();

    // Set foreground notification options
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Setup foreground message listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      showForegroundNotification(message);
    });

    // Handle notification tap when app opens from terminated state
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        Future.delayed(const Duration(seconds: 2), () {
          try {
            Get.toNamed('/events');
          } catch (_) {}
        });
      }
    });

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      Future.delayed(const Duration(milliseconds: 500), () {
        try {
          Get.toNamed('/events');
        } catch (_) {}
      });
    });

    // Initialize NotificationService
    await NotificationService().initialize(flutterLocalNotificationsPlugin);

    // Get FCM token (for server registration if needed)
    await FirebaseMessaging.instance.getToken();

    // Listen for token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      // TODO: Send new token to your server
    });
  } catch (_) {}

  runApp(Phoenix(child: const MyApp()));
}

// Initialize local notifications plugin
Future<void> _initializeLocalNotifications() async {
  const AndroidInitializationSettings androidSettings =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
    requestSoundPermission: true,
    requestBadgePermission: true,
    requestAlertPermission: true,
    defaultPresentAlert: true,
    defaultPresentBadge: true,
    defaultPresentSound: true,
  );

  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
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

// Create notification channels
Future<void> _createNotificationChannels() async {
  if (!Platform.isAndroid) return;

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();

  if (androidPlugin != null) {
    const AndroidNotificationChannel highChannel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'Used for important notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await androidPlugin.createNotificationChannel(highChannel);

    const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
      'alert_channel',
      'Alert Notifications',
      description: 'Critical alerts and emergency notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await androidPlugin.createNotificationChannel(alertChannel);

    const AndroidNotificationChannel defaultChannel =
    AndroidNotificationChannel(
      'default_channel',
      'Default Notifications',
      description: 'Default notification channel',
      importance: Importance.high,
      playSound: true,
    );
    await androidPlugin.createNotificationChannel(defaultChannel);
  }
}

// Request notification permissions
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
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }
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

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFFF0000),
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
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
            scrollBehavior: const _PremiumScrollBehavior(),
            theme: ThemeData(
              useMaterial3: true,
              primaryColor: CustomColor.primary,
              colorScheme: ColorScheme.fromSeed(
                seedColor: CustomColor.primary,
                primary: CustomColor.primary,
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.black,
              ),
              visualDensity: VisualDensity.adaptivePlatformDensity,
              splashFactory: InkSparkle.splashFactory,
              fontFamily: 'Plus Jakarta Sans',
              appBarTheme: const AppBarTheme(
                elevation: 0,
                scrolledUnderElevation: 0,
                systemOverlayStyle: SystemUiOverlayStyle(
                  statusBarColor: Color(0xFFFF0000),
                  statusBarBrightness: Brightness.dark,
                  statusBarIconBrightness: Brightness.light,
                ),
              ),
              pageTransitionsTheme: PageTransitionsTheme(
                builders: {
                  TargetPlatform.android: const _SmoothPageTransitionBuilder(),
                  TargetPlatform.iOS: const _SmoothPageTransitionBuilder(),
                },
              ),
            ),
            builder: (context, child) {
              return Stack(
                children: [
                  child!,
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: MediaQuery.of(context).padding.top,
                    child: IgnorePointer(
                      child: Container(
                        color: const Color(0xFFFF0000),
                      ),
                    ),
                  ),
                ],
              );
            },
            initialRoute: '/',
            routes: routes,
          ),
        );
      });
    });
  }
}