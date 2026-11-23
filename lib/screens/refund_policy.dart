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
            _header('💜 Love Care Global - Refund Policy\nLast Updated: 23 Nov 2026'),
            _section('1. What Can Be Refunded?'),
            _card('Only the 20% booking fee paid INSIDE the App can be refunded by Love Care Global.\nThe 80% paid directly to Nurse after work is NOT held by Love Care - if Nurse already worked, that 80% is not refundable by us.'),
            _section('2. Nurse Did Not Show Up - Full 20% Refund'),
            _card('If Nurse does not show up and does not inform you, report within 24 hours. CEO will verify. If confirmed, you get 100% of your 20% booking fee back.'),
            _section('3. Client Cancels Early - Partial Refund'),
            _card('If you cancel more than 24 hours before start time, you get 50% of your 20% booking fee back.\nIf you cancel less than 24 hours before start, no refund - Nurse already reserved that time.'),
            _section('4. Nurse Cancels - Full 20% Refund'),
            _card('If Nurse cancels before work starts, you get 100% of your 20% booking fee back.'),
            _section('5. How To Request Refund'),
            _card('Go to: My Bookings > Refund Query, OR Settings > Refund Query.\nProvide booking ID, reason, and proof (chat screenshot). CEO reviews within 3 working days. Approved refunds are paid to your original payment method within 3-5 working days.'),
            _section('6. Nurse Earnings - NO Withdrawal'),
            _card('Nurse receives 80% directly from Client AFTER work is finished (cash or MoMo). Love Care Global does NOT hold Nurse earnings, so there is NO withdrawal, NO Monday payout, NO minimum balance. If Client refuses to pay 80% after work, Nurse should report immediately with proof for CEO action.'),
            _section('7. No Refund Cases'),
            _card('• Work already completed and Client is satisfied\n• Client gave wrong address / phone and Nurse could not find them\n• Fake complaint to get refund - account may be penalised'),
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
