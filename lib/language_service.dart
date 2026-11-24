// lib/language_service.dart
// BRIDGE - Do NOT delete this file. main.dart imports it.
// Your translations live in main_translations.dart (MainTranslations).
// This file makes LanguageService.instance work by forwarding to MainTranslations.
import 'package:flutter/foundation.dart';
import 'main_translations.dart';

class LanguageService {
  LanguageService._();
  static final LanguageService instance = LanguageService._();

  // For AnimatedBuilder / ValueListenableBuilder in main.dart
  ValueNotifier<int> get notifier => MainTranslations.notifier;

  String get code => MainTranslations.lang;
  String get lang => MainTranslations.lang;

  List<Map<String, String>> get languages => MainTranslations.langs;

  // Called in main(): await LanguageService.instance.loadSaved();
  Future<void> loadSaved() async => MainTranslations.load();
  Future<void> load() async => MainTranslations.load();

  // Called from dropdowns: await LanguageService.instance.setLanguage(code, country);
  // country is ignored - MainTranslations only needs code.
  Future<void> setLanguage(String code, [String? country]) async {
    await MainTranslations.setLang(code);
  }

  Future<void> setLang(String code) async => MainTranslations.setLang(code);

  String t(String key) => MainTranslations.t(key);
  String get(String lang, String key) => MainTranslations.get(lang, key);
}
