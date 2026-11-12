import 'package:flutter/material.dart';

class CommunityGuidelinesPage extends StatelessWidget {
  const CommunityGuidelinesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _PolicyScaffold(
      title: 'Community Guidelines',
      sections: const [
        _Section('1. Respect', 'No insults, tribal hate, sexual harassment, or threats. Be kind to Nurses, Clients and elderly.'),
        _Section('2. No Cash Outside App', 'NEVER pay cash outside App. If Nurse asks for cash, report immediately. You lose protection if you pay outside.'),
        _Section('3. No Fake Info', 'No fake names, fake certificates, fake locations. Verified = Trusted.'),
        _Section('4. Safety', 'Meet in safe place. Share booking with family. Use SOS if you feel unsafe.'),
        _Section('5. Penalties', '1st warning -> 2nd suspension 7 days -> 3rd permanent ban + account deleted. CEO decision is final.'),
      ],
    );
  }
}

class _PolicyScaffold extends StatelessWidget {
  final String title;
  final List<_Section> sections;
  const _PolicyScaffold({required this.title, required this.sections});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sections.length,
        itemBuilder: (c, i) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sections[i].title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(sections[i].body),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section {
  final String title;
  final String body;
  const _Section(this.title, this.body);
}
