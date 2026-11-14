import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

class NurseRegistrationPage extends StatefulWidget {
  const NurseRegistrationPage({super.key});
  @override
  State<NurseRegistrationPage> createState() => _NurseRegistrationPageState();
}

class _NurseRegistrationPageState extends State<NurseRegistrationPage> {
  // ---- APP COLOUR: DARK PINK (not bright) - use on ALL pages ----
  static const Color _darkPink = Color(0xFF880E4F); // deep dark pink - headers, main buttons
  static const Color _pink = Color(0xFFAD1457); // dark pink - secondary buttons / accents
  static const Color _pinkSoft = Color(0xFFFCE4EC); // very light pink - button backgrounds, chips
  static const Color _pinkBorder = Color(0xFFF8BBD0); // soft pink border
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  static const List<Map<String, String>> _countries = [{"name": "Afghanistan", "code": "+93"},
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
    {"name": "Zimbabwe", "code": "+263"}];
  String _selectedCountry = 'Ghana|+233';
  final _otherCode = TextEditingController();
  bool get _isOtherCountry => _selectedCountry == 'Other|';
  String get _selectedCountryName => _isOtherCountry ? 'Other' : _selectedCountry.split('|')[0];
  String get _selectedDialCode { if (_isOtherCountry) { var c = _otherCode.text.trim(); if (!c.startsWith('+')) c = '+$c'; return c; } return _selectedCountry.split('|')[1]; }
  String get _fullPhone { var local = _phone.text.trim().replaceAll(RegExp(r'[\s\-\(\)]'), ''); if (local.startsWith('+')) return local; if (local.startsWith('00')) return '+${local.substring(2)}'; if (local.startsWith('0')) local = local.substring(1); return _selectedDialCode.replaceAll(' ', '') + local; }
  String _selectedIdCountry = '';
  String _selectedIdType = '';
  final _idNumberTyped = TextEditingController();
  String _idNumber = '';
  String _idExpiry = '';
  int _idScore = 0;
  double _faceMatchScore = 0;
  String _faceCheck = '';
  // Label for the upload rows - FOLLOWS the picked ID type. Passport -> "Upload Passport - FRONT", Ghana Card -> "Upload Ghana Card - FRONT", etc. Never stuck on "National ID".
  String get _idLabel => _selectedIdType.isEmpty ? 'ID' : _selectedIdType;
  static const List<String> _idCountries = ['Afghanistan', 'Albania', 'Algeria', 'Andorra', 'Angola', 'Antigua and Barbuda', 'Argentina', 'Armenia', 'Australia', 'Austria', 'Azerbaijan', 'Bahamas', 'Bahrain', 'Bangladesh', 'Barbados', 'Belarus', 'Belgium', 'Belize', 'Benin', 'Bhutan', 'Bolivia', 'Bosnia and Herzegovina', 'Botswana', 'Brazil', 'Brunei', 'Bulgaria', 'Burkina Faso', 'Burundi', 'Cambodia', 'Cameroon', 'Canada', 'Cape Verde', 'Central African Republic', 'Chad', 'Chile', 'China', 'Colombia', 'Comoros', 'Congo', 'Congo (DRC)', 'Costa Rica', 'Côte d'Ivoire', 'Croatia', 'Cuba', 'Cyprus', 'Czechia', 'Denmark', 'Djibouti', 'Dominica', 'Dominican Republic', 'Ecuador', 'Egypt', 'El Salvador', 'Equatorial Guinea', 'Eritrea', 'Estonia', 'Eswatini', 'Ethiopia', 'Fiji', 'Finland', 'France', 'Gabon', 'Gambia', 'Georgia', 'Germany', 'Ghana', 'Greece', 'Grenada', 'Guatemala', 'Guinea', 'Guinea-Bissau', 'Guyana', 'Haiti', 'Honduras', 'Hungary', 'Iceland', 'India', 'Indonesia', 'Iran', 'Iraq', 'Ireland', 'Israel', 'Italy', 'Jamaica', 'Japan', 'Jordan', 'Kazakhstan', 'Kenya', 'Kiribati', 'Kuwait', 'Kyrgyzstan', 'Laos', 'Latvia', 'Lebanon', 'Lesotho', 'Liberia', 'Libya', 'Liechtenstein', 'Lithuania', 'Luxembourg', 'Madagascar', 'Malawi', 'Malaysia', 'Maldives', 'Mali', 'Malta', 'Marshall Islands', 'Mauritania', 'Mauritius', 'Mexico', 'Micronesia', 'Moldova', 'Monaco', 'Mongolia', 'Montenegro', 'Morocco', 'Mozambique', 'Myanmar', 'Namibia', 'Nauru', 'Nepal', 'Netherlands', 'New Zealand', 'Nicaragua', 'Niger', 'Nigeria', 'North Korea', 'North Macedonia', 'Norway', 'Oman', 'Pakistan', 'Palau', 'Palestine', 'Panama', 'Papua New Guinea', 'Paraguay', 'Peru', 'Philippines', 'Poland', 'Portugal', 'Qatar', 'Romania', 'Russia', 'Rwanda', 'Saint Kitts and Nevis', 'Saint Lucia', 'Saint Vincent', 'Samoa', 'San Marino', 'Sao Tome and Principe', 'Saudi Arabia', 'Senegal', 'Serbia', 'Seychelles', 'Sierra Leone', 'Singapore', 'Slovakia', 'Slovenia', 'Solomon Islands', 'Somalia', 'South Africa', 'South Korea', 'South Sudan', 'Spain', 'Sri Lanka', 'Sudan', 'Suriname', 'Sweden', 'Switzerland', 'Syria', 'Taiwan', 'Tajikistan', 'Tanzania', 'Thailand', 'Togo', 'Tonga', 'Trinidad and Tobago', 'Tunisia', 'Turkey', 'Turkmenistan', 'Tuvalu', 'Uganda', 'Ukraine', 'United Arab Emirates', 'United Kingdom', 'United States', 'Uruguay', 'Uzbekistan', 'Vanuatu', 'Vatican City', 'Venezuela', 'Vietnam', 'Yemen', 'Zambia', 'Zimbabwe', 'Other'];
  static const List<String> _idTypes = ['Passport','National ID / National Identity Card','Ghana Card',"Voter ID / Voter's Card","Driving Licence / Driver's License",'Health Insurance Card (NHIS / Health Card)','Aadhaar Card (India)','PAN Card (India)','Social Security Card (USA)','State ID Card (USA)'];
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


  Future<Map<String, List<double>>?> _faceLandmarks(Uint8List bytes) async {
    try {
      final res = await http.post(Uri.parse('https://vision.googleapis.com/v1/images:annotate?key=$_visionApiKey'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'requests': [{'image': {'content': base64Encode(bytes)}, 'features': [{'type': 'FACE_DETECTION', 'maxResults': 5}]}]}));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final faces = (data['responses'] as List?)?.first['faceAnnotations'] as List?;
      if (faces == null || faces.isEmpty) return {'__no_face__': []};
      if (faces.length > 1) return {'__many_faces__': [faces.length.toDouble()]};
      final face = faces[0] as Map<String, dynamic>;
      final box = face['boundingPoly']?['vertices'] as List?;
      if (box == null || box.length < 2) return null;
      final x0 = (box[0]['x'] ?? 0).toDouble(), y0 = (box[0]['y'] ?? 0).toDouble();
      final x1 = (box[2]['x'] ?? 1).toDouble(), y1 = (box[2]['y'] ?? 1).toDouble();
      final w = (x1 - x0).abs().clamp(1.0, 100000.0), h = (y1 - y0).abs().clamp(1.0, 100000.0);
      final out = <String, List<double>>{};
      for (final lm in (face['landmarks'] as List? ?? [])) { final type = lm['type'] as String? ?? ''; final pos = lm['position'] as Map<String, dynamic>?; if (pos == null) continue; out[type] = [((pos['x'] ?? 0).toDouble() - x0) / w, ((pos['y'] ?? 0).toDouble() - y0) / h]; }
      return out;
    } catch (_) { return null; }
  }
  Future<double?> _faceSimilarity(Uint8List profileBytes, Uint8List idBytes) async {
    final a = await _faceLandmarks(profileBytes); final b = await _faceLandmarks(idBytes);
    if (a == null || b == null) return null;
    if (a.containsKey('__no_face__') || b.containsKey('__no_face__')) return -1;
    if (a.containsKey('__many_faces__') || b.containsKey('__many_faces__')) return -2;
    const keys = ['LEFT_EYE','RIGHT_EYE','NOSE_TIP','MOUTH_LEFT','MOUTH_CENTER','MOUTH_RIGHT','LEFT_EAR','RIGHT_EAR','CHIN_GNATHION','FOREHEAD_GLABELLA'];
    double total = 0; int used = 0;
    for (final k in keys) { if (!a.containsKey(k) || !b.containsKey(k)) continue; final dx = a[k]![0] - b[k]![0], dy = a[k]![1] - b[k]![1]; total += math.sqrt(dx * dx + dy * dy); used++; }
    if (used < 6) return null;
    return (100 - ((total / used) * 320)).clamp(0.0, 100.0);
  }

  Future<bool> _verifyIdDocument() async {
    if (_selectedIdCountry.isEmpty) { setState(() { _idCheck = '❌ Pick your ID COUNTRY first (the country you are a citizen of).'; _idVerified = false; _idScore = 0; }); return false; }
    if (_selectedIdType.isEmpty) { setState(() { _idCheck = '❌ Pick your ID TYPE (Passport, Ghana Card, Voter ID, Driving Licence...).'; _idVerified = false; _idScore = 0; }); return false; }
    if (_photo == null) { setState(() { _idCheck = '❌ Upload YOUR OWN profile photo FIRST. We must compare the face on your ID with your profile photo - without it we cannot tell if the ID is yours.'; _idVerified = false; _idScore = 0; }); return false; }
    if (_idFront == null) { setState(() { _idCheck = '❌ No ID Front uploaded. Upload FRONT of your $_selectedIdType.'; _idVerified = false; _idScore = 0; }); return false; }
    if (_selectedIdType != 'Passport' && _idBack == null) { setState(() { _idCheck = '❌ Upload BACK of your $_selectedIdType too (front + back required).'; _idVerified = false; _idScore = 0; }); return false; }
    setState(() => _idCheck = '🔍 Auto-checking your $_selectedIdType ($_selectedIdCountry) + face match, please wait...');
    if (_visionApiKey == 'PASTE_YOUR_GOOGLE_VISION_API_KEY_HERE' || _visionApiKey.isEmpty) {
      setState(() { _idType = ''; _idVerified = false; _idScore = 0; _idCheck = '❌ Auto ID check is not configured yet. Ask admin to add the Google Vision API key. Registration is blocked until then.'; });
      return false;
    }
    try {
      final frontBytes = await _idFront!.readAsBytes();
      final backBytes = _idBack != null ? await _idBack!.readAsBytes() : Uint8List(0);
      final profileBytes = await _photo!.readAsBytes();
      if (frontBytes.length < 15000) { setState(() { _idCheck = '❌ Front ID photo is too small / blurry. Retake a clear, close photo.'; _idVerified = false; _idScore = 10; }); return false; }
      final frontText = await _ocrWithVision(frontBytes);
      final backText = _idBack != null ? await _ocrWithVision(backBytes) : '';
      if (frontText == null || backText == null) { setState(() { _idCheck = '❌ Could not reach ID check service. Check internet and try again.'; _idVerified = false; _idScore = 0; }); return false; }
      final text = ('$frontText\n$backText').toUpperCase();
      final compact = text.replaceAll(RegExp(r'\s+'), ' ');
      if (text.replaceAll(RegExp(r'[^A-Z0-9]'), '').length < 20) { setState(() { _idCheck = '❌ ID photo is not readable - too dark, blurry or cropped. Retake it so ALL text is clear.'; _idVerified = false; _idScore = 20; }); return false; }
      String country = 'UNKNOWN';
      const countryWords = {'GHANA':'GHANA','NIGERIA':'NIGERIA','KENYA':'KENYA','SOUTH AFRICA':'SOUTH AFRICA','INDIA':'INDIA','AADHAAR':'INDIA','UNITED KINGDOM':'UNITED KINGDOM','GREAT BRITAIN':'UNITED KINGDOM','UNITED STATES':'USA','USA':'USA','AMERICA':'USA','CANADA':'CANADA','AUSTRALIA':'AUSTRALIA','FRANCE':'FRANCE','GERMANY':'GERMANY','BUNDESREPUBLIK':'GERMANY','TOGO':'TOGO',"COTE D'IVOIRE":"COTE D'IVOIRE",'IVORY COAST':"COTE D'IVOIRE",'BENIN':'BENIN','BURKINA':'BURKINA FASO','SENEGAL':'SENEGAL','SIERRA LEONE':'SIERRA LEONE','LIBERIA':'LIBERIA','CAMEROON':'CAMEROON','ETHIOPIA':'ETHIOPIA','UGANDA':'UGANDA','TANZANIA':'TANZANIA','EGYPT':'EGYPT','PAKISTAN':'PAKISTAN','PHILIPPINES':'PHILIPPINES','BRAZIL':'BRAZIL','BRASIL':'BRAZIL'};
      for (final e in countryWords.entries) { if (text.contains(e.key)) { country = e.value; break; } }
      if (_selectedIdType == 'Ghana Card' && _selectedIdCountry != 'Ghana') { setState(() { _idCheck = '❌ Ghana Card is only for Ghana. Pick Ghana, or pick your own country\'s ID.'; _idVerified = false; _idScore = 40; }); return false; }
      if (_selectedIdCountry != 'Other') {
        if (country == 'UNKNOWN') { setState(() { _idCheck = '❌ Could not read the COUNTRY on this ID. Retake a clear photo showing "$_selectedIdCountry" on the ID.'; _idVerified = false; _idScore = 35; }); return false; }
        String sel = _selectedIdCountry.toUpperCase(); if (sel == 'UNITED STATES') sel = 'USA';
        if (country != sel) { setState(() { _idCheck = '❌ CITIZENSHIP MISMATCH: you picked "$_selectedIdCountry" but this ID is from "$country". Upload an ID that shows you are a citizen of $_selectedIdCountry.'; _idType = 'ID ($country)'; _idVerified = false; _idScore = 40; }); return false; }
      }
      String detected = 'UNKNOWN';
      final hasMrz = RegExp(r'P<[A-Z]{3}').hasMatch(compact.replaceAll(' ', ''));
      if (text.contains('PASSPORT') || hasMrz) detected = 'Passport';
      else if (text.contains('DRIV') && (text.contains('LICEN') || text.contains('PERMIS') || text.contains('DVLA'))) detected = "Driving Licence / Driver's License";
      else if (text.contains('GHANA CARD') || text.contains('NATIONAL IDENTIFICATION') || RegExp(r'GHA-\d{9}-\d').hasMatch(text)) detected = 'Ghana Card';
      else if (text.contains('AADHAAR') || text.contains('UNIQUE IDENTIFICATION')) detected = 'Aadhaar Card (India)';
      else if (text.contains('VOTER') || text.contains('ELECTORAL')) detected = "Voter ID / Voter's Card";
      else if (text.contains('NHIS') || text.contains('HEALTH INSURANCE')) detected = 'Health Insurance Card (NHIS / Health Card)';
      else if (text.contains('NATIONAL IDENTITY') || text.contains('NATIONAL ID') || text.contains('IDENTITY CARD') || text.contains('IDENTITY DOCUMENT') || text.contains('CARTE NATIONALE')) detected = 'National ID / National Identity Card';
      else if (text.contains('SOCIAL SECURITY')) detected = 'Social Security Card (USA)';
      else if (text.contains('PAN') && RegExp(r'[A-Z]{5}\d{4}[A-Z]').hasMatch(compact.replaceAll(' ', ''))) detected = 'PAN Card (India)';
      if (detected == 'UNKNOWN') { setState(() { _idCheck = '❌ Could not read this as an ID. Take a clearer photo of your $_selectedIdType.'; _idVerified = false; _idScore = 30; }); return false; }
      bool typeMatches = detected == _selectedIdType || (_selectedIdType == 'National ID / National Identity Card' && detected == 'Ghana Card');
      if (!typeMatches) { setState(() { _idCheck = '❌ MISMATCH: you picked "$_selectedIdType" but this photo looks like "$detected". Pick the correct ID type and re-upload.'; _idType = '$detected ($country)'; _idVerified = false; _idScore = 40; }); return false; }
      String formatError = ''; String foundNumber = ''; final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
      if (_selectedIdType == 'Ghana Card' || detected == 'Ghana Card') { final m = RegExp(r'GHA-\d{9}-\d').firstMatch(text); foundNumber = m?.group(0) ?? ''; if (foundNumber.isEmpty) formatError = 'Ghana Card number should look like GHA-XXXXXXXXX-X.'; }
      else if (detected == 'Aadhaar Card (India)') { final m = RegExp(r'\d{4}\s?\d{4}\s?\d{4}').firstMatch(text); foundNumber = m?.group(0) ?? ''; if (foundNumber.isEmpty) formatError = 'Aadhaar number should be 12 digits.'; }
      else if (detected == 'PAN Card (India)') { final m = RegExp(r'[A-Z]{5}\d{4}[A-Z]').firstMatch(compact.replaceAll(' ', '')); foundNumber = m?.group(0) ?? ''; if (foundNumber.isEmpty) formatError = 'PAN number should look like ABCDE1234F.'; }
      else if (country == 'NIGERIA' && detected.contains('National ID')) { if (!RegExp(r'\d{11}').hasMatch(digitsOnly)) formatError = 'Nigeria NIN should be 11 digits.'; }
      else if (country == 'SOUTH AFRICA' && detected.contains('National ID')) { if (!RegExp(r'\d{13}').hasMatch(digitsOnly)) formatError = 'South Africa ID number should be 13 digits.'; }
      else { if (!RegExp(r'\d{6,}').hasMatch(digitsOnly)) formatError = 'No ID number found on this photo.'; else foundNumber = RegExp(r'\d{6,}').firstMatch(digitsOnly)?.group(0) ?? ''; }
      if (formatError.isNotEmpty) { setState(() { _idCheck = '❌ $detected ($country) found, but $formatError Take a clearer photo.'; _idType = '$detected ($country)'; _idVerified = false; _idScore = 50; }); return false; }
      final typedNum = _idNumberTyped.text.trim().replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
      if (typedNum.isNotEmpty) { final ocrFlat = text.replaceAll(RegExp(r'[^A-Z0-9]'), ''); if (typedNum.length < 5 || !ocrFlat.contains(typedNum)) { setState(() { _idCheck = '❌ The ID number you typed is NOT on this photo. Check the number or re-upload the correct ID.'; _idType = '$detected ($country)'; _idVerified = false; _idScore = 55; }); return false; } }
      String expiryError = ''; String expiryFound = '';
      if (detected == 'Passport') {
        final mrzLines = text.split('\n').where((l) => l.replaceAll(' ', '').length >= 30 && RegExp(r'[A-Z0-9<]{20,}').hasMatch(l.replaceAll(' ', ''))).toList();
        if (mrzLines.length >= 2) { final line2 = mrzLines.last.replaceAll(' ', ''); if (line2.length >= 28) { final yy = int.tryParse(line2.substring(21, 23)) ?? 0; final mm = int.tryParse(line2.substring(23, 25)) ?? 0; final dd = int.tryParse(line2.substring(25, 27)) ?? 0; if (yy > 0 && mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31) { expiryFound = '$dd/$mm/${2000 + yy}'; if (DateTime(2000 + yy, mm, dd).isBefore(DateTime.now())) expiryError = 'EXPIRED ($expiryFound)'; } } }
      } else {
        final expMatch = RegExp(r'(EXP|EXPIRY|VALID UNTIL|VALID THRU|DATE OF EXPIRY)[^\d]{0,10}(\d{1,2}[-/\.]\d{1,2}[-/\.]\d{2,4})').firstMatch(text);
        if (expMatch != null) { final parts = expMatch.group(2)!.split(RegExp(r'[-/.]')); int year = int.tryParse(parts[2]) ?? 0; if (year < 100) year += 2000; final month = int.tryParse(parts[1]) ?? 1; final day = int.tryParse(parts[0]) ?? 1; if (year > 1900 && month >= 1 && month <= 12 && day >= 1 && day <= 31) { expiryFound = '$day/$month/$year'; if (DateTime(year, month, day).isBefore(DateTime.now())) expiryError = 'EXPIRED ($expiryFound)'; } }
      }
      if (expiryError.isNotEmpty) { setState(() { _idCheck = '❌ This $detected ($country) is $expiryError. Upload a valid, unexpired ID.'; _idType = '$detected ($country)'; _idVerified = false; _idScore = 60; }); return false; }
      final typedName = _name.text.trim().toUpperCase(); bool nameMatches = false;
      if (typedName.isNotEmpty) { for (final word in typedName.split(' ')) { if (word.length >= 3 && text.contains(word)) { nameMatches = true; break; } } }
      if (!nameMatches) { setState(() { _idCheck = '❌ Name on ID does not match "$typedName". Upload YOUR OWN ID.'; _idType = '$detected ($country)'; _idVerified = false; _idScore = 70; }); return false; }
      setState(() => _idCheck = '🔍 Checking face: does the face on your ID match your profile photo?');
      final faceScore = await _faceSimilarity(profileBytes, frontBytes);
      if (faceScore == null) { setState(() { _idCheck = '❌ Could not compare faces (not enough face detail). Upload a clear front-facing profile photo AND a clear ID photo showing the face.'; _idVerified = false; _idScore = 70; _faceMatchScore = 0; }); return false; }
      if (faceScore == -1) { setState(() { _idCheck = '❌ No face found on your profile photo OR on the ID. Both must show ONE clear face, looking at the camera.'; _idVerified = false; _idScore = 70; _faceMatchScore = 0; }); return false; }
      if (faceScore == -2) { setState(() { _idCheck = '❌ More than one face found in your profile photo or ID photo. Upload photos with ONLY YOU in them.'; _idVerified = false; _idScore = 70; _faceMatchScore = 0; }); return false; }
      _faceMatchScore = faceScore;
      if (faceScore < 55) {
        setState(() { _faceCheck = 'Face match ${faceScore.toStringAsFixed(0)}/100 - TOO LOW'; _idCheck = '❌ FACE DOES NOT MATCH: the face on this ID (score ${faceScore.toStringAsFixed(0)}/100) does NOT look like the face in your profile photo. This looks like SOMEONE ELSE\'S ID. Upload YOUR OWN ID + YOUR OWN photo.'; _idType = '$detected ($country)'; _idVerified = false; _idScore = 75; });
        return false;
      }
      setState(() {
        _idType = country == 'UNKNOWN' ? detected : '$detected ($country)';
        _idNumber = foundNumber.isNotEmpty ? foundNumber : _idNumberTyped.text.trim();
        _idExpiry = expiryFound; _idVerified = true; _idScore = 100;
        _faceCheck = 'Face match ${faceScore.toStringAsFixed(0)}/100 - SAME PERSON';
        _idCheck = '✅ $_idType VERIFIED (100/100). Citizenship OK, type matches, number OK, name matches, not expired, FACE MATCHES your profile photo (${faceScore.toStringAsFixed(0)}/100).';
      });
      return true;
    } catch (e) { setState(() { _idCheck = '❌ Could not check ID automatically ($e). Try again with clearer photos.'; _idVerified = false; _idScore = 0; }); return false; }
  }

  Future<void> _pickIdSide(bool isFront) async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (f == null) return;
    setState(() { if (isFront) _idFront = f; else _idBack = f; _idVerified = false; });
    if (_photo != null && _idFront != null && (_selectedIdType == 'Passport' || _idBack != null) && _selectedIdType.isNotEmpty && _selectedIdCountry.isNotEmpty) await _verifyIdDocument();
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
        'idCountry': _selectedIdCountry,
        'idNumber': _idNumber,
        'idNumberTyped': _idNumberTyped.text.trim(),
        'idExpiry': _idExpiry,
        'idScore': _idScore,
        'faceMatchScore': _faceMatchScore,
        'faceCheck': _faceCheck,
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
        'idCountry': _selectedIdCountry,
        'idNumber': _idNumber,
        'idNumberTyped': _idNumberTyped.text.trim(),
        'idExpiry': _idExpiry,
        'idScore': _idScore,
        'faceMatchScore': _faceMatchScore,
        'faceCheck': _faceCheck,
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
      appBar: AppBar(title: const Text('Nurse Registration'), backgroundColor: _darkPink, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name')),
            TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username')),
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: DropdownButtonFormField<String>(value: _selectedCountry, isExpanded: true, decoration: const InputDecoration(labelText: 'Country Code'),
                items: [..._countries.map((c) => DropdownMenuItem<String>(value: '${c['name']}|${c['code']}', child: Text('${c['name']} (${c['code']})', overflow: TextOverflow.ellipsis))), const DropdownMenuItem<String>(value: 'Other|', child: Text('Other (type code)'))],
                onChanged: (v) { if (v != null) setState(() => _selectedCountry = v); })),
              const SizedBox(width: 10),
              Expanded(flex: 3, child: TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Phone Number', hintText: _isOtherCountry ? 'Number without code' : 'e.g. 241234567 (no 0, no code)'))),
            ]),
            if (_isOtherCountry) Padding(padding: const EdgeInsets.only(top: 8), child: TextField(controller: _otherCode, keyboardType: TextInputType.phone, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Your Country Code', hintText: 'e.g. +999'))),
            Align(alignment: Alignment.centerLeft, child: Text('Full number: ${_phone.text.trim().isEmpty ? '...' : _fullPhone}', style: const TextStyle(fontSize: 12, color: Colors.grey))),
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
              title: Text(_photo == null ? 'Upload Photo - YOUR OWN FACE (required for face match)' : 'Photo Selected: ${_photo!.name}'),
              trailing: ElevatedButton(onPressed: _pickPhoto, style: ElevatedButton.styleFrom(backgroundColor: _pinkSoft, foregroundColor: _darkPink), child: const Text('Pick Photo')),
            ),
            // VIDEO
            ListTile(
              leading: const Icon(Icons.videocam),
              title: Text(_video == null ? 'Upload Intro Video' : 'Video Selected: ${_video!.name}'),
              trailing: ElevatedButton(onPressed: _pickVideo, style: ElevatedButton.styleFrom(backgroundColor: _pinkSoft, foregroundColor: _darkPink), child: const Text('Pick Video')),
            ),
            // CV
            ListTile(
              leading: const Icon(Icons.description),
              title: Text(_cv == null ? 'Upload CV' : 'CV Selected: ${_cv!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _cv = f), style: ElevatedButton.styleFrom(backgroundColor: _pinkSoft, foregroundColor: _darkPink), child: const Text('Pick CV')),
            ),
            // NURSING PIN NUMBER
            TextField(controller: _pinNumber, decoration: const InputDecoration(labelText: 'Nursing PIN Number')),
            // NURSING PIN DOCUMENT
            ListTile(
              leading: const Icon(Icons.badge),
              title: Text(_pinDoc == null ? 'Upload Nursing PIN Card' : 'PIN Card Selected: ${_pinDoc!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _pinDoc = f), style: ElevatedButton.styleFrom(backgroundColor: _pinkSoft, foregroundColor: _darkPink), child: const Text('Pick PIN')),
            ),
            // ---- ID SECTION (NOT Nursing PIN) ----
            // ID Country + ID Type + ID Number sit here, directly above the ID upload rows.
            DropdownButtonFormField<String>(value: _selectedIdCountry.isEmpty ? null : _selectedIdCountry, isExpanded: true, decoration: const InputDecoration(labelText: 'ID Country - Country you are a citizen of', hintText: 'e.g. Ghana, Nigeria, Kenya, India...'), items: _idCountries.map((c) => DropdownMenuItem<String>(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() { _selectedIdCountry = v ?? ''; _idVerified = false; _idCheck = ''; })),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(value: _selectedIdType.isEmpty ? null : _selectedIdType, isExpanded: true, decoration: const InputDecoration(labelText: 'ID Type - Select your ID', hintText: 'e.g. Passport, Ghana Card, Voter ID...'), items: _idTypes.map((t) => DropdownMenuItem<String>(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() { _selectedIdType = v ?? ''; _idVerified = false; _idCheck = ''; })),
            const SizedBox(height: 8),
            TextField(controller: _idNumberTyped, decoration: const InputDecoration(labelText: 'ID Number (as printed on your ID)', hintText: 'e.g. GHA-123456789-0')),
            // ID VERIFICATION RESULT
            if (_idCheck.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_idCheck, style: TextStyle(color: _idVerified ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
              ),
            // NATIONAL ID - FRONT
            ListTile(
              leading: const Icon(Icons.credit_card),
              title: Text(_idFront == null ? 'Upload $_idLabel - FRONT' : '$_idLabel Front Selected: ${_idFront!.name}'),
              subtitle: Text(_selectedIdType.isEmpty ? 'Pick ID Country + ID Type first' : 'Front of $_selectedIdType ($_selectedIdCountry)'),
              trailing: ElevatedButton(onPressed: () => _pickIdSide(true), style: ElevatedButton.styleFrom(backgroundColor: _pinkSoft, foregroundColor: _darkPink), child: const Text('Pick Front')),
            ),
            // ID - BACK (hidden for Passport - front only)
            if (_selectedIdType != 'Passport')
            ListTile(
              leading: const Icon(Icons.credit_card),
              title: Text(_idBack == null ? 'Upload $_idLabel - BACK' : '$_idLabel Back Selected: ${_idBack!.name}'),
              subtitle: Text(_selectedIdType == 'Passport' ? 'Passport - no back needed' : 'Back of $_selectedIdType (required)'),
              trailing: ElevatedButton(onPressed: () => _pickIdSide(false), style: ElevatedButton.styleFrom(backgroundColor: _pinkSoft, foregroundColor: _darkPink), child: const Text('Pick Back')),
            ),
            // CERTIFICATE
            ListTile(
              leading: const Icon(Icons.school),
              title: Text(_certificate == null ? 'Upload Certificate' : 'Certificate Selected: ${_certificate!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _certificate = f), style: ElevatedButton.styleFrom(backgroundColor: _pinkSoft, foregroundColor: _darkPink), child: const Text('Pick Cert')),
            ),
            const SizedBox(height: 20),
            _loading
                ? const CircularProgressIndicator()
                : Column(children: [
                    ElevatedButton(onPressed: _verifyIdDocument, style: ElevatedButton.styleFrom(backgroundColor: _pink, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)), child: const Text('🔍 CHECK MY ID AGAIN')),
                    const SizedBox(height: 10),
                    ElevatedButton(onPressed: _register, style: ElevatedButton.styleFrom(backgroundColor: _darkPink, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)), child: const Text('REGISTER AS NURSE')),
                  ]),
          ],
        ),
      ),
    );
  }
}
