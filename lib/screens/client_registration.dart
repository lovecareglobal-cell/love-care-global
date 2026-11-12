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
  bool _showPass = false;
  String _msg = '';
  String _passMsg = '';
  String _fakeEmail = '';

  // 1. COUNTRY CODE - SAME AS NURSE
  String _countryCode = '+233';
  final _codes = ['+233', '+234', '+225', '+228', '+44', '+1', '+33', '+49', '+27'];
  final _codeNames = {'+233': 'Ghana', '+234': 'Nigeria', '+225': "Côte d'Ivoire", '+228': 'Togo', '+44': 'UK', '+1': 'USA/Canada', '+33': 'France', '+49': 'Germany', '+27': 'South Africa'};

  // 2. STRONG PASSWORD CHECK - SAME AS NURSE
  String _checkPassword(String p) {
    if (p.isEmpty) return '';
    if (p.length < 8) return '❌ Too short - Need 8+ characters';
    if (!RegExp(r'[A-Z]').hasMatch(p)) return '❌ Add 1 CAPITAL letter (A-Z)';
    if (!RegExp(r'[a-z]').hasMatch(p)) return '❌ Add 1 small letter (a-z)';
    if (!RegExp(r'[0-9]').hasMatch(p)) return '❌ Add 1 number (0-9)';
    if (!RegExp(r'[!@#\$%^&*]').hasMatch(p)) return '❌ Add 1 symbol (!@#\$ etc)';
    return '✅ Strong Password - Good!';
  }
  bool get _isStrong => _checkPassword(_passCtrl.text).startsWith('✅');
  Color get _passColor => _isStrong ? Colors.green : (_passCtrl.text.length < 4 ? Colors.red : Colors.orange);
  double get _passStrength {
    var s = 0.0;
    if (_passCtrl.text.length >= 8) s += 0.2;
    if (RegExp(r'[A-Z]').hasMatch(_passCtrl.text)) s += 0.2;
    if (RegExp(r'[a-z]').hasMatch(_passCtrl.text)) s += 0.2;
    if (RegExp(r'[0-9]').hasMatch(_passCtrl.text)) s += 0.2;
    if (RegExp(r'[!@#\$%^&*]').hasMatch(_passCtrl.text)) s += 0.2;
    return s;
  }

  String get _fullPhone => '$_countryCode${_phoneCtrl.text.trim()}';

  Future<String?> _checkExists(String user, String phone, String email) async {
    try {
      final db = FirebaseFirestore.instance;
      final c1 = await db.collection('clients').where('username', isEqualTo: user.toLowerCase()).limit(1).get().timeout(const Duration(seconds: 8));
      if (c1.docs.isNotEmpty) return 'client';
      final c2 = await db.collection('clients').where('phone', isEqualTo: phone).limit(1).get().timeout(const Duration(seconds: 8));
      if (c2.docs.isNotEmpty) return 'client';
      final n1 = await db.collection('nurses').where('phone', isEqualTo: phone).limit(1).get().timeout(const Duration(seconds: 8));
      if (n1.docs.isNotEmpty) return 'nurse';
      return null;
    } catch (_) { return null; }
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
    final phone = _fullPhone;
    if (user.isEmpty || _phoneCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _msg = 'Fill username, phone, password');
      return;
    }
    // BLOCK WEAK PASSWORD BEFORE OTP
    if (!_isStrong) {
      setState(() => _msg = 'Password too weak! $_passMsg');
      return;
    }
    setState(() { _loading = true; _msg = 'Checking double account...'; });
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
    if (!_isStrong) {
      setState(() => _msg = 'Password too weak! $_passMsg');
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
        'phone': _fullPhone,
        'countryCode': _countryCode,
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
            // COUNTRY CODE + PHONE
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                child: DropdownButton<String>(value: _countryCode, underline: const SizedBox(), items: _codes.map((c) => DropdownMenuItem(value: c, child: Text('$c ${_codeNames[c]}'))).toList(), onChanged: (v) => setState(() => _countryCode = v ?? '+233'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: 'Phone e.g. 241234567', border: OutlineInputBorder()))),
            ]),
            Text('Saved as: $_fullPhone', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 12),
            // STRONG PASSWORD
            TextField(controller: _passCtrl, obscureText: !_showPass, onChanged: (v) => setState(() => _passMsg = _checkPassword(v)),
              decoration: InputDecoration(hintText: 'Password - Strong Required', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPass = !_showPass)))),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: _passStrength, backgroundColor: Colors.grey.shade200, color: _passColor, minHeight: 6),
            const SizedBox(height: 4),
            Text(_passMsg.isEmpty ? 'Need: 8+ chars, 1 CAPITAL, 1 small, 1 number, 1 symbol (!@#)' : _passMsg, style: TextStyle(fontSize: 12, color: _passColor, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_showOtp) ...[
              TextField(controller: _otpCtrl, decoration: const InputDecoration(hintText: 'OTP - 123456', border: OutlineInputBorder())),
              const SizedBox(height: 12),
            ],
            if (_msg.isNotEmpty) Text(_msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            if (!_showOtp)
              ElevatedButton(onPressed: _loading ? null : _sendOtp, child: Text(_loading ? 'Checking...' : 'Send OTP')),
            if (_showOtp)
              ElevatedButton(onPressed: _loading ? null : _register, child: Text(_loading ? 'Registering...' : 'Register')),
          ],
        ),
      ),
    );
  }
}
