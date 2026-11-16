import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ClientLoginPage extends StatefulWidget {
  const ClientLoginPage({super.key});
  @override
  State<ClientLoginPage> createState() => _ClientLoginPageState();
}

class _ClientLoginPageState extends State<ClientLoginPage> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _msg = '';
  bool _loading = false;
  bool _showPass = false;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _userCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;
    if (username.isEmpty || pass.isEmpty) {
      setState(() => _msg = 'Enter username/email + password');
      return;
    }
    setState(() { _loading = true; _msg = 'Checking...'; });
    try {
      // GUARD: ONE EMAIL = ONE ROLE - if user typed an email, block if it is a Nurse email.
      // Also check pending_nurses, not just nurses.
      if (username.contains('@')) {
        final nurseCheckEmail = await FirebaseFirestore.instance.collection('nurses').where('email', isEqualTo: username).limit(1).get();
        final pendingCheckEmail = await FirebaseFirestore.instance.collection('pending_nurses').where('email', isEqualTo: username).limit(1).get();
        if (nurseCheckEmail.docs.isNotEmpty || pendingCheckEmail.docs.isNotEmpty) {
          setState(() { _loading = false; _msg = 'BLOCKED: This is a NURSE account. Use Nurse Login.'; });
          return;
        }
      }
      // GUARD: If username is a NURSE email/phone, BLOCK
      final nurseCheck = await FirebaseFirestore.instance
          .collection('nurses')
          .where('email', isEqualTo: username)
          .limit(1)
          .get();
      if (nurseCheck.docs.isNotEmpty) {
        setState(() {
          _loading = false;
          _msg = 'BLOCKED: This is a NURSE account. Use Nurse Login.';
        });
        return;
      }
      // LOGIN WITH REAL EMAIL - registration now uses Email Verification, NOT OTP / fake email.
      // User can type Email OR Username. If Username, look up the real email from Firestore first.
      String loginEmail = username;
      if (!username.contains('@')) {
        // Username -> real email lookup (clients store username + real email)
        var byUsername = await FirebaseFirestore.instance.collection('clients').where('username', isEqualTo: username).limit(1).get();
        if (byUsername.docs.isEmpty) {
          // Try case-insensitive: username may have been typed with different case
          byUsername = await FirebaseFirestore.instance.collection('clients').where('username', isEqualTo: username.toLowerCase()).limit(1).get();
        }
        if (byUsername.docs.isEmpty) {
          setState(() { _loading = false; _msg = 'Login failed: Username not found. Register first, or login with your Email.'; });
          return;
        }
        loginEmail = (byUsername.docs.first.data()['email'] as String?)?.trim().toLowerCase() ?? '';
        if (loginEmail.isEmpty) {
          setState(() { _loading = false; _msg = 'Login failed: This client has no email. Contact CEO.'; });
          return;
        }
      }
      final cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: loginEmail, password: pass);
      final uid = cred.user!.uid;

      // CLIENT GATE: Email Verification is the ONLY gate (no CEO approval for clients).
      // If verification failed, that email CANNOT login - even if password is correct.
      // We check Auth first, then Firestore legacy (old OTP clients have phoneVerified=true).
      // New clients: Firestore doc only exists AFTER verification, so unverified = no doc = blocked anyway.
      // But we check Auth explicitly too, so an unverified Auth account with no doc can never slip through.
      final authVerified = cred.user!.emailVerified;
      if (!authVerified) {
        final legacyDoc = await FirebaseFirestore.instance.collection('clients').doc(uid).get();
        final legacyPhoneVerified = legacyDoc.exists && (legacyDoc.data()?['phoneVerified'] == true || legacyDoc.data()?['otpVerified'] == true);
        if (!legacyPhoneVerified) {
          await FirebaseAuth.instance.signOut();
          setState(() { _loading = false; _msg = 'BLOCKED: Email NOT verified. Open Gmail, tap the verification link, then login again. That email cannot login until verified.'; });
          return;
        }
        // Legacy OTP client: allow, but still require a clients doc (checked below)
      }

      // GUARD 1b: Same Auth account cannot be a Nurse - check by UID (covers same email+password)
      final nurseByUid = await FirebaseFirestore.instance.collection('nurses').doc(uid).get();
      final pendingByUid = await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).get();
      if (nurseByUid.exists || pendingByUid.exists) {
        await FirebaseAuth.instance.signOut();
        setState(() { _loading = false; _msg = 'BLOCKED: This account is a NURSE. Use Nurse Login. One email cannot be both.'; });
        return;
      }

      // GUARD 2: Must exist in clients
      final doc = await FirebaseFirestore.instance
          .collection('clients')
          .doc(uid)
          .get();
      if (!doc.exists) {
        // BYPASS FIX: This Auth account has NO Firestore profile in ANY role.
        // It is a leftover from a failed / bypassed registration. Sign-out alone
        // leaves it in Auth, so the 2nd login slips through. DELETE it.
        // (We already checked nurses/pending above - if it were a Nurse, we returned earlier and did NOT delete.)
        try { await cred.user!.delete(); } catch (_) { await FirebaseAuth.instance.signOut(); }
        setState(() {
          _loading = false;
          _msg = 'BLOCKED: NOT A REGISTERED CLIENT. Go Register first. Leftover account deleted.';
        });
        return;
      }
      final data = doc.data()!;
      // CLIENT GATE 2 (Firestore): doc must say verified. New flow saves emailVerified=true + hasAll4=true.
      final firestoreVerified = data['emailVerified'] == true || data['verifiedByEmail'] == true || data['phoneVerified'] == true || data['otpVerified'] == true;
      final complete = data['isComplete'] == true || data['hasAll4'] == true || firestoreVerified;
      if (!firestoreVerified) {
        await FirebaseAuth.instance.signOut();
        setState(() { _loading = false; _msg = 'BLOCKED: Email NOT verified. Open Gmail, tap the verification link, then login again.'; });
        return;
      }
      if (!complete) {
        await FirebaseAuth.instance.signOut();
        setState(() { _loading = false; _msg = 'BLOCKED: Registration incomplete. Register again.'; });
        return;
      }
      setState(() { _loading = false; _msg = '✅ Welcome Client!'; });
      // FIXED: No /client-home in app - go back to Home, user is logged in
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      setState(() {
        _loading = false;
        _msg = 'Login failed: Wrong username/password or not registered.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE91E63),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE91E63),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Client Login', style: TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.favorite, color: Colors.white, size: 70),
            const SizedBox(height: 12),
            const Text('Welcome Back',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
            const Text('Username + Password ONLY - No SMS on login',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Username or Email',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // PASSWORD WITH EYE - ALREADY THERE, KEPT
                  TextField(
                    controller: _passCtrl,
                    obscureText: !_showPass,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showPass = !_showPass),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_msg.isNotEmpty)
                    Text(_msg,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: _msg.startsWith('✅') ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE91E63),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _loading ? null : _login,
                    child: Text(_loading ? 'Checking...' : 'Login as Client',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              // FIXED: Was /client-register (does NOT exist) -> now /client-registration
              onPressed: () => Navigator.pushNamed(context, '/client-registration'),
              child: const Text("Don't have account? Register as Client",
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
