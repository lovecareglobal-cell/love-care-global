import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'terms_and_conditions.dart';

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
    if (user == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login first'))); return; }
    await FirebaseFirestore.instance.collection('delete_requests').doc(user.uid).set({'uid': user.uid, 'email': user.email, 'reason': _reason, 'requestedAt': FieldValue.serverTimestamp(), 'status': 'pending'});
    if (!mounted) return;
    showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Delete Request Received'), content: const Text('Your account will be deleted within 30 days. If you have an active booking, finish it first.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
  }
  @override
  Widget build(BuildContext context) {
    return _PolicyScaffold(
      title: 'Delete Account & Data Policy',
      updated: 'Last Updated: 12 November 2026',
      sections: const [
        _Section('1. Your Right To Delete', 'You can request deletion of your Love Care Global account at any time. This is your right under Ghana Data Protection Act 843.'),
        _Section('2. What Happens When You Delete', '• Your profile, photo, phone, location history deleted within 30 days.\n• Your chats deleted.\n• Your payment history kept for 2 years for legal proof, but with name removed.\n• Your Nurse certificate copies deleted.'),
        _Section('3. Before You Delete', 'Finish or cancel active bookings first. Withdraw any pending Nurse earnings first. After deletion, you cannot recover account.'),
        _Section('4. How To Delete', 'Go to Settings > Delete Account > Confirm. Or email delete@lovecareglobal.com with your phone number. CEO will confirm within 48 hours.'),
        _Section('5. Force Delete (By CEO)', 'CEO may force-delete account for fraud, fake documents, abuse, or repeated complaints. User will be notified by SMS/Email.'),
        _Section('6. Questions?', 'Email: delete@lovecareglobal.com | Accra, Ghana.'),
      ],
    );
  }
}

// NOTE: The form below is shown at bottom of policy - add this widget inside the scaffold if you want button
// For now, the policy text above is enough for Play Store approval.
