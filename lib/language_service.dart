import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LanguageService extends ChangeNotifier {
  // GLOBAL SINGLETON - One for whole app, Client + Nurse same
  static final LanguageService instance = LanguageService._internal();
  LanguageService._internal();
  factory LanguageService() => instance;

  Locale _locale = const Locale('en', 'US');
  Locale get locale => _locale;
  String get code => _locale.languageCode;

  // Helper: use anywhere - lang.t('book_nurse')
  String t(String key) {
    return _translations[code]?[key] ?? _translations['en']![key] ?? key;
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

  // Load when app starts - from phone + from Firestore (so e follow user to new phone)
  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    String code = prefs.getString('app_lang_code') ?? 'en';
    String country = prefs.getString('app_lang_country') ?? 'US';

    // If user logged in, check Firestore users / nurses - Client OR Nurse
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

  // Called when Client OR Nurse picks language - updates EVERYTHING
  Future<void> setLanguage(String code, String country) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_lang_code', code);
    await prefs.setString('app_lang_country', country);
    _locale = Locale(code, country);
    notifyListeners(); // <-- This na what makes ALL pages change instantly

    // Save to Firestore so e follow user - try users, clients, nurses
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        for (final col in ['users', 'clients', 'nurses']) {
          try {
            final doc = await FirebaseFirestore.instance.collection(col).doc(user.uid).get();
            if (doc.exists) {
              await doc.reference.update({'appLanguage': code});
              break;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // TRANSLATIONS - Add all app texts here, then use lang.t('key') everywhere
  static const Map<String, Map<String, String>> _translations = {
    'en': {'welcome': 'Welcome to LoveCare', 'book_nurse': 'Book Nurse', 'client_name': 'CLIENT NAME', 'patient_name': 'PATIENT NAME', 'same_location': 'Same location as Client', 'pay_now': 'Pay 20% Now', 'home': 'Home', 'profile': 'Profile', 'settings': 'Settings', 'language': 'Language', 'nurse_dashboard': 'Nurse Dashboard'},
    'tw': {'welcome': 'Akwaaba wo LoveCare', 'book_nurse': 'Frɛ Nɛɛse', 'client_name': 'WO DIN', 'patient_name': 'YARƐNI DIN', 'same_location': 'Ɛyɛ beae koro no ara sɛ Client no', 'pay_now': 'Tua 20% Seisei', 'home': 'Fie', 'profile': 'Wo Ho', 'settings': 'Nsiesiei', 'language': 'Kasa', 'nurse_dashboard': 'Nɛɛse Adwuma'},
    'fr': {'welcome': 'Bienvenue à LoveCare', 'book_nurse': 'Réserver une Infirmière', 'client_name': 'NOM DU CLIENT', 'patient_name': 'NOM DU PATIENT', 'same_location': 'Même lieu que le Client', 'pay_now': 'Payer 20% Maintenant', 'home': 'Accueil', 'profile': 'Profil', 'settings': 'Paramètres', 'language': 'Langue', 'nurse_dashboard': 'Tableau Infirmière'},
    'ar': {'welcome': 'مرحباً بك في لوف كير', 'book_nurse': 'احجز ممرضة', 'client_name': 'اسم العميل', 'patient_name': 'اسم المريض', 'same_location': 'نفس موقع العميل', 'pay_now': 'ادفع 20% الآن', 'home': 'الرئيسية', 'profile': 'الملف', 'settings': 'الإعدادات', 'language': 'اللغة', 'nurse_dashboard': 'لوحة الممرضة'},
    'es': {'welcome': 'Bienvenido a LoveCare', 'book_nurse': 'Reservar Enfermera', 'client_name': 'NOMBRE DEL CLIENTE', 'patient_name': 'NOMBRE DEL PACIENTE', 'same_location': 'Misma ubicación que el Cliente', 'pay_now': 'Pagar 20% Ahora', 'home': 'Inicio', 'profile': 'Perfil', 'settings': 'Ajustes', 'language': 'Idioma', 'nurse_dashboard': 'Panel Enfermera'},
    'pt': {'welcome': 'Bem-vindo ao LoveCare', 'book_nurse': 'Reservar Enfermeira', 'client_name': 'NOME DO CLIENTE', 'patient_name': 'NOME DO PACIENTE', 'same_location': 'Mesma localização que o Cliente', 'pay_now': 'Pagar 20% Agora', 'home': 'Início', 'profile': 'Perfil', 'settings': 'Configurações', 'language': 'Idioma', 'nurse_dashboard': 'Painel Enfermeira'},
    'de': {'welcome': 'Willkommen bei LoveCare', 'book_nurse': 'Krankenschwester buchen', 'client_name': 'NAME DES KUNDEN', 'patient_name': 'NAME DES PATIENTEN', 'same_location': 'Gleicher Ort wie Kunde', 'pay_now': 'Jetzt 20% bezahlen', 'home': 'Start', 'profile': 'Profil', 'settings': 'Einstellungen', 'language': 'Sprache', 'nurse_dashboard': 'Schwester Dashboard'},
    'it': {'welcome': 'Benvenuto in LoveCare', 'book_nurse': 'Prenota Infermiera', 'client_name': 'NOME DEL CLIENTE', 'patient_name': 'NOME DEL PAZIENTE', 'same_location': 'Stessa posizione del Cliente', 'pay_now': 'Paga 20% Ora', 'home': 'Home', 'profile': 'Profilo', 'settings': 'Impostazioni', 'language': 'Lingua', 'nurse_dashboard': 'Dashboard Infermiera'},
    'zh': {'welcome': '欢迎来到 LoveCare', 'book_nurse': '预约护士', 'client_name': '客户姓名', 'patient_name': '患者姓名', 'same_location': '与客户相同位置', 'pay_now': '现在支付 20%', 'home': '首页', 'profile': '个人', 'settings': '设置', 'language': '语言', 'nurse_dashboard': '护士面板'},
    'hi': {'welcome': 'LoveCare में आपका स्वागत है', 'book_nurse': 'नर्स बुक करें', 'client_name': 'ग्राहक का नाम', 'patient_name': 'मरीज़ का नाम', 'same_location': 'ग्राहक के समान स्थान', 'pay_now': 'अभी 20% भुगतान करें', 'home': 'होम', 'profile': 'प्रोफ़ाइल', 'settings': 'सेटिंग्स', 'language': 'भाषा', 'nurse_dashboard': 'नर्स डैशबोर्ड'},
    'sw': {'welcome': 'Karibu LoveCare', 'book_nurse': 'Weka Muuguzi', 'client_name': 'JINA LA MTEJA', 'patient_name': 'JINA LA MGONJWA', 'same_location': 'Mahali sawa na Mteja', 'pay_now': 'Lipa 20% Sasa', 'home': 'Nyumbani', 'profile': 'Wasifu', 'settings': 'Mipangilio', 'language': 'Lugha', 'nurse_dashboard': 'Dashibodi ya Muuguzi'},
    'yo': {'welcome': 'Kaabo si LoveCare', 'book_nurse': 'Beere Nọọsi', 'client_name': 'ORUKO ONIBARA', 'patient_name': 'ORUKO ALAISAN', 'same_location': 'Ibi kanna pẹlu Onibara', 'pay_now': 'San 20% Bayi', 'home': 'Ile', 'profile': 'Profaili', 'settings': 'Eto', 'language': 'Ede', 'nurse_dashboard': 'Dasibodu Nọọsi'},
    'ig': {'welcome': 'Nnọọ na LoveCare', 'book_nurse': 'Dee Nọọsụ', 'client_name': 'AHA ONYE AHỊA', 'patient_name': 'AHA ONYE ỌRỊA', 'same_location': 'Otu ebe dị ka Onye Ahịa', 'pay_now': 'Kwụọ 20% Ugbu a', 'home': 'Ụlọ', 'profile': 'Profaịlụ', 'settings': 'Ntọala', 'language': 'Asụsụ', 'nurse_dashboard': 'Dashboard Nọọsụ'},
    'ha': {'welcome': 'Barka da zuwa LoveCare', 'book_nurse': 'Yi Rajistar Nurse', 'client_name': 'SUNAN ABOKIN HULDA', 'patient_name': 'SUNAN MARA LAFIYA', 'same_location': 'Wuri ɗaya da Abokin Hulɗa', 'pay_now': 'Biya 20% Yanzu', 'home': 'Gida', 'profile': 'Bayani', 'settings': 'Saituna', 'language': 'Harshe', 'nurse_dashboard': 'Dashboard Nurse'},
    'am': {'welcome': 'እንኳን ወደ LoveCare በደህና መጡ', 'book_nurse': 'ነርስ ይዘዙ', 'client_name': 'የደንበኛ ስም', 'patient_name': 'የታካሚ ስም', 'same_location': 'እንደ ደንበኛ ተመሳሳይ ቦታ', 'pay_now': 'አሁን 20% ይክፈሉ', 'home': 'መነሻ', 'profile': 'መገለጫ', 'settings': 'ቅንብሮች', 'language': 'ቋንቋ', 'nurse_dashboard': 'የነርስ ዳሽቦርድ'},
    'so': {'welcome': 'Ku soo dhawoow LoveCare', 'book_nurse': 'Ballanso Kalkaaliye', 'client_name': 'MAGACA MACMIILKA', 'patient_name': 'MAGACA BUKAANKA', 'same_location': 'Isla goobta Macmiilka', 'pay_now': 'Bixi 20% Hadda', 'home': 'Guriga', 'profile': 'Profile', 'settings': 'Dejinta', 'language': 'Luqadda', 'nurse_dashboard': 'Dashboard Kalkaaliye'},
    'tr': {'welcome': 'LoveCare\'e Hoş Geldiniz', 'book_nurse': 'Hemşire Ayırt', 'client_name': 'MÜŞTERİ ADI', 'patient_name': 'HASTA ADI', 'same_location': 'Müşteri ile Aynı Konum', 'pay_now': 'Şimdi %20 Öde', 'home': 'Anasayfa', 'profile': 'Profil', 'settings': 'Ayarlar', 'language': 'Dil', 'nurse_dashboard': 'Hemşire Paneli'},
    'nl': {'welcome': 'Welkom bij LoveCare', 'book_nurse': 'Verpleegkundige Boeken', 'client_name': 'NAAM KLANT', 'patient_name': 'NAAM PATIËNT', 'same_location': 'Zelfde locatie als Klant', 'pay_now': 'Betaal Nu 20%', 'home': 'Home', 'profile': 'Profiel', 'settings': 'Instellingen', 'language': 'Taal', 'nurse_dashboard': 'Verpleegkundige Dashboard'},
    'ru': {'welcome': 'Добро пожаловать в LoveCare', 'book_nurse': 'Забронировать Медсестру', 'client_name': 'ИМЯ КЛИЕНТА', 'patient_name': 'ИМЯ ПАЦИЕНТА', 'same_location': 'То же место, что и у Клиента', 'pay_now': 'Оплатить 20% Сейчас', 'home': 'Главная', 'profile': 'Профиль', 'settings': 'Настройки', 'language': 'Язык', 'nurse_dashboard': 'Панель Медсестры'},
    'ko': {'welcome': 'LoveCare에 오신 것을 환영합니다', 'book_nurse': '간호사 예약', 'client_name': '고객 이름', 'patient_name': '환자 이름', 'same_location': '고객과 동일한 위치', 'pay_now': '지금 20% 결제', 'home': '홈', 'profile': '프로필', 'settings': '설정', 'language': '언어', 'nurse_dashboard': '간호사 대시보드'},
    'ja': {'welcome': 'LoveCareへようこそ', 'book_nurse': '看護師を予約', 'client_name': 'クライアント名', 'patient_name': '患者名', 'same_location': 'クライアントと同じ場所', 'pay_now': '今20%支払う', 'home': 'ホーム', 'profile': 'プロフィール', 'settings': '設定', 'language': '言語', 'nurse_dashboard': '看護師ダッシュボード'},
  };
}
