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

  Future<void> _login() async {
    final username = _userCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;
    if (username.isEmpty || pass.isEmpty) { setState(() => _msg = 'Enter username + password'); return; }
    setState(() { _loading = true; _msg = 'Checking...'; });
    try {
      // GUARD: If username is a NURSE email/phone, BLOCK
      final nurseCheck = await FirebaseFirestore.instance.collection('nurses').where('email', isEqualTo: username).limit(1).get();
      if (nurseCheck.docs.isNotEmpty) {
        setState(() { _loading = false; _msg = 'BLOCKED: This is a NURSE account. Use Nurse Login.'; });
        return;
      }
      // Client uses Username -> fake email
      final fakeEmail = '$username@lovecare.client';
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: fakeEmail, password: pass);
      final uid = cred.user!.uid;

      // GUARD 2: Must exist in clients
      final doc = await FirebaseFirestore.instance.collection('clients').doc(uid).get();
      if (!doc.exists) {
        await cred.user!.delete().catchError((_) {});
        await FirebaseAuth.instance.signOut();
        setState(() { _loading = false; _msg = 'BLOCKED: NOT A REGISTERED CLIENT. Go Register first.'; });
        return;
      }
      final data = doc.data()!;
      if (data['isComplete'] != true) {
        await FirebaseAuth.instance.signOut();
        setState(() { _loading = false; _msg = 'BLOCKED: Registration incomplete. Register again.'; });
        return;
      }
      setState(() { _loading = false; _msg = '✅ Welcome Client!'; });
    } catch (e) {
      setState(() { _loading = false; _msg = 'Login failed: Wrong username/password or not registered.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Client Login')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Client Login', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Text('Username + Password ONLY - No SMS on login', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 16),
            TextField(controller: _userCtrl, decoration: const InputDecoration(hintText: 'Username', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(hintText: 'Password', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            if (_msg.isNotEmpty) Text(_msg, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loading ? null : _login, child: Text(_loading ? 'Checking...' : 'Login as Client')),
          ],
        ),
      ),
    );
  }
}
