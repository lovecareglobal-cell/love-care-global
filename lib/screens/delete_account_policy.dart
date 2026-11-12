import 'package:flutter/material.dart';

class DeleteAccountPolicyPage extends StatelessWidget {
  const DeleteAccountPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delete Account Policy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text('1. How to Delete', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('You can delete your account anytime from Settings > Delete Account. Once you confirm, your account will be deactivated.'),
          SizedBox(height: 16),
          Text('2. What Happens', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Your personal data will be deleted within 30 days. Bookings history may be kept for legal reasons.'),
          SizedBox(height: 16),
          Text('3. Contact Us', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('For any question, contact us at support@lovecareglobal.com'),
        ],
      ),
    );
  }
}
