// apk_alerts.dart - ROAD B ONLY: Real APK, not website.
// Put in: lib/screens/apk_alerts.dart
// Call once in main.dart AFTER Firebase init:
//   await ApkAlerts.init();
//
// HOW IT WORKS (APK only):
//   App CLOSED -> FCM push arrives -> Firebase background handler wakes APK
//   -> flutter_local_notifications shows notification WITH your custom sound
//   -> Sound file MUST be in: android/app/src/main/res/raw/love_care_bell.mp3
//   -> That file is NOT in assets/ - Android only plays notification sounds from res/raw.
//   On WEBSITE / PWA this file does nothing - Chrome blocks custom sound when closed.
//   On APK it works - this is why APK is needed for your exact bell/siren.
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();

Future<void> _apkBackgroundHandler(RemoteMessage msg) async {
  // This runs even when APK is CLOSED. Keep it tiny - no Firebase init here
  // if main() already did it, but for safety we play via local notification.
  await ApkAlerts.showWithCustomSound(
    title: msg.notification?.title ?? 'Love Care Global',
    body: msg.notification?.body ?? 'New info on your dashboard',
  );
}

class ApkAlerts {
  static bool _init = false;

  static Future<void> init() async {
    if (_init) return;
    _init = true;
    // WEB: no Android notifications, no background handler - skip everything.
    // This is what lets `flutter build web` pass.
    if (kIsWeb) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const init = InitializationSettings(android: androidInit);
      await _notif.initialize(init);
      // Create a channel that uses YOUR sound. Channel ID must match Cloud Function.
      // NOTE: NOT const anymore - RawResourceAndroidNotificationSound
      // breaks const evaluation on Flutter 3.35 / v19.
      final channel = AndroidNotificationChannel(
        'love_care_alerts', // <-- Cloud Function sends to this channel
        'Love Care Alerts',
        description: 'CEO / Nurse / Client alerts - custom Love Care sound',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('love_care_bell'),
        enableVibration: true,
      );
      await _notif
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      // Ask Android 13+ permission: "Allow Notifications?"
      await _notif
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      // FCM background handler - this is what wakes the APK when closed.
      FirebaseMessaging.onBackgroundMessage(_apkBackgroundHandler);
      // FCM foreground - app OPEN, also show local notification with custom sound
      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        showWithCustomSound(
          title: msg.notification?.title ?? 'Love Care Global',
          body: msg.notification?.body ?? 'New info on your dashboard',
        );
      });
    } catch (_) {}
  }

  static Future<void> showWithCustomSound({required String title, required String body}) async {
    if (kIsWeb) return;
    try {
      // NOTE: NOT const anymore - same fix as above.
      final android = AndroidNotificationDetails(
        'love_care_alerts',
        'Love Care Alerts',
        channelDescription: 'CEO / Nurse / Client alerts - custom Love Care sound',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('love_care_bell'),
        enableVibration: true,
        ticker: 'Love Care Global',
      );
      final details = NotificationDetails(android: android);
      await _notif.show(DateTime.now().millisecondsSinceEpoch % 100000, title, body, details);
    } catch (_) {}
  }
}
