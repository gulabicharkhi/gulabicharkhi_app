// ============================================================
// lib/services/notification_service.dart
//
// Flutter-side setup for Firebase Cloud Messaging (FCM).
//
// USAGE (in main.dart):
//   await NotificationService.init();
//
// USAGE (after login or in AuthService.login()):
//   await NotificationService.registerToken();
//
// USAGE (in logout):
//   await NotificationService.clearToken();
// ============================================================

import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

// ── Background message handler (top-level function — required by FCM) ──────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // A message arrived while the app is in the background
  // Firebase already shows the notification on Android
  debugPrint('[FCM] Background message: ${message.messageId}');
}

class NotificationService {
  NotificationService._();

  static final _fcm         = FirebaseMessaging.instance;
  static final _localPlugin = FlutterLocalNotificationsPlugin();

  // ── To navigate on notification tap ───────────────────────────
  // Set in main.dart: NotificationService.onTap = (data) { ... }
  static void Function(Map<String, dynamic> data)? onTap;

  // The onTokenRefresh listener is attached only once (registerToken can be called multiple times)
  static bool _refreshListening = false;

  // ============================================================
  // INIT — in main.dart, after WidgetsFlutterBinding.ensureInitialized()
  //         call this
  // ============================================================
  static Future<void> init() async {
    // 1. Register the background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Create the Android notification channel (high importance)
    const channel = AndroidNotificationChannel(
      'gulabi_battles',          // match the channelId sent by the server
      'Gulabi Battle Alerts',
      description: 'Kite battle challenges and updates',
      importance: Importance.high,
      playSound: true,
    );

    await _localPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 3. Initialize flutter_local_notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings     = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _localPlugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // 4. iOS/macOS permissions: request them
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 5. Handle foreground messages (when the app is open)
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 6. Handle notification tap (app opened from the background)
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // 7. The app was terminated and opened from a notification
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      _handleNavigation(initial.data);
    }

    debugPrint('[FCM] NotificationService initialized');
  }

  // ============================================================
  // TOKEN REGISTER — call after login
  // ============================================================
  static Future<void> registerToken() async {
    try {
      final token = await _fcm.getToken();
      if (token == null) return;

      debugPrint('[FCM] Token: ${token.substring(0, 20)}...');
      await _sendTokenToServer(token);

      // Send again when the token refreshes (listen only once)
      if (!_refreshListening) {
        _refreshListening = true;
        _fcm.onTokenRefresh.listen((newToken) async {
          debugPrint('[FCM] Token refreshed');
          await _sendTokenToServer(newToken);
        });
      }
    } catch (e) {
      debugPrint('[FCM] Token register error: $e');
    }
  }

  // ============================================================
  // TOKEN CLEAR — call on logout
  // ============================================================
  static Future<void> clearToken() async {
    try {
      final authToken = await AuthService.getToken();
      if (authToken == null) return;

      await http.delete(
        Uri.parse('${AuthService.baseUrl}/notifications/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[FCM] Clear token error: $e');
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static Future<void> _sendTokenToServer(String fcmToken) async {
    try {
      final authToken = await AuthService.getToken();
      if (authToken == null) return;

      final res = await http.post(
        Uri.parse('${AuthService.baseUrl}/notifications/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'token': fcmToken}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        debugPrint('[FCM] Token saved to server ✅');
      } else {
        debugPrint('[FCM] Token save failed: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('[FCM] Send token error: $e');
    }
  }

  // If the app is in the foreground, show a local notification
  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    debugPrint('[FCM] Foreground message: ${message.notification?.title}');
    final notification = message.notification;
    final android      = message.notification?.android;
    if (notification == null) return;

    await _localPlugin.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'gulabi_battles',
          'Gulabi Battle Alerts',
          channelDescription: 'Kite battle challenges and updates',
          importance: Importance.high,
          priority:   Priority.high,
          icon: android?.smallIcon ?? '@mipmap/ic_launcher',
          playSound: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  static void _onMessageOpenedApp(RemoteMessage message) {
    debugPrint('[FCM] App opened from notification');
    _handleNavigation(message.data);
  }

  static void _onLocalNotificationTap(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _handleNavigation(data);
    } catch (_) {}
  }

  // Navigate based on the notification data
  static void _handleNavigation(Map<String, dynamic> data) {
    if (onTap != null) {
      onTap!(data);
    } else {
      // Default: print the data (onTap is not set)
      debugPrint('[FCM] Navigation data: $data');
    }
  }
}
