// lib/select_language_screen.dart
// Language picker screen. Uses your main_translations.dart.
// Has a const constructor so `const SelectLanguageScreen()` in main.dart compiles.
import 'package:flutter/material.dart';
import 'main_translations.dart';

class SelectLanguageScreen extends StatelessWidget {
  const SelectLanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final current = MainTranslations.lang;
    return Scaffold(
      appBar: AppBar(title: Text(MainTranslations.t('appTitle'))),
      body: ListView.builder(
        itemCount: MainTranslations.langs.length,
        itemBuilder: (context, i) {
          final e = MainTranslations.langs[i];
          final code = e['code']!;
          final name = e['name']!;
          final selected = code == current;
          return ListTile(
            title: Text(name),
            subtitle: Text(code),
            trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
            selected: selected,
            onTap: () async {
              await MainTranslations.setLang(code);
              if (context.mounted) Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}
