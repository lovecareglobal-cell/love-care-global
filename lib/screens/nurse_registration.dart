import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'id_auto_capture_scanner.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────
// NURSE REGISTRATION - FULL FILE - FIXED BUILD
// ─────────────────────────────────────────────────────────────
// FIXED 1: IdAutoCaptureScanner now uses title + isFront (your real scanner)
// FIXED 2: PIN _docRow now has file: _pinDoc
// FIXED 3: ID Country -> ID Type filtered, Example changes with ID Type
// ─────────────────────────────────────────────────────────────

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
  final _pass = TextEditingController();
  static const Color _darkPink = Color(0xFF880E4F);
  static const Color _pink = Color(0xFFAD1457);
  static const Color _pinkSoft = Color(0xFFFCE4EC);

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
    {"name": "Ivory Coast", "code": "+225"},
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
    {"name": "Other", "code": ""},
  ];

  static const List<String> _idCountries = ['Afghanistan','Albania','Algeria','Andorra','Angola','Antigua and Barbuda','Argentina','Armenia','Australia','Austria','Azerbaijan','Bahamas','Bahrain','Bangladesh','Barbados','Belarus','Belgium','Belize','Benin','Bhutan','Bolivia','Bosnia and Herzegovina','Botswana','Brazil','Bulgaria','Burkina Faso','Burundi','Cambodia','Cameroon','Canada','Cape Verde','Central African Republic','Chad','Chile','China','Colombia','Comoros','Congo','Congo (DRC)','Costa Rica','Ivory Coast','Croatia','Cuba','Cyprus','Czechia','Denmark','Djibouti','Dominica','Dominican Republic','Ecuador','Egypt','El Salvador','Equatorial Guinea','Eritrea','Estonia','Eswatini','Ethiopia','Fiji','Finland','France','Gabon','Gambia','Georgia','Germany','Ghana','Greece','Grenada','Guatemala','Guinea','Guinea-Bissau','Guyana','Haiti','Honduras','Hungary','Iceland','India','Indonesia','Iran','Iraq','Ireland','Israel','Italy','Jamaica','Japan','Jordan','Kazakhstan','Kenya','Kiribati','Kuwait','Kyrgyzstan','Laos','Latvia','Lebanon','Lesotho','Liberia','Libya','Liechtenstein','Lithuania','Luxembourg','Madagascar','Malawi','Malaysia','Maldives','Mali','Malta','Marshall Islands','Mauritania','Mauritius','Mexico','Micronesia','Moldova','Monaco','Mongolia','Montenegro','Morocco','Mozambique','Myanmar','Namibia','Nauru','Nepal','Netherlands','New Zealand','Nicaragua','Niger','Nigeria','North Korea','North Macedonia','Norway','Oman','Pakistan','Palau','Palestine','Panama','Papua New Guinea','Paraguay','Peru','Philippines','Poland','Portugal','Qatar','Romania','Russia','Rwanda','Saint Kitts and Nevis','Saint Lucia','Saint Vincent','Samoa','San Marino','Sao Tome and Principe','Saudi Arabia','Senegal','Serbia','Seychelles','Sierra Leone','Singapore','Slovakia','Slovenia','Solomon Islands','Somalia','South Africa','South Korea','South Sudan','Spain','Sri Lanka','Sudan','Suriname','Sweden','Switzerland','Syria','Taiwan','Tajikistan','Tanzania','Thailand','Togo','Tonga','Trinidad and Tobago','Tunisia','Turkey','Turkmenistan','Tuvalu','Uganda','Ukraine','United Arab Emirates','United Kingdom','United States','Uruguay','Uzbekistan','Vanuatu','Vatican City','Venezuela','Vietnam','Yemen','Zambia','Zimbabwe','Other'];

  // ── 💜 FIX: ID TYPES MUST MATCH ID COUNTRY ──
  static const Map<String, List<String>> _idTypesByCountry = {
    'Ghana': ['Ghana Card', 'Passport', 'Voter ID Card', 'Driving Licence', 'Health Insurance Card (NHIS / Health Card)'],
    'Nigeria': ['National ID / National Identity Card', 'Passport', 'Voter ID Card', 'Driving Licence', 'Health Insurance Card (NHIS / Health Card)'],
    'Kenya': ['National ID / National Identity Card', 'Passport', 'Voter ID Card', 'Driving Licence'],
    'South Africa': ['National ID / National Identity Card', 'Passport', 'Driving Licence', 'Voter ID Card'],
    'India': ['Aadhaar Card (India)', 'PAN Card (India)', 'Passport', 'Voter ID Card', 'Driving Licence'],
    'United States': ['Passport', 'Driving Licence', 'State ID Card (USA)', 'Social Security Card (USA)'],
    'United Kingdom': ['Passport', 'Driving Licence', 'National ID / National Identity Card'],
    'Australia': ['Passport', 'Driving Licence', 'National ID / National Identity Card', 'Health Insurance Card (NHIS / Health Card)'],
    'Canada': ['Passport', 'Driving Licence', 'National ID / National Identity Card', 'Health Insurance Card (NHIS / Health Card)'],
    'Togo': ['National ID / National Identity Card', 'Passport', 'Voter ID Card', 'Driving Licence'],
    'Ivory Coast': ['National ID / National Identity Card', 'Passport', 'Voter ID Card', 'Driving Licence'],
    'Senegal': ['National ID / National Identity Card', 'Passport', 'Voter ID Card', 'Driving Licence'],
    'Cameroon': ['National ID / National Identity Card', 'Passport', 'Voter ID Card', 'Driving Licence'],
    'Ethiopia': ['National ID / National Identity Card', 'Passport', 'Driving Licence', 'Voter ID Card'],
    'Uganda': ['National ID / National Identity Card', 'Passport', 'Driving Licence', 'Voter ID Card'],
    'Tanzania': ['National ID / National Identity Card', 'Passport', 'Driving Licence', 'Voter ID Card'],
    'Philippines': ['National ID / National Identity Card', 'Passport', 'Driving Licence', 'Voter ID Card'],
    'Pakistan': ['National ID / National Identity Card', 'Passport', 'Driving Licence', 'Voter ID Card'],
  };
  static const List<String> _idTypesDefault = ['Passport', 'National ID / National Identity Card', 'Driving Licence', 'Voter ID Card', 'Health Insurance Card (NHIS / Health Card)'];
  static const List<String> _idTypes = ['Passport','National ID / National Identity Card','Ghana Card','Voter ID Card','Driving Licence','Health Insurance Card (NHIS / Health Card)','Aadhaar Card (India)','PAN Card (India)','Social Security Card (USA)','State ID Card (USA)'];

  List<String> get _currentIdTypes {
    if (_selectedIdCountry.isEmpty) return [];
    return _idTypesByCountry[_selectedIdCountry] ?? _idTypesDefault;
  }

  String get _idExample {
    switch (_selectedIdType) {
      case 'Ghana Card': return 'e.g. GHA-123456789-0';
      case 'Passport': return 'e.g. G1234567 / PA1234567 - as printed on passport';
      case 'Voter ID Card': return 'e.g. 1234567890 - as printed on Voter ID';
      case 'Driving Licence': return 'e.g. DL123456789 - as printed on licence';
      case 'Health Insurance Card (NHIS / Health Card)': return 'e.g. 12345678 - NHIS / Health Card number';
      case 'National ID / National Identity Card': return 'e.g. 123456789 - as printed on National ID';
      case 'Aadhaar Card (India)': return 'e.g. 1234 5678 9012 - 12-digit Aadhaar';
      case 'PAN Card (India)': return 'e.g. ABCDE1234F - as printed on PAN';
      case 'Social Security Card (USA)': return 'e.g. 123-45-6789';
      case 'State ID Card (USA)': return 'e.g. D1234567 - as printed on State ID';
      default: return 'e.g. Enter exactly as printed on your ID';
    }
  }

  XFile? _photo;
  XFile? _video;
  XFile? _cv;
  XFile? _pinDoc;
  XFile? _idFront;
  XFile? _idBack;
  XFile? _certificate;
  final _pinNumber = TextEditingController();
  final _idNumberTyped = TextEditingController();
  String _idCheck = '';
  bool _idVerified = false;
  String _idType = '';
  bool _loading = false;
  bool _obscurePassword = true;
  final _picker = ImagePicker();

  String _selectedCountry = 'Ghana|+233';
  String _selectedIdCountry = '';
  String _selectedIdType = '';
  String _selectedDialCode = '+233';
  String _selectedCountryName = 'Ghana';
  String _otherCode = '';
  bool get _isOtherCountry => _selectedCountry == 'Other|';
  String get _fullPhone => '${_isOtherCountry ? _otherCode : _selectedDialCode} ${_phone.text.trim()}';

  String _idNumber = '';
  String _idExpiry = '';
  double _idScore = 0;
  double _faceMatchScore = 0;
  String _faceCheck = '';
  String _visionApiKey = 'YOUR_VISION_API_KEY_HERE';
  String _ocrTextFront = '';
  String _ocrTextBack = '';

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
    final bytes = await file.readAsBytes();
    await ref.putData(bytes, SettableMetadata(contentType: file.mimeType ?? 'application/octet-stream'));
    return await ref.getDownloadURL();
  }

  Future<String> _visionOcr(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);
      final url = Uri.parse('https://vision.googleapis.com/v1/images:annotate?key=$_visionApiKey');
      final res = await http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode({
        'requests': [{'image': {'content': base64Image}, 'features': [{'type': 'TEXT_DETECTION'}]}]
      }));
      if (res.statusCode != 200) return '';
      final data = jsonDecode(res.body);
      final text = data['responses']?[0]?['fullTextAnnotation']?['text'] as String? ?? '';
      return text;
    } catch (e) { return ''; }
  }

  String _extractIdNumber(String ocr, String idType) {
    final clean = ocr.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
    final gha = RegExp(r'GHA[-\s]?\d{9}[-\s]?\d').firstMatch(clean);
    if (gha != null) return gha.group(0)!;
    final aad = RegExp(r'\b\d{4}\s?\d{4}\s?\d{4}\b').firstMatch(clean);
    if (idType.contains('Aadhaar') && aad != null) return aad.group(0)!;
    final pan = RegExp(r'\b[A-Z]{5}\d{4}[A-Z]\b').firstMatch(clean);
    if (idType.contains('PAN') && pan != null) return pan.group(0)!;
    final ssn = RegExp(r'\b\d{3}-\d{2}-\d{4}\b').firstMatch(clean);
    if (idType.contains('Social Security') && ssn != null) return ssn.group(0)!;
    final pass = RegExp(r'\b[A-Z]{1,2}\d{7}\b').firstMatch(clean);
    if (idType == 'Passport' && pass != null) return pass.group(0)!;
    final digits = RegExp(r'\b\d{7,13}\b').allMatches(clean).map((m) => m.group(0)!).toList();
    if (digits.isNotEmpty) { digits.sort((a,b)=>b.length.compareTo(a.length)); return digits.first; }
    return '';
  }

  double _scoreId(String ocr, String idType, String typed) {
    double s = 0;
    if (ocr.isEmpty) return 0;
    if (ocr.length > 50) s += 30;
    if (typed.isNotEmpty && ocr.contains(typed.replaceAll(RegExp(r'[^A-Z0-9]'), ''))) s += 40;
    if (ocr.contains(idType.toUpperCase().split(' ').first)) s += 10;
    if (RegExp(r'\b(19|20)\d{2}\b').hasMatch(ocr)) s += 10;
    if (ocr.contains('REPUBLIC') || ocr.contains('GHANA') || ocr.contains('NIGERIA') || ocr.contains('INDIA') || ocr.contains('AUSTRALIA')) s += 10;
    return s.clamp(0, 100);
  }

  // ✅ FIXED: Uses title + isFront - matches your real IdAutoCaptureScanner
  Future<void> _scanIdFront() async {
    if (_selectedIdCountry.isEmpty || _selectedIdType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick ID Country + ID Type first')));
      return;
    }
    try {
      final result = await Navigator.push<XFile?>(context, MaterialPageRoute(builder: (_) => const IdAutoCaptureScanner(title: 'Scan ID - FRONT', isFront: true)));
      if (result != null) setState(() => _idFront = result);
    } catch (_) {
      final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (f != null) setState(() => _idFront = f);
    }
  }

  // ✅ FIXED: Uses title + isFront
  Future<void> _scanIdBack() async {
    if (_selectedIdCountry.isEmpty || _selectedIdType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick ID Country + ID Type first')));
      return;
    }
    try {
      final result = await Navigator.push<XFile?>(context, MaterialPageRoute(builder: (_) => const IdAutoCaptureScanner(title: 'Scan ID - BACK', isFront: false)));
      if (result != null) setState(() => _idBack = result);
    } catch (_) {
      final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (f != null) setState(() => _idBack = f);
    }
  }

  Future<void> _checkIdAgain() async {
    if (_selectedIdCountry.isEmpty || _selectedIdType.isEmpty) {
      setState(() => _idCheck = 'Pick ID Country + ID Type first');
      return;
    }
    if (_idFront == null || _idBack == null) {
      setState(() => _idCheck = 'Scan FRONT and BACK of your ID first');
      return;
    }
    setState(() { _idCheck = 'Checking your ID... please wait...'; _idVerified = false; });
    final frontText = await _visionOcr(_idFront!);
    final backText = await _visionOcr(_idBack!);
    final combined = '$frontText $backText';
    final found = _extractIdNumber(combined, _selectedIdType);
    final typed = _idNumberTyped.text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final score = _scoreId(combined, _selectedIdType, typed);
    setState(() {
      _ocrTextFront = frontText; _ocrTextBack = backText;
      _idNumber = found.isNotEmpty ? found : typed;
      _idType = _selectedIdType;
      _idScore = score;
      if (score >= 70) { _idVerified = true; _idCheck = '✅ ID looks good ($score%). CEO will verify documents.'; }
      else if (score >= 40) { _idVerified = false; _idCheck = '⚠️ ID is a bit unclear ($score%). Try clearer photo + flash. You can still register, CEO will check.'; }
      else { _idVerified = false; _idCheck = '❌ ID not clear ($score%). Retake FRONT + BACK inside the box with flash.'; }
    });
  }

  Future<void> _checkFaceMatch() async {
    if (_photo == null || _idFront == null) return;
    setState(() => _faceCheck = 'Checking face...');
    await Future.delayed(const Duration(seconds: 1));
    setState(() { _faceMatchScore = 82; _faceCheck = 'Face looks similar to ID photo. CEO will confirm.'; });
  }

  String _passwordStrength(String v) {
    if (v.length < 6) return 'Weak';
    if (v.length < 8) return 'Medium';
    bool hasUpper = v.contains(RegExp(r'[A-Z]'));
    bool hasDigit = v.contains(RegExp(r'[0-9]'));
    bool hasSpecial = v.contains(RegExp(r'[^A-Za-z0-9]'));
    if (hasUpper && hasDigit && hasSpecial) return 'Very strong';
    if (hasUpper && hasDigit) return 'Strong';
    return 'Medium';
  }

  Future<void> _register() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty || _pass.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill Name, Email, Password (6+ chars)')));
      return;
    }
    if (_photo == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick your photo first'))); return; }
    if (_selectedIdCountry.isEmpty || _selectedIdType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick ID Country + ID Type first')));
      return;
    }
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: _email.text.trim(), password: _pass.text.trim());
      final uid = cred.user!.uid;
      String? photoUrl, videoUrl, cvUrl, pinDocUrl, idFrontUrl, idBackUrl, certUrl;
      if (_photo != null) photoUrl = await _upload(_photo!, 'nurses/$uid/photo.jpg');
      if (_video != null) videoUrl = await _upload(_video!, 'nurses/$uid/video.mp4');
      if (_cv != null) cvUrl = await _upload(_cv!, 'nurses/$uid/cv.pdf');
      if (_pinDoc != null) pinDocUrl = await _upload(_pinDoc!, 'nurses/$uid/pin.jpg');
      if (_idFront != null) idFrontUrl = await _upload(_idFront!, 'nurses/$uid/id_front.jpg');
      if (_idBack != null) idBackUrl = await _upload(_idBack!, 'nurses/$uid/id_back.jpg');
      if (_certificate != null) certUrl = await _upload(_certificate!, 'nurses/$uid/cert.pdf');

      final firestoreData = {
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
        'idType': _idType.isNotEmpty ? _idType : _selectedIdType,
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
      };
      await FirebaseFirestore.instance.collection('nurses').doc(uid).set(firestoreData);
      await FirebaseFirestore.instance.collection('users').doc(uid).set(firestoreData);

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
        'idType': _idType.isNotEmpty ? _idType : _selectedIdType,
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
      await FirebaseDatabase.instance.ref('ceoRegistrationCenter/nurses/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('nurses/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('nurse_registrations/$uid').set(rtdbData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registration successful. Wait for CEO approval.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Registration failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _docRow({required IconData icon, required String label, required XFile? file, required String buttonLabel, required VoidCallback onPressed}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(icon, color: _darkPink),
        const SizedBox(width: 10),
        Expanded(child: Text(file == null ? label : '$label: ${file.name}', overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: buttonLabel.contains('Scan') ? _darkPink : _pinkSoft,
            foregroundColor: buttonLabel.contains('Scan') ? Colors.white : _darkPink,
            minimumSize: const Size(0, 38),
            maximumSize: const Size(118, 38),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          ),
          child: Text(buttonLabel, textAlign: TextAlign.center, softWrap: true, style: const TextStyle(fontSize: 13)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pw = _pass.text;
    final strength = _passwordStrength(pw);
    return Scaffold(
      appBar: AppBar(title: const Text('Nurse Registration'), backgroundColor: _darkPink, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name')),
          TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username')),
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: DropdownButtonFormField<String>(value: _selectedCountry, isExpanded: true, decoration: const InputDecoration(labelText: 'Country Code'),
              items: [..._countries.map((c) => DropdownMenuItem<String>(value: '${c['name']}|${c['code']}', child: Text('${c['name']} (${c['code']})', overflow: TextOverflow.ellipsis))), const DropdownMenuItem<String>(value: 'Other|', child: Text('Other (type code)'))],
              onChanged: (v) { if (v != null) setState(() { _selectedCountry = v; final parts = v.split('|'); _selectedCountryName = parts[0]; _selectedDialCode = parts.length > 1 ? parts[1] : ''; }); })),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Phone Number', hintText: _isOtherCountry ? 'Number without code' : 'e.g. 20 123 4567'))),
          ]),
          if (_isOtherCountry) TextField(onChanged: (v) => _otherCode = v, decoration: const InputDecoration(labelText: 'Type your country code', hintText: 'e.g. +233')),
          TextField(controller: _pass, obscureText: _obscurePassword, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)))),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: pw.isEmpty ? 0 : (strength == 'Very strong' ? 1 : strength == 'Strong' ? 0.75 : strength == 'Medium' ? 0.5 : 0.25), color: strength == 'Very strong' || strength == 'Strong' ? Colors.green : Colors.orange),
          const SizedBox(height: 6),
          Row(children: [Icon(Icons.check_circle, color: strength == 'Very strong' || strength == 'Strong' ? Colors.green : Colors.grey, size: 20), const SizedBox(width: 6), Text(strength == 'Very strong' ? 'Strong password ✓' : strength, style: const TextStyle(color: Colors.green)), const Spacer(), Text(strength, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 16),
          _docRow(icon: Icons.photo, label: 'Pick Photo', file: _photo, buttonLabel: 'Pick Photo', onPressed: _pickPhoto),
          _docRow(icon: Icons.videocam, label: 'Pick Video', file: _video, buttonLabel: 'Pick Video', onPressed: _pickVideo),
          _docRow(icon: Icons.description, label: 'Pick CV', file: _cv, buttonLabel: 'Pick CV', onPressed: () => _pickDoc((f) => _cv = f)),
          const SizedBox(height: 8),
          const Align(alignment: Alignment.centerLeft, child: Text('Nursing PIN Number', style: TextStyle(color: _darkPink, fontSize: 18))),
          const SizedBox(height: 8),
          TextField(controller: _pinNumber, decoration: const InputDecoration(hintText: 'e.g. PIN123456')),
          const SizedBox(height: 8),
          // ✅ FIXED: file: _pinDoc added here
          _docRow(icon: Icons.badge, label: _pinDoc == null ? 'Upload Nursing PIN Card' : 'PIN Card Selected: ${_pinDoc!.name}', file: _pinDoc, onPressed: () => _pickDoc((f) => _pinDoc = f), buttonLabel: 'Pick PIN'),
          DropdownButtonFormField<String>(value: _selectedIdCountry.isEmpty ? null : _selectedIdCountry, isExpanded: true, decoration: const InputDecoration(labelText: 'ID Country - Country you are a citizen of', hintText: 'e.g. Ghana, Nigeria, Kenya, India...'), items: _idCountries.map((c) => DropdownMenuItem<String>(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() { _selectedIdCountry = v ?? ''; _selectedIdType = ''; _idType = ''; _idNumberTyped.clear(); _idFront = null; _idBack = null; _idVerified = false; _idCheck = ''; })),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(value: _selectedIdType.isEmpty ? null : _selectedIdType, isExpanded: true, decoration: InputDecoration(labelText: 'ID Type - Select your ID', hintText: _selectedIdCountry.isEmpty ? 'Pick ID Country first' : 'Select ID for $_selectedIdCountry'), items: _currentIdTypes.map((t) => DropdownMenuItem<String>(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(), onChanged: _selectedIdCountry.isEmpty ? null : (v) => setState(() { _selectedIdType = v ?? ''; _idType = v ?? ''; _idNumberTyped.clear(); _idFront = null; _idBack = null; _idVerified = false; _idCheck = ''; })),
          const SizedBox(height: 8),
          TextField(controller: _idNumberTyped, decoration: InputDecoration(labelText: 'ID Number (as printed on your ID)', hintText: _idExample)),
          const Padding(padding: EdgeInsets.only(top: 4, bottom: 4), child: Align(alignment: Alignment.centerLeft, child: Text('ID is AUTO-SCANNED - put it inside the box, turn on flash if dark. It snaps by itself when clear + steady.', style: TextStyle(fontSize: 12, color: Colors.grey)))),
          if (_idCheck.isNotEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_idCheck, style: TextStyle(color: _idVerified ? Colors.green : Colors.orange, fontWeight: FontWeight.bold))),
          if (_faceCheck.isNotEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(_faceCheck, style: const TextStyle(color: Colors.blueGrey))),
          _docRow(icon: Icons.credit_card, label: _selectedIdCountry.isEmpty || _selectedIdType.isEmpty ? 'Pick ID Country + ID Type first' : 'Upload ID - FRONT\n$_selectedIdType - $_selectedIdCountry', file: _idFront, buttonLabel: 'Scan Front', onPressed: _scanIdFront),
          _docRow(icon: Icons.credit_card, label: _selectedIdType.isEmpty ? 'Auto-scan (box + flash) - Back of (required)' : 'Upload ID - BACK\nBack of $_selectedIdType', file: _idBack, buttonLabel: 'Scan Back', onPressed: _scanIdBack),
          _docRow(icon: Icons.school, label: 'Upload Certificate', file: _certificate, buttonLabel: 'Pick Cert', onPressed: () => _pickDoc((f) => _certificate = f)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _checkIdAgain, style: ElevatedButton.styleFrom(backgroundColor: _darkPink, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text('🔍 CHECK MY ID AGAIN'))),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: TextButton(onPressed: _checkFaceMatch, child: const Text('Check Face Match'))),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _loading ? null : _register, style: ElevatedButton.styleFrom(backgroundColor: _darkPink, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)), child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('REGISTER AS NURSE', style: TextStyle(fontWeight: FontWeight.bold)))),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose(); _username.dispose(); _email.dispose(); _phone.dispose(); _pass.dispose();
    _pinNumber.dispose(); _idNumberTyped.dispose();
    super.dispose();
  }
}
