import 'package:flutter/material.dart';

class TermsAndConditionsPage extends StatelessWidget {
  const TermsAndConditionsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return _PolicyScaffold(
      title: 'Terms & Conditions',
      updated: 'Last Updated: 12 November 2026',
      sections: const [
        _Section('1. Welcome to Love Care Global', 'By using Love Care Global App, you agree to these Terms. If you do not agree, please do not use the App. Love Care Global connects Clients who need care with verified Nurses, Caregivers and Health Workers in Ghana and beyond.'),
        _Section('2. Who Can Use The App', 'You must be 18 years or older. Nurses must provide valid ID, Nursing Council / Health Training Certificate, and proof of qualification. Clients must provide accurate name, phone, location and care needs. Fake accounts will be deleted.'),
        _Section('3. Services We Provide', 'Home nursing, elderly care, baby / post-natal care, hospital accompaniment, wound care, vital signs monitoring, medication reminders, and companionship. We do NOT provide emergency ambulance service. For emergencies, call 112 / 193 or go to nearest hospital.'),
        _Section('4. Booking & Payment', 'Client books a Nurse, pays via Mobile Money, Paystack, Stripe or Flutterwave. Payment is held safely until Client confirms work is completed. Nurse is paid after Client confirmation minus Love Care Global service fee. Prices shown in GHS are final unless CEO approves a change.'),
        _Section('5. Nurse Duties', 'Nurse must arrive on time, dress professionally, be respectful, follow care plan, NOT ask Client for extra cash outside App, NOT share Client private info, and update booking status: Accepted > On The Way > Close > Completed.'),
        _Section('6. Client Duties', 'Client must provide safe working environment, accurate location, respect Nurse, pay only through App, and confirm completion honestly. Client must NOT harass, abuse or request services outside care scope.'),
        _Section('7. Cancellation', 'Client can cancel before Nurse accepts for full refund. After Nurse accepts, 20% fee may apply. If Nurse cancels without reason, Nurse may be penalized. See Cancellation & Refund Policy.'),
        _Section('8. Safety & SOS', 'Both Nurse and Client have SOS button. SOS alerts CEO, nearest Nurse and Emergency Contact with live location. Misuse of SOS is punishable.'),
        _Section('9. Ratings & Complaints', 'After every job, Client rates Nurse 1-5 stars. Complaints are reviewed by CEO within 48 hours. CEO decision is final.'),
        _Section('10. Account Termination', 'We may suspend or delete any account for fraud, abuse, fake documents, harassment, or breaking these Terms. See Delete Policy.'),
        _Section('11. Liability', 'Love Care Global is a platform connecting Nurses and Clients. We verify Nurses, but we are not liable for medical outcomes beyond our control. Nurses are responsible for their professional care.'),
        _Section('12. Changes', 'We may update these Terms. Continued use means you accept new Terms. Contact: support@lovecareglobal.com | Accra, Ghana.'),
      ],
    );
  }
}

// Shared UI for all policy pages - reuse it
class _Section { final String title; final String body; const _Section(this.title, this.body); }

class _PolicyScaffold extends StatelessWidget {
  final String title; final String updated; final List<_Section> sections;
  const _PolicyScaffold({required this.title, required this.updated, required this.sections});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(backgroundColor: const Color(0xFF0C0A1E), title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFFFACC15)), onPressed: () => Navigator.pop(context))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFA855F7)]), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('Love Care Global • Trusted Care, With Love', style: const TextStyle(color: Colors.white70, fontSize: 12)), const SizedBox(height: 8), Text(updated, style: const TextStyle(color: Colors.white70, fontSize: 11))])),
          const SizedBox(height: 18),
          ...sections.map((s) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x14FFFFFF))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.title, style: const TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(height: 6), Text(s.body, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5))]))),
          const SizedBox(height: 10),
          const Center(child: Text('© 2026 Love Care Global. All rights reserved.', style: TextStyle(color: Color(0xFF9A95B8), fontSize: 11))),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }
}
