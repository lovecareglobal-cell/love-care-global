import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/index.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase is optional on Web - if it fails, app still opens
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyB52-X1D8Cg-wUDWPds_tR7X3cF82dMdRg",
          authDomain: "web-care-618e8.firebaseapp.com",
          databaseURL: "https://web-care-618e8-default-rtdb.firebaseio.com",
          projectId: "web-care-618e8",
          storageBucket: "web-care-618e8.firebasestorage.app",
          messagingSenderId: "1062578660694",
          appId: "1:1062578660694:web:f94dfe12c929df05bce2f7",
        ),
      );
    }
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
  }
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFA855F7), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const IndexScreen(),
      // NOTE: Add other routes ONLY after index.dart opens green.
      // Do NOT import all screens here yet - one broken screen breaks the whole build.
    );
  }
}
