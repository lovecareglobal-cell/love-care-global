import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NurseLoginPage extends StatefulWidget {
  const NurseLoginPage({super.key});
  @override
  State<NurseLoginPage> createState() => _NurseLoginPageState();
}

class _NurseLoginPageState extends State<NurseLoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _msg = '';
  bool _loading = false;

  Future<void> _login() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) { setState(() => _msg = 'Enter email + password'); return; }
    setState(() { _loading = true; _msg = 'Checking...'; });
    try {
      // GUARD: If this email is a CLIENT, BLOCK immediately - before sign in
      final clientCheck = await FirebaseFirestore.instance.collection('clients').where('email', isEqualTo: email).limit(1).get();
      if (clientCheck.docs.isNotEmpty) {
        setState(() { _loading = false; _msg = 'BLOCKED: This is a CLIENT account. Use Client Login.'; });
        return;
      }
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
      final uid = cred.user!.uid;

      // GUARD 2: Must exist in nurses/pending + be approved + complete
      var doc = await FirebaseFirestore.instance.collection('nurses').doc(uid).get();
      if (!doc.exists) {
        doc = await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).get();
      }
      if (!doc.exists) {
        // NOT REGISTERED - DELETE Auth user + BLOCK
        await cred.user!.delete().catchError((_) {});
        await FirebaseAuth.instance.signOut();
        setState(() { _loading = false; _msg = 'BLOCKED: NOT A REGISTERED NURSE. Go Register first.'; });
        return;
      }
      final data = doc.data()!;
      final approved = data['isApproved'] == true || data['approved'] == true || data['status'] == 'approved';
      final complete = data['isComplete'] == true && data['hasPhoto'] == true && data['hasVideo'] == true && data['hasPhone'] == true;
      if (!approved) {
        await FirebaseAuth.instance.signOut();
        setState(() { _loading = false; _msg = 'WAITING FOR CEO APPROVAL. You cannot login yet.'; });
        return;
      }
      if (!complete) {
        await FirebaseAuth.instance.signOut();
        setState(() { _loading = false; _msg = 'BLOCKED: Approved but missing Photo/Video/Phone. Contact CEO.'; });
        return;
      }
      setState(() { _loading = false; _msg = '✅ Welcome Nurse! Redirecting to dashboard...'; });
    } catch (e) {
      setState(() { _loading = false; _msg = 'Login failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nurse Login')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nurse Login', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(hintText: 'Email', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(hintText: 'Password', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            if (_msg.isNotEmpty) Text(_msg, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loading ? null : _login, child: Text(_loading ? 'Checking...' : 'Login as Nurse')),
          ],
        ),
      ),
    );
  }
}
