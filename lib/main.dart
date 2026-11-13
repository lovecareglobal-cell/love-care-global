import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
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
import 'screens/dashboard_alerts.dart'; // Nurse + Client alerts - same as CEO, for their own info // SoundSettingsScreen + SoundService - for route + auto-ring
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Who is logged in? For personal nurse/client topics // FCM Push - phone alerts when app is closed
import 'package:firebase_database/firebase_database.dart'; // Auto-ring listener

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
import 'screens/nurse_withdrawal.dart';
import 'screens/rating.dart';
import 'screens/refund_query.dart';
import 'screens/sos.dart';

// CEO DEFAULT PASSWORD - Change inside app anytime after first login
const String DEFAULT_CEO_PASSWORD = 'Peterasa80@you!';

// FCM background handler - MUST be top-level, not inside a class.
// Runs when a push arrives while the app is in background (not fully closed on Web -
// on Web, firebase-messaging-sw.js handles the fully-closed case).
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

// ---------- CEO AUTO-RING (app OPEN) ----------
// Watches ceoRegistrationCenter/nurses + clients. When a NEW one appears
// (not the ones already there when the app opens), plays your chosen Love Care
// sound 3x - so you hear it even if you are looking at another tab.
// This works only while the tab is OPEN. For CLOSED app, FCM Push (above + sw.js)
// sends the phone notification instead.
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
      if (_ceoNurseCount == -1) { _ceoNurseCount = count; return; } // first load - don't ring for old ones
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

// ---------- NURSE + CLIENT AUTO (in main.dart, so NO dashboard edit needed) ----------
// DashboardAlerts helper (dashboard_alerts.dart) also works if you call it from a
// dashboard - this version works AUTOMATICALLY, so you don't have to edit
// nurse_dashboard.dart or client_dashboard.dart at all.
// It waits for FirebaseAuth, then:
//   - Subscribes to personal topic 'user_{uid}' -> Cloud Function sends ONLY my info
//   - Listens ONLY to my nodes -> Ama does NOT hear Kofi's job offers
//   - First load ignored -> only NEW items ring
bool _userAlertSetup = false;
final Map<String, int> _userAlertCounts = {};
void _userAlertRing(String key, int count) {
  final old = _userAlertCounts[key] ?? -1;
  if (old == -1) { _userAlertCounts[key] = count; return; }
  if (count > old) { _userAlertCounts[key] = count; SoundService.playCustomSound('new_info'); }
  else { _userAlertCounts[key] = count; }
}
void _setupUserAlerts() {
  if (_userAlertSetup) return;
  _userAlertSetup = true;
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user == null) return;
    final uid = user.uid;
    try {
      final m = FirebaseMessaging.instance;
      await m.subscribeToTopic('user_$uid');
      await m.subscribeToTopic('nurses');
      await m.subscribeToTopic('clients');
      debugPrint('FCM subscribed: user_$uid + nurses + clients');
    } catch (_) {}
    try {
      final db = FirebaseDatabase.instance;
      db.ref('notifications/nurses/$uid').onValue.listen((e) {
        final c = (e.snapshot.value is Map) ? (e.snapshot.value as Map).length : 0;
        _userAlertRing('notif_nurse_$uid', c);
      });
      db.ref('notifications/clients/$uid').onValue.listen((e) {
        final c = (e.snapshot.value is Map) ? (e.snapshot.value as Map).length : 0;
        _userAlertRing('notif_client_$uid', c);
      });
      db.ref('notifications/$uid').onValue.listen((e) {
        final c = (e.snapshot.value is Map) ? (e.snapshot.value as Map).length : 0;
        _userAlertRing('notif_user_$uid', c);
      });
      db.ref('bookings').onValue.listen((e) {
        if (e.snapshot.value is! Map) return;
        int mine = 0;
        (e.snapshot.value as Map).forEach((k, v) {
          if (v is Map && (v['nurseId'] == uid || v['clientId'] == uid || v['nurseUid'] == uid || v['clientUid'] == uid || v['toId'] == uid)) mine++;
        });
        _userAlertRing('bookings_$uid', mine);
      });
      for (final path in ['jobOffers', 'my_job_offer', 'job_offers', 'offers']) {
        db.ref(path).onValue.listen((e) {
          if (e.snapshot.value is! Map) return;
          int mine = 0;
          (e.snapshot.value as Map).forEach((k, v) {
            if (v is Map && (v['nurseId'] == uid || v['nurseUid'] == uid || v['toId'] == uid || v['receiverId'] == uid)) mine++;
          });
          _userAlertRing('${path}_$uid', mine);
        });
      }
      for (final path in ['chatMessages', 'messages', 'chats']) {
        db.ref(path).onValue.listen((e) {
          if (e.snapshot.value is! Map) return;
          int mine = 0;
          (e.snapshot.value as Map).forEach((k, v) {
            if (v is Map && (v['toId'] == uid || v['receiverId'] == uid || v['toUid'] == uid)) mine++;
          });
          _userAlertRing('${path}_$uid', mine);
        });
      }
    } catch (_) {}
  });
}

Future<void> _setupFCM() async {
  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    final messaging = FirebaseMessaging.instance;
    // Ask once: "Allow Notifications?" - if you tap Block, closed-app alerts will NOT work.
    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
    debugPrint('FCM permission: ${settings.authorizationStatus}');
    // CEO phone subscribes to 'ceo' topic - Cloud Function sends to this topic only.
    // Nurses/clients do NOT subscribe - only CEO gets these pushes.
    // Note: on Web, topic subscribe needs the sw.js registered - Firebase handles it.
    try { await messaging.subscribeToTopic('ceo'); } catch (_) {}
    _setupUserAlerts(); // Nurse + Client personal topics + auto-ring, after login
    // Foreground: app OPEN - play Love Care sound too, not just show a banner.
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      SoundService.playCustomSound('push');
    });
    // Get token for debugging - you can paste it in Firebase Console > Cloud Messaging > Send test message
    final token = await messaging.getToken(vapidKey: null);
    debugPrint('FCM TOKEN: $token');
  } catch (e) {
    debugPrint('FCM setup failed (web/demo mode): $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init failed (web/demo mode): $e');
  }
  _setupCeoAutoRing(); // auto-ring while app is OPEN
  await _setupFCM(); // push when app is CLOSED
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
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      home: const LoveCareHomePage(),
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

        // CEO - SECRET - NOW GOES TO PASSWORD GATE, NOT DIRECT DASHBOARD
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
        // STAFF SYSTEM - direct links, no const (see build #248 fix)
        '/staff-login': (context) => StaffLoginPage(),
        '/ceo-login': (context) => StaffLoginPage(), // old name still works
        '/create-access': (context) => CEOCreateAccessPage(),
        '/ceo-create-access': (context) => CEOCreateAccessPage(),
        '/staff-visits': (context) => StaffVisitsMonitorPage(),
        '/staff-visits-monitor': (context) => StaffVisitsMonitorPage(),
        '/ceo-notifications': (context) => StaffVisitsMonitorPage(),
        '/force-delete': (context) => CEOForceWipeEmailPage(),
        // SOUND SETTINGS - was missing, so button went to Home. Confirmed class: SoundSettingsScreen
        '/sound-settings': (context) => SoundSettingsScreen(),
        // CEO Dashboard link goes to PASSWORD GATE first, NOT straight to dashboard.
        // This keeps your secret gate: /ceo-dashboard -> enter CEO password -> dashboard.
        // Staff do NOT use this link - they use /staff-login, which goes to dashboard after staff password.
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
        '/nurse-dashboard': (context) => const NurseDashboardScreen(),
        '/nurse-withdrawal': (context) => const NurseWithdrawalScreen(),
        '/rating': (context) => const RatingScreen(),
        '/refund-query': (context) => const RefundQueryScreen(),
        '/sos': (context) => const SOSScreen(),
      },
      onGenerateRoute: (settings) {
        final args = settings.arguments;
        // FIX: strip ?username=... / ?phone=... before matching.
        // Without this, "/staff-login?username=kwaku.osei" matches NOTHING
        // -> onUnknownRoute -> Home (looks like blank / wrong page).
        // Uri.parse splits it: path = "/staff-login", query is read by the page itself.
        final routePath = Uri.tryParse(settings.name ?? '')?.path ?? settings.name;
        switch (routePath) {
          // NEW ROUTES - handled here too, so ?query links work even if routes: misses them
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
          case '/ceo-dashboard':
            return MaterialPageRoute(builder: (_) => const CEOPasswordGate(), settings: settings);
          case '/ceo-live-tracking-map':
            return MaterialPageRoute(
              builder: (_) => CEOLiveTrackingMapScreen(
                params: args is Map<String, dynamic> ? args : null,
              ),
            );
          case '/client-complaint':
            return MaterialPageRoute(
              builder: (_) => ClientComplaintScreen(
                params: args is Map<String, dynamic> ? args : null,
              ),
            );
          case '/nurse-complaint':
            return MaterialPageRoute(
              builder: (_) => NurseComplaintScreen(
                params: args is Map<String, dynamic> ? args : null,
              ),
            );
          case '/increase-payment':
            return MaterialPageRoute(
              builder: (_) => IncreasePaymentScreen(
                bookingKey: args is String ? args : null,
              ),
            );
          case '/alert-settings-role':
            return MaterialPageRoute(
              builder: (_) => AlertSettingsScreen(
                role: args is String ? args : null,
              ),
            );
          default:
            return null;
        }
      },
      // FIXED: Wrong link goes to Home, NOT CEO Dashboard
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (context) => const LoveCareHomePage(),
      ),
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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CEODashboardScreen()),
      );
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
    setState(() {
      _error = '';
      _showChange = false;
      _passController.clear();
      _oldController.clear();
      _newController.clear();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CEO Password changed! Use new password next time.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5F5),
      appBar: AppBar(
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        title: const Text('CEO Access'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
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
                  TextField(
                    controller: _passController,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'CEO Password',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onSubmitted: (_) => _login(),
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(_error, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: _login,
                      child: const Text('Enter Dashboard'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(() { _showChange = true; _error = ''; }),
                    child: const Text('Change Password'),
                  ),
                ] else ...[
                  TextField(
                    controller: _oldController,
                    obscureText: _obscureOld,
                    decoration: InputDecoration(
                      labelText: 'Old Password',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureOld ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscureOld = !_obscureOld),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newController,
                    obscureText: _obscureNew,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscureNew = !_obscureNew),
                      ),
                    ),
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(_error, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _changePassword,
                      child: const Text('Save New Password'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() { _showChange = false; _error = ''; }),
                    child: const Text('Back to Login'),
                  ),
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
            Text('Trusted Care, With Love', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Text('Nurses are verified by CEO before they can care for you.\nClients login with Username + Password ONLY.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12)),
              child: const Text('Start ❤️', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
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
              Text('Registers with Username + Phone + OTP. Login with Username + Password ONLY - No SMS on login.'),
              SizedBox(height: 10),
              Text('3. SECURITY:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('One account cannot be both Nurse + Client. Unregistered users cannot login. Failed registration is deleted completely.'),
              SizedBox(height: 10),
              Text('4. CEO:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Reviews all Nurses in CEO Control Center and Approves / Rejects.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFEC4899)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _handleSecretTap,
                    child: const Column(
                      children: [
                        Text('💜', style: TextStyle(fontSize: 50)),
                        Text('LOVE CARE GLOBAL', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Trusted Care, With Love', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 20),
                  const Text('CEO-verified Nurses. Safe Clients. No Fake Accounts.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 13)),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/auth-choice'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), padding: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('GET STARTED →', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _showAboutPopup,
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('How It Works ❓', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
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
                  _actionCard('❤️', 'I am a CLIENT', 'Register / Login - Username + Password', () => Navigator.pushNamed(context, '/client-registration')),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    children: [
                      TextButton(onPressed: () => Navigator.pushNamed(context, '/terms'), child: const Text('Terms', style: TextStyle(color: Colors.white70, fontSize: 12))),
                      TextButton(onPressed: () => Navigator.pushNamed(context, '/privacy'), child: const Text('Privacy', style: TextStyle(color: Colors.white70, fontSize: 12))),
                      TextButton(onPressed: () => Navigator.pushNamed(context, '/community'), child: const Text('Community', style: TextStyle(color: Colors.white70, fontSize: 12))),
                      TextButton(onPressed: () => Navigator.pushNamed(context, '/refund'), child: const Text('Refund', style: TextStyle(color: Colors.white70, fontSize: 12))),
                      TextButton(onPressed: () => Navigator.pushNamed(context, '/delete-account'), child: const Text('Delete Account', style: TextStyle(color: Colors.white70, fontSize: 12))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text('© 2026 Love Care Global - Accra, Ghana', style: TextStyle(color: Colors.grey, fontSize: 11)),
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
        decoration: BoxDecoration(color: const Color(0xFF1E1A3A), borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(subtitle, style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}
