import 'package:flutter/material.dart';

class RefundPolicyPage extends StatelessWidget {
  const RefundPolicyPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Refund Policy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text('1. Full Refund (100%)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('If Client cancels BEFORE Nurse accepts, full refund in 3-5 working days to same MoMo / Card. If Nurse does not show up, full refund + Nurse penalized.'),
          SizedBox(height: 16),
          Text('2. Partial Refund (80%)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('If Client cancels AFTER Nurse accepts but BEFORE Nurse arrives, 20% cancellation fee applies for Nurse transport / time.'),
          SizedBox(height: 16),
          Text('3. No Refund', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('If Nurse already arrived and started work, no refund. If Client gives false location or refuses service on arrival, no refund.'),
          SizedBox(height: 16),
          Text('4. Nurse / Client Complaint Refund', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('If service was poor, Client must report within 24 hours with photos / proof. CEO reviews within 48 hours. If approved, partial or full refund.'),
          SizedBox(height: 16),
          Text('5. How Refund Is Paid', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('Refunds go to same Mobile Money or Card used. Processing 3-7 working days.'),
        ],
      ),
    );
  }
}
