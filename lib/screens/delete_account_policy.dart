import 'package:flutter/material.dart';

class DeleteAccountPolicyPage extends StatelessWidget {
  const DeleteAccountPolicyPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCE4EC),
      appBar: AppBar(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, title: const Text('Delete Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _header('💜 Love Care Global - Delete Account Policy\nLast Updated: 23 Nov 2026'),
            _section('What Happens When You Delete?'),
            _card('Your account is PERMANENTLY DELETED, not just deactivated.\n• Your profile, photo, video, phone, email, chats, bookings history are deleted within 30 days.\n• You will be logged out immediately and cannot login again with same account.\n• You will lose access to bookings, refunds in progress, and history.\n• Anonymous booking receipts may be kept for legal / tax only - no name, no phone, no photo.'),
            _section('Before You Delete'),
            _card('• Finish or cancel active bookings first.\n• Request any pending refund BEFORE deleting - after deletion we cannot process refunds.\n• Save any chat / receipt you need - you cannot recover it after deletion.'),
            _section('How To Delete (In-App)'),
            _card('1. Open App > Settings > Delete Account\n2. Tap Delete My Account\n3. Type DELETE to confirm\n4. Tap Confirm Delete\nYour account is deleted immediately and you are logged out.'),
            _section('How To Delete By Email (If You Cannot Login)'),
            _card('Email lovecareglobal@gmail.com from your registered email with subject: DELETE MY ACCOUNT.\nInclude your full name + phone + email. We will verify and delete within 30 days.'),
            _section('Can I Create Account Again?'),
            _card('Yes. After deletion, you can register again as a new user. Nurse must go through CEO approval again. Old data will NOT be restored.'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  static Widget _header(String t) => Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF880E4F))));
  static Widget _section(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Align(alignment: Alignment.centerLeft, child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF880E4F)))));
  static Widget _card(String t) => Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(t, style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF333333))));
}
