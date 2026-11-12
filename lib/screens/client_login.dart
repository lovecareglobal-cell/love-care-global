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
      setState(() => _msg = 'Enter username + password');
      return;
    }
    setState(() { _loading = true; _msg = 'Checking...'; });
    try {
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
      // Client uses Username -> fake email
      final fakeEmail = '$username@lovecare.client';
      final cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: fakeEmail, password: pass);
      final uid = cred.user!.uid;

      // GUARD 2: Must exist in clients
      final doc = await FirebaseFirestore.instance
          .collection('clients')
          .doc(uid)
          .get();
      if (!doc.exists) {
        await FirebaseAuth.instance.signOut();
        setState(() {
          _loading = false;
          _msg = 'BLOCKED: NOT A REGISTERED CLIENT. Go Register first.';
        });
        return;
      }
      final data = doc.data()!;
      if (data['isComplete'] != true) {
        await FirebaseAuth.instance.signOut();
        setState(() {
          _loading = false;
          _msg = 'BLOCKED: Registration incomplete. Register again.';
        });
        return;
      }
      setState(() { _loading = false; _msg = '✅ Welcome Client!'; });
      // GO TO CLIENT HOME - this was missing before!
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/client-home',
        (route) => false,
      );
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
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
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
              onPressed: () => Navigator.pushNamed(context, '/client-register'),
              child: const Text("Don't have account? Register as Client",
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
