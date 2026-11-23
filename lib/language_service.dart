import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LanguageService extends ChangeNotifier {
  static final LanguageService instance = LanguageService._internal();
  LanguageService._internal();
  factory LanguageService() => instance;

  Locale _locale = const Locale('en', 'US');
  Locale get locale => _locale;
  String get code => _locale.languageCode;

  // OLD way still works: t('book_nurse')
  String t(String key) => _translations[code]?[key] ?? _translations['en']![key] ?? key;

  // NEW way - use this everywhere, NO keys needed:
  // lang.tr('Book Nurse') -> in Twi gives 'Frɛ Nɛɛse', in French gives 'Réserver une Infirmière'
  // If we don't have translation yet, it just shows the English you wrote - app never breaks.
  String tr(String english) {
    if (code == 'en') return english;
    final map = _byEnglish[code];
    if (map == null) return english;
    return map[english] ?? map[english.trim()] ?? english;
  }

  static const List<Map<String, String>> languages = [
    {'code': 'en', 'country': 'US', 'name': 'English - US', 'flag': '🇺🇸'},
    {'code': 'tw', 'country': 'GH', 'name': 'Twi', 'flag': '🇬🇭'},
    {'code': 'fr', 'country': 'FR', 'name': 'Français', 'flag': '🇫🇷'},
    {'code': 'ar', 'country': 'SA', 'name': 'العربية', 'flag': '🇸🇦'},
    {'code': 'es', 'country': 'ES', 'name': 'Español', 'flag': '🇪🇸'},
    {'code': 'pt', 'country': 'PT', 'name': 'Português', 'flag': '🇵🇹'},
    {'code': 'de', 'country': 'DE', 'name': 'Deutsch', 'flag': '🇩🇪'},
    {'code': 'it', 'country': 'IT', 'name': 'Italiano', 'flag': '🇮🇹'},
    {'code': 'zh', 'country': 'CN', 'name': '中文', 'flag': '🇨🇳'},
    {'code': 'hi', 'country': 'IN', 'name': 'हिन्दी', 'flag': '🇮🇳'},
    {'code': 'sw', 'country': 'TZ', 'name': 'Kiswahili', 'flag': '🇹🇿'},
    {'code': 'yo', 'country': 'NG', 'name': 'Yorùbá', 'flag': '🇳🇬'},
    {'code': 'ig', 'country': 'NG', 'name': 'Igbo', 'flag': '🇳🇬'},
    {'code': 'ha', 'country': 'NG', 'name': 'Hausa', 'flag': '🇳🇬'},
    {'code': 'am', 'country': 'ET', 'name': 'አማርኛ', 'flag': '🇪🇹'},
    {'code': 'so', 'country': 'SO', 'name': 'Soomaali', 'flag': '🇸🇴'},
    {'code': 'tr', 'country': 'TR', 'name': 'Türkçe', 'flag': '🇹🇷'},
    {'code': 'nl', 'country': 'NL', 'name': 'Nederlands', 'flag': '🇳🇱'},
    {'code': 'ru', 'country': 'RU', 'name': 'Русский', 'flag': '🇷🇺'},
    {'code': 'ko', 'country': 'KR', 'name': '한국어', 'flag': '🇰🇷'},
    {'code': 'ja', 'country': 'JP', 'name': '日本語', 'flag': '🇯🇵'},
  ];

  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    String code = prefs.getString('app_lang_code') ?? 'en';
    String country = prefs.getString('app_lang_country') ?? 'US';
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        for (final col in ['users', 'clients', 'nurses']) {
          try {
            final doc = await FirebaseFirestore.instance.collection(col).doc(user.uid).get();
            if (doc.exists && doc.data()!['appLanguage'] != null) {
              code = doc.data()!['appLanguage'].toString();
              country = languages.firstWhere((l) => l['code'] == code, orElse: () => languages[0])['country']!;
              break;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    _locale = Locale(code, country);
    notifyListeners();
  }

  Future<void> setLanguage(String code, String country) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_lang_code', code);
    await prefs.setString('app_lang_country', country);
    _locale = Locale(code, country);
    notifyListeners();
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        for (final col in ['users', 'clients', 'nurses']) {
          try {
            final doc = await FirebaseFirestore.instance.collection(col).doc(user.uid).get();
            if (doc.exists) { await doc.reference.update({'appLanguage': code}); break; }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // Keep your old key-based map for the few places that already use t()
  static const Map<String, Map<String, String>> _translations = {
    'en': {'welcome': 'Welcome to LoveCare', 'book_nurse': 'Book Nurse', 'client_name': 'CLIENT NAME', 'patient_name': 'PATIENT NAME', 'same_location': 'Same location as Client', 'pay_now': 'Pay 20% Now', 'home': 'Home', 'profile': 'Profile', 'settings': 'Settings', 'language': 'Language', 'nurse_dashboard': 'Nurse Dashboard'},
    'tw': {'welcome': 'Akwaaba wo LoveCare', 'book_nurse': 'Frɛ Nɛɛse', 'client_name': 'WO DIN', 'patient_name': 'YARƐNI DIN', 'same_location': 'Ɛyɛ beae koro no ara sɛ Client no', 'pay_now': 'Tua 20% Seisei', 'home': 'Fie', 'profile': 'Wo Ho', 'settings': 'Nsiesiei', 'language': 'Kasa', 'nurse_dashboard': 'Nɛɛse Adwuma'},
    'fr': {'welcome': 'Bienvenue à LoveCare', 'book_nurse': 'Réserver une Infirmière', 'client_name': 'NOM DU CLIENT', 'patient_name': 'NOM DU PATIENT', 'same_location': 'Même lieu que le Client', 'pay_now': 'Payer 20% Maintenant', 'home': 'Accueil', 'profile': 'Profil', 'settings': 'Paramètres', 'language': 'Langue', 'nurse_dashboard': 'Tableau Infirmière'},
  };

  // NEW: English text -> translation. ADD MORE ROWS HERE as you find untranslated words.
  // Format: 'Exact English in your app': 'Translation'
  // Tip: copy a phrase from your app, paste it here as key, add translation.
  static const Map<String, Map<String, String>> _byEnglish = {
    'tw': {
      'Welcome to LoveCare': 'Akwaaba wo LoveCare',
      'Book Nurse': 'Frɛ Nɛɛse',
      'Home': 'Fie',
      'Profile': 'Wo Ho',
      'Settings': 'Nsiesiei',
      'Language': 'Kasa',
      'Login': 'Kɔ mu',
      'Register': 'Kyerɛw wo din',
      'Logout': 'Fi mu',
      'Dashboard': 'Adwuma',
      'Bookings': 'Nhyiamu',
      'My Bookings': 'Me Nhyiamu',
      'Nurse Dashboard': 'Nɛɛse Adwuma',
      'Client Dashboard': 'Client Adwuma',
      'Pay 20% Now': 'Tua 20% Seisei',
      'Pay Now': 'Tua Seisei',
      'Cancel': 'Gyae',
      'Confirm': 'Gye to mu',
      'Save': 'Kora',
      'Edit': 'Sesa',
      'Delete': 'Pepa',
      'Search': 'Hwehwɛ',
      'Notifications': 'Nkrasɛm',
      'Chat': 'Nkɔmmɔ',
      'Complaint': 'Antobo',
      'Rating': 'Nkyerɛmu',
      'SOS': 'Mmoa!',
      'Help': 'Mmoa',
      'Back': 'San kɔ',
      'Next': 'Di kan',
      'Continue': 'Toa so',
      'Submit': 'Fa kɔ',
      'Loading...': 'Ɛreyɛ adwuma...',
      'No bookings yet': 'Nhyiamu biara nni hɔ',
      'Welcome': 'Akwaaba',
      'Email': 'Email',
      'Password': 'Password',
      'Phone': 'Telefon',
      'Name': 'Din',
      'Address': 'Beae',
      'Price': 'Bo',
      'Total': 'Ne nyinaa',
      'Status': 'Tebea',
      'Approved': 'Wɔagye atom',
      'Pending': 'Ɛretwɛn',
      'Rejected': 'Wɔapo',
    },
    'fr': {
      'Welcome to LoveCare': 'Bienvenue à LoveCare',
      'Book Nurse': 'Réserver une Infirmière',
      'Home': 'Accueil',
      'Profile': 'Profil',
      'Settings': 'Paramètres',
      'Language': 'Langue',
      'Login': 'Connexion',
      'Register': 'Inscription',
      'Logout': 'Déconnexion',
      'Dashboard': 'Tableau de bord',
      'Bookings': 'Réservations',
      'My Bookings': 'Mes Réservations',
      'Nurse Dashboard': 'Tableau Infirmière',
      'Client Dashboard': 'Tableau Client',
      'Pay 20% Now': 'Payer 20% Maintenant',
      'Pay Now': 'Payer Maintenant',
      'Cancel': 'Annuler',
      'Confirm': 'Confirmer',
      'Save': 'Enregistrer',
      'Edit': 'Modifier',
      'Delete': 'Supprimer',
      'Search': 'Rechercher',
      'Notifications': 'Notifications',
      'Chat': 'Discussion',
      'Complaint': 'Plainte',
      'Rating': 'Évaluation',
      'SOS': 'SOS',
      'Help': 'Aide',
      'Back': 'Retour',
      'Next': 'Suivant',
      'Continue': 'Continuer',
      'Submit': 'Envoyer',
      'Loading...': 'Chargement...',
      'No bookings yet': 'Aucune réservation',
      'Welcome': 'Bienvenue',
      'Email': 'Email',
      'Password': 'Mot de passe',
      'Phone': 'Téléphone',
      'Name': 'Nom',
      'Address': 'Adresse',
      'Price': 'Prix',
      'Total': 'Total',
      'Status': 'Statut',
      'Approved': 'Approuvé',
      'Pending': 'En attente',
      'Rejected': 'Rejeté',
    },
    'yo': {
      'Welcome to LoveCare': 'Kaabo si LoveCare',
      'Book Nurse': 'Beere Nọọsi',
      'Home': 'Ile',
      'Profile': 'Profaili',
      'Settings': 'Eto',
      'Language': 'Ede',
      'Login': 'Wọle',
      'Register': 'Forukọsilẹ',
      'Logout': 'Jade',
      'Dashboard': 'Dasibodu',
      'Bookings': 'Awọn ifiṣura',
      'Pay Now': 'San Bayi',
      'Cancel': 'Fagilee',
      'Confirm': 'Jẹrisi',
      'Save': 'Fi pamọ',
      'Search': 'Wa',
      'Chat': 'Ibaraẹnisọrọ',
    },
    'ha': {
      'Welcome to LoveCare': 'Barka da zuwa LoveCare',
      'Book Nurse': 'Yi Rajistar Nurse',
      'Home': 'Gida',
      'Profile': 'Bayani',
      'Settings': 'Saituna',
      'Language': 'Harshe',
      'Login': 'Shiga',
      'Register': 'Yi Rajista',
      'Logout': 'Fita',
      'Dashboard': 'Dashboard',
      'Bookings': 'Rajista',
      'Pay Now': 'Biya Yanzu',
      'Cancel': 'Soke',
      'Confirm': 'Tabbatar',
      'Save': 'Ajiye',
      'Search': 'Bincika',
    },
    'ig': {
      'Welcome to LoveCare': 'Nnọọ na LoveCare',
      'Book Nurse': 'Dee Nọọsụ',
      'Home': 'Ụlọ',
      'Profile': 'Profaịlụ',
      'Settings': 'Ntọala',
      'Language': 'Asụsụ',
      'Login': 'Banye',
      'Register': 'Debanye aha',
      'Logout': 'Pụọ',
      'Dashboard': 'Dashboard',
      'Pay Now': 'Kwụọ Ugbu a',
      'Cancel': 'Kagbuo',
      'Confirm': 'Kwenye',
      'Save': 'Chekwa',
      'Search': 'Chọọ',
    },
  };
}
