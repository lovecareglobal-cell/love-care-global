import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class NurseRegistrationPage extends StatefulWidget {
  const NurseRegistrationPage({super.key});
  @override
  State<NurseRegistrationPage> createState() => _NurseRegistrationPageState();
}

class _NurseRegistrationPageState extends State<NurseRegistrationPage> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  // ---- COUNTRY CODE (WORLD) ----
  // Full world list. Value is "Name|+code" so countries sharing a code
  // (e.g. USA +1 / Canada +1) stay unique in the dropdown.
  // "Other" lets anyone whose country is not listed type their own code.
  static const List<Map<String, String>> _countries = [
    {"name": "Afghanistan", "code": "+93"},
    {"name": "Albania", "code": "+355"},
    {"name": "Algeria", "code": "+213"},
    {"name": "Andorra", "code": "+376"},
    {"name": "Angola", "code": "+244"},
    {"name": "Antigua and Barbuda", "code": "+1268"},
    {"name": "Argentina", "code": "+54"},
    {"name": "Armenia", "code": "+374"},
    {"name": "Australia", "code": "+61"},
    {"name": "Austria", "code": "+43"},
    {"name": "Azerbaijan", "code": "+994"},
    {"name": "Bahamas", "code": "+1242"},
    {"name": "Bahrain", "code": "+973"},
    {"name": "Bangladesh", "code": "+880"},
    {"name": "Barbados", "code": "+1246"},
    {"name": "Belarus", "code": "+375"},
    {"name": "Belgium", "code": "+32"},
    {"name": "Belize", "code": "+501"},
    {"name": "Benin", "code": "+229"},
    {"name": "Bhutan", "code": "+975"},
    {"name": "Bolivia", "code": "+591"},
    {"name": "Bosnia and Herzegovina", "code": "+387"},
    {"name": "Botswana", "code": "+267"},
    {"name": "Brazil", "code": "+55"},
    {"name": "Brunei", "code": "+673"},
    {"name": "Bulgaria", "code": "+359"},
    {"name": "Burkina Faso", "code": "+226"},
    {"name": "Burundi", "code": "+257"},
    {"name": "Cambodia", "code": "+855"},
    {"name": "Cameroon", "code": "+237"},
    {"name": "Canada", "code": "+1"},
    {"name": "Cape Verde", "code": "+238"},
    {"name": "Central African Republic", "code": "+236"},
    {"name": "Chad", "code": "+235"},
    {"name": "Chile", "code": "+56"},
    {"name": "China", "code": "+86"},
    {"name": "Colombia", "code": "+57"},
    {"name": "Comoros", "code": "+269"},
    {"name": "Congo", "code": "+242"},
    {"name": "Congo (DRC)", "code": "+243"},
    {"name": "Costa Rica", "code": "+506"},
    {"name": "Côte d'Ivoire", "code": "+225"},
    {"name": "Croatia", "code": "+385"},
    {"name": "Cuba", "code": "+53"},
    {"name": "Cyprus", "code": "+357"},
    {"name": "Czechia", "code": "+420"},
    {"name": "Denmark", "code": "+45"},
    {"name": "Djibouti", "code": "+253"},
    {"name": "Dominica", "code": "+1767"},
    {"name": "Dominican Republic", "code": "+1809"},
    {"name": "Ecuador", "code": "+593"},
    {"name": "Egypt", "code": "+20"},
    {"name": "El Salvador", "code": "+503"},
    {"name": "Equatorial Guinea", "code": "+240"},
    {"name": "Eritrea", "code": "+291"},
    {"name": "Estonia", "code": "+372"},
    {"name": "Eswatini", "code": "+268"},
    {"name": "Ethiopia", "code": "+251"},
    {"name": "Fiji", "code": "+679"},
    {"name": "Finland", "code": "+358"},
    {"name": "France", "code": "+33"},
    {"name": "Gabon", "code": "+241"},
    {"name": "Gambia", "code": "+220"},
    {"name": "Georgia", "code": "+995"},
    {"name": "Germany", "code": "+49"},
    {"name": "Ghana", "code": "+233"},
    {"name": "Greece", "code": "+30"},
    {"name": "Grenada", "code": "+1473"},
    {"name": "Guatemala", "code": "+502"},
    {"name": "Guinea", "code": "+224"},
    {"name": "Guinea-Bissau", "code": "+245"},
    {"name": "Guyana", "code": "+592"},
    {"name": "Haiti", "code": "+509"},
    {"name": "Honduras", "code": "+504"},
    {"name": "Hungary", "code": "+36"},
    {"name": "Iceland", "code": "+354"},
    {"name": "India", "code": "+91"},
    {"name": "Indonesia", "code": "+62"},
    {"name": "Iran", "code": "+98"},
    {"name": "Iraq", "code": "+964"},
    {"name": "Ireland", "code": "+353"},
    {"name": "Israel", "code": "+972"},
    {"name": "Italy", "code": "+39"},
    {"name": "Jamaica", "code": "+1876"},
    {"name": "Japan", "code": "+81"},
    {"name": "Jordan", "code": "+962"},
    {"name": "Kazakhstan", "code": "+7"},
    {"name": "Kenya", "code": "+254"},
    {"name": "Kiribati", "code": "+686"},
    {"name": "Kuwait", "code": "+965"},
    {"name": "Kyrgyzstan", "code": "+996"},
    {"name": "Laos", "code": "+856"},
    {"name": "Latvia", "code": "+371"},
    {"name": "Lebanon", "code": "+961"},
    {"name": "Lesotho", "code": "+266"},
    {"name": "Liberia", "code": "+231"},
    {"name": "Libya", "code": "+218"},
    {"name": "Liechtenstein", "code": "+423"},
    {"name": "Lithuania", "code": "+370"},
    {"name": "Luxembourg", "code": "+352"},
    {"name": "Madagascar", "code": "+261"},
    {"name": "Malawi", "code": "+265"},
    {"name": "Malaysia", "code": "+60"},
    {"name": "Maldives", "code": "+960"},
    {"name": "Mali", "code": "+223"},
    {"name": "Malta", "code": "+356"},
    {"name": "Marshall Islands", "code": "+692"},
    {"name": "Mauritania", "code": "+222"},
    {"name": "Mauritius", "code": "+230"},
    {"name": "Mexico", "code": "+52"},
    {"name": "Micronesia", "code": "+691"},
    {"name": "Moldova", "code": "+373"},
    {"name": "Monaco", "code": "+377"},
    {"name": "Mongolia", "code": "+976"},
    {"name": "Montenegro", "code": "+382"},
    {"name": "Morocco", "code": "+212"},
    {"name": "Mozambique", "code": "+258"},
    {"name": "Myanmar", "code": "+95"},
    {"name": "Namibia", "code": "+264"},
    {"name": "Nauru", "code": "+674"},
    {"name": "Nepal", "code": "+977"},
    {"name": "Netherlands", "code": "+31"},
    {"name": "New Zealand", "code": "+64"},
    {"name": "Nicaragua", "code": "+505"},
    {"name": "Niger", "code": "+227"},
    {"name": "Nigeria", "code": "+234"},
    {"name": "North Korea", "code": "+850"},
    {"name": "North Macedonia", "code": "+389"},
    {"name": "Norway", "code": "+47"},
    {"name": "Oman", "code": "+968"},
    {"name": "Pakistan", "code": "+92"},
    {"name": "Palau", "code": "+680"},
    {"name": "Palestine", "code": "+970"},
    {"name": "Panama", "code": "+507"},
    {"name": "Papua New Guinea", "code": "+675"},
    {"name": "Paraguay", "code": "+595"},
    {"name": "Peru", "code": "+51"},
    {"name": "Philippines", "code": "+63"},
    {"name": "Poland", "code": "+48"},
    {"name": "Portugal", "code": "+351"},
    {"name": "Qatar", "code": "+974"},
    {"name": "Romania", "code": "+40"},
    {"name": "Russia", "code": "+7"},
    {"name": "Rwanda", "code": "+250"},
    {"name": "Saint Kitts and Nevis", "code": "+1869"},
    {"name": "Saint Lucia", "code": "+1758"},
    {"name": "Saint Vincent", "code": "+1784"},
    {"name": "Samoa", "code": "+685"},
    {"name": "San Marino", "code": "+378"},
    {"name": "Sao Tome and Principe", "code": "+239"},
    {"name": "Saudi Arabia", "code": "+966"},
    {"name": "Senegal", "code": "+221"},
    {"name": "Serbia", "code": "+381"},
    {"name": "Seychelles", "code": "+248"},
    {"name": "Sierra Leone", "code": "+232"},
    {"name": "Singapore", "code": "+65"},
    {"name": "Slovakia", "code": "+421"},
    {"name": "Slovenia", "code": "+386"},
    {"name": "Solomon Islands", "code": "+677"},
    {"name": "Somalia", "code": "+252"},
    {"name": "South Africa", "code": "+27"},
    {"name": "South Korea", "code": "+82"},
    {"name": "South Sudan", "code": "+211"},
    {"name": "Spain", "code": "+34"},
    {"name": "Sri Lanka", "code": "+94"},
    {"name": "Sudan", "code": "+249"},
    {"name": "Suriname", "code": "+597"},
    {"name": "Sweden", "code": "+46"},
    {"name": "Switzerland", "code": "+41"},
    {"name": "Syria", "code": "+963"},
    {"name": "Taiwan", "code": "+886"},
    {"name": "Tajikistan", "code": "+992"},
    {"name": "Tanzania", "code": "+255"},
    {"name": "Thailand", "code": "+66"},
    {"name": "Togo", "code": "+228"},
    {"name": "Tonga", "code": "+676"},
    {"name": "Trinidad and Tobago", "code": "+1868"},
    {"name": "Tunisia", "code": "+216"},
    {"name": "Turkey", "code": "+90"},
    {"name": "Turkmenistan", "code": "+993"},
    {"name": "Tuvalu", "code": "+688"},
    {"name": "Uganda", "code": "+256"},
    {"name": "Ukraine", "code": "+380"},
    {"name": "United Arab Emirates", "code": "+971"},
    {"name": "United Kingdom", "code": "+44"},
    {"name": "United States", "code": "+1"},
    {"name": "Uruguay", "code": "+598"},
    {"name": "Uzbekistan", "code": "+998"},
    {"name": "Vanuatu", "code": "+678"},
    {"name": "Vatican City", "code": "+379"},
    {"name": "Venezuela", "code": "+58"},
    {"name": "Vietnam", "code": "+84"},
    {"name": "Yemen", "code": "+967"},
    {"name": "Zambia", "code": "+260"},
    {"name": "Zimbabwe", "code": "+263"},
  ];
  String _selectedCountry = 'Ghana|+233'; // default: Ghana
  final _otherCode = TextEditingController(); // only used when "Other" is picked
  bool get _isOtherCountry => _selectedCountry == 'Other|';
  String get _selectedCountryName => _isOtherCountry ? 'Other' : _selectedCountry.split('|')[0];
  String get _selectedDialCode {
    if (_isOtherCountry) {
      var c = _otherCode.text.trim();
      if (!c.startsWith('+')) c = '+$c';
      return c;
    }
    return _selectedCountry.split('|')[1];
  }
  // Full international number: selected code + local number (leading 0 removed).
  // If the user already typed a full +... number, use it as-is (no double code).
  String get _fullPhone {
    var local = _phone.text.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (local.startsWith('+')) return local;
    if (local.startsWith('00')) return '+${local.substring(2)}';
    if (local.startsWith('0')) local = local.substring(1);
    return '$_selectedDialCode'.replaceAll(' ', '') + local;
  }
  final _pass = TextEditingController();
  XFile? _photo;
  XFile? _video;
  XFile? _cv;
  XFile? _pinDoc;
  XFile? _idFront;
  XFile? _idBack;
  XFile? _certificate;
  final _pinNumber = TextEditingController();
  String _idCheck = ''; // ✅ / ⚠️ / ❌ result shown to nurse + saved for CEO
  bool _idVerified = false;
  String _idType = ''; // GHANA CARD / DRIVER LICENCE / PASSPORT / VOTER ID
  bool _loading = false;
  bool _obscurePassword = true;
  final _picker = ImagePicker();

  Future<void> _pickPhoto() async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (f != null) setState(() => _photo = f);
  }

  Future<void> _pickVideo() async {
    final f = await _picker.pickVideo(source: ImageSource.gallery);
    if (f != null) setState(() => _video = f);
  }

  Future<void> _pickDoc(void Function(XFile f) setFile) async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (f != null) setState(() => setFile(f));
  }

  Future<String?> _upload(XFile file, String path) async {
    final ref = FirebaseStorage.instance.ref().child(path);
    // Web: use bytes, Mobile: use file
    final bytes = await file.readAsBytes();
    await ref.putData(bytes, SettableMetadata(contentType: file.mimeType ?? 'application/octet-stream'));
    return await ref.getDownloadURL();
  }


  // ---- ID AUTHENTICITY PRE-CHECK (OCR) - INTERNATIONAL, WEB-COMPATIBLE ----
  // Uses Google Cloud Vision API over HTTP - works on Web, Android and iOS.
  // ML Kit does NOT work on Web, so we do NOT use it here.
  // To turn on auto-check: paste a Google Cloud Vision API key below
  // (Google Cloud Console -> APIs -> Cloud Vision API -> Create API key).
  // If no key is set, registration is NOT blocked - it is marked for CEO manual check.
  static const String _visionApiKey = 'PASTE_YOUR_GOOGLE_VISION_API_KEY_HERE';

  Future<String?> _ocrWithVision(Uint8List bytes) async {
    if (_visionApiKey == 'PASTE_YOUR_GOOGLE_VISION_API_KEY_HERE' || _visionApiKey.isEmpty) return null;
    try {
      final res = await http.post(
        Uri.parse('https://vision.googleapis.com/v1/images:annotate?key=$_visionApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requests': [
            {
              'image': {'content': base64Encode(bytes)},
              'features': [
                {'type': 'TEXT_DETECTION'}
              ]
            }
          ]
        }),
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final responses = data['responses'] as List?;
      if (responses == null || responses.isEmpty) return '';
      final annotations = responses[0]['textAnnotations'] as List?;
      if (annotations == null || annotations.isEmpty) return '';
      return (annotations[0]['description'] as String?) ?? '';
    } catch (_) {
      return null;
    }
  }

  Future<bool> _verifyIdDocument() async {
    if (_idFront == null) {
      setState(() => _idCheck = '❌ No ID Front uploaded');
      return false;
    }
    setState(() => _idCheck = '🔍 Checking ID, please wait...');
    // No Vision key configured -> do NOT block, mark for CEO manual check.
    if (_visionApiKey == 'PASTE_YOUR_GOOGLE_VISION_API_KEY_HERE' || _visionApiKey.isEmpty) {
      setState(() {
        _idType = 'ID (manual check)';
        _idVerified = false;
        _idCheck = '⚠️ Auto-check not configured yet. Your ID was sent to CEO for manual check.';
      });
      return true;
    }
    try {
      final bytes = await _idFront!.readAsBytes();
      final ocrText = await _ocrWithVision(bytes);
      if (ocrText == null) {
        setState(() {
          _idType = 'ID (manual check)';
          _idVerified = false;
          _idCheck = '⚠️ Could not reach ID check service. Your ID was sent to CEO for manual check.';
        });
        return true;
      }
      final text = ocrText.toUpperCase();
      final compact = text.replaceAll(RegExp(r'\s+'), ' ');

      String country = 'UNKNOWN';
      if (text.contains('GHANA')) country = 'GHANA';
      else if (text.contains('NIGERIA')) country = 'NIGERIA';
      else if (text.contains('KENYA')) country = 'KENYA';
      else if (text.contains('SOUTH AFRICA')) country = 'SOUTH AFRICA';
      else if (text.contains('INDIA') || text.contains('AADHAAR')) country = 'INDIA';
      else if (text.contains('UNITED KINGDOM') || text.contains('GREAT BRITAIN')) country = 'UNITED KINGDOM';
      else if (text.contains('UNITED STATES') || text.contains('USA') || text.contains('AMERICA')) country = 'USA';
      else if (text.contains('CANADA')) country = 'CANADA';
      else if (text.contains('AUSTRALIA')) country = 'AUSTRALIA';
      else if (text.contains('FRANCE')) country = 'FRANCE';
      else if (text.contains('GERMANY') || text.contains('BUNDESREPUBLIK')) country = 'GERMANY';
      else if (text.contains('TOGO')) country = 'TOGO';
      else if (text.contains("COTE D'IVOIRE") || text.contains('IVORY COAST')) country = "COTE D'IVOIRE";
      else if (text.contains('BENIN')) country = 'BENIN';
      else if (text.contains('BURKINA')) country = 'BURKINA FASO';
      else if (text.contains('SENEGAL')) country = 'SENEGAL';
      else if (text.contains('SIERRA LEONE')) country = 'SIERRA LEONE';
      else if (text.contains('LIBERIA')) country = 'LIBERIA';
      else if (text.contains('CAMEROON')) country = 'CAMEROON';
      else if (text.contains('ETHIOPIA')) country = 'ETHIOPIA';
      else if (text.contains('UGANDA')) country = 'UGANDA';
      else if (text.contains('TANZANIA')) country = 'TANZANIA';
      else if (text.contains('EGYPT')) country = 'EGYPT';
      else if (text.contains('PAKISTAN')) country = 'PAKISTAN';
      else if (text.contains('PHILIPPINES')) country = 'PHILIPPINES';
      else if (text.contains('BRAZIL') || text.contains('BRASIL')) country = 'BRAZIL';

      String type = 'UNKNOWN';
      final hasMrz = RegExp(r'P<[A-Z]{3}').hasMatch(compact.replaceAll(' ', ''));
      if (text.contains('PASSPORT') || hasMrz) {
        type = 'PASSPORT';
      } else if (text.contains('DRIV') && (text.contains('LICEN') || text.contains('PERMIS') || text.contains('DVLA'))) {
        type = 'DRIVER LICENCE';
      } else if (text.contains('GHANA CARD') || text.contains('NATIONAL IDENTIFICATION') || RegExp(r'GHA-\d{9}-\d').hasMatch(text)) {
        type = 'GHANA CARD';
      } else if (text.contains('AADHAAR') || text.contains('UNIQUE IDENTIFICATION')) {
        type = 'AADHAAR CARD';
      } else if (text.contains('NATIONAL IDENTITY') || text.contains('NATIONAL ID') || text.contains('IDENTITY CARD') || text.contains('IDENTITY DOCUMENT') || text.contains('CARTE NATIONALE')) {
        type = 'NATIONAL ID';
      } else if (text.contains('VOTER') || text.contains('ELECTORAL')) {
        type = 'VOTER ID';
      } else if (text.contains('NHIS') || text.contains('HEALTH INSURANCE')) {
        type = 'HEALTH INSURANCE CARD';
      } else if (text.contains('RESIDENCE') || text.contains('PERMIT')) {
        type = 'RESIDENCE PERMIT';
      }

      if (type == 'UNKNOWN') {
        setState(() {
          _idCheck = '❌ Could not read this as an ID. Take a clearer photo of your Passport, Driver Licence, or National ID (any country).';
          _idVerified = false;
        });
        return false;
      }

      String formatError = '';
      if (type == 'GHANA CARD' && country == 'GHANA' && !RegExp(r'GHA-\d{9}-\d').hasMatch(text)) {
        formatError = 'Ghana Card number should look like GHA-XXXXXXXXX-X.';
      } else if (type == 'AADHAAR CARD' && !RegExp(r'\d{4}\s?\d{4}\s?\d{4}').hasMatch(text)) {
        formatError = 'Aadhaar number should be 12 digits.';
      } else if (type == 'NATIONAL ID' && country == 'NIGERIA' && !RegExp(r'\d{11}').hasMatch(text.replaceAll(' ', ''))) {
        formatError = 'Nigeria NIN should be 11 digits.';
      } else if (type == 'NATIONAL ID' && country == 'SOUTH AFRICA' && !RegExp(r'\d{13}').hasMatch(text.replaceAll(' ', ''))) {
        formatError = 'South Africa ID number should be 13 digits.';
      }
      if (formatError.isNotEmpty) {
        setState(() {
          _idCheck = '⚠️ $type ($country) found, but $formatError CEO must check manually.';
          _idType = '$type ($country)';
          _idVerified = false;
        });
        return false;
      }

      if (type == 'PASSPORT') {
        final mrzLines = text.split('\n').where((l) => l.replaceAll(' ', '').length >= 30 && RegExp(r'[A-Z0-9<]{20,}').hasMatch(l.replaceAll(' ', ''))).toList();
        if (mrzLines.length >= 2) {
          final line2 = mrzLines.last.replaceAll(' ', '');
          if (line2.length >= 28) {
            final yy = int.tryParse(line2.substring(21, 23)) ?? 0;
            final mm = int.tryParse(line2.substring(23, 25)) ?? 0;
            final dd = int.tryParse(line2.substring(25, 27)) ?? 0;
            if (yy > 0 && mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31) {
              final expiry = DateTime(2000 + yy, mm, dd);
              if (expiry.isBefore(DateTime.now())) {
                setState(() {
                  _idCheck = '❌ This PASSPORT ($country) is EXPIRED ($dd/$mm/${2000 + yy}). Upload a valid, unexpired passport.';
                  _idType = 'PASSPORT ($country)';
                  _idVerified = false;
                });
                return false;
              }
            }
          }
        }
      }

      if (type != 'PASSPORT') {
        final expMatch = RegExp(r'(EXP|EXPIRY|VALID UNTIL|VALID THRU|DATE OF EXPIRY)[^\d]{0,10}(\d{1,2}[-/\.]\d{1,2}[-/\.]\d{2,4})').firstMatch(text);
        if (expMatch != null) {
          final parts = expMatch.group(2)!.split(RegExp(r'[-/.]'));
          int year = int.tryParse(parts[2]) ?? 0;
          if (year < 100) year += 2000;
          final month = int.tryParse(parts[1]) ?? 1;
          final day = int.tryParse(parts[0]) ?? 1;
          if (year > 1900 && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
            final expiry = DateTime(year, month, day);
            if (expiry.isBefore(DateTime.now())) {
              setState(() {
                _idCheck = '❌ This $type ($country) is EXPIRED ($day/$month/$year). Upload a valid, unexpired ID.';
                _idType = '$type ($country)';
                _idVerified = false;
              });
              return false;
            }
          }
        }
      }

      final typedName = _name.text.trim().toUpperCase();
      bool nameMatches = false;
      if (typedName.isNotEmpty) {
        for (final word in typedName.split(' ')) {
          if (word.length >= 3 && text.contains(word)) { nameMatches = true; break; }
        }
      }
      if (!nameMatches) {
        setState(() {
          _idCheck = '⚠️ Name on ID does not match "$typedName". CEO must check manually - could be a different person\'s ID.';
          _idType = '$type ($country)';
          _idVerified = false;
        });
        return false;
      }

      setState(() {
        _idType = country == 'UNKNOWN' ? type : '$type ($country)';
        _idVerified = true;
        _idCheck = '✅ $_idType detected. Format OK. Name matches. Not expired (where expiry was readable). Sent to CEO for final approval.';
      });
      return true;
    } catch (e) {
      setState(() => _idCheck = '⚠️ Could not check ID automatically ($e). CEO will check manually.');
      return false;
    }
  }


  // ---- STRONG PASSWORD ----
  // Strong = at least 8 chars + upper + lower + digit + special. No spaces.
  int get _passwordScore {
    final p = _pass.text;
    var score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    return score; // 0-6
  }
  bool get _isStrongPassword {
    final p = _pass.text;
    return p.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(p) &&
        RegExp(r'[a-z]').hasMatch(p) &&
        RegExp(r'[0-9]').hasMatch(p) &&
        RegExp(r'[^A-Za-z0-9]').hasMatch(p) &&
        !p.contains(' ');
  }
  String get _passwordStrengthLabel {
    if (_pass.text.isEmpty) return '';
    final sc = _passwordScore;
    if (sc <= 2) return 'Weak';
    if (sc <= 4) return 'Medium';
    if (sc == 5) return 'Strong';
    return 'Very strong';
  }
  Color get _passwordStrengthColor {
    if (_pass.text.isEmpty) return Colors.grey;
    final sc = _passwordScore;
    if (sc <= 2) return Colors.red;
    if (sc <= 4) return Colors.orange;
    if (sc == 5) return Colors.lightGreen;
    return Colors.green;
  }
  List<String> get _passwordMissing {
    final p = _pass.text;
    final missing = <String>[];
    if (p.length < 8) missing.add('At least 8 characters');
    if (!RegExp(r'[A-Z]').hasMatch(p)) missing.add('One UPPERCASE letter (A-Z)');
    if (!RegExp(r'[a-z]').hasMatch(p)) missing.add('One lowercase letter (a-z)');
    if (!RegExp(r'[0-9]').hasMatch(p)) missing.add('One number (0-9)');
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(p)) missing.add('One special character (! @ # \$ % etc.)');
    if (p.contains(' ')) missing.add('No spaces');
    return missing;
  }

  Future<void> _register() async {
    if (_name.text.isEmpty || _email.text.isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill all fields')));
      return;
    }
    if (_isOtherCountry && !RegExp(r'^\+\d{1,4}$').hasMatch(_selectedDialCode)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid country code for Other, e.g. +999')));
      return;
    }
    if (_phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your phone number')));
      return;
    }
    if (!_isStrongPassword) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Password too weak. Missing: ${_passwordMissing.join(', ')}'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    // ID must be verified BEFORE registration is sent to CEO
    final idOk = await _verifyIdDocument();
    if (!idOk) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_idCheck)));
      return;
    }
    setState(() => _loading = true);
    try {
      // 1. Create Auth
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text.trim(),
      );
      final uid = cred.user!.uid;

      // 2. Upload ALL docs - Photo, Video, CV, Nursing PIN, ID Front/Back, Certificate
      String? photoUrl;
      String? videoUrl;
      String? cvUrl;
      String? pinDocUrl;
      String? idFrontUrl;
      String? idBackUrl;
      String? certUrl;
      if (_photo != null) {
        photoUrl = await _upload(_photo!, 'nurses/$uid/photo.jpg');
      }
      if (_video != null) {
        videoUrl = await _upload(_video!, 'nurses/$uid/video.mp4');
      }
      if (_cv != null) {
        cvUrl = await _upload(_cv!, 'nurses/$uid/cv.jpg');
      }
      if (_pinDoc != null) {
        pinDocUrl = await _upload(_pinDoc!, 'nurses/$uid/nursing_pin.jpg');
      }
      if (_idFront != null) {
        idFrontUrl = await _upload(_idFront!, 'nurses/$uid/id_front.jpg');
      }
      if (_idBack != null) {
        idBackUrl = await _upload(_idBack!, 'nurses/$uid/id_back.jpg');
      }
      if (_certificate != null) {
        certUrl = await _upload(_certificate!, 'nurses/$uid/certificate.jpg');
      }

      // 3. Save to Firestore (for the nurse's own app)
      await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).set({
        'uid': uid,
        'name': _name.text.trim(),
        'fullName': _name.text.trim(),
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'phone': _fullPhone,
        'countryCode': _selectedDialCode,
        'country': _selectedCountryName,
        'role': 'nurse',
        'type': 'nurse',
        'status': 'pending',
        'isApproved': false,
        'photoUrl': photoUrl ?? '',
        'photoURL': photoUrl ?? '',
        'photo': photoUrl ?? '',
        'videoUrl': videoUrl ?? '',
        'videoURL': videoUrl ?? '',
        'cvUrl': cvUrl ?? '',
        'cvURL': cvUrl ?? '',
        'pinNumber': _pinNumber.text.trim(),
        'pinDocUrl': pinDocUrl ?? '',
        'pinDocURL': pinDocUrl ?? '',
        'idFrontUrl': idFrontUrl ?? '',
        'idFrontURL': idFrontUrl ?? '',
        'idBackUrl': idBackUrl ?? '',
        'idBackURL': idBackUrl ?? '',
        'nationalIdFrontUrl': idFrontUrl ?? '',
        'nationalIdBackUrl': idBackUrl ?? '',
        'certificateUrl': certUrl ?? '',
        'certificateURL': certUrl ?? '',
        'idType': _idType,
        'idCountry': _idType,
        'idVerified': _idVerified,
        'idCheck': _idCheck,
        'certUrl': certUrl ?? '',
        'certURL': certUrl ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 4. ALSO save to Realtime Database - THIS is what CEO Registration Center reads.
      // CEO does NOT read Firestore at all. It only reads RTDB paths like
      // ceoRegistrationCenter/nurses, nurses, nurse_registrations.
      // Without this write, registration says "successful" but CEO sees nothing.
      // Do NOT set hasAll4: true here - CEO treats hasAll4==true as already approved
      // and would hide the nurse from the Pending tab.
      final rtdbData = <String, Object?>{
        'uid': uid,
        'id': uid,
        'name': _name.text.trim(),
        'fullName': _name.text.trim(),
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'phone': _fullPhone,
        'countryCode': _selectedDialCode,
        'country': _selectedCountryName,
        'role': 'nurse',
        'type': 'nurse',
        'status': 'pending',
        'isApproved': false,
        'approved': false,
        'hasAll4': false,
        'photo': photoUrl ?? '',
        'photoUrl': photoUrl ?? '',
        'photoURL': photoUrl ?? '',
        'videoUrl': videoUrl ?? '',
        'videoURL': videoUrl ?? '',
        'idURL': idFrontUrl ?? '',
        'idFrontURL': idFrontUrl ?? '',
        'idBackURL': idBackUrl ?? '',
        'nationalIdFrontUrl': idFrontUrl ?? '',
        'nationalIdBackUrl': idBackUrl ?? '',
        'licenceURL': pinDocUrl ?? '',
        'pinNumber': _pinNumber.text.trim(),
        'pinDocURL': pinDocUrl ?? '',
        'idType': _idType,
        'idVerified': _idVerified,
        'idCheck': _idCheck,
        'cvURL': cvUrl ?? '',
        'cvUrl': cvUrl ?? '',
        'certificateURL': certUrl ?? '',
        'certURL': certUrl ?? '',
        'certUrl': certUrl ?? '',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      // Write to ALL 3 RTDB paths the CEO screen checks, so it cannot miss it.
      await FirebaseDatabase.instance.ref('ceoRegistrationCenter/nurses/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('nurses/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('nurse_registrations/$uid').set(rtdbData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registered! Wait for CEO approval')));
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nurse Registration'), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name')),
            TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username')),
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _selectedCountry,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Country Code'),
                    items: [
                      ..._countries.map((c) => DropdownMenuItem<String>(
                            value: '${c['name']}|${c['code']}',
                            child: Text('${c['name']} (${c['code']})', overflow: TextOverflow.ellipsis),
                          )),
                      const DropdownMenuItem<String>(value: 'Other|', child: Text('Other (type code)')),
                    ],
                    onChanged: (v) { if (v != null) setState(() => _selectedCountry = v); },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: 'Phone Number', hintText: _isOtherCountry ? 'Number without code' : 'e.g. 241234567 (no 0, no code)'),
                  ),
                ),
              ],
            ),
            if (_isOtherCountry)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _otherCode,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Your Country Code', hintText: 'e.g. +999', prefixText: ''),
                ),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Full number: ${_phone.text.trim().isEmpty ? '...' : _fullPhone}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            TextField(
              controller: _pass,
              obscureText: _obscurePassword,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Min 8 chars, upper + lower + number + symbol',
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_pass.text.isNotEmpty) ...[
              Row(children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: _passwordScore / 6,
                    backgroundColor: Colors.grey.shade300,
                    color: _passwordStrengthColor,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_passwordStrengthLabel,
                    style: TextStyle(color: _passwordStrengthColor, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 6),
              ..._passwordMissing.map((m) => Row(children: [
                    const Icon(Icons.close, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Expanded(child: Text(m, style: const TextStyle(fontSize: 12, color: Colors.red))),
                  ])),
              if (_isStrongPassword)
                const Row(children: [
                  Icon(Icons.check_circle, size: 14, color: Colors.green),
                  SizedBox(width: 4),
                  Text('Strong password ✓', style: TextStyle(fontSize: 12, color: Colors.green)),
                ]),
            ],
            const SizedBox(height: 16),
            // PHOTO
            ListTile(
              leading: const Icon(Icons.photo),
              title: Text(_photo == null ? 'Upload Photo' : 'Photo Selected: ${_photo!.name}'),
              trailing: ElevatedButton(onPressed: _pickPhoto, child: const Text('Pick Photo')),
            ),
            // VIDEO
            ListTile(
              leading: const Icon(Icons.videocam),
              title: Text(_video == null ? 'Upload Intro Video' : 'Video Selected: ${_video!.name}'),
              trailing: ElevatedButton(onPressed: _pickVideo, child: const Text('Pick Video')),
            ),
            // CV
            ListTile(
              leading: const Icon(Icons.description),
              title: Text(_cv == null ? 'Upload CV' : 'CV Selected: ${_cv!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _cv = f), child: const Text('Pick CV')),
            ),
            // NURSING PIN NUMBER
            TextField(controller: _pinNumber, decoration: const InputDecoration(labelText: 'Nursing PIN Number')),
            // NURSING PIN DOCUMENT
            ListTile(
              leading: const Icon(Icons.badge),
              title: Text(_pinDoc == null ? 'Upload Nursing PIN Card' : 'PIN Card Selected: ${_pinDoc!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _pinDoc = f), child: const Text('Pick PIN')),
            ),
            // ID VERIFICATION RESULT
            if (_idCheck.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_idCheck, style: TextStyle(color: _idVerified ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
              ),
            // NATIONAL ID - FRONT
            ListTile(
              leading: const Icon(Icons.credit_card),
              title: Text(_idFront == null ? 'Upload National ID - FRONT' : 'ID Front Selected: ${_idFront!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _idFront = f), child: const Text('Pick Front')),
            ),
            // NATIONAL ID - BACK
            ListTile(
              leading: const Icon(Icons.credit_card),
              title: Text(_idBack == null ? 'Upload National ID - BACK' : 'ID Back Selected: ${_idBack!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _idBack = f), child: const Text('Pick Back')),
            ),
            // CERTIFICATE
            ListTile(
              leading: const Icon(Icons.school),
              title: Text(_certificate == null ? 'Upload Certificate' : 'Certificate Selected: ${_certificate!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _certificate = f), child: const Text('Pick Cert')),
            ),
            const SizedBox(height: 20),
            _loading
                ? const CircularProgressIndicator()
                : Column(children: [
                    ElevatedButton(onPressed: _verifyIdDocument, child: const Text('🔍 VERIFY MY ID FIRST')),
                    const SizedBox(height: 10),
                    ElevatedButton(onPressed: _register, child: const Text('REGISTER AS NURSE')),
                  ]),
          ],
        ),
      ),
    );
  }
}
