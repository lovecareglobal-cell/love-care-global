import 'package:flutter/material.dart';
import 'language_service.dart';

class SelectLanguageScreen extends StatelessWidget {
  const SelectLanguageScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.instance;
    return Scaffold(
      appBar: AppBar(title: Text(lang.t('language')), centerTitle: true),
      body: ListenableBuilder(
        listenable: lang,
        builder: (_, __) => ListView.separated(
          itemCount: LanguageService.languages.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final l = LanguageService.languages[i];
            final selected = lang.code == l['code'];
            return ListTile(
              leading: Text(l['flag']!, style: const TextStyle(fontSize: 28)),
              title: Text(l['name']!, style: const TextStyle(fontSize: 18)),
              trailing: selected ? const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.check, color: Colors.white)) : null,
              onTap: () async {
                await lang.setLanguage(l['code']!, l['country']!);
                if (context.mounted) Navigator.pop(context);
              },
            );
          },
        ),
      ),
    );
  }
}
