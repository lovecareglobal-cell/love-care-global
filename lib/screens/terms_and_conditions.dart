import 'package:flutter/material.dart';

class TermsAndConditionsPage extends StatelessWidget {
  const TermsAndConditionsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCE4EC),
      appBar: AppBar(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, title: const Text('Terms & Conditions')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _header('💜 Love Care Global - Terms & Conditions\nLast Updated: 23 Nov 2026'),
            _section('1. Acceptance'),
            _card('By using Love Care Global, you agree to these Terms, Privacy Policy, Community Guidelines, Refund Policy and Health Disclaimer. If you do not agree, do not use the app.'),
            _section('2. Who Can Use'),
            _card('You must be 18 years or older. Nurses must upload real Photo, Video, Phone, ID and Nursing Certificate and wait for CEO approval. Clients must verify email before login. One person cannot be both Nurse and Client with same phone / email.'),
            _section('3. Emergency Disclaimer - IMPORTANT'),
            _card('Love Care Global does NOT provide emergency medical services. We do NOT provide ambulance. For emergencies, call Ambulance / 112 or go to nearest hospital immediately. See full Health Disclaimer page.'),
            _section('4. Nurses Are Independent, Not Employees'),
            _card('Nurses are independent caregivers, not employees of Love Care Global. Love Care connects Client and Nurse. Nurse is responsible for the quality of care she / he provides. Love Care does not guarantee medical outcomes.'),
            _section('5. Payment - 20/80 Rule'),
            _card('Client pays 20% booking fee inside App to confirm booking. Client pays remaining 80% directly to Nurse AFTER work is finished (cash or MoMo). CEO never holds Nurse earnings. There is NO nurse withdrawal - Nurse already collects 80% from Client.'),
            _section('6. Cancellations & Refunds'),
            _card('See Refund Policy page. Only the 20% booking fee is handled by Love Care. 80% paid to Nurse after work is between Client and Nurse, unless Nurse did not show up or did not work - then report for CEO review.'),
            _section('7. Your Account'),
            _card('Keep password secret. You are responsible for all activity on your account. If your account is hacked, tell us immediately. We can suspend or delete accounts that break rules, use fake identity, or commit fraud.'),
            _section('8. Limitation of Liability'),
            _card('To the maximum allowed by Ghana law, Love Care Global is not liable for indirect loss, or for actions of independent Nurses / Clients. Our liability for any booking is limited to the 20% booking fee paid for that booking.'),
            _section('9. Governing Law'),
            _card('These Terms are governed by the laws of Ghana. Any dispute will be settled in Accra, Ghana. First, try to settle by contacting CEO. If not settled, follow Ghana law.'),
            _section('10. Changes'),
            _card('We may update these Terms. Updated date will be shown. Continued use means you accept new Terms.'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  static Widget _header(String t) => Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF880E4F))));
  static Widget _section(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Align(alignment: Alignment.centerLeft, child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF880E4F)))));
  static Widget _card(String t) => Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(t, style: const TextStyle(fontSize: 13, height: 1.5)));
}
