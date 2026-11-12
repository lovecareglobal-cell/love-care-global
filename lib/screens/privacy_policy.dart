import 'package:flutter/material.dart';
import 'terms_and_conditions.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _PolicyScaffold(
      title: 'Privacy Policy',
      updated: 'Love Care Global - Updated 2026',
      sections: const [
        _Section('1. What We Collect', 'We collect your name, phone, location and profile details to match you with care partners and to keep the app safe. We do not sell your data.'),
        _Section('2. How We Use It', 'We use your data to show matches, process payments, send notifications, and prevent fraud. We only use what we need to run the service.'),
        _Section('3. What We Share', 'We share only what is needed with your matched partner - like first name and general area. We never share your exact address, password or payment details.'),
        _Section('4. Your Control', 'You can update, download or delete your data anytime from Settings. If you delete your account, we delete your personal data within 30 days.'),
        _Section('5. Contact Us', 'For any privacy question, contact us at support@lovecareglobal.com or from the app Help Center.'),
      ],
    );
  }
}
