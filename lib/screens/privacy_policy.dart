import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: const Color(0xFF880E4F),
        foregroundColor: Colors.white,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Text(
          'LoveCare Global - Privacy Policy\n\n'
          'We respect your privacy.\n\n'
          '1. What we collect: Name, phone, email, location for bookings, care needs.\n\n'
          '2. How we use it: To match you with nurses, manage bookings, payments, support.\n\n'
          '3. We do NOT sell your data.\n\n'
          '4. Data stored securely in Firebase.\n\n'
          '5. You can request deletion anytime from Settings > Delete Account.\n\n'
          'Contact: lovecareglobal@gmail.com\nAccra, Ghana',
          style: TextStyle(fontSize: 16, height: 1.5),
        ),
      ),
    );
  }
}
