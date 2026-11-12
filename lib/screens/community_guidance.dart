import 'package:flutter/material.dart';
import 'terms-and-conditions.dart';

class CommunityGuidelinesPage extends StatelessWidget {
  const CommunityGuidelinesPage({super.key});
  @override
  Widget build(BuildContext context) {
    return _PolicyScaffold(
      title: 'Community Guidelines & Safety',
      updated: 'Love Care Global - Be Kind, Be Safe',
      sections: const [
        _Section('1. Respect', 'No insults, tribal hate, sexual harassment, or threats. Be kind to Nurses, Clients and elderly.'),
        _Section('2. No Cash Outside App', 'NEVER pay cash outside App. If Nurse asks for cash, report immediately. You lose protection if you pay outside.'),
        _Section('3. No Fake Info', 'No fake names, fake certificates, fake locations. Verified = Trusted.'),
        _Section('4. Safety', 'Meet in safe place. Share booking with family. Use SOS if you feel unsafe.'),
        _Section('5. Penalties', '1st warning → 2nd suspension 7 days → 3rd permanent ban + account deleted. CEO decision is final.'),
      ],
    );
  }
}
