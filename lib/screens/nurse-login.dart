import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// Nurse Login - STRICT CEO APPROVAL
/// If photo + phone + video + CEO approval missing -> delete Auth user, block login
class NurseLoginScreen extends StatefulWidget {
  const NurseLoginScreen({super.key});
  @override
  State<NurseLoginScreen> createState() => _NurseLoginScreenState();
}

class _NurseLoginScreenState extends State<NurseLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool isLoading = false;

  Future<void> _login() async {
    setState(() => isLoading = true);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      final uid = cred.user!.uid;
      final snap = await FirebaseDatabase.instance.ref('nurses/$uid').get();
      final data = snap.value as Map?;
      final hasPhoto = data?['photoURL'] != null || data?['photo'] != null;
      final hasPhone = (data?['phone']?.toString().isNotEmpty ?? false);
      final hasVideo = data?['videoURL'] != null || data?['video'] != null;
      final isApproved = data?['isApproved'] == true || data?['approved'] == true || data?['canLogin'] == true || data?['status'] == 'approved';

      if (!hasPhoto || !hasPhone || !hasVideo || !isApproved) {
        // STRICT: Delete Auth user, do NOT save login
        try { await cred.user!.delete(); } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Not approved yet. Photo + Phone + Video + CEO approval required. Contact CEO.')));
        return;
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/dashboard');
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Login failed')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nurse Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _passCtrl, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()), obscureText: true),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: isLoading ? null : _login, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), padding: const EdgeInsets.symmetric(vertical: 16)), child: Text(isLoading ? 'Checking CEO Approval...' : 'LOGIN'))),
          const SizedBox(height: 12),
          TextButton(onPressed: () => Navigator.pushNamed(context, '/register'), child: const Text('No account? Register')),
        ]),
      ),
    );
  }
}
