import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ClientRegistrationPage extends StatefulWidget {
  const ClientRegistrationPage({super.key});
  @override
  State<ClientRegistrationPage> createState() => _ClientRegistrationPageState();
}

class _ClientRegistrationPageState extends State<ClientRegistrationPage> {
  final _userCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _showOtp = false;
  bool _loading = false;
  bool _showPass = false; // NEW: For show/hide password eye
  String _msg = '';
  String _fakeEmail = '';

  Future<String?> _checkExists(String username, String phone, String email) async {
    final db = FirebaseFirestore.instance;
    final u = username.trim().toLowerCase();
    final p = phone.trim();
    // Check Clients
    final byUser = await db.collection('clients').where('username', isEqualTo: u).limit(1).get();
    if (byUser.docs.isNotEmpty) return 'client';
    final byPhone = await db.collection('clients').where('phone', isEqualTo: p).limit(1).get();
    if (byPhone.docs.isNotEmpty) return 'client';
    // Check Nurses - BLOCK DOUBLE
    final nursePhone = await db.collection('nurses').where('phone', isEqualTo: p).limit(1).get();
    if (nursePhone.docs.isNotEmpty) return 'nurse';
    final nurseEmail = await db.collection('nurses').where('email', isEqualTo: email).limit(1).get();
    if (nurseEmail.docs.isNotEmpty) return 'nurse';
    final pendingNurse = await db.collection('pending_nurses').where('phone', isEqualTo: p).limit(1).get();
    if (pendingNurse.docs.isNotEmpty) return 'pending_nurse';
    return null;
  }

  Future<void> _cleanup(String? uid) async {
    try {
      if (uid != null) {
        await FirebaseFirestore.instance.collection('clients').doc(uid).delete().catchError((_) {});
        await FirebaseFirestore.instance.collection('pending_clients').doc(uid).delete().catchError((_) {});
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) await user.delete().catchError((_) {});
      await FirebaseAuth.instance.signOut().catchError((_) {});
    } catch (_) {}
  }

  Future<void> _sendOtp() async {
    final user = _userCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (user.isEmpty || phone.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _msg = 'Fill username, phone, password');
      return;
    }
    setState(() { _loading = true; _msg = 'Checking double account...'; });
    // Fake email for Firebase Auth - Client uses Username, not Email
    _fakeEmail = '${user.toLowerCase()}@lovecare.client';
    final exists = await _checkExists(user, phone, _fakeEmail);
    if (exists != null) {
      setState(() { _loading = false; _msg = 'BLOCKED: Username/phone already exists as $exists. Use Login.'; });
      return;
    }
    setState(() { _loading = false; _showOtp = true; _msg = 'OTP sent (Demo: 123456)'; });
  }

  Future<void> _register() async {
    if (_otpCtrl.text != '123456') {
      setState(() => _msg = 'Wrong OTP');
      return;
    }
    setState(() => _loading = true);
    String? uid;
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: _fakeEmail, password: _passCtrl.text);
      uid = cred.user!.uid;
      final data = {
        'uid': uid,
        'username': _userCtrl.text.trim().toLowerCase(),
        'phone': _phoneCtrl.text.trim(),
        'email': _fakeEmail,
        'role': 'client',
        'isComplete': true,
        'isApproved': true,
        'status': 'approved',
        'createdAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance.collection('clients').doc(uid).set(data);
      await FirebaseAuth.instance.signOut();
      setState(() { _loading = false; _msg = '✅ Registered! Go to Login with Username + Password'; });
    } catch (e) {
      await _cleanup(uid);
      setState(() { _loading = false; _msg = 'Failed - cleaned up. Try again. $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Client Registration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Client Registration', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: _userCtrl, decoration: const InputDecoration(hintText: 'Username', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(hintText: 'Phone +233...', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            // FIXED: Password with Show/Hide Eye
            TextField(
              controller: _passCtrl,
              obscureText: !_showPass,
              decoration: InputDecoration(
                hintText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_showOtp) ...[
              TextField(controller: _otpCtrl, decoration: const InputDecoration(hintText: 'OTP - 123456', border: OutlineInputBorder())),
              const SizedBox(height: 12),
            ],
            if (_msg.isNotEmpty) Text(_msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loading ? null : (_showOtp ? _register : _sendOtp), child: Text(_showOtp ? 'Verify & Register' : 'Send OTP')),
          ],
        ),
      ),
    );
  }
}
