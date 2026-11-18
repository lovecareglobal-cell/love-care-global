import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _showVerifyHelp = false;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // NEW RULE - CLIENT:
  // Pending = NOT verified email ONLY. CEO does NOT approve Client.
  // Immediately emailVerified == true -> isApproved = true, canLogin = true, status = approved
  // We auto-fix Firestore + RTDB on login, so CEO Pending list go only show unverified clients.
  Future<Map<String, dynamic>> _autoApproveVerifiedClient({
    required String uid,
    required String email,
    required Map<String, dynamic>? existing,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final data = <String, Object?>{
      'uid': uid, 'id': uid,
      'email': email.toLowerCase(),
      'role': 'client', 'type': 'client',
      'emailVerified': true, 'verifiedByEmail': true,
      // CLIENT AUTO-APPROVED ON VERIFY - NO CEO APPROVAL
      'isApproved': true, 'approved': true,
      'status': 'approved', 'approvalStatus': 'approved',
      'canLogin': true, 'isVerified': true,
      'isComplete': true, 'hasAll4': true,
      'approvedAt': now, 'updatedAt': now,
    };
    // Keep old name/username/phone if dem exist, no overwrite with empty
    if (existing != null) {
      if ((existing['fullName'] ?? existing['name'] ?? '').toString().isNotEmpty) {
        data['fullName'] = existing['fullName'] ?? existing['name'];
        data['name'] = existing['fullName'] ?? existing['name'];
      }
      if ((existing['username'] ?? '').toString().isNotEmpty) data['username'] = existing['username'];
      if ((existing['phone'] ?? '').toString().isNotEmpty) data['phone'] = existing['phone'];
      if ((existing['photo'] ?? existing['photoUrl'] ?? existing['photoURL'] ?? '').toString().isNotEmpty) {
        data['photo'] = existing['photo'] ?? existing['photoUrl'] ?? existing['photoURL'];
        data['photoUrl'] = existing['photo'] ?? existing['photoUrl'] ?? existing['photoURL'];
        data['photoURL'] = existing['photo'] ?? existing['photoUrl'] ?? existing['photoURL'];
      }
    }
    // Firestore - merge so we no delete name/phone
    await FirebaseFirestore.instance.collection('clients').doc(uid).set(data, SetOptions(merge: true));
    // RTDB - CEO reads from here. Approved clients go to Approved tab, Pending go empty if all verified.
    final rtdb = Map<String, Object?>.from(data)..['createdAt'] = now;
    await FirebaseDatabase.instance.ref('clients/$uid').update(rtdb);
    await FirebaseDatabase.instance.ref('ceoRegistrationCenter/clients/$uid').update(rtdb);
    await FirebaseDatabase.instance.ref('client_registrations/$uid').update(rtdb);
    await FirebaseDatabase.instance.ref('allowedClients/${email.toLowerCase().replaceAll(RegExp(r'[.#\$@\[\]]'), '_')}').set({...rtdb, 'uid': uid});
    await FirebaseDatabase.instance.ref('allowedClientsByUid/$uid').set({...rtdb, 'uid': uid});
    return {...?existing, ...data};
  }

  Future<void> _login() async {
    final username = _userCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;
    if (username.isEmpty || pass.isEmpty) {
      setState(() { _msg = 'Enter username/email + password'; _showVerifyHelp = false; });
      return;
    }
    setState(() { _loading = true; _msg = 'Checking...'; _showVerifyHelp = false; });
    try {
      // GUARD: ONE EMAIL = ONE ROLE - if user typed an email, block if it is a Nurse email.
      if (username.contains('@')) {
        final nurseCheckEmail = await FirebaseFirestore.instance.collection('nurses').where('email', isEqualTo: username).limit(1).get();
        final pendingCheckEmail = await FirebaseFirestore.instance.collection('pending_nurses').where('email', isEqualTo: username).limit(1).get();
        if (nurseCheckEmail.docs.isNotEmpty || pendingCheckEmail.docs.isNotEmpty) {
          setState(() { _loading = false; _msg = 'BLOCKED: This is a NURSE account. Use Nurse Login.'; });
          return;
        }
      }

      // LOGIN WITH REAL EMAIL - User can type Email OR Username
      String loginEmail = username;
      if (!username.contains('@')) {
        // Username -> real email lookup. Try Firestore first, then RTDB (for orphans)
        var byUsername = await FirebaseFirestore.instance.collection('clients').where('username', isEqualTo: username).limit(1).get();
        if (byUsername.docs.isEmpty) {
          byUsername = await FirebaseFirestore.instance.collection('clients').where('username', isEqualTo: username.toLowerCase()).limit(1).get();
        }
        if (byUsername.docs.isEmpty) {
          // RTDB fallback - registration saves to RTDB immediately, so username fit dey there even if Firestore missing
          try {
            final snap = await FirebaseDatabase.instance.ref('clients').get();
            if (snap.exists) {
              for (final e in (snap.value as Map).entries) {
                final v = e.value is Map ? Map<String, dynamic>.from(e.value as Map) : {};
                if ((v['username'] ?? '').toString().toLowerCase() == username) {
                  loginEmail = (v['email'] ?? '').toString().trim().toLowerCase();
                  break;
                }
              }
            }
          } catch (_) {}
        } else {
          loginEmail = (byUsername.docs.first.data()['email'] as String?)?.trim().toLowerCase() ?? '';
        }
        if (loginEmail.isEmpty || !loginEmail.contains('@')) {
          // Username not found - maybe user never finished registration, or typed wrong username
          // Tell am to try Email, NO delete anything
          setState(() { _loading = false; _msg = 'Login failed: Username not found. Try login with your Email instead, or Register first.'; });
          return;
        }
      }

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: loginEmail, password: pass);
      // FIX: reload - without this, phone sees cached emailVerified=false even after Gmail verify
      try { await cred.user!.reload(); } catch (_) {}
      final freshUser = FirebaseAuth.instance.currentUser ?? cred.user!;
      final uid = freshUser.uid;

      // GUARD: Same Auth account cannot be a Nurse
      final nurseByUid = await FirebaseFirestore.instance.collection('nurses').doc(uid).get();
      final pendingByUid = await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).get();
      if (nurseByUid.exists || pendingByUid.exists) {
        await FirebaseAuth.instance.signOut();
        setState(() { _loading = false; _msg = 'BLOCKED: This account is a NURSE. Use Nurse Login. One email cannot be both.'; });
        return;
      }

      // ===== CLIENT GATE - ONLY GATE NA EMAIL VERIFICATION =====
      // Pending = NOT verified. Verified = login immediately, NO CEO.
      final authVerified = freshUser.emailVerified;
      if (!authVerified) {
        // Check legacy OTP clients - dem no get email verify, but phoneVerified true
        final legacyDoc = await FirebaseFirestore.instance.collection('clients').doc(uid).get();
        final legacyPhoneVerified = legacyDoc.exists && (legacyDoc.data()?['phoneVerified'] == true || legacyDoc.data()?['otpVerified'] == true);
        if (!legacyPhoneVerified) {
          // DO NOT signOut + delete. Keep user logged in so "I Have Verified" fit work without re-typing password.
          // Just show verify help.
          setState(() {
            _loading = false;
            _showVerifyHelp = true;
            _msg = '⏳ PENDING: Email NOT verified yet. You are still Pending.\n\nOpen Gmail, tap the verification link, then press "I HAVE VERIFIED" below. No need to type password again.';
          });
          return;
        }
        // Legacy OTP - allow, treat as verified
      }

      // Get existing doc - if missing (old bug: Auth exists, DB missing), DO NOT DELETE, DO NOT SAY "not registered"
      // Auto-create + auto-approve. This fixes Michael case.
      var doc = await FirebaseFirestore.instance.collection('clients').doc(uid).get();
      Map<String, dynamic>? existing = doc.exists ? doc.data() : null;

      // If Firestore missing, try RTDB - registration saves there immediately
      if (existing == null) {
        try {
          final rtdbSnap = await FirebaseDatabase.instance.ref('clients/$uid').get();
          if (rtdbSnap.exists && rtdbSnap.value is Map) existing = Map<String, dynamic>.from(rtdbSnap.value as Map);
        } catch (_) {}
      }

      // AUTO-APPROVE: verified -> approved immediately
      final data = await _autoApproveVerifiedClient(uid: uid, email: loginEmail, existing: existing);

      // Save for ClientDashboardScreen
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('clientName', (data['fullName'] ?? data['name'] ?? '').toString());
        await prefs.setString('fullName', (data['fullName'] ?? data['name'] ?? '').toString());
        await prefs.setString('clientUsername', (data['username'] ?? '').toString());
        await prefs.setString('username', (data['username'] ?? '').toString());
        await prefs.setString('clientPhone', (data['phone'] ?? '').toString());
        await prefs.setString('phone', (data['phone'] ?? '').toString());
        await prefs.setString('clientPhoto', (data['photoUrl'] ?? data['photo'] ?? data['photoURL'] ?? '').toString());
        await prefs.setString('photoUrl', (data['photoUrl'] ?? data['photo'] ?? data['photoURL'] ?? '').toString());
        await prefs.setString('clientPhotoUrl', (data['photoUrl'] ?? data['photo'] ?? data['photoURL'] ?? '').toString());
        await prefs.setString('clientCountryCode', (data['countryCode'] ?? '+233').toString());
        await prefs.setString('lcg_client_uid', uid);
        await prefs.setString('clientUid', uid);
        await prefs.setString('clientEmail', loginEmail);
        await prefs.setBool('client_pending_verification', false);
      } catch (_) {}

      setState(() { _loading = false; _msg = '✅ Welcome Client!'; _showVerifyHelp = false; });
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/client-dashboard', (route) => false);
    } on FirebaseAuthException catch (e) {
      String m;
      if (e.code == 'user-not-found' || e.code == 'invalid-credential' || e.code == 'wrong-password') {
        m = 'Login failed: Wrong email/username or password. If you never finished email verification, check Gmail and tap link, then try again.';
      } else if (e.code == 'invalid-email') { m = 'Login failed: Enter a valid email.'; }
      else if (e.code == 'too-many-requests') { m = 'Too many tries. Wait a few minutes and try again.'; }
      else if (e.code == 'user-disabled') { m = 'This account is disabled. Contact CEO.'; }
      else { m = 'Login failed: ${e.message ?? e.code}'; }
      setState(() { _loading = false; _msg = m; _showVerifyHelp = false; });
    } catch (e) {
      setState(() { _loading = false; _msg = 'Login failed: Wrong username/password or not registered.'; });
    }
  }

  // I HAVE VERIFIED - user don tap Gmail link, we just reload and try login again, no need to re-type password
  Future<void> _iHaveVerified() async {
    setState(() { _loading = true; _msg = 'Checking Gmail verification...'; });
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) {
        // User was signed out before - just try normal login with typed email/pass
        setState(() { _loading = false; _msg = 'Type your email + password again and press Login.'; });
        return;
      }
      await u.reload();
      final fresh = FirebaseAuth.instance.currentUser;
      if (fresh != null && fresh.emailVerified) {
        // Verified now - auto-approve + go dashboard, no need password again
        final data = await _autoApproveVerifiedClient(uid: fresh.uid, email: fresh.email ?? _userCtrl.text.trim(), existing: null);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('clientName', (data['fullName'] ?? data['name'] ?? '').toString());
          await prefs.setString('fullName', (data['fullName'] ?? data['name'] ?? '').toString());
          await prefs.setString('clientUsername', (data['username'] ?? '').toString());
          await prefs.setString('username', (data['username'] ?? '').toString());
          await prefs.setString('clientPhone', (data['phone'] ?? '').toString());
          await prefs.setString('phone', (data['phone'] ?? '').toString());
          await prefs.setString('lcg_client_uid', fresh.uid);
          await prefs.setString('clientUid', fresh.uid);
          await prefs.setString('clientEmail', fresh.email ?? '');
          await prefs.setBool('client_pending_verification', false);
        } catch (_) {}
        setState(() { _loading = false; _msg = '✅ Email verified! Welcome Client!'; _showVerifyHelp = false; });
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/client-dashboard', (route) => false);
      } else {
        setState(() { _loading = false; _msg = 'Still NOT verified. Open Gmail, tap the link, wait 5 seconds, then press I HAVE VERIFIED again.'; });
      }
    } catch (e) {
      setState(() { _loading = false; _msg = 'Check failed: $e'; });
    }
  }

  Future<void> _resendVerification() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        await u.sendEmailVerification();
        setState(() => _msg = '✅ Verification email resent to ${u.email}. Check Gmail + Spam.');
      } else {
        setState(() => _msg = 'Login first with email + password, then press Resend.');
      }
    } catch (e) {
      setState(() => _msg = 'Resend failed: $e');
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
          onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/home', (r) => false),
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
            const Text('Welcome Back', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
            const Text('Verified = Login immediately. No CEO approval for Clients.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(controller: _userCtrl, decoration: const InputDecoration(labelText: 'Username or Email', prefixIcon: Icon(Icons.person), border: OutlineInputBorder())),
                  const SizedBox(height: 14),
                  TextField(controller: _passCtrl, obscureText: !_showPass, decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock), suffixIcon: IconButton(icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPass = !_showPass)), border: const OutlineInputBorder())),
                  const SizedBox(height: 14),
                  if (_msg.isNotEmpty) Text(_msg, textAlign: TextAlign.center, style: TextStyle(color: _msg.startsWith('✅') ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE91E63), padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: _loading ? null : _login, child: Text(_loading ? 'Checking...' : 'Login as Client', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                  if (_showVerifyHelp) ...[
                    const SizedBox(height: 12),
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: _loading ? null : _iHaveVerified, child: const Text('I HAVE VERIFIED - Tap After Gmail', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: _resendVerification, child: const Text('Resend Verification Email')),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: () => Navigator.pushNamed(context, '/client-registration'), child: const Text("Don't have account? Register as Client", style: TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }
}
