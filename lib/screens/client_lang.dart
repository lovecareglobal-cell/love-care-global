// client_lang.dart - BRIDGE: connects your main_translations.dart language choice
// to ClientRegistrationTranslations, so Client Registration follows the same language
// the user picked on Home. CEO stays English (rule inside ClientRegistrationTranslations).
// Put this file in lib/screens/ next to client_registration_translations.dart
import '../main_translations.dart';
import 'client_registration_translations.dart';

String crT(String key) {
  // Client role = chosen language. CEO role would force English - Client screen is always client role.
  return ClientRegistrationTranslations.getForRole('client', MainTranslations.lang, key);
}

String crTWith(String key, Map<String, String> params) {
  return ClientRegistrationTranslations.getWith('client', MainTranslations.lang, key, params);
}
