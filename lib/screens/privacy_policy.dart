import 'package:flutter/material.dart';
import 'community_guidance.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text('1. What We Collect', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('We collect your name, phone, location and profile details to match you with care partners and to keep the app safe. We do not sell your data.'),
          SizedBox(height: 16),
          Text('2. How We Use It', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('We use your data to show matches, process payments, send notifications, and prevent fraud. We only use what we need to run the service.'),
          SizedBox(height: 16),
          Text('3. What We Share', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('We share only what is needed with your matched partner - like first name and general area. We never share your exact address, password or payment details.'),
          SizedBox(height: 16),
          Text('4. Your Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('You can update, download or delete your data anytime from Settings. If you delete your account, we delete your personal data within 30 days.'),
          SizedBox(height: 16),
          Text('5. Contact Us', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('For any privacy question, contact us at support@lovecareglobal.com or from the app Help Center.'),
        ],
      ),
    );
  }
}
