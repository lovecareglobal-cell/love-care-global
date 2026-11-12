import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'terms-and-conditions.dart';

class DeleteAccountPolicyPage extends StatefulWidget {
  const DeleteAccountPolicyPage({super.key});
  @override
  State<DeleteAccountPolicyPage> createState() => _DeleteAccountPolicyPageState();
}

class _DeleteAccountPolicyPageState extends State<DeleteAccountPolicyPage> {
  bool _confirm = false;
  String _reason = 'No longer need the service';
  Future<void> _requestDelete() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('delete_requests').doc(user.uid).set({
      'uid': user.uid, 'email': user.email, 'reason': _reason,
      'requestedAt': FieldValue.serverTimestamp(), 'status': 'pending',
    });
    if (!mounted) return;
    showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Delete Request Received'), content: const Text('Your account will be deleted within 30 days. You will receive a confirmation email. If you have an active booking, finish it first.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(backgroundColor: const Color(0xFF0C0A1E), title: const Text('Delete Account Policy', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFFFACC15)), onPressed: () => Navigator.pop(context))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _PolicyScaffold(title: '', updated: '', sections: []).build(context), // placeholder to reuse style - replaced below
        ]),
      ),
    );
  }
}
