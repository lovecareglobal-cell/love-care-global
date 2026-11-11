import 'package:flutter/material.dart';
import 'nurse_registration.dart';
import 'client_login.dart';

// SAME AS YOUR HTML - Nurse Login
// Email + Password OR Google
// CEO APPROVAL REQUIRED - ceo-registration-center must approve first
// CLIENT email BLOCKED - must use Client Login

class NurseLoginPage extends StatefulWidget {
  const NurseLoginPage({super.key});

  @override
  State<NurseLoginPage> createState() => _NurseLoginPageState();
}

class _NurseLoginPageState extends State<NurseLoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _showPass = false;
  String _msg = '';
  bool _isOk = false;
  bool _loading = false;

  void _show(String m, bool ok) {
    setState(() { _msg = m; _isOk = ok; });
  }

  Future<void> _emailLogin() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;

    if (email.isEmpty || pass.isEmpty) {
      _show('Enter email and password', false);
      return;
    }
    if (!email.contains('@')) {
      _show('Enter valid email', false);
      return;
    }

    setState(() => _loading = true);
    _show('Checking CLIENT block + CEO approval...', true);

    // TODO: Connect Firebase Auth + RTDB + Firestore same as your HTML:
    // 1. isClientAccount(email) -> if true: BLOCK "CLIENT email - Use Client Login"
    // 2. signInWithEmailAndPassword(auth, email, pass)
    // 3. checkNurseCompleteAndApproved(uid, email):
    //    - Check allowedNurses, allowedNursesByUid, nurses, ceoRegistrationCenter/nurses, pending_nurses, etc.
    //    - approved = isApproved==true || approved==true || status=='approved'
    //    - missing = photo? phone? video? (video only required if NOT approved)
    //    - complete = missing==0 || (approved && photo && phone)
    // 4. If !approved:
    //    - if isRegistered: "WAITING FOR CEO APPROVAL" + signOut + save pendingApprovalEmail/Uid
    //    - else: "NOT A REGISTERED NURSE" + deleteUser + go to nurse-registration.html
    // 5. If approved but !complete and !(photo && phone): BLOCK "Approved but missing: ..."
    // 6. If OK: saveNurseSession(uid, name) -> lcg_nurse_uid, nurseUid, nurseEmail, lcg_role=nurse, lcg_session_expiry 24h
    //    + nursePhoto, nurseVideo, nursePhone -> go to nurses-dashboard.html

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _loading = false);

    // Demo - remove when Firebase is connected
    _show('✅ CEO Approved! Photo, Video, Phone complete — Redirecting to dashboard...', true);
  }

  Future<void> _googleLogin() async {
    setState(() => _loading = true);
    _show('Opening Google...', true);

    // TODO: Same as HTML googleLogin():
    // signInWithPopup(GoogleAuthProvider) -> check isClientAccount -> checkNurseCompleteAndApproved
    // Same CEO approval + missing checks as email login

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _loading = false);
    _show('Checking photo, video, phone + CEO approval...', true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Nurse Login', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(color: const Color(0xFF7C3AED), borderRadius: BorderRadius.circular(30)),
                    child: const Center(child: Text('N', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold))),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Nurse Login', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('LOVE CARE GLOBAL - CEO APPROVAL REQUIRED', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _loading ? null : _googleLogin,
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Continue with Google', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                Row(children: const [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('OR', style: TextStyle(color: Colors.grey, fontSize: 12))), Expanded(child: Divider())]),
                const SizedBox(height: 12),
                const Text('Email', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _dec('nurse@email.com'),
                ),
                const SizedBox(height: 12),
                const Text('Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                TextField(
                  controller: _passCtrl,
                  obscureText: !_showPass,
                  decoration: _dec('Enter password').copyWith(
                    suffixIcon: TextButton(
                      onPressed: () => setState(() => _showPass = !_showPass),
                      child: Text(_showPass ? 'Hide' : 'Show', style: const TextStyle(color: Color(0xFF7C3AED))),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_msg.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _isOk ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_msg, textAlign: TextAlign.center, style: TextStyle(color: _isOk ? Colors.green : Colors.red, fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _loading ? null : _emailLogin,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text(_loading ? 'Checking...' : 'Login as Nurse', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NurseRegistrationPage())),
                  child: const Text('No account? Register', style: TextStyle(color: Colors.black)),
                ),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientLoginPage())),
                  child: const Text('Client Login', style: TextStyle(color: Colors.grey, fontSize: 11)),
                ),
                const Text('CEO must approve in ceo-registration-center before login works', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true, fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
    );
  }
}
