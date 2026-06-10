import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:smart_lock/services/model/event.dart';


@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await _showBackgroundNotification(message);
}

// Helper function to show notification in background
Future<void> _showBackgroundNotification(RemoteMessage message) async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings initializationSettingsIOS =
  DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.max,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  final notification = message.notification;
  final data = message.data;

  String title = notification?.title ?? data['title'] ?? 'New Notification';
  String body = notification?.body ?? data['body'] ?? 'You have a new message';

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'high_importance_channel',
    'High Importance Notifications',
    channelDescription: 'This channel is used for important notifications.',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
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

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    notificationDetails,
    payload: message.data.toString(),
  );
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
      await _requestPermissions();
      await _createNotificationChannels();
      _setupMessageHandlers();
      await _fcm.getToken();
      _isInitialized = true;
    } catch (_) {}
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
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
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

    const AndroidNotificationChannel highImportanceChannel =
    AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      ledColor: Color(0xFFFF0000),
    );

    const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
      'alert_channel_v1',
      'Alert Notifications',
      description: 'Critical alerts and SOS notifications',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      ledColor: Color(0xFFFF0000),
    );

    const AndroidNotificationChannel eventChannel = AndroidNotificationChannel(
      'event_channel_v1',
      'Event Notifications',
      description: 'GPS tracking event notifications',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    const AndroidNotificationChannel sosChannel = AndroidNotificationChannel(
      'sos_channel_v1',
      'SOS Notifications',
      description: 'Emergency SOS alerts',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      ledColor: Color(0xFFFF0000),
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(highImportanceChannel);
      await androidPlugin.createNotificationChannel(alertChannel);
      await androidPlugin.createNotificationChannel(eventChannel);
      await androidPlugin.createNotificationChannel(sosChannel);
    }
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
        _handleNotificationOpen(message.data);
      }
    });

    // Handle notification tap when app is in BACKGROUND
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationOpen(message.data);
    });
  }

  Future<void> _showForegroundNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'This channel is used for important notifications.',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(''),
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

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
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
          summaryText: 'Smart lock GPS',
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
    final eventStyle = _getEventStyle(event.message ?? '');

    String channelId;
    if (eventStyle.isSOS) {
      channelId = 'sos_channel_v1';
    } else if (eventStyle.isAlert) {
      channelId = 'alert_channel_v1';
    } else {
      channelId = 'event_channel_v1';
    }

    await showLocalNotification(
      id: event.id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: '${eventStyle.emoji} ${event.device_name ?? "Unknown Device"}',
      body: event.message ?? 'New event occurred',
      payload: event.id.toString(),
      channelId: channelId,
      priority: eventStyle.isAlert ? Priority.max : Priority.high,
      importance: eventStyle.isAlert ? Importance.max : Importance.high,
    );
  }

  String _getChannelName(String channelId) {
    switch (channelId) {
      case 'alert_channel_v1':
        return 'Alert Notifications';
      case 'sos_channel_v1':
        return 'SOS Notifications';
      case 'event_channel_v1':
      default:
        return 'Event Notifications';
    }
  }

  String _getChannelDescription(String channelId) {
    switch (channelId) {
      case 'alert_channel_v1':
        return 'Critical alerts notifications';
      case 'sos_channel_v1':
        return 'Emergency SOS alerts';
      case 'event_channel_v1':
      default:
        return 'GPS tracking event notifications';
    }
  }

  void _handleNotificationOpen(Map<String, dynamic> data) {
    Future.delayed(const Duration(milliseconds: 500), () {
      try {
        Get.toNamed('/events');
      } catch (_) {}
    });
  }

  _EventNotificationStyle _getEventStyle(String message) {
    message = message.toLowerCase();

    if (message.contains('sos')) {
      return _EventNotificationStyle(emoji: '🆘', isAlert: true, isSOS: true);
    } else if (message.contains('alarm') || message.contains('alert')) {
      return _EventNotificationStyle(emoji: '🚨', isAlert: true, isSOS: false);
    } else if (message.contains('speed')) {
      return _EventNotificationStyle(emoji: '⚡', isAlert: true, isSOS: false);
    } else if (message.contains('geofence')) {
      return _EventNotificationStyle(emoji: '📍', isAlert: false, isSOS: false);
    } else if (message.contains('ignition')) {
      return _EventNotificationStyle(emoji: '🔑', isAlert: false, isSOS: false);
    } else if (message.contains('online')) {
      return _EventNotificationStyle(emoji: '✅', isAlert: false, isSOS: false);
    } else if (message.contains('offline')) {
      return _EventNotificationStyle(emoji: '❌', isAlert: false, isSOS: false);
    } else if (message.contains('fuel')) {
      return _EventNotificationStyle(emoji: '⛽', isAlert: true, isSOS: false);
    } else if (message.contains('battery')) {
      return _EventNotificationStyle(emoji: '🔋', isAlert: true, isSOS: false);
    }

    return _EventNotificationStyle(emoji: '🔔', isAlert: false, isSOS: false);
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

class _EventNotificationStyle {
  final String emoji;
  final bool isAlert;
  final bool isSOS;

  _EventNotificationStyle({
    required this.emoji,
    required this.isAlert,
    required this.isSOS,
  });
}