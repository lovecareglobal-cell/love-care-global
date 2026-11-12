import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
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

// CEO FILES - ALL RED MARKED + NURSE GROUP CHAT - NO HOME BANNER
import 'screens/ceo_dashboard.dart';
import 'screens/ceo_bookings_progress.dart';
import 'screens/ceo_complainant.dart';
import 'screens/ceo_control_chat.dart';
import 'screens/ceo_control_pricing.dart';
import 'screens/ceo_finance.dart';
import 'screens/ceo_live_tracking_map.dart';
import 'screens/ceo_notification_room.dart';
import 'screens/ceo_penalize.dart';
import 'screens/ceo_refund_management.dart';
import 'screens/ceo_registration_center.dart';
import 'screens/ceo_service.dart';
import 'screens/chat_room.dart';
import 'screens/cleanup_auto_approval.dart';
import 'screens/force_delete.dart';
import 'screens/hr_page.dart';
import 'screens/sound_settings.dart';
import 'screens/nurse_group_chat.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase Init - MUST be first before runApp
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init failed (web/demo mode): $e');
  }
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
      // Home = Your Landing Page
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

        // CEO - SECRET - NO BUTTON, NO README, ONLY YOU KNOW
        '/lc-ceo-9x7k2q-2026': (context) => const CEODashboardScreen(),
        '/ceo-control': (context) => const CeoControlPage(),
        '/ceo-bookings-progress': (context) => const CEOBookingsProgressScreen(),
        '/ceo-complainant': (context) => const CEOComplainantScreen(),
        '/ceo-control-chat': (context) => const CEOControlChatScreen(),
        '/ceo-control-pricing': (context) => const CEOControlPricingScreen(),
        '/ceo-finance': (context) => const CEOFinanceScreen(),
        '/ceo-live-tracking-map': (context) => const CEOLiveTrackingMapScreen(),
        '/ceo-notification-room': (context) => const CEONotificationRoomScreen(),
        '/ceo-penalize': (context) => const CEOPenalizeScreen(),
        '/ceo-refund-management': (context) => const CEORefundManagementScreen(),
        '/ceo-registration-center': (context) => const CEORegistrationCenterScreen(),
        '/force-delete': (context) => const ForceDeleteScreen(),
        '/hr-page': (context) => const HRPageScreen(),
        '/sound-settings': (context) => const SoundSettingsScreen(),
        '/chat-room': (context) => const ChatRoomScreen(),
        '/nurse-group-chat': (context) => const NurseGroupChatScreen(),
        // NO HOME BANNER - REMOVED - file does not exist
        // ceo_service + cleanup_auto_approval na service files, no route needed
      },
      // If old home-banner link try open, go Dashboard instead of crash
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (context) => const CEODashboardScreen(),
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
  @override
  void initState() {
    super.initState();
    // POPUP 1: Welcome Popup - Shows once when app opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showWelcomePopup();
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

  // POPUP 2: About / How It Works Popup
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
            // HERO SECTION
            Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFEC4899)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
              ),
              child: Column(
                children: [
                  const Text('💜', style: TextStyle(fontSize: 50)),
                  const Text('LOVE CARE GLOBAL', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Trusted Care, With Love', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 20),
                  const Text('CEO-verified Nurses. Safe Clients. No Fake Accounts.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 13)),
                  const SizedBox(height: 24),
                  // GET STARTED BUTTON
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
            // QUICK ACTIONS - CEO BUTTON REMOVED HERE
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
