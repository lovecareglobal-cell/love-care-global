import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCE4EC),
      appBar: AppBar(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, title: const Text('Privacy Policy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _header('💜 Love Care Global - Privacy Policy'),
            _card('Last Updated: 23 November 2026\nCompany: Love Care Global, Accra, Ghana\nContact: lovecareglobal@gmail.com\nThis policy explains what we collect, why, and your rights under Ghana Data Protection Act, 2012 (Act 843).'),
            _section('1. What We Collect'),
            _card('• Name, Username, Email, Phone, Password (encrypted, never stored in plain text)\n• Profile Photo, Nurse Video, ID / Nursing Certificate\n• Location: only while booking / SOS / live tracking, with your permission. We do NOT track you 24/7.\n• Device info, App usage, Chat messages\n• Booking history, Ratings, Complaints\n• Payment info: We do NOT store your card number. Paystack / Flutterwave / Stripe handles payment securely.'),
            _section('2. Why We Collect It'),
            _card('• To verify Nurses (CEO approval) and Clients (email verification)\n• To match Client with nearby verified Nurse\n• To show booking, chat, SOS and tracking\n• To prevent fraud, fake accounts, and abuse\n• To process 20% booking fee refunds where applicable'),
            _section('3. Who We Share With'),
            _card('• Firebase / Google - login, database, notifications\n• Paystack / Flutterwave / Stripe - payments only\n• We NEVER sell your data. We NEVER share your phone / address with strangers. Only your matched Nurse / Client sees what is needed for the booking.'),
            _section('4. Children'),
            _card('This app is 18+ ONLY. We do not knowingly collect data from anyone under 18. If we find an under-18 account, we delete it immediately.'),
            _section('5. Security'),
            _card('Data is encrypted in transit and at rest. Passwords are hashed. Access is restricted to CEO + authorised staff. No method is 100% safe - if you suspect your account is hacked, change password and contact us immediately.'),
            _section('6. How Long We Keep Data'),
            _card('While your account is active. After you delete your account, personal data (photo, video, chats, phone) is deleted within 30 days. Anonymous booking receipts may be kept for legal / tax reasons only.'),
            _section('7. Your Rights (Ghana Act 843)'),
            _card('You can: request a copy of your data, correct wrong data, delete your account, withdraw consent. To do this: Settings > Delete Account, or email lovecareglobal@gmail.com. We will reply within 30 days.'),
            _section('8. Changes'),
            _card('If we change this policy, we will update the date above and show it in-app. Continued use means you accept the new policy.'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  static Widget _header(String t) => Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF880E4F))));
  static Widget _section(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Align(alignment: Alignment.centerLeft, child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF880E4F)))));
  static Widget _card(String t) => Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(t, style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF333333))));
}
