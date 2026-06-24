import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:smart_lock/firebase_options.dart';
import 'package:smart_lock/services/model/event.dart';

// ─── Background plugin singletons (initialized once, reused on every message) ─
FlutterLocalNotificationsPlugin? _bgPlugin;
bool _bgPluginReady = false;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Only initialize Firebase if it hasn't been initialized yet
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
    } catch (_) {}
  }
  await _showBackgroundNotification(message);
}

// Helper function to show notification in background
Future<void> _showBackgroundNotification(RemoteMessage message) async {
  try {
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
      _bgPluginReady = true;
    }

    final String title = message.notification?.title ??
        message.data['title'] as String? ??
        'New Notification';
    final String body = message.notification?.body ??
        message.data['body'] as String? ??
        'You have a new message';
    final String emoji = _getEmojiForMessage(body);
    final String channelId = _getChannelIdForMessage(body);

    await _bgPlugin!.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '$emoji $title',
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _getChannelName(channelId),
          channelDescription: _getChannelDescription(channelId),
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data.toString(),
    );
  } catch (e) {
    debugPrint('Background notification error: $e');
  }
}

@pragma('vm:entry-point')
void onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  // Handle background notification tap if needed
}

// ─── Helper Functions ────────────────────────────────────────────────────────
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
  if (lower.contains('power')) return '🔌';
  if (lower.contains('battery')) return '🔋';
  return '🔔';
}

String _getChannelIdForMessage(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('sos')) return 'sos_channel_v1';
  if (lower.contains('alarm') ||
      lower.contains('alert') ||
      lower.contains('speed') ||
      lower.contains('fuel') ||
      lower.contains('power') ||
      lower.contains('battery')) {
    return 'alert_channel_v1';
  }
  return 'event_channel_v1';
}

String _getChannelName(String channelId) {
  switch (channelId) {
    case 'alert_channel_v1':
    case 'alert_channel':
      return 'Alert Notifications';
    case 'sos_channel_v1':
    case 'sos_channel':
      return 'SOS Notifications';
    case 'event_channel_v1':
    case 'event_channel':
    default:
      return 'Event Notifications';
  }
}

String _getChannelDescription(String channelId) {
  switch (channelId) {
    case 'alert_channel_v1':
    case 'alert_channel':
      return 'Critical alerts notifications';
    case 'sos_channel_v1':
    case 'sos_channel':
      return 'Emergency SOS alerts';
    case 'event_channel_v1':
    case 'event_channel':
    default:
      return 'GPS tracking event notifications';
  }
}

// ============ MAIN NOTIFICATION SERVICE CLASS ============
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  late FlutterLocalNotificationsPlugin _localNotifications;

  bool _isInitialized = false;

  Future<void> initialize(FlutterLocalNotificationsPlugin plugin) async {
    if (_isInitialized) return;

    _localNotifications = plugin;

    try {
      // 1. Initialize local notifications
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

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          if (response.payload != null) {
            _handleNotificationOpen(response.payload);
          }
        },
        onDidReceiveBackgroundNotificationResponse:
            onDidReceiveBackgroundNotificationResponse,
      );

      // 2. Request permissions
      await _requestPermissions();

      // 3. Create all notification channels
      await _createNotificationChannels();

      // 4. Setup FCM handlers
      _setupMessageHandlers();

      // 5. Fetch and update FCM token
      await _fcm.getToken();

      _isInitialized = true;
    } catch (e) {
      debugPrint('NotificationService initialization error: $e');
    }
  }

  Future<void> _requestPermissions() async {
    await _fcm.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: true,
      provisional: false,
      sound: true,
    );

    if (Platform.isAndroid) {
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
      }
    }

    if (Platform.isIOS) {
      await _localNotifications
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

  Future<void> _createNotificationChannels() async {
    if (!Platform.isAndroid) return;

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return;

    const AndroidNotificationChannel highImportanceChannel =
        AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'Used for important notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
      'alert_channel',
      'Alert Notifications',
      description: 'Critical alerts and emergency notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    const AndroidNotificationChannel alertChannelV1 =
        AndroidNotificationChannel(
      'alert_channel_v1',
      'Alert Notifications',
      description: 'Critical alerts and SOS notifications',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      ledColor: Color(0xFFFF0000),
    );

    const AndroidNotificationChannel eventChannelV1 =
        AndroidNotificationChannel(
      'event_channel_v1',
      'Event Notifications',
      description: 'GPS tracking event notifications',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    const AndroidNotificationChannel sosChannelV1 = AndroidNotificationChannel(
      'sos_channel_v1',
      'SOS Notifications',
      description: 'Emergency SOS alerts',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      ledColor: Color(0xFFFF0000),
    );

    const AndroidNotificationChannel defaultChannel =
        AndroidNotificationChannel(
      'default_channel',
      'Default Notifications',
      description: 'Default notification channel',
      importance: Importance.high,
      playSound: true,
    );

    await Future.wait([
      androidPlugin.createNotificationChannel(highImportanceChannel),
      androidPlugin.createNotificationChannel(alertChannel),
      androidPlugin.createNotificationChannel(alertChannelV1),
      androidPlugin.createNotificationChannel(eventChannelV1),
      androidPlugin.createNotificationChannel(sosChannelV1),
      androidPlugin.createNotificationChannel(defaultChannel),
    ]);
  }

  void _setupMessageHandlers() {
    // Handle messages when app is in FOREGROUND
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;

      if (notification != null) {
        _showForegroundNotification(
          title: notification.title ?? 'New Notification',
          body: notification.body ?? '',
          data: message.data,
        );
      } else if (message.data.isNotEmpty) {
        _showForegroundNotification(
          title: message.data['title'] ?? 'New Notification',
          body: message.data['body'] ?? '',
          data: message.data,
        );
      }
    });

    // Handle notification tap when app was TERMINATED
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _handleNotificationOpen(message.data.toString());
      }
    });

    // Handle notification tap when app is in BACKGROUND
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationOpen(message.data.toString());
    });
  }

  Future<void> _showForegroundNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final String emoji = _getEmojiForMessage(body);
    final String channelId = _getChannelIdForMessage(body);

    final androidDetails = AndroidNotificationDetails(
      channelId,
      _getChannelName(channelId),
      channelDescription: _getChannelDescription(channelId),
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: '$emoji $title',
        summaryText: 'Smart Lock GPS',
      ),
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '$emoji $title',
      body,
      notificationDetails,
      payload: data?.toString(),
    );
  }

  Future<void> showLocalNotification({
    int? id,
    required String title,
    required String body,
    String? payload,
    String channelId = 'event_channel_v1',
    Priority priority = Priority.high,
    Importance importance = Importance.high,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        channelId,
        _getChannelName(channelId),
        channelDescription: _getChannelDescription(channelId),
        importance: importance,
        priority: priority,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'Smart Lock GPS',
        ),
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
    } catch (_) {
      await _showFallbackNotification(id, title, body, payload);
    }
  }

  Future<void> _showFallbackNotification(
    int? id,
    String title,
    String body,
    String? payload,
  ) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'default_channel',
        'Default Notifications',
        channelDescription: 'Default notification channel',
        importance: Importance.high,
        priority: Priority.high,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      await _localNotifications.show(
        id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(android: androidDetails, iOS: iosDetails),
        payload: payload,
      );
    } catch (_) {}
  }

  Future<void> showEventNotification(Event event) async {
    final String emoji = _getEmojiForMessage(event.message ?? '');
    final String channelId = _getChannelIdForMessage(event.message ?? '');
    final bool isAlert =
        channelId == 'alert_channel_v1' || channelId == 'sos_channel_v1';

    await showLocalNotification(
      id: event.id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: '$emoji ${event.device_name ?? "Unknown Device"}',
      body: event.message ?? 'New event occurred',
      payload: event.id.toString(),
      channelId: channelId,
      priority: isAlert ? Priority.max : Priority.high,
      importance: isAlert ? Importance.max : Importance.high,
    );
  }

  void _handleNotificationOpen(dynamic payload) {
    Future.delayed(const Duration(milliseconds: 500), () {
      try {
        Get.toNamed('/events');
      } catch (_) {}
    });
  }

  Future<String?> getToken() async {
    return await _fcm.getToken();
  }

  Future<void> cancelAll() async {
    await _localNotifications.cancelAll();
  }

  Future<void> cancel(int id) async {
    await _localNotifications.cancel(id);
  }
}
