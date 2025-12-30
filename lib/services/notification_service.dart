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

  Future<void> initialize(FlutterLocalNotificationsPlugin plugin) async {
    if (_isInitialized) return;

    _localNotifications = plugin;

    try {
      await _createNotificationChannels();
      _setupMessageHandlers();
      _isInitialized = true;
    } catch (e) {
      print("Error initializing notification service: $e");
    }
  }

  // Create Android notification channels - USE DEFAULT SOUND FIRST
  Future<void> _createNotificationChannels() async {
    if (!Platform.isAndroid) return;

    // Alert channel - using default sound (safer)
    const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
      'alert_channel_v1', // Use versioned channel ID
      'Alert Notifications',
      description: 'Critical alerts and SOS notifications',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      ledColor: Color(0xFFFF0000),
      // Remove custom sound to test first, or use:
      // sound: RawResourceAndroidNotificationSound('alert_sound'),
    );

    // Event channel
    const AndroidNotificationChannel eventChannel = AndroidNotificationChannel(
      'event_channel_v1', // Use versioned channel ID
      'Event Notifications',
      description: 'GPS tracking event notifications',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    // SOS channel
    const AndroidNotificationChannel sosChannel = AndroidNotificationChannel(
      'sos_channel_v1', // Use versioned channel ID
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
      await androidPlugin.createNotificationChannel(alertChannel);
      await androidPlugin.createNotificationChannel(eventChannel);
      await androidPlugin.createNotificationChannel(sosChannel);
    }
  }

  void _setupMessageHandlers() {
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _handleNotificationOpen(message.data);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationOpen(message.data);
    });
  }

  // Show local notification - WITH ERROR HANDLING
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
        // Use default sound (remove custom sound for now)
        // sound: RawResourceAndroidNotificationSound('notification_sound'),
        icon: '@mipmap/ic_launcher', // Use default launcher icon
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'Trust Me',
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
    } catch (e) {
      print("Error showing notification: $e");
      // Fallback: Try with minimal settings
      await _showFallbackNotification(id, title, body, payload);
    }
  }

  // Fallback notification with minimal settings
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
    } catch (e) {
      print("Fallback notification also failed: $e");
    }
  }

  // Show event notification
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
    print("Notification opened with data: $data");

    Future.delayed(const Duration(milliseconds: 500), () {
      try {
        Get.toNamed('/events');
      } catch (e) {
        print("Navigation error: $e");
      }
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