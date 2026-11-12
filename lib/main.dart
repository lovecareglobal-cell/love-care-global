import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'ceo_dashboard.dart';
import 'nurse_dashboard.dart';
import 'client_dashboard.dart';

// CEO DEFAULT PASSWORD - You can change it inside app anytime
// This is only used first time. After you change it, new one is saved.
const String DEFAULT_CEO_PASSWORD = 'Peterasa80@you!';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
        primarySwatch: Colors.purple,
        useMaterial3: true,
      ),
      home: const LoveCareHomePage(),
      routes: {
        '/client-dashboard': (context) => const ClientDashboard(),
        '/nurse-dashboard': (context) => const NurseDashboard(),
        // SECRET CEO ROUTE - Now goes to Password Gate, NOT direct dashboard
        '/lc-ceo-9x7k2q-2026': (context) => const CEOPasswordGate(),
      },
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (context) => const LoveCareHomePage(),
      ),
    );
  }
}

// ================= CEO PASSWORD GATE =================
// No button, only secret tap / secret link can reach here.
// Has Show/Hide Eye + Change Password anytime.
class CEOPasswordGate extends StatefulWidget {
  const CEOPasswordGate({super.key});
  @override
  State<CEOPasswordGate> createState() => _CEOPasswordGateState();
}

class _CEOPasswordGateState extends State<CEOPasswordGate> {
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _oldController = TextEditingController();
  final TextEditingController _newController = TextEditingController();
  bool _obscure = true; // true = hidden, false = show
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
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CEO Password changed successfully! Use new password next time.')),
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
        title: const Column(
          children: [
            Text('💜', style: TextStyle(fontSize: 40)),
            SizedBox(height: 8),
            Text('Welcome to Love Care Global', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Trusted Care, With Love', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
            SizedBox(height: 12),
            Text('Nurses are verified by CEO before they can care for you.', textAlign: TextAlign.center),
            SizedBox(height: 8),
            Text('Clients login with Username + Password ONLY.', textAlign: TextAlign.center),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
              onPressed: () => Navigator.pop(context),
              child: const Text('Start ❤️'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5F5),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 30),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF8E24AA), Color(0xFFE040FB)], begin: Alignment.topLeft, end: Alignment.bottomRight),
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
                  const Text('Your Health, Our Priority', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text('Professional Nurses • Verified Care • Compassionate Service', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildRoleCard(
                    context,
                    icon: '👤',
                    title: 'I am a CLIENT',
                    subtitle: 'Register / Login',
                    desc: 'Find a verified nurse for yourself or your loved one. Pay securely.',
                    color: Colors.purple,
                    onTap: () => Navigator.pushNamed(context, '/client-dashboard'),
                  ),
                  const SizedBox(height: 16),
                  _buildRoleCard(
                    context,
                    icon: '👩‍⚕️',
                    title: 'I am a NURSE',
                    subtitle: 'Register / Login',
                    desc: 'Join Love Care Global. Get verified by CEO and start receiving care requests.',
                    color: Colors.teal,
                    onTap: () => Navigator.pushNamed(context, '/nurse-dashboard'),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: const Column(
                      children: [
                        Text('How It Works', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(height: 12),
                        Row(children: [Text('1️⃣ ', style: TextStyle(fontSize: 18)), Expanded(child: Text('Client registers and requests a nurse'))]),
                        SizedBox(height: 8),
                        Row(children: [Text('2️⃣ ', style: TextStyle(fontSize: 18)), Expanded(child: Text('CEO verifies nurse credentials'))]),
                        SizedBox(height: 8),
                        Row(children: [Text('3️⃣ ', style: TextStyle(fontSize: 18)), Expanded(child: Text('Nurse accepts and provides care'))]),
                        SizedBox(height: 8),
                        Row(children: [Text('4️⃣ ', style: TextStyle(fontSize: 18)), Expanded(child: Text('Client rates and pays securely'))]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('© 2026 Love Care Global • Accra, Ghana', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard(BuildContext context, {required String icon, required String title, required String subtitle, required String desc, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 36)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                      Text(subtitle, style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: color, size: 18),
              ],
            ),
            const SizedBox(height: 12),
            Text(desc, style: const TextStyle(color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}
