import 'dart:developer';
import 'dart:io';
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
import 'package:gpspro/services/notification_service.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'translation/translation_service.dart';

// Global notification plugin instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

// High importance notification channel WITH SOUND
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: 'Used for important notifications',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  enableLights: true,
  ledColor: Color(0xFFFF0000),
  // Add custom sound (make sure file exists in android/app/src/main/res/raw/)
  sound: RawResourceAndroidNotificationSound('notification_sound'),
);

// Alert channel for critical alerts
const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
  'alert_channel',
  'Alert Notifications',
  description: 'Critical alerts and emergency notifications',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  enableLights: true,
  ledColor: Color(0xFFFF0000),
  sound: RawResourceAndroidNotificationSound('alert_sound'),
);

// ⚠️ MUST BE TOP-LEVEL FUNCTION - Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase for background isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  log("Background message received: ${message.messageId}");
  log("Background message data: ${message.data}");
  log("Background notification: ${message.notification?.title}");

  // Show notification
  await _showBackgroundNotification(message);
}

// Show notification for background messages
Future<void> _showBackgroundNotification(RemoteMessage message) async {
  // Re-initialize the plugin for background isolate
  const AndroidInitializationSettings androidSettings =
  AndroidInitializationSettings('logo');

  const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
    requestSoundPermission: false,
    requestBadgePermission: false,
    requestAlertPermission: false,
  );

  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    ),
  );

  // Create the channel (in case it doesn't exist)
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // Get notification content
  String title = message.notification?.title ??
      message.data['title'] ??
      'New Notification';
  String body = message.notification?.body ??
      message.data['body'] ??
      'You have a new message';

  // Get emoji based on message content
  String emoji = _getEmojiForMessage(body);

  // Determine which channel to use
  String channelId = channel.id;
  String channelName = channel.name;
  RawResourceAndroidNotificationSound? sound =
  const RawResourceAndroidNotificationSound('notification_sound');

  if (body.toLowerCase().contains('sos') ||
      body.toLowerCase().contains('alert') ||
      body.toLowerCase().contains('alarm')) {
    channelId = alertChannel.id;
    channelName = alertChannel.name;
    sound = const RawResourceAndroidNotificationSound('alert_sound');
  }

  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    channelId,
    channelName,
    channelDescription: 'Important notifications',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    sound: sound,
    enableVibration: true,
    icon: 'logo',
    styleInformation: BigTextStyleInformation(
      body,
      contentTitle: '$emoji $title',
      summaryText: 'Trust Me',
    ),
  );

  const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    sound: 'notification_sound.aiff',
  );

  NotificationDetails notificationDetails = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique ID
    '$emoji $title',
    body,
    notificationDetails,
    payload: message.data.toString(),
  );

  log("Background notification shown: $title");
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
  log("Foreground message received: ${message.notification?.title}");

  String title = message.notification?.title ??
      message.data['title'] ??
      'New Notification';
  String body = message.notification?.body ??
      message.data['body'] ??
      'You have a new message';

  String emoji = _getEmojiForMessage(body);

  // Determine channel and sound
  String channelId = channel.id;
  String channelName = channel.name;
  RawResourceAndroidNotificationSound sound =
  const RawResourceAndroidNotificationSound('notification_sound');

  if (body.toLowerCase().contains('sos') ||
      body.toLowerCase().contains('alert') ||
      body.toLowerCase().contains('alarm')) {
    channelId = alertChannel.id;
    channelName = alertChannel.name;
    sound = const RawResourceAndroidNotificationSound('alert_sound');
  }

  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    channelId,
    channelName,
    channelDescription: 'Important notifications',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    sound: sound,
    enableVibration: true,
    icon: 'logo',
    largeIcon: const DrawableResourceAndroidBitmap('logo'),
    styleInformation: BigTextStyleInformation(
      body,
      contentTitle: '$emoji $title',
      summaryText: 'Trust Me',
    ),
  );

  const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    sound: 'notification_sound.aiff',
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

  log("Foreground notification shown: $title");
}

// Background notification response handler
@pragma('vm:entry-point')
void onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  log('Background notification tapped: ${response.payload}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 1. Initialize Firebase FIRST
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    log("Firebase initialized successfully");

    // 2. Set background message handler IMMEDIATELY after Firebase init
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 3. Initialize local notifications
    await _initializeLocalNotifications();

    // 4. Create notification channels
    await _createNotificationChannels();

    // 5. Request permissions
    await _requestNotificationPermissions();

    // 6. Set foreground notification options
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 7. Setup foreground message listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log("onMessage: ${message.notification?.title}");
      showForegroundNotification(message);
    });

    // 8. Handle notification tap when app opens from terminated state
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        log("App opened from terminated state: ${message.data}");
        Future.delayed(const Duration(seconds: 1), () {
          Get.toNamed('/events');
        });
      }
    });

    // 9. Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      log("Notification opened app: ${message.data}");
      Future.delayed(const Duration(milliseconds: 500), () {
        Get.toNamed('/events');
      });
    });

    // 10. Initialize NotificationService (for event notifications)
    await NotificationService().initialize(flutterLocalNotificationsPlugin);

    // 11. Get and log FCM token
    String? token = await FirebaseMessaging.instance.getToken();
    log("FCM Token: $token");

    // 12. Initialize SharedPreferences
    UserRepository.prefs = await SharedPreferences.getInstance();
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('language_code') ?? 'en_US';
    Get.updateLocale(Locale(languageCode));

    runApp(Phoenix(child: const MyApp()));

  } catch (e, stackTrace) {
    log('Error during initialization: $e');
    log('Stack trace: $stackTrace');
    // Run app even if there's an error
    runApp(Phoenix(child: const MyApp()));
  }
}

// Initialize local notifications plugin
Future<void> _initializeLocalNotifications() async {
  const AndroidInitializationSettings androidSettings =
  AndroidInitializationSettings('logo');

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
      log('Notification tapped: ${response.payload}');
      if (response.payload != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          try {
            Get.toNamed('/events');
          } catch (e) {
            log('Navigation error: $e');
          }
        });
      }
    },
    onDidReceiveBackgroundNotificationResponse:
    onDidReceiveBackgroundNotificationResponse,
  );

  log("Local notifications initialized");
}

// Create notification channels
Future<void> _createNotificationChannels() async {
  if (!Platform.isAndroid) return;

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();

  if (androidPlugin != null) {
    // Create main channel
    await androidPlugin.createNotificationChannel(channel);

    // Create alert channel
    await androidPlugin.createNotificationChannel(alertChannel);

    // Create default channel (without custom sound as fallback)
    const AndroidNotificationChannel defaultChannel = AndroidNotificationChannel(
      'default_channel',
      'Default Notifications',
      description: 'Default notification channel',
      importance: Importance.high,
      playSound: true,
    );
    await androidPlugin.createNotificationChannel(defaultChannel);

    log("Notification channels created");
  }
}

// Request notification permissions
Future<void> _requestNotificationPermissions() async {
  // FCM permissions
  NotificationSettings settings =
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: true,
    provisional: false,
    sound: true,
  );

  log('FCM permission status: ${settings.authorizationStatus}');

  // Android 13+ permission
  if (Platform.isAndroid) {
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      log('Android notification permission granted: $granted');
    }
  }

  // iOS permissions
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
      });
    });
  }
}