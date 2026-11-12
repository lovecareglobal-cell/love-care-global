import 'package:flutter/material.dart';
import 'terms-and-conditions.dart';

class RefundPolicyPage extends StatelessWidget {
  const RefundPolicyPage({super.key});
  @override
  Widget build(BuildContext context) {
    return _PolicyScaffold(
      title: 'Refund & Cancellation Policy',
      updated: 'Last Updated: 12 November 2026',
      sections: const [
        _Section('1. Full Refund (100%)', 'If Client cancels BEFORE Nurse accepts, full refund in 3-5 working days to same MoMo / Card. If Nurse does not show up, full refund + Nurse penalized.'),
        _Section('2. Partial Refund (80%)', 'If Client cancels AFTER Nurse accepts but BEFORE Nurse arrives, 20% cancellation fee applies for Nurse transport / time.'),
        _Section('3. No Refund', 'If Nurse already arrived and started work, no refund. If Client gives false location or refuses service on arrival, no refund.'),
        _Section('4. Nurse / Client Complaint Refund', 'If service was poor, Client must report within 24 hours with photos / proof. CEO reviews within 48 hours. If approved, partial or full refund.'),
        _Section('5. How Refund Is Paid', 'Refunds go to same Mobile Money or Card used. Processing 3-7 working days. Contact: refunds@lovecareglobal.com'),
        _Section('6. Nurse Withdrawal', 'Nurse can withdraw earnings every Monday. Minimum withdrawal GHS 50. Withdrawal fee may apply. Fraudulent earnings will be held.'),
      ],
    );
  }
}
