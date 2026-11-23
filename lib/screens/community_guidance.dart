import 'package:flutter/material.dart';

class CommunityGuidelinesPage extends StatelessWidget {
  const CommunityGuidelinesPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCE4EC),
      appBar: AppBar(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, title: const Text('Community Guidelines')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _header('💜 Love Care Global - Community Guidelines\nLast Updated: 23 Nov 2026'),
            _section('1. Be Honest'),
            _card('Nurses: Only upload your REAL photo, video, ID and certificate. No fake identity.\nClients: Use your real name and phone. Fake accounts will be banned.'),
            _section('2. Payment - 20/80 Rule (READ CAREFULLY)'),
            _card('THIS IS THE ONLY PAYMENT RULE:\n• Pay 20% booking fee INSIDE the App to confirm booking.\n• Pay remaining 80% to Nurse AFTER work is finished - in cash or MoMo, only after Nurse finishes.\n• NEVER pay full amount before work starts.\n• NEVER pay Nurse outside a confirmed booking.\n• If a Nurse asks for full payment before work, or asks you to cancel in-app booking to pay outside, REPORT immediately. That is fraud.'),
            _section('3. Be Respectful'),
            _card('No insults, no threats, no harassment, no sexual messages, no discrimination. Nurses and Clients must respect each other, respect homes, respect privacy.'),
            _section('4. No Fake Complaints / No Fake Reviews'),
            _card('Do not file fake complaints to get refund. Do not leave fake 1-star to punish Nurse. Fake reports = account penalty.'),
            _section('5. Penalties'),
            _card('1st Offence: Warning\n2nd Offence: 7-day suspension\n3rd Offence: Permanent Ban + account deleted\nSerious offences (fraud, theft, violence, sexual misconduct) = Immediate Permanent Ban.'),
            _section('6. Child Safety - ZERO TOLERANCE'),
            _card('We have ZERO tolerance for any sexual content involving minors, or any attempt to exploit a child.\n• Never post, send, or request sexual content involving anyone under 18.\n• Never ask a minor for photos, videos, or meeting.\n• If you see such content, REPORT immediately.\nAccount will be PERMANENTLY banned and reported to Ghana Police / authorities.\nThis applies to photos, videos, chats, and profiles.'),
            _section('7. How to Report / Block (User-Generated Content)'),
            _card('To REPORT a user, photo, video or message:\nChat > Tap user name > Report > Choose reason > Submit. CEO reviews within 24 hours.\nTo BLOCK a user:\nChat > Tap user name > Block. Blocked user cannot message you again.\nTo report serious abuse: Email lovecareglobal@gmail.com with screenshots.\nWe review all reports. Content that breaks these rules is removed.'),
            _section('8. No Sharing Personal Data in Chat'),
            _card('Do not share bank PIN, OTP, password, or ID number in chat. CEO / Love Care will NEVER ask for your password or OTP.'),
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
