import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
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
import 'screens/alert_settings.dart';
import 'screens/book_nurse.dart';
import 'screens/book_nurse_50.dart';
import 'screens/client_complaint.dart';
import 'screens/client_dashboard.dart';
import 'screens/client_settings.dart';
import 'screens/increase_payment.dart';
import 'screens/my_bookings.dart';
import 'screens/my_job_offer.dart';
import 'screens/nurse_complaint.dart';
import 'screens/nurse_dashboard.dart';
import 'screens/nurse_settings.dart';
import 'screens/nurse_withdrawal.dart';
import 'screens/rating.dart';
import 'screens/refund_query.dart';
import 'screens/sos.dart';

// CEO DEFAULT PASSWORD - Change inside app anytime after first login
const String DEFAULT_CEO_PASSWORD = 'Peterasa80@you!';

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
// ALSO DO IN CONSOLE (once): Firebase Console > App Check > Android > Play Integrity ON
// + Google Cloud > Enable Play Integrity API + Android Device Verification.
// + Keep GitHub SHAs in Firebase: SHA-1 B3:88:7A... / SHA-256 E6:D1:6A... + Play Signing SHAs.
Future<void> _setupPhoneAuthNoRecaptcha() async {
  try {
    // Warm up App Check token BEFORE any OTP request - this is the key fix.
    // If token is ready, Firebase uses silent Play Integrity check, NO reCAPTCHA page.
    try {
      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
      final token = await FirebaseAppCheck.instance.getToken(false);
      debugPrint('AppCheck token ready: ${token != null && token.isNotEmpty}');
    } catch (e) {
      debugPrint('AppCheck warmup failed (will fallback): $e');
    }
    // Tell Firebase Auth: do NOT force reCAPTCHA. Use Play Integrity first.
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
    if (_sending) return; // prevent double-tap -> double reCAPTCHA -> spinning
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
          // ONLY here is OTP truly sent. Never show "OTP sent" before this.
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
    // NEW: Warm up AppCheck + disable forced reCAPTCHA BEFORE runApp
    await _setupPhoneAuthNoRecaptcha();
  } catch (e) {
    debugPrint('Firebase init failed (web/demo mode): $e');
  }
  _setupCeoAutoRing();
  await _setupFCM();
  await ApkAlerts.init();
  runApp(const LoveCareApp());
}

class LoveCareApp extends StatelessWidget {
  const LoveCareApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Love Care Global',
      debugShowCheckedModeBanner: false,
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
      // NEW: StartupGate decides where to go on app open - fixes "app went back to fresh"
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
        '/home': (context) => const LoveCareHomePage(),
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
        '/book-nurse-50': (context) => const BookNurse50Screen(),
        '/client-dashboard': (context) => const ClientDashboardScreen(),
        '/client-settings': (context) => const ClientSettingsScreen(),
        '/my-bookings': (context) => const MyBookingsScreen(),
        '/my-job-offer': (context) => const MyJobOfferScreen(),
        '/my-job-offers': (context) => const MyJobOfferScreen(),
        '/nurse-settings': (context) => const NurseSettingsScreen(),
        '/nurse-dashboard': (context) => const NurseDashboardScreen(),
        '/nurse-withdrawal': (context) => const NurseWithdrawalScreen(),
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
          case '/increase-payment':
            return MaterialPageRoute(builder: (_) => IncreasePaymentScreen(bookingKey: args is String ? args : null));
          case '/alert-settings-role':
            return MaterialPageRoute(builder: (_) => AlertSettingsScreen(role: args is String ? args : null));
          default:
            return null;
        }
      },
      onUnknownRoute: (settings) => MaterialPageRoute(builder: (context) => const LoveCareHomePage()),
    );
  }
}

// ================= STARTUP GATE - NEW FIX FOR "APP WENT BACK TO FRESH" =================
// Rules:
// CLIENT: Pending = NOT verified email ONLY. CEO does NOT approve Client.
//   - If pending verification flag == true + user exists -> go back to ClientRegistrationPage (it will resume waiting page, NOT Home)
//   - If user exists + emailVerified == true + clients doc exists -> go Client Dashboard straight, NO Home, NO re-login
//   - If user exists + NOT verified -> go Client Login (it will show "I HAVE VERIFIED" help)
// NURSE: CEO approval still required. Verified email alone NO fit login.
//   - If nurse doc exists + isApproved == true -> Nurse Dashboard
//   - Else -> Home (must login / wait approval)
// NEVER signOut here - signing out on startup na wetin dey kill Michael's session when e come back from Gmail.
class StartupGate extends StatelessWidget {
  const StartupGate({super.key});

  Future<Widget> _decide() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();
      final clientPending = prefs.getBool('client_pending_verification') == true;
      final nursePending = prefs.getBool('nurse_pending_verification') == true;

      if (user == null) return const LoveCareHomePage();

      // If user was in middle of client verification when app was killed, resume there
      if (clientPending) return const ClientRegistrationPage();
      if (nursePending) return const NurseRegistrationPage();

      // Reload to get TRUE verified status from server, not cached false
      try { await user.reload(); } catch (_) {}
      final fresh = FirebaseAuth.instance.currentUser ?? user;
      final uid = fresh.uid;
      final email = (fresh.email ?? '').toLowerCase();

      // Check role: clients first, then nurses
      // 1. Is this a CLIENT?
      try {
        final cDoc = await FirebaseFirestore.instance.collection('clients').doc(uid).get();
        if (cDoc.exists) {
          final d = cDoc.data() ?? {};
          // CLIENT GATE: only emailVerified matters. If verified, auto-approve + go dashboard.
          if (fresh.emailVerified) {
            // Auto-fix: if old doc still says pending, update to approved so CEO list + login agree
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
            // Save prefs so Dashboard reads them instantly
            await prefs.setString('clientEmail', email);
            await prefs.setString('lcg_client_uid', uid);
            await prefs.setString('clientUid', uid);
            await prefs.setBool('client_pending_verification', false);
            return const ClientDashboardScreen();
          } else {
            // Not verified yet -> Client Login will show "I HAVE VERIFIED" help. Do NOT go Home.
            return const ClientLoginPage();
          }
        }
      } catch (_) {}

      // 2. Is this a NURSE? Nurse still needs CEO approval.
      try {
        final nDoc = await FirebaseFirestore.instance.collection('nurses').doc(uid).get();
        final pDoc = await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).get();
        if (nDoc.exists || pDoc.exists) {
          final d = nDoc.exists ? (nDoc.data() ?? {}) : (pDoc.data() ?? {});
          if (fresh.emailVerified && d['isApproved'] == true) {
            return const NurseDashboardScreen();
          }
          // Nurse not approved yet -> go Nurse Login (it will show pending message)
          return const NurseLoginPage();
        }
      } catch (_) {}

      // 3. Auth exists but no doc in either collection = orphan (old bug).
      // If verified, treat as Client (most orphans are clients) and let Client Login auto-recover + auto-approve.
      // Do NOT delete, do NOT go Home and lose am.
      if (fresh.emailVerified) return const ClientLoginPage();

      // Not verified + no doc -> go Home, user can choose Register/Login
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

// ================= CEO PASSWORD GATE =================
class CEOPasswordGate extends StatefulWidget {
  const CEOPasswordGate({super.key});
  @override
  State<CEOPasswordGate> createState() => _CEOPasswordGateState();
}

class _CEOPasswordGateState extends State<CEOPasswordGate> {
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _oldController = TextEditingController();
  final TextEditingController _newController = TextEditingController();
  bool _obscure = true;
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _showChange = false;
  String _error = '';

  Future<String> _getSavedPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ceo_password') ?? DEFAULT_CEO_PASSWORD;
  }

  Future<void> _login() async {
    final saved = await _getSavedPassword();
    if (_passController.text == saved) {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CEODashboardScreen()));
    } else {
      setState(() => _error = 'Wrong password. Try again.');
    }
  }

  Future<void> _changePassword() async {
    final saved = await _getSavedPassword();
    if (_oldController.text != saved) {
      setState(() => _error = 'Old password wrong.');
      return;
    }
    if (_newController.text.length < 6) {
      setState(() => _error = 'New password must be at least 6 characters.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ceo_password', _newController.text);
    setState(() { _error = ''; _showChange = false; _passController.clear(); _oldController.clear(); _newController.clear(); });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CEO Password changed! Use new password next time.')));
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
                const Text('Enter your CEO password to continue', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                if (!_showChange) ...[
                  TextField(controller: _passController, obscureText: _obscure, decoration: InputDecoration(labelText: 'CEO Password', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.lock), suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscure = !_obscure))), onSubmitted: (_) => _login()),
                  if (_error.isNotEmpty) ...[const SizedBox(height: 10), Text(_error, style: const TextStyle(color: Colors.red))],
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _login, child: const Text('Enter Dashboard'))),
                  const SizedBox(height: 12),
                  TextButton(onPressed: () => setState(() { _showChange = true; _error = ''; }), child: const Text('Change Password')),
                ] else ...[
                  TextField(controller: _oldController, obscureText: _obscureOld, decoration: InputDecoration(labelText: 'Old Password', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(icon: Icon(_obscureOld ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscureOld = !_obscureOld)))),
                  const SizedBox(height: 12),
                  TextField(controller: _newController, obscureText: _obscureNew, decoration: InputDecoration(labelText: 'New Password', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.lock), suffixIcon: IconButton(icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscureNew = !_obscureNew)))),
                  if (_error.isNotEmpty) ...[const SizedBox(height: 10), Text(_error, style: const TextStyle(color: Colors.red))],
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: _changePassword, child: const Text('Save New Password'))),
                  TextButton(onPressed: () => setState(() { _showChange = false; _error = ''; }), child: const Text('Back to Login')),
                ],
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('💜 Welcome to Love Care Global', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Trusted Care, With Love', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF880E4F), fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            // FIXED TEXT - NEW CLIENT RULE
            Text('Nurses are verified by CEO before they can care for you.\nClients verify email and login immediately - No CEO approval for Clients.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
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
    return Scaffold(
      backgroundColor: const Color(0xFF4A0A26),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
              decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF880E4F), Color(0xFFC2185B)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _handleSecretTap,
                    child: const Column(children: [Text('💜', style: TextStyle(fontSize: 50)), Text('LOVE CARE GLOBAL', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold))]),
                  ),
                  const SizedBox(height: 8),
                  const Text('Trusted Care, With Love', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 20),
                  const Text('CEO-verified Nurses. Safe Clients. No Fake Accounts.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 13)),
                  const SizedBox(height: 24),
                  SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pushNamed(context, '/auth-choice'), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, padding: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('GET STARTED →', style: TextStyle(color: Color(0xFF880E4F), fontWeight: FontWeight.bold, fontSize: 16)))),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _showAboutPopup, style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('How It Works ❓', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                ],
              ),
            ),
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
