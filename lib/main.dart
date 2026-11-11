import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'screens/home_screen.dart';
import 'screens/nurse_login.dart';
import 'screens/nurse_register.dart';
import 'screens/nurse_dashboard.dart';
import 'screens/nurse_group_chat.dart';
import 'screens/ceo_control.dart';

/// Background FCM handler - works even when app is closed
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Background notification: ${message.notification?.title}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // OneSignal - Replace with your App ID from OneSignal Dashboard
  OneSignal.initialize("YOUR_ONESIGNAL_APP_ID");
  OneSignal.Notifications.requestPermission(true);

  // FCM - Request permission + get token
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);
  String? token = await messaging.getToken();
  print('FCM Token: $token');

  runApp(const LoveCareApp());
}

class LoveCareApp extends StatelessWidget {
  const LoveCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LOVE CARE GLOBAL',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFA855F7),
        scaffoldBackgroundColor: const Color(0xFF0E0A1C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFA855F7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      routes: {
        '/login': (context) => const NurseLoginScreen(),
        '/register': (context) => const NurseRegisterScreen(),
        '/dashboard': (context) => const NurseDashboardScreen(),
        '/group-chat': (context) => const NurseGroupChatScreen(),
        '/ceo': (context) => const CEOControlScreen(),
      },
    );
  }
}
