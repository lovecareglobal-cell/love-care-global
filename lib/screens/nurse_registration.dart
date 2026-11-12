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
  bool _loading = false;
  bool _showPass = false;
  String _msg = '';

  Future<void> _login() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) { setState(() => _msg = 'Fill Email + Password'); return; }
    setState(() { _loading = true; _msg = 'Checking approval...'; });
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
      final uid = cred.user!.uid;
      final db = FirebaseFirestore.instance;

      // 1. CHECK IF CEO DON APPROVE - IN MAIN nurses COLLECTION?
      final approvedDoc = await db.collection('nurses').doc(uid).get();
      if (approvedDoc.exists) {
        final d = approvedDoc.data()!;
        if (d['isApproved'] == true || d['approved'] == true || d['status'] == 'approved') {
          setState(() { _loading = false; _msg = '✅ Welcome! Login success.'; });
          // TODO: Navigate to Nurse Home here
          // Navigator.pushReplacementNamed(context, '/nurse_home');
          return;
        }
        // In nurses but still not approved (CEO never approve)
        await FirebaseAuth.instance.signOut();
        setState(() { _loading = false; _msg = '❌ BLOCKED: CEO never accept you yet. Waiting CEO Approval at CEO Center.'; });
        return;
      }

      // 2. CHECK IF STILL IN PENDING - WAITING CEO
      final pendingDoc = await db.collection('pending_nurses').doc(uid).get();
      if (pendingDoc.exists) {
        final d = pendingDoc.data()!;
        final status = (d['status'] ?? 'pending').toString();
        await FirebaseAuth.instance.signOut();
        if (status == 'rejected') {
          setState(() { _loading = false; _msg = '❌ CEO REJECTED your application. Contact Support / CEO Center.'; });
        } else {
          setState(() { _loading = false; _msg = '⏳ WAITING CEO APPROVAL! You cannot login until CEO accept you at CEO Registration Center. Check back later.'; });
        }
        return;
      }

      // 3. NO RECORD - NOT A NURSE OR DELETED
      await FirebaseAuth.instance.signOut();
      setState(() { _loading = false; _msg = '❌ No Nurse account found. Register as Nurse first or use Client Login.'; });
    } on FirebaseAuthException catch (e) {
      await FirebaseAuth.instance.signOut().catchError((_) {});
      String m = 'Login failed';
      if (e.code == 'user-not-found') m = '❌ No account with this email. Register first.';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') m = '❌ Wrong Email or Password.';
      if (e.code == 'user-disabled') m = '❌ Account disabled by CEO.';
      setState(() { _loading = false; _msg = m; });
    } catch (e) {
      await FirebaseAuth.instance.signOut().catchError((_) {});
      setState(() { _loading = false; _msg = 'Login failed. Try again. $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nurse Login')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Nurse Login', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const Text('Only CEO-Approved Nurses can login', textAlign: TextAlign.center, style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(controller: _emailCtrl, decoration: const InputDecoration(hintText: 'Email', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _passCtrl, obscureText: !_showPass,
            decoration: InputDecoration(hintText: 'Password', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPass = !_showPass)))),
          const SizedBox(height: 12),
          if (_msg.isNotEmpty) Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _msg.startsWith('✅') ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(8)), child: Text(_msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _loading ? null : _login, child: Text(_loading ? 'Checking CEO Approval...' : 'Login')),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pushNamed(context, '/nurse_register'), child: const Text("No account? Register as Nurse - Wait CEO Approval")),
        ]),
      ),
    );
  }
}
