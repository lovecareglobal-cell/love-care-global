import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'language_service.dart';
import 'select_language_screen.dart';
import 'screens/auth_choice.dart';
import 'screens/auth_choice_page.dart';
import 'screens/client_login.dart';
import 'screens/client_registration.dart';
import 'screens/nurse_login.dart';
import 'screens/nurse_registration.dart';
import 'screens/ceo_control_page.dart';
import 'screens/community_guidance.dart';
import 'screens/privacy_policy.dart';
import 'screens/refund_policy.dart';
import 'screens/delete_account_policy.dart';
import 'screens/terms_and_conditions.dart';
import 'screens/health_disclaimer.dart';

// CEO FILES
import 'screens/ceo_dashboard.dart';
import 'screens/ceo_booking_progress.dart';
import 'screens/ceo_complainant.dart';
import 'screens/ceo_control_chat.dart';
import 'screens/ceo_control_pricing.dart';
import 'screens/ceo_finance.dart';
import 'screens/ceo_live_tracking_map.dart';
import 'screens/ceo_notification_room.dart';
import 'screens/ceo_penalize.dart';
import 'screens/ceo_refund_management.dart';
import 'screens/ceo_registration_center.dart';
import 'screens/chat_room.dart';
import 'screens/hr_page.dart';
import 'screens/nurse_group_chat.dart';

// STAFF LOGIN + CREATE ACCESS + VISITS MONITOR + FORCE DELETE
import 'screens/staff_login.dart';
import 'screens/ceo_create_access.dart';
import 'screens/staff_visits_monitor.dart';
import 'screens/force_delete.dart';
import 'screens/sound_settings.dart';
import 'screens/dashboard_alerts.dart';
import 'screens/apk_alerts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';

// ALL SCREENS
// NEW 20/80 RULE: 50% DELETED, Increase Payment DELETED, Nurse Withdrawal DELETED.
// Client pays 20% CEO fee in app. Nurse cash 80% paid CASH by client after work. CEO never pays nurse.
import 'screens/alert_settings.dart';
import 'screens/book_nurse.dart';
import 'screens/client_complaint.dart';
import 'screens/client_dashboard.dart';
import 'screens/client_settings.dart';
import 'screens/my_bookings.dart';
import 'screens/my_job_offer.dart';
import 'screens/nurse_complaint.dart';
import 'screens/nurse_dashboard.dart';
import 'screens/nurse_settings.dart';
import 'screens/rating.dart';
import 'screens/refund_query.dart';
import 'screens/sos.dart';

// NO HARDCODED CEO PASSWORD HERE - Play Store safe.
// CEO login uses Firebase Auth (email + password typed by CEO) + Firestore ceoAccess check.

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

int _ceoNurseCount = -1;
int _ceoClientCount = -1;
bool _ceoRingSetup = false;
void _setupCeoAutoRing() {
  if (_ceoRingSetup) return;
  _ceoRingSetup = true;
  try {
    final db = FirebaseDatabase.instance;
    db.ref('ceoRegistrationCenter/nurses').onValue.listen((e) {
      final count = (e.snapshot.value is Map) ? (e.snapshot.value as Map).length : 0;
      if (_ceoNurseCount == -1) { _ceoNurseCount = count; return; }
      if (count > _ceoNurseCount) {
        _ceoNurseCount = count;
        SoundService.playCustomSound('new_nurse');
      } else {
        _ceoNurseCount = count;
      }
    });
    db.ref('ceoRegistrationCenter/clients').onValue.listen((e) {
      final count = (e.snapshot.value is Map) ? (e.snapshot.value as Map).length : 0;
      if (_ceoClientCount == -1) { _ceoClientCount = count; return; }
      if (count > _ceoClientCount) {
        _ceoClientCount = count;
        SoundService.playCustomSound('new_client');
      } else {
        _ceoClientCount = count;
      }
    });
  } catch (_) {}
}

Future<void> _setupFCM() async {
  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
    debugPrint('FCM permission: ${settings.authorizationStatus}');
    try { await messaging.subscribeToTopic('ceo'); } catch (_) {}
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      SoundService.playCustomSound('push');
    });
    final token = await messaging.getToken(vapidKey: null);
    debugPrint('FCM TOKEN: $token');
  } catch (e) {
    debugPrint('FCM setup failed (web/demo mode): $e');
  }
}

// ===== FIX FOR reCAPTCHA SPINNING / OTP NEVER COMES - NEW =====
Future<void> _setupPhoneAuthNoRecaptcha() async {
  try {
    try {
      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
      final token = await FirebaseAppCheck.instance.getToken(false);
      debugPrint('AppCheck token ready: ${token != null && token.isNotEmpty}');
    } catch (e) {
      debugPrint('AppCheck warmup failed (will fallback): $e');
    }
    try {
      await FirebaseAuth.instance.setSettings(
        appVerificationDisabledForTesting: false,
        forceRecaptchaFlow: false,
      );
    } catch (e) {
      debugPrint('Auth settings failed: $e');
    }
  } catch (_) {}
}

/// Helper - use this everywhere you send OTP, instead of raw verifyPhoneNumber
class PhoneAuthHelper {
  static bool _sending = false;
  static Future<void> sendOtp({
    required String phone,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String message) onFailed,
    void Function()? onAutoVerified,
    int? forceResendingToken,
  }) async {
    if (_sending) return;
    _sending = true;
    try {
      try {
        await FirebaseAppCheck.instance.getToken(true);
      } catch (_) {}
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone.trim(),
        timeout: const Duration(seconds: 60),
        forceResendingToken: forceResendingToken,
        verificationCompleted: (PhoneAuthCredential cred) async {
          try {
            await FirebaseAuth.instance.signInWithCredential(cred);
            onAutoVerified?.call();
          } catch (_) {}
        },
        verificationFailed: (FirebaseAuthException e) {
          String msg = e.message ?? 'Verification failed';
          if (e.code == 'captcha-check-failed') {
            msg = 'reCAPTCHA check failed. Check internet, update Play Services, try again.';
          } else if (e.code == 'too-many-requests') {
            msg = 'Too many tries. Wait 10 mins and try again.';
          } else if (e.code == 'app-not-authorized') {
            msg = 'App not authorized. SHA-1 / SHA-256 missing in Firebase. Add B3:88... / E6:D1... + Play Signing SHAs.';
          }
          onFailed(msg);
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      onFailed('Could not send OTP: $e');
    } finally {
      Future.delayed(const Duration(seconds: 2), () => _sending = false);
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    try {
      await FirebaseAppCheck.instance.activate(androidProvider: AndroidProvider.playIntegrity);
    } catch (e) {
      debugPrint('App Check activate failed: $e');
    }
    await _setupPhoneAuthNoRecaptcha();
  } catch (e) {
    debugPrint('Firebase init failed (web/demo mode): $e');
  }
  _setupCeoAutoRing();
  await _setupFCM();
  await ApkAlerts.init();
  // LANGUAGE: Load saved language (Client / Nurse / CEO) BEFORE app starts
  // If user picked Yoruba before, app go start for Yoruba, no need pick again
  try { await LanguageService.instance.loadSaved(); } catch (_) {}
  runApp(const LoveCareApp());
}

class LoveCareApp extends StatelessWidget {
  const LoveCareApp({super.key});
  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.instance;
    // LANGUAGE GLOBAL: When language changes, rebuild WHOLE MaterialApp
    // That na why ALL pages change at once - Home, Book Nurse, Dashboards, Settings
    return ListenableBuilder(
      listenable: lang,
      builder: (_, __) => MaterialApp(
        title: 'Love Care Global',
        debugShowCheckedModeBanner: false,
        locale: lang.locale,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          primaryColor: const Color(0xFF880E4F),
          scaffoldBackgroundColor: const Color(0xFF4A0A26),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF880E4F),
            secondary: Color(0xFFAD1457),
            surface: Color(0xFF4A0A26),
            onPrimary: Colors.white,
            onSecondary: Colors.white,
            onSurface: Colors.white,
          ),
          textTheme: const TextTheme(
            bodyLarge: TextStyle(color: Colors.white),
            bodyMedium: TextStyle(color: Colors.white),
            bodySmall: TextStyle(color: Colors.white70),
            titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            titleMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            titleSmall: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            labelLarge: TextStyle(color: Colors.white),
            labelMedium: TextStyle(color: Colors.white),
          ),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF880E4F), foregroundColor: Colors.white, elevation: 0),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
          textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: const Color(0xFFF8BBD0))),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF5C1230),
            hintStyle: const TextStyle(color: Colors.white60),
            labelStyle: const TextStyle(color: Color(0xFFF8BBD0)),
            enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFF8BBD0)), borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFF8BBD0)), borderRadius: BorderRadius.circular(8)),
          ),
          cardTheme: const CardThemeData(color: Color(0xFF5C1230)),
          dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF4A0A26), titleTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18), contentTextStyle: TextStyle(color: Colors.white)),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: Color(0xFF880E4F), foregroundColor: Colors.white),
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(backgroundColor: Color(0xFF4A0A26), selectedItemColor: Color(0xFFF8BBD0), unselectedItemColor: Colors.white60),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        home: const StartupGate(),
        routes: {
          '/auth-choice': (context) => const AuthChoicePage(),
          '/client-login': (context) => const ClientLoginPage(),
          '/client-registration': (context) => const ClientRegistrationPage(),
          '/nurse-login': (context) => const NurseLoginPage(),
          '/nurse-registration': (context) => const NurseRegistrationPage(),
          '/community': (context) => const CommunityGuidelinesPage(),
          '/privacy': (context) => const PrivacyPolicyPage(),
          '/refund': (context) => const RefundPolicyPage(),
          '/delete-account': (context) => const DeleteAccountPolicyPage(),
          '/terms': (context) => const TermsAndConditionsPage(),
          '/health-disclaimer': (context) => const HealthDisclaimerPage(),
          '/home': (context) => const LoveCareHomePage(),
          '/language': (context) => const SelectLanguageScreen(),
          '/lc-ceo-9x7k2q-2026': (context) => const CEOPasswordGate(),
          '/ceo-control': (context) => const CeoControlPage(),
          '/ceo-bookings-progress': (context) => const CEOBookingProgressScreen(),
          '/ceo-complainant': (context) => const CEOComplainantScreen(),
          '/ceo-control-chat': (context) => const CEOControlChatScreen(),
          '/ceo-control-pricing': (context) => const CEOControlPricingScreen(),
          '/ceo-finance': (context) => const CEOFinanceScreen(),
          '/ceo-notification-room': (context) => const CEONotificationRoomScreen(),
          '/ceo-penalize': (context) => const CEOPenalizeScreen(),
          '/ceo-refund-management': (context) => const CEORefundManagementScreen(),
          '/ceo-registration-center': (context) => const CEORegistrationCenterScreen(),
          '/hr-page': (context) => const HRPageScreen(),
          '/staff-login': (context) => StaffLoginPage(),
          '/ceo-login': (context) => StaffLoginPage(),
          '/create-access': (context) => CEOCreateAccessPage(),
          '/ceo-create-access': (context) => CEOCreateAccessPage(),
          '/staff-visits': (context) => StaffVisitsMonitorPage(),
          '/staff-visits-monitor': (context) => StaffVisitsMonitorPage(),
          '/ceo-notifications': (context) => StaffVisitsMonitorPage(),
          '/force-delete': (context) => CEOForceWipeEmailPage(),
          '/sound-settings': (context) => SoundSettingsScreen(),
          '/ceo-dashboard': (context) => const CEOPasswordGate(),
          '/chat-room': (context) => const ChatRoomScreen(),
          '/nurse-group-chat': (context) => const NurseGroupChatScreen(),
          '/alert-settings': (context) => const AlertSettingsScreen(),
          '/book-nurse': (context) => const BookNurseScreen(),
          '/client-dashboard': (context) => ClientDashboardScreen(),
          '/client-settings': (context) => const ClientSettingsScreen(),
          '/my-bookings': (context) => MyBookingsScreen(),
          '/my-job-offer': (context) => const MyJobOfferScreen(),
          '/my-job-offers': (context) => const MyJobOfferScreen(),
          '/nurse-settings': (context) => const NurseSettingsScreen(),
          '/nurse-dashboard': (context) => const NurseDashboardScreen(),
          '/rating': (context) => const RatingScreen(),
          '/refund-query': (context) => const RefundQueryScreen(),
          '/sos': (context) => const SOSScreen(),
        },
        onGenerateRoute: (settings) {
          final args = settings.arguments;
          final routePath = Uri.tryParse(settings.name ?? '')?.path ?? settings.name;
          switch (routePath) {
            case '/staff-login':
            case '/ceo-login':
              return MaterialPageRoute(builder: (_) => StaffLoginPage(), settings: settings);
            case '/create-access':
            case '/ceo-create-access':
              return MaterialPageRoute(builder: (_) => CEOCreateAccessPage(), settings: settings);
            case '/staff-visits':
            case '/staff-visits-monitor':
            case '/ceo-notifications':
              return MaterialPageRoute(builder: (_) => StaffVisitsMonitorPage(), settings: settings);
            case '/force-delete':
              return MaterialPageRoute(builder: (_) => CEOForceWipeEmailPage(), settings: settings);
            case '/sound-settings':
              return MaterialPageRoute(builder: (_) => SoundSettingsScreen(), settings: settings);
            case '/my-job-offer':
            case '/my-job-offers':
              return MaterialPageRoute(builder: (_) => const MyJobOfferScreen(), settings: settings);
            case '/nurse-settings':
              return MaterialPageRoute(builder: (_) => const NurseSettingsScreen(), settings: settings);
            case '/ceo-dashboard':
              return MaterialPageRoute(builder: (_) => const CEOPasswordGate(), settings: settings);
            case '/ceo-live-tracking-map':
              return MaterialPageRoute(builder: (_) => CEOLiveTrackingMapScreen(params: args is Map<String, dynamic> ? args : null));
            case '/client-complaint':
              return MaterialPageRoute(builder: (_) => ClientComplaintScreen(params: args is Map<String, dynamic> ? args : null));
            case '/nurse-complaint':
              return MaterialPageRoute(builder: (_) => NurseComplaintScreen(params: args is Map<String, dynamic> ? args : null));
            case '/alert-settings-role':
              return MaterialPageRoute(builder: (_) => AlertSettingsScreen(role: args is String ? args : null));
            case '/health-disclaimer':
              return MaterialPageRoute(builder: (_) => const HealthDisclaimerPage(), settings: settings);
            case '/language':
              return MaterialPageRoute(builder: (_) => const SelectLanguageScreen(), settings: settings);
            default:
              return null;
          }
        },
        onUnknownRoute: (settings) => MaterialPageRoute(builder: (context) => const LoveCareHomePage()),
      ),
    );
  }
}

// ================= STARTUP GATE =================
class StartupGate extends StatelessWidget {
  const StartupGate({super.key});
  Future<Widget> _decide() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();
      final clientPending = prefs.getBool('client_pending_verification') == true;
      final nursePending = prefs.getBool('nurse_pending_verification') == true;
      if (user == null) return const LoveCareHomePage();
      if (clientPending) return const ClientRegistrationPage();
      if (nursePending) return const NurseRegistrationPage();
      try { await user.reload(); } catch (_) {}
      final fresh = FirebaseAuth.instance.currentUser ?? user;
      final uid = fresh.uid;
      final email = (fresh.email ?? '').toLowerCase();
      try {
        final cDoc = await FirebaseFirestore.instance.collection('clients').doc(uid).get();
        if (cDoc.exists) {
          final d = cDoc.data() ?? {};
          if (fresh.emailVerified) {
            if (d['isApproved'] != true) {
              await FirebaseFirestore.instance.collection('clients').doc(uid).set({
                'emailVerified': true, 'verifiedByEmail': true,
                'isApproved': true, 'approved': true, 'status': 'approved',
                'approvalStatus': 'approved', 'canLogin': true, 'isComplete': true, 'hasAll4': true,
              }, SetOptions(merge: true));
              try {
                final now = DateTime.now().millisecondsSinceEpoch;
                await FirebaseDatabase.instance.ref('clients/$uid').update({'emailVerified': true, 'isApproved': true, 'status': 'approved', 'canLogin': true, 'updatedAt': now});
                await FirebaseDatabase.instance.ref('ceoRegistrationCenter/clients/$uid').update({'emailVerified': true, 'isApproved': true, 'status': 'approved', 'canLogin': true, 'updatedAt': now});
              } catch (_) {}
            }
            await prefs.setString('clientEmail', email);
            await prefs.setString('lcg_client_uid', uid);
            await prefs.setString('clientUid', uid);
            await prefs.setBool('client_pending_verification', false);
            return ClientDashboardScreen();
          } else {
            return const ClientLoginPage();
          }
        }
      } catch (_) {}
      try {
        final nDoc = await FirebaseFirestore.instance.collection('nurses').doc(uid).get();
        final pDoc = await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).get();
        if (nDoc.exists || pDoc.exists) {
          final d = nDoc.exists ? (nDoc.data() ?? {}) : (pDoc.data() ?? {});
          if (fresh.emailVerified && d['isApproved'] == true) {
            return const NurseDashboardScreen();
          }
          return const NurseLoginPage();
        }
      } catch (_) {}
      if (fresh.emailVerified) return const ClientLoginPage();
      return const LoveCareHomePage();
    } catch (_) {
      return const LoveCareHomePage();
    }
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _decide(),
      builder: (context, snap) {
        if (snap.hasData) return snap.data!;
        return const Scaffold(
          backgroundColor: Color(0xFF4A0A26),
          body: Center(child: CircularProgressIndicator(color: Colors.white)),
        );
      },
    );
  }
}

// ================= CEO PASSWORD GATE - NO HARDCODED PASSWORD =================
class CEOPasswordGate extends StatefulWidget {
  const CEOPasswordGate({super.key});
  @override
  State<CEOPasswordGate> createState() => _CEOPasswordGateState();
}

class _CEOPasswordGateState extends State<CEOPasswordGate> {
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _obscure = true;
  String _error = '';

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final pass = _passController.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Enter CEO Email + Password.');
      return;
    }
    setState(() => _error = 'Logging in as CEO...');
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
      final uid = cred.user?.uid ?? '';
      if (uid.isEmpty) {
        setState(() => _error = 'Login failed. Try again.');
        return;
      }
      bool isCeo = false;
      try {
        for (final col in ['ceoAccess', 'admins', 'ceos']) {
          final doc = await FirebaseFirestore.instance.collection(col).doc(uid).get();
          if (doc.exists) { isCeo = true; break; }
        }
      } catch (_) {
        isCeo = true;
      }
      if (!isCeo) {
        await FirebaseAuth.instance.signOut();
        setState(() => _error = 'This account is not a CEO account. Contact admin.');
        return;
      }
      print('CEO LOGGED IN UID: $uid');
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CEODashboardScreen()));
    } on FirebaseAuthException catch (e) {
      String msg = e.message ?? 'Login failed';
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        msg = 'Wrong CEO Email or Password.';
      } else if (e.code == 'too-many-requests') {
        msg = 'Too many tries. Wait 10 mins.';
      }
      setState(() => _error = msg);
    } catch (e) {
      setState(() => _error = 'CEO login failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCE4EC),
      appBar: AppBar(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, title: const Text('CEO Access'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('💜', style: TextStyle(fontSize: 50)),
                const SizedBox(height: 8),
                const Text('CEO Only', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Login with your CEO Firebase account', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: 'CEO Email', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.email)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passController,
                  obscureText: _obscure,
                  decoration: InputDecoration(labelText: 'CEO Password', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.lock), suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscure = !_obscure))),
                  onSubmitted: (_) => _login(),
                ),
                if (_error.isNotEmpty) ...[const SizedBox(height: 10), Text(_error, style: const TextStyle(color: Colors.red))],
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _login, child: const Text('Enter Dashboard'))),
                const SizedBox(height: 12),
                const Text('Forgot password? Reset am for Firebase Console > Authentication.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LoveCareHomePage extends StatefulWidget {
  const LoveCareHomePage({super.key});
  @override
  State<LoveCareHomePage> createState() => _LoveCareHomePageState();
}

class _LoveCareHomePageState extends State<LoveCareHomePage> {
  int _secretTaps = 0;
  DateTime _lastTap = DateTime.now();
  void _handleSecretTap() {
    final now = DateTime.now();
    if (now.difference(_lastTap).inSeconds > 2) _secretTaps = 0;
    _lastTap = now;
    _secretTaps++;
    if (_secretTaps >= 5) {
      _secretTaps = 0;
      Navigator.pushNamed(context, '/lc-ceo-9x7k2q-2026');
    }
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Uri.base.queryParameters['ceo'] == 'true') {
        Navigator.pushNamed(context, '/lc-ceo-9x7k2q-2026');
      } else {
        _showWelcomePopup();
      }
    });
  }
  void _showWelcomePopup() {
    final lang = LanguageService.instance;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('💜 ${lang.t('welcome')}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Trusted Care, With Love', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF880E4F), fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Text('Nurses are verified by CEO before they can care for you.\nClients verify email and login immediately - No CEO approval for Clients.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
            SizedBox(height: 10),
            Text('⚠️ Not for emergencies. For emergency, call 112 / Ambulance immediately.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          Center(child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF880E4F), padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12)), child: const Text('Start ❤️', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }
  void _showAboutPopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('How Love Care Works', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('⚠️ EMERGENCY DISCLAIMER:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              Text('This app does NOT provide emergency medical services. For emergencies, call Ambulance / 112 or go to nearest hospital immediately. Love Care Global is for non-emergency home care only.'),
              SizedBox(height: 10),
              Text('1. NURSE:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Registers with Photo + Video + Phone. Waits for CEO Approval. Cannot login until approved.'),
              SizedBox(height: 10),
              Text('2. CLIENT:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Registers with Name + Username + Email + Phone + Password. Verify email in Gmail. Once verified, you are approved and can login immediately - No CEO approval, No SMS.'),
              SizedBox(height: 10),
              Text('3. SECURITY:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('One account cannot be both Nurse + Client. Unverified Clients are Pending. Verified Clients can login. Failed registration is deleted completely.'),
              SizedBox(height: 10),
              Text('4. CEO:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Reviews all Nurses in CEO Control Center and Approves / Rejects. Clients do NOT need CEO approval.'),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.instance;
    return ListenableBuilder(
      listenable: lang,
      builder: (_, __) => Scaffold(
        backgroundColor: const Color(0xFF4A0A26),
        appBar: AppBar(
          backgroundColor: const Color(0xFF880E4F),
          foregroundColor: Colors.white,
          title: const Text('💜 Love Care Global', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          centerTitle: false,
          actions: [
            // LANGUAGE BUTTON - Top right, Client / Nurse / Guest fit change am here
            TextButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/language'),
              icon: const Icon(Icons.language, color: Colors.white),
              label: Text(lang.code.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        drawer: const _LoveCareDrawer(),
        body: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF880E4F), Color(0xFFC2185B)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _handleSecretTap,
                      child: const Column(children: [Text('💜', style: TextStyle(fontSize: 50)), Text('LOVE CARE GLOBAL', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold))]),
                    ),
                    const SizedBox(height: 8),
                    const Text('Trusted Care, With Love', style: TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text('Tap ☰ top-left to see all Policies', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 20),
                    const Text('CEO-verified Nurses. Safe Clients. No Fake Accounts.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 13)),
                    const SizedBox(height: 24),
                    SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pushNamed(context, '/auth-choice'), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, padding: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('GET STARTED →', style: TextStyle(color: Color(0xFF880E4F), fontWeight: FontWeight.bold, fontSize: 16)))),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _showAboutPopup, style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('How It Works ❓', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                    const SizedBox(height: 12),
                    // LANGUAGE BUTTON FOR HOME TOO
                    SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => Navigator.pushNamed(context, '/language'), icon: const Icon(Icons.language, color: Colors.white), label: Text('🌐 ${lang.t('language')} - ${lang.code.toUpperCase()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFF9800)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('⚠️', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'EMERGENCY DISCLAIMER: This app does NOT provide emergency medical services. For emergencies, call Ambulance / 112 or go to the nearest hospital immediately.\nLove Care Global connects you to verified nurses for non-emergency home care only.',
                        style: TextStyle(color: Color(0xFF4E342E), fontSize: 12, fontWeight: FontWeight.w600, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const _CeoAnnouncementBanner(),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _actionCard('🩺', 'I am a NURSE', 'Register / Login - CEO Approval Required', () => Navigator.pushNamed(context, '/nurse-registration')),
                    const SizedBox(height: 12),
                    _actionCard('❤️', 'I am a CLIENT', 'Register / Login - Verify Email, Login Immediately', () => Navigator.pushNamed(context, '/client-registration')),
                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      children: [
                        TextButton(onPressed: () => Navigator.pushNamed(context, '/terms'), child: const Text('Terms', style: TextStyle(color: Color(0xFFF8BBD0), fontSize: 12))),
                        TextButton(onPressed: () => Navigator.pushNamed(context, '/privacy'), child: const Text('Privacy', style: TextStyle(color: Color(0xFFF8BBD0), fontSize: 12))),
                        TextButton(onPressed: () => Navigator.pushNamed(context, '/community'), child: const Text('Community', style: TextStyle(color: Color(0xFFF8BBD0), fontSize: 12))),
                        TextButton(onPressed: () => Navigator.pushNamed(context, '/refund'), child: const Text('Refund', style: TextStyle(color: Color(0xFFF8BBD0), fontSize: 12))),
                        TextButton(onPressed: () => Navigator.pushNamed(context, '/health-disclaimer'), child: const Text('Health', style: TextStyle(color: Color(0xFFF8BBD0), fontSize: 12))),
                        TextButton(onPressed: () => Navigator.pushNamed(context, '/delete-account'), child: const Text('Delete Account', style: TextStyle(color: Color(0xFFF8BBD0), fontSize: 12))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text('© 2026 Love Care Global - Accra, Ghana', style: TextStyle(color: Colors.white60, fontSize: 11)),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _actionCard(String emoji, String title, String subtitle, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFF8BBD0))),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Color(0xFF880E4F), fontWeight: FontWeight.bold, fontSize: 15)), Text(subtitle, style: const TextStyle(color: Color(0xFF6D6D6D), fontSize: 12))])),
            const Icon(Icons.arrow_forward_ios, color: Color(0xFF880E4F), size: 16),
          ],
        ),
      ),
    );
  }
}

// ================= DRAWER MENU - ALL POLICIES IN ONE PLACE - PLAY STORE =================
class _LoveCareDrawer extends StatelessWidget {
  const _LoveCareDrawer();
  void _go(BuildContext context, String route) {
    Navigator.pop(context);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (context.mounted) Navigator.pushNamed(context, route);
    });
  }
  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.instance;
    return Drawer(
      backgroundColor: const Color(0xFFFCE4EC),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF880E4F)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('💜', style: TextStyle(fontSize: 36)),
                SizedBox(height: 6),
                Text('LOVE CARE GLOBAL', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Trusted Care, With Love\nAccra, Ghana', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          _tile(context, Icons.home, 'Home', () => _go(context, '/home')),
          _tile(context, Icons.rocket_launch, 'Get Started', () => _go(context, '/auth-choice')),
          _tile(context, Icons.sos, 'SOS / Emergency', () => _go(context, '/sos')),
          // LANGUAGE FOR DRAWER TOO - Client / Nurse fit change from anywhere
          ListTile(
            leading: const Icon(Icons.language, color: Color(0xFF880E4F)),
            title: Text('🌐 ${lang.t('language')} (${lang.code.toUpperCase()})', style: const TextStyle(color: Color(0xFF4A0A26), fontWeight: FontWeight.w600, fontSize: 14)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF880E4F)),
            onTap: () => _go(context, '/language'),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('📋 POLICIES & LEGAL', style: TextStyle(color: Color(0xFF880E4F), fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          _tile(context, Icons.description, 'Terms & Conditions', () => _go(context, '/terms')),
          _tile(context, Icons.privacy_tip, 'Privacy Policy', () => _go(context, '/privacy')),
          _tile(context, Icons.groups, 'Community Guidelines', () => _go(context, '/community')),
          _tile(context, Icons.money_off, 'Refund Policy', () => _go(context, '/refund')),
          _tile(context, Icons.health_and_safety, 'Health Disclaimer', () => _go(context, '/health-disclaimer')),
          _tile(context, Icons.delete_forever, 'Delete Account Policy', () => _go(context, '/delete-account')),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('⚠️ EMERGENCY: This app is NOT ambulance. For emergency, call 112 immediately.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text('© 2026 Love Care Global\nlovecareglobal@gmail.com', style: TextStyle(color: Colors.grey, fontSize: 11)),
          ),
        ],
      ),
    );
  }
  static Widget _tile(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF880E4F)),
      title: Text(title, style: const TextStyle(color: Color(0xFF4A0A26), fontWeight: FontWeight.w600, fontSize: 14)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF880E4F)),
      onTap: onTap,
    );
  }
}

// ================= CEO ANNOUNCEMENT BANNER - DISPLAY EVERYTHING + MOVE =================
class _CeoAnnouncementBanner extends StatefulWidget {
  const _CeoAnnouncementBanner();
  @override
  State<_CeoAnnouncementBanner> createState() => _CeoAnnouncementBannerState();
}

class _CeoAnnouncementBannerState extends State<_CeoAnnouncementBanner> {
  List<Map<String, dynamic>> _posts = [];
  Map<String, dynamic>? _current;
  @override
  void initState() {
    super.initState();
    final db = FirebaseDatabase.instance;
    db.ref('ceoHomePageAnnouncements').orderByChild('createdAt').limitToLast(20).onValue.listen((e) {
      if (e.snapshot.value is! Map) return;
      final data = Map<String, dynamic>.from(e.snapshot.value as Map);
      final list = <Map<String, dynamic>>[];
      for (final entry in data.entries) {
        if (entry.value is! Map) continue;
        final m = Map<String, dynamic>.from(entry.value as Map);
        if (m['active'] == false) continue;
        list.add({...m, 'key': entry.key.toString()});
      }
      list.sort((a, b) {
        final ta = int.tryParse('${a['createdAt'] ?? 0}') ?? 0;
        final tb = int.tryParse('${b['createdAt'] ?? 0}') ?? 0;
        return tb.compareTo(ta);
      });
      if (mounted) setState(() => _posts = list);
    });
    db.ref('homePageBanner/current').onValue.listen((e) {
      if (e.snapshot.value is Map) {
        final m = Map<String, dynamic>.from(e.snapshot.value as Map);
        if (mounted) setState(() => _current = m);
      } else {
        if (mounted) setState(() => _current = null);
      }
    });
    db.ref('ceoHomePageCurrent').onValue.listen((e) {
      if (e.snapshot.value is Map) {
        final m = Map<String, dynamic>.from(e.snapshot.value as Map);
        if (mounted && _current == null) setState(() => _current = m);
      }
    });
  }
  Color _parseColor(dynamic v, Color fallback) {
    try {
      final s = (v ?? '').toString().trim();
      if (s.isEmpty) return fallback;
      var hex = s.replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      if (hex.length == 8) return Color(int.parse(hex, radix: 16));
    } catch (_) {}
    return fallback;
  }
  List<String> _allMediaUrls(Map m, String key) {
    final urls = <String>[];
    final list = m[key];
    if (list is List) {
      for (final item in list) {
        if (item is Map) {
          final u = (item['url'] ?? item['data'] ?? '').toString();
          if (u.isNotEmpty) urls.add(u);
        } else if (item is String && item.isNotEmpty) {
          urls.add(item);
        }
      }
    }
    return urls;
  }
  Uint8List? _base64ToBytes(String s) {
    try {
      var clean = s.trim();
      if (clean.contains(',')) clean = clean.split(',').last;
      if (clean.length > 2000000) return null;
      return base64Decode(clean);
    } catch (_) {
      return null;
    }
  }
  Widget _mediaWidget(String url) {
    if (url.isEmpty) return const SizedBox.shrink();
    if (url.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: double.infinity,
            height: 120,
            color: Colors.black26,
            child: const Center(child: Text('🎥 CEO Video / Photo', style: TextStyle(color: Colors.white))),
          ),
        ),
      );
    }
    if (url.startsWith('data:image')) {
      final bytes = _base64ToBytes(url);
      if (bytes != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes, width: double.infinity, fit: BoxFit.cover),
        );
      }
    }
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
      child: const Center(child: Text('🎥 CEO Video Announcement', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
    );
  }
  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> show = _posts;
    if (show.isEmpty && _current != null) show = [_current!];
    if (show.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [for (final b in show) _onePost(b)],
    );
  }
  Widget _onePost(Map b) {
    final text = (b['text'] ?? b['message'] ?? b['title'] ?? b['announcement'] ?? '').toString();
    final displayType = (b['displayType'] ?? 'marquee_slow').toString();
    final speed = (b['speed'] ?? 'slow').toString();
    final textColor = _parseColor(b['textColor'], Colors.white);
    final bgColor = _parseColor(b['bgColor'], const Color(0xFF191531));
    final imageUrls = _allMediaUrls(b, 'images');
    final videoUrls = _allMediaUrls(b, 'videos');
    final createdAt = int.tryParse('${b['createdAt'] ?? 0}') ?? 0;
    final timeStr = createdAt > 0 ? DateTime.fromMillisecondsSinceEpoch(createdAt).toString().substring(0, 16) : '';
    if (text.isEmpty && imageUrls.isEmpty && videoUrls.isEmpty) return const SizedBox.shrink();
    final isStatic = displayType == 'static';
    final isFast = speed == 'fast' || displayType == 'marquee_fast';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('📢 CEO ANNOUNCEMENT', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              if (timeStr.isNotEmpty) Text(timeStr, style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 8),
          for (final url in imageUrls) ...[
            _mediaWidget(url),
            const SizedBox(height: 10),
          ],
          if (text.isNotEmpty)
            isStatic
                ? Text(text, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600, height: 1.4), softWrap: true, maxLines: null, overflow: TextOverflow.visible)
                : _MovingText(text: text, color: textColor, fast: isFast),
          for (final url in videoUrls) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
              child: Text('🎥 Video attached (${videoUrls.length}) - see CEO Control', style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }
}

// TRUE MOVING TEXT - measures FULL text, moves screen -> -text, restart only after last word
class _MovingText extends StatefulWidget {
  final String text;
  final Color color;
  final bool fast;
  const _MovingText({required this.text, required this.color, required this.fast});
  @override
  State<_MovingText> createState() => _MovingTextState();
}

class _MovingTextState extends State<_MovingText> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    final base = widget.text.length * 150;
    final millis = widget.fast ? base ~/ 2 : base;
    _ctrl = AnimationController(
      duration: Duration(milliseconds: millis.clamp(8000, 30000)),
      vsync: this,
    )..repeat();
  }
  @override
  void didUpdateWidget(covariant _MovingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.fast != widget.fast) {
      final base = widget.text.length * 150;
      final millis = widget.fast ? base ~/ 2 : base;
      _ctrl.duration = Duration(milliseconds: millis.clamp(8000, 30000));
      _ctrl.reset();
      _ctrl.repeat();
    }
  }
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  double _measure(String text) {
    final p = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return p.width;
  }
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final screenW = c.maxWidth;
        final textW = _measure(widget.text);
        final total = screenW + textW;
        return SizedBox(
          width: screenW,
          height: 22,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final dx = screenW - (_ctrl.value * total);
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: Text(
                    widget.text,
                    style: TextStyle(color: widget.color, fontSize: 14, fontWeight: FontWeight.w600),
                    softWrap: false,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
