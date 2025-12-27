import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:gpspro/services/model/event.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  late FlutterLocalNotificationsPlugin _localNotifications;

  bool _isInitialized = false;

  // Initialize notification service
  Future<void> initialize(FlutterLocalNotificationsPlugin plugin) async {
    if (_isInitialized) return;

    _localNotifications = plugin;

    try {
      // Create additional notification channels
      await _createNotificationChannels();

      // Setup message handlers
      _setupMessageHandlers();

      _isInitialized = true;
      print("✅ Notification Service Initialized");
    } catch (e) {
      print("❌ Notification initialization error: $e");
    }
  }

  // Create Android notification channels
  Future<void> _createNotificationChannels() async {
    if (!Platform.isAndroid) return;

    const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
      'alert_channel',
      'Alert Notifications',
      description: 'Critical alerts and SOS notifications',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      ledColor: Color(0xFFFF0000),
    );

    const AndroidNotificationChannel eventChannel = AndroidNotificationChannel(
      'event_channel',
      'Event Notifications',
      description: 'GPS tracking event notifications',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(alertChannel);
      await androidPlugin.createNotificationChannel(eventChannel);
    }
  }

  // Setup message handlers
  void _setupMessageHandlers() {
    // Handle notification opened from terminated state
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _handleNotificationOpen(message.data);
      }
    });

    // Handle notification opened from background state
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationOpen(message.data);
    });
  }

  // Show local notification for events
  Future<void> showEventNotification(Event event) async {
    final eventStyle = _getEventStyle(event.message ?? '');

    await showLocalNotification(
      id: event.id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: '${eventStyle.emoji} ${event.device_name ?? "Unknown Device"}',
      body: event.message ?? 'New event occurred',
      payload: event.id.toString(),
      channelId: eventStyle.isAlert ? 'alert_channel' : 'event_channel',
      priority: eventStyle.isAlert ? Priority.max : Priority.high,
      importance: eventStyle.isAlert ? Importance.max : Importance.high,
    );
  }

  // Show local notification
  Future<void> showLocalNotification({
    int? id,
    required String title,
    required String body,
    String? payload,
    String channelId = 'event_channel',
    Priority priority = Priority.high,
    Importance importance = Importance.high,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId == 'alert_channel'
          ? 'Alert Notifications'
          : 'Event Notifications',
      channelDescription: channelId == 'alert_channel'
          ? 'Critical alerts and SOS notifications'
          : 'GPS tracking event notifications',
      importance: importance,
      priority: priority,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: 'logo', // Your existing icon
      largeIcon: const DrawableResourceAndroidBitmap('logo'),
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'GPS Pro',
      ),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      subtitle: body,
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
  }

  // Handle notification open
  void _handleNotificationOpen(Map<String, dynamic> data) {
    print("Notification opened with data: $data");

    Future.delayed(const Duration(milliseconds: 500), () {
      try {
        if (data.containsKey('eventId')) {
          // Navigate to specific event
          Get.toNamed('/events');
        } else {
          // Navigate to events page
          Get.toNamed('/events');
        }
      } catch (e) {
        print("Navigation error: $e");
      }
    });
  }

  // Get event style
  _EventNotificationStyle _getEventStyle(String message) {
    message = message.toLowerCase();

    if (message.contains('alarm') ||
        message.contains('sos') ||
        message.contains('alert')) {
      return _EventNotificationStyle(emoji: '🚨', isAlert: true);
    } else if (message.contains('speed')) {
      return _EventNotificationStyle(emoji: '⚡', isAlert: true);
    } else if (message.contains('geofence')) {
      return _EventNotificationStyle(emoji: '📍', isAlert: false);
    } else if (message.contains('ignition')) {
      return _EventNotificationStyle(emoji: '🔑', isAlert: false);
    } else if (message.contains('online')) {
      return _EventNotificationStyle(emoji: '✅', isAlert: false);
    } else if (message.contains('offline')) {
      return _EventNotificationStyle(emoji: '❌', isAlert: false);
    } else if (message.contains('fuel')) {
      return _EventNotificationStyle(emoji: '⛽', isAlert: true);
    } else if (message.contains('battery')) {
      return _EventNotificationStyle(emoji: '🔋', isAlert: true);
    }

    return _EventNotificationStyle(emoji: '🔔', isAlert: false);
  }

  // Get FCM token
  Future<String?> getToken() async {
    return await _fcm.getToken();
  }

  // Cancel all notifications
  Future<void> cancelAll() async {
    await _localNotifications.cancelAll();
  }

  // Cancel specific notification
  Future<void> cancel(int id) async {
    await _localNotifications.cancel(id);
  }
}

class _EventNotificationStyle {
  final String emoji;
  final bool isAlert;

  _EventNotificationStyle({required this.emoji, required this.isAlert});
}