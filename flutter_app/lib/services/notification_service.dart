// ============================================================
// lib/services/notification_service.dart
//
// Firebase Cloud Messaging (FCM) ka Flutter side setup.
//
// USAGE (main.dart mein):
//   await NotificationService.init();
//
// USAGE (login ke baad ya AuthService.login() mein):
//   await NotificationService.registerToken();
//
// USAGE (logout mein):
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
  // App background mein hai tab message aaya
  // Firebase already notification show kar deta hai Android par
  debugPrint('[FCM] Background message: ${message.messageId}');
}

class NotificationService {
  NotificationService._();

  static final _fcm         = FirebaseMessaging.instance;
  static final _localPlugin = FlutterLocalNotificationsPlugin();

  // ── Notification tap par navigate karne ke liye ───────────────────────────
  // main.dart mein set karo: NotificationService.onTap = (data) { ... }
  static void Function(Map<String, dynamic> data)? onTap;

  // onTokenRefresh listener sirf ek baar lagta hai (registerToken kai baar call ho sakta hai)
  static bool _refreshListening = false;

  // ============================================================
  // INIT — main.dart mein WidgetsFlutterBinding.ensureInitialized()
  //         ke baad call karo
  // ============================================================
  static Future<void> init() async {
    // 1. Background handler register karo
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Android notification channel create karo (high importance)
    const channel = AndroidNotificationChannel(
      'gulabi_battles',          // server se jo channelId bheja hai usse match karo
      'Gulabi Battle Alerts',
      description: 'Kite battle challenges aur updates',
      importance: Importance.high,
      playSound: true,
    );

    await _localPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 3. flutter_local_notifications initialize karo
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

    // 4. iOS/macOS permissions maango
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 5. Foreground messages handle karo (app khuli ho tab)
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 6. Notification tap handle karo (app background se open hui)
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // 7. App terminate thi aur notification se khuli
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      _handleNavigation(initial.data);
    }

    debugPrint('[FCM] NotificationService initialized');
  }

  // ============================================================
  // TOKEN REGISTER — login ke baad call karo
  // ============================================================
  static Future<void> registerToken() async {
    try {
      final token = await _fcm.getToken();
      if (token == null) return;

      debugPrint('[FCM] Token: ${token.substring(0, 20)}...');
      await _sendTokenToServer(token);

      // Token refresh hone par dobara bhejo (sirf ek baar listen karo)
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
  // TOKEN CLEAR — logout par call karo
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

  // App foreground mein hai to local notification dikhao
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
          channelDescription: 'Kite battle challenges aur updates',
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

  // Notification data ke basis par navigate karo
  static void _handleNavigation(Map<String, dynamic> data) {
    if (onTap != null) {
      onTap!(data);
    } else {
      // Default: data print karo (onTap set nahi hai)
      debugPrint('[FCM] Navigation data: $data');
    }
  }
}
