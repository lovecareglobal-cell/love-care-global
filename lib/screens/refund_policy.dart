// lib/screens/refund_policy.dart - English only, no translations.
// This file was overwritten with Privacy Policy before - this is the correct Refund Policy.
import 'package:flutter/material.dart';

class RefundPolicyPage extends StatelessWidget {
  const RefundPolicyPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCE4EC),
      appBar: AppBar(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, title: const Text('Refund Policy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _header('💜 Love Care Global - Refund Policy'),
            _card('Last Updated: 23 November 2026\nCompany: Love Care Global, Accra, Ghana\nContact: lovecareglobal@gmail.com\nThis policy explains when you get a refund and how it works.'),
            _section('1. How Payment Works'),
            _card('• You pay 20% booking fee in the app when you book a nurse.\n• You pay the remaining 80% in cash to the nurse after the work is done.\n• The 20% fee secures your booking and pays for verification, support and platform costs.'),
            _section('2. When You Get a Full Refund of the 20% Fee'),
            _card('• The nurse cancels the booking.\n• The nurse does not show up and does not contact you.\n• Love Care Global cancels the booking.\n• The nurse is found to be unverified or fake.'),
            _section('3. When You Do NOT Get a Refund'),
            _card('• You cancel after the nurse has already started work.\n• You cancel less than 2 hours before the booking time and the nurse was already travelling.\n• You refuse the nurse at the door for a reason not related to safety or identity.\n• You used the service and then ask for a refund because you changed your mind.'),
            _section('4. Partial Refund'),
            _card('• If the nurse works less than half the agreed time, the CEO team may approve a partial refund.\n• If there is a dispute, the CEO team reviews chat messages, booking time and nurse report before deciding.'),
            _section('5. How to Ask for a Refund'),
            _card('• In the app: go to your booking > Refund / Complaint, explain what happened.\n• Or email lovecareglobal@gmail.com with your booking ID, name and phone.\n• We reply within 48 hours and decide within 7 days.'),
            _section('6. How Refund Is Paid'),
            _card('• Refunds go back to the same method you paid with (Mobile Money / card via Paystack).\n• Mobile Money refunds take 1-3 working days. Card refunds take 5-10 working days.\n• The 80% cash part is between you and the nurse - Love Care does not hold it, so we cannot refund cash you already paid directly.'),
            _section('7. Nurse No-Show'),
            _card('If your nurse does not show up, report it in the app within 24 hours. Do not pay the 80% cash. We will re-assign another nurse or refund your 20% fee.'),
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

// Alias - if any other file calls RefundPolicyScreen, it still works.
class RefundPolicyScreen extends RefundPolicyPage {
  const RefundPolicyScreen({super.key});
}
