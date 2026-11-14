
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

// DARK PINK THEME - same as rest of app
const Color kDarkPink = Color(0xFF880E4F);
const Color kPink = Color(0xFFAD1457);
const Color kSoftPink = Color(0xFFFCE4EC);
const Color kLightBg = Color(0xFFFFF5F8);

// PASTE YOUR REAL KEY HERE when you get it from Google Cloud.
// If this stays as placeholder, registration still works - CEO checks ID manually.
const String kVisionApiKey = 'PASTE_YOUR_GOOGLE_VISION_API_KEY_HERE';

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
  final _pin = TextEditingController();
  final _idNumber = TextEditingController();
  final _picker = ImagePicker();

  XFile? _photo;
  XFile? _video;
  XFile? _cv;
  XFile? _pinDoc;
  XFile? _idFront;
  XFile? _idBack;
  XFile? _certificate;

  bool _loading = false;
  bool _obscure = true;
  String _idCheck = '';
  bool _idVerified = false;
  int _idScore = 0;
  String _idTypeDetected = '';
  bool _faceMatch = false;
  String _faceCheck = '';

  // Phone country code - default Ghana +233, Other lets nurse type code
  String _phoneCode = '+233';
  String _phoneCountry = 'Ghana';
  final List<Map<String,String>> _phoneCodes = [
    {'c':'Ghana','code':'+233'},{'c':'Nigeria','code':'+234'},{'c':'Kenya','code':'+254'},
    {'c':'South Africa','code':'+27'},{'c':'Togo','code':'+228'},{'c':'Benin','code':'+229'},
    {'c':'Burkina Faso','code':'+226'},{'c':'Ivory Coast','code':'+225'},{'c':'Senegal','code':'+221'},
    {'c':'Sierra Leone','code':'+232'},{'c':'Liberia','code':'+231'},{'c':'Cameroon','code':'+237'},
    {'c':'United Kingdom','code':'+44'},{'c':'United States','code':'+1'},{'c':'Canada','code':'+1'},
    {'c':'India','code':'+91'},{'c':'Australia','code':'+61'},{'c':'France','code':'+33'},
    {'c':'Germany','code':'+49'},{'c':'Other','code':'+'},
  ];

  // ID Country (citizenship) -> real local ID names. Unknown countries get generic list.
  String _idCountry = 'Ghana';
  String _idType = 'Ghana Card';
  final Map<String, List<String>> _idsByCountry = {
    'Ghana': ['Ghana Card', 'Passport', 'Voter ID Card', 'Driving Licence'],
    'Nigeria': ['National ID Card (NIN)', 'Passport', 'Voter Card', 'Driving Licence'],
    'Kenya': ['National ID Card', 'Passport', 'Voter Card', 'Driving Licence'],
    'South Africa': ['Smart ID Card', 'Passport', 'Driving Licence'],
    'Togo': ['National ID Card', 'Passport', 'Voter Card', 'Driving Licence'],
    'Benin': ['National ID Card', 'Passport', 'Voter Card', 'Driving Licence'],
    'Burkina Faso': ['National ID Card (CNIB)', 'Passport', 'Voter Card', 'Driving Licence'],
    'Ivory Coast': ['National ID Card (CNI)', 'Passport', 'Voter Card', 'Driving Licence'],
    'Senegal': ['National ID Card (CNI)', 'Passport', 'Voter Card', 'Driving Licence'],
    'Sierra Leone': ['National ID Card', 'Passport', 'Voter Card', 'Driving Licence'],
    'Liberia': ['National ID Card', 'Passport', 'Voter Card', 'Driving Licence'],
    'Cameroon': ['National ID Card (CNI)', 'Passport', 'Voter Card', 'Driving Licence'],
    'United Kingdom': ['Passport', 'Driving Licence', 'National ID'],
    'United States': ['Passport', 'Driving Licence', 'State ID'],
    'Canada': ['Passport', 'Driving Licence', 'National ID'],
    'India': ['Aadhaar Card', 'Passport', 'Voter ID Card', 'Driving Licence'],
    'Australia': ['Passport', 'Driving Licence', 'National ID'],
    'France': ['National ID Card (CNI)', 'Passport', 'Driving Licence'],
    'Germany': ['National ID Card', 'Passport', 'Driving Licence'],
  };
  List<String> get _genericIds => ['Passport', 'National ID', 'Voter ID Card', 'Driving Licence'];
  List<String> get _idTypesForCountry => _idsByCountry[_idCountry] ?? _genericIds;
  List<String> get _idCountries => [..._idsByCountry.keys, 'Gambia', 'Mali', 'Guinea', 'Niger', 'Chad', 'Other'];

  String _passwordStrength(String p) {
    if (p.isEmpty) return '';
    if (p.length < 6) return 'Weak - use at least 6 characters';
    bool hasUpper = p.contains(RegExp(r'[A-Z]'));
    bool hasDigit = p.contains(RegExp(r'[0-9]'));
    bool hasSymbol = p.contains(RegExp(r'[^A-Za-z0-9]'));
    if (p.length >= 8 && hasUpper && hasDigit && hasSymbol) return 'Strong password';
    if (p.length >= 8 && (hasUpper || hasDigit)) return 'Good - add a symbol for Strong';
    return 'Fair - add uppercase, number and symbol';
  }

  // ---------- SCAN ID - CAMERA ONLY, NOT GALLERY ----------
  Future<void> _scanIdSide(bool isFront) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isFront ? 'Scan ID - FRONT' : 'Scan ID - BACK'),
        content: const Text('1. Hold your REAL card flat, not a photo of a photo\n2. Good light, no shadow, no glare\n3. All 4 corners must be visible\n4. Do not cover your name / number / photo'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open Camera')),
        ],
      ),
    );
    if (go != true) return;
    final f = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, preferredCameraDevice: CameraDevice.rear);
    if (f == null) return;
    setState(() {
      if (isFront) _idFront = f; else _idBack = f;
      _idVerified = false; _idScore = 0; _idCheck = ''; _faceMatch = false; _faceCheck = '';
    });
    // Scan straight away - send this fresh photo to Vision
    await _checkIdWithVision();
  }

  Future<void> _pickFile(void Function(XFile f) set) async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (f != null) setState(() => set(f));
  }

  // ---------- GOOGLE VISION: OCR + FACE ----------
  Future<Map<String, dynamic>?> _visionAnnotate(Uint8List bytes) async {
    if (kVisionApiKey == 'PASTE_YOUR_GOOGLE_VISION_API_KEY_HERE' || kVisionApiKey.isEmpty) return null;
    try {
      final res = await http.post(
        Uri.parse('https://vision.googleapis.com/v1/images:annotate?key=$kVisionApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'requests': [{'image': {'content': base64Encode(bytes)}, 'features': [{'type': 'TEXT_DETECTION'}, {'type': 'FACE_DETECTION', 'maxResults': 5}]}]}),
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['responses'] as List?;
      if (list == null || list.isEmpty) return {};
      return list[0] as Map<String, dynamic>;
    } catch (_) { return null; }
  }

  Future<void> _checkIdWithVision() async {
    if (_idFront == null) { setState(() => _idCheck = 'Please Scan Front of your ID first'); return; }
    if (_idNumber.text.trim().isEmpty) { setState(() => _idCheck = 'Please type your ID Number as printed on your ID'); return; }
    setState(() => _idCheck = 'Checking ID, please wait...');
    // NO KEY -> DO NOT BLOCK. Send to CEO for manual check.
    if (kVisionApiKey == 'PASTE_YOUR_GOOGLE_VISION_API_KEY_HERE' || kVisionApiKey.isEmpty) {
      setState(() {
        _idTypeDetected = 'ID (manual CEO check)';
        _idVerified = true; // allow registration - CEO checks manually
        _idScore = 0;
        _idCheck = 'Auto-check not set up yet. Your ID was sent to CEO for manual check. You can register now.';
        _faceCheck = 'Face match will be checked by CEO';
      });
      return;
    }
    try {
      final bytes = await _idFront!.readAsBytes();
      final resp = await _visionAnnotate(bytes);
      if (resp == null) {
        setState(() { _idTypeDetected = 'ID (manual CEO check)'; _idVerified = true; _idCheck = 'Could not reach ID check service. Your ID was sent to CEO for manual check.'; });
        return;
      }
      final text = (((resp['textAnnotations'] as List?)?.isNotEmpty ?? false) ? (resp['textAnnotations'][0]['description'] as String? ?? '') : '').toUpperCase();
      final compact = text.replaceAll(RegExp(r'\s+'), ' ');
      final typedNum = _idNumber.text.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
      final textCompact = compact.replaceAll(RegExp(r'[\s-]'), '');
      int score = 0; List<String> ok = []; List<String> bad = [];
      if (textCompact.contains(typedNum) && typedNum.length >= 5) { score += 40; ok.add('ID number matches'); } else { bad.add('ID number on photo does not match what you typed'); }
      if (text.contains(_idCountry.toUpperCase())) { score += 20; ok.add('Country matches'); } else { bad.add('Country on ID does not look like $_idCountry'); }
      final typeWords = _idType.toUpperCase().split(' ');
      if (typeWords.any((w) => w.length > 3 && text.contains(w))) { score += 20; ok.add('ID type looks right'); } else { bad.add('ID type on photo does not look like $_idType'); }
      if (_name.text.trim().isNotEmpty) {
        final firstName = _name.text.trim().split(' ').first.toUpperCase();
        if (firstName.length >= 3 && text.contains(firstName)) { score += 20; ok.add('Name matches'); } else { bad.add('Name on ID does not match your name'); }
      }
      // Face: did Vision find a face on the ID?
      final faces = resp['faceAnnotations'] as List?;
      bool idHasFace = faces != null && faces.isNotEmpty;
      // Face match: compare ID face vs profile photo face (presence + count). Full embedding compare needs a face-match service; CEO does final check.
      _faceMatch = false; _faceCheck = '';
      if (_photo != null && idHasFace) {
        final pResp = await _visionAnnotate(await _photo!.readAsBytes());
        final pFaces = pResp?['faceAnnotations'] as List?;
        if (pFaces != null && pFaces.isNotEmpty) { _faceMatch = true; _faceCheck = 'Face found on ID and on profile photo - CEO will confirm they are the same person'; }
        else { _faceCheck = 'No face found on your profile photo - take a clear face photo'; }
      } else if (!idHasFace) { _faceCheck = 'No face found on ID photo - scan again with better light'; }
      setState(() {
        _idScore = score; _idTypeDetected = _idType;
        if (score >= 80) { _idVerified = true; _idCheck = 'ID check passed ($score/100). ${ok.join(', ')}. $_faceCheck'; }
        else { _idVerified = false; _idCheck = 'ID check failed ($score/100). ${bad.join('. ')}. Please scan again or check your details.'; }
      });
    } catch (e) {
      setState(() { _idTypeDetected = 'ID (manual CEO check)'; _idVerified = true; _idCheck = 'ID check service had a problem. Your ID was sent to CEO for manual check.'; });
    }
  }

  Future<String> _upload(XFile f, String path) async {
    final ref = FirebaseStorage.instance.ref().child(path);
    await ref.putData(await f.readAsBytes());
    return await ref.getDownloadURL();
  }

  Future<void> _register() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty || _phone.text.trim().isEmpty || _pass.text.length < 6 || _pin.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill Name, Email, Phone, Password (6+) and Nursing PIN'))); return;
    }
    if (_idFront == null || _idBack == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please Scan Front and Back of your ID'))); return; }
    if (!_idVerified) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please tap CHECK MY ID first and make sure it passes'))); return; }
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: _email.text.trim(), password: _pass.text.trim());
      final uid = cred.user!.uid;
      String photoUrl = ''; String idFrontUrl = ''; String idBackUrl = ''; String certUrl = '';
      if (_photo != null) photoUrl = await _upload(_photo!, 'nurses/$uid/profile.jpg');
      idFrontUrl = await _upload(_idFront!, 'nurses/$uid/id_front.jpg');
      idBackUrl = await _upload(_idBack!, 'nurses/$uid/id_back.jpg');
      if (_certificate != null) certUrl = await _upload(_certificate!, 'nurses/$uid/certificate.jpg');
      await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).set({
        'uid': uid, 'name': _name.text.trim(), 'username': _username.text.trim(), 'email': _email.text.trim(),
        'phone': '$_phoneCode${_phone.text.trim()}', 'phoneCountry': _phoneCountry, 'phoneCode': _phoneCode,
        'pin': _pin.text.trim(), 'photoUrl': photoUrl,
        'idCountry': _idCountry, 'idType': _idType, 'idNumber': _idNumber.text.trim(),
        'idFrontUrl': idFrontUrl, 'idBackUrl': idBackUrl, 'certificateUrl': certUrl,
        'idCheck': _idCheck, 'idScore': _idScore, 'idVerified': _idVerified, 'idTypeDetected': _idTypeDetected,
        'faceMatch': _faceMatch, 'faceCheck': _faceCheck, 'idVerification': _idScore == 0 ? 'manual_ceo_check' : 'vision_auto_check',
        'status': 'pending', 'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
        title: const Text('Registration Sent'),
        content: const Text('Your registration was sent. Please wait for CEO approval before you can login.'),
        actions: [TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text('OK'))],
      ));
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Registration failed')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Widget _field(IconData icon, String label, TextEditingController c, {bool obscure = false, TextInputType? type, Widget? suffix}) {
    return TextField(controller: c, obscureText: obscure, keyboardType: type, decoration: InputDecoration(prefixIcon: Icon(icon, color: kDarkPink), labelText: label, suffixIcon: suffix, border: const OutlineInputBorder()));
  }
  Widget _idRow(String label, String sub, XFile? file, String btn, VoidCallback onTap) {
    return ListTile(leading: const Icon(Icons.credit_card, color: kDarkPink), title: Text(label), subtitle: Text(file == null ? sub : 'Selected: ${file.name}\n$sub'), trailing: ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(backgroundColor: kSoftPink, foregroundColor: kDarkPink, minimumSize: const Size(0, 36)), child: Text(btn)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: kLightBg, appBar: AppBar(backgroundColor: kDarkPink, foregroundColor: Colors.white, leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)), title: const Text('Nurse Registration')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _field(Icons.person, 'Full Name', _name), const SizedBox(height: 12),
        _field(Icons.account_circle, 'Username', _username), const SizedBox(height: 12),
        _field(Icons.email, 'Email', _email, type: TextInputType.emailAddress), const SizedBox(height: 12),
        // Phone: country code + number
        Row(children: [
          Expanded(flex: 2, child: DropdownButtonFormField<String>(value: _phoneCountry, decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder()), items: _phoneCodes.map((m) => DropdownMenuItem(value: m['c'], child: Text('${m['c']} (${m['code']})'))).toList(), onChanged: (v) { if (v == null) return; final m = _phoneCodes.firstWhere((e) => e['c'] == v); setState(() { _phoneCountry = v; _phoneCode = m['code']!; }); })),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: _field(Icons.phone, 'Phone Number', _phone, type: TextInputType.phone)),
        ]), const SizedBox(height: 12),
        _field(Icons.lock, 'Password', _pass, obscure: _obscure, suffix: IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscure = !_obscure))),
        if (_pass.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_passwordStrength(_pass.text), style: TextStyle(color: _passwordStrength(_pass.text).startsWith('Strong') ? Colors.green : Colors.orange))),
        const SizedBox(height: 12),
        _field(Icons.badge, 'Nursing PIN', _pin), const SizedBox(height: 20),
        const Text('ID - SCAN with camera (not upload)', style: TextStyle(fontWeight: FontWeight.bold, color: kDarkPink)),
        const SizedBox(height: 8),
        // ID SCAN FIRST
        _idRow('Scan $_idType - FRONT', 'Front of $_idType ($_idCountry)', _idFront, 'Scan Front', () => _scanIdSide(true)),
        _idRow('Scan $_idType - BACK', 'Back of $_idType (required)', _idBack, 'Scan Back', () => _scanIdSide(false)),
        const SizedBox(height: 12),
        // THEN ID Country / Type / Number - under the Scan buttons
        DropdownButtonFormField<String>(value: _idCountry, decoration: const InputDecoration(labelText: 'ID Country (citizenship)', border: OutlineInputBorder()), items: _idCountries.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) { if (v == null) return; setState(() { _idCountry = v; _idType = (_idsByCountry[v] ?? _genericIds).first; _idVerified = false; _idCheck = ''; }); }),
        const SizedBox(height: 4), Text('Showing IDs for $_idCountry only', style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _idType, decoration: const InputDecoration(labelText: 'ID Type', border: OutlineInputBorder()), items: _idTypesForCountry.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(), onChanged: (v) { if (v == null) return; setState(() { _idType = v; _idVerified = false; _idCheck = ''; }); }),
        const SizedBox(height: 12),
        _field(Icons.numbers, 'ID Number (as printed on your ID)', _idNumber),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: _checkIdWithVision, style: ElevatedButton.styleFrom(backgroundColor: kDarkPink, foregroundColor: Colors.white, minimumSize: const Size(0, 48)), child: const Text('CHECK MY ID')),
        if (_idCheck.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_idCheck, style: TextStyle(color: _idVerified ? Colors.green.shade800 : Colors.orange.shade800, fontWeight: FontWeight.bold))),
        if (_faceCheck.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_faceCheck)),
        const SizedBox(height: 20),
        const Text('Other Documents', style: TextStyle(fontWeight: FontWeight.bold, color: kDarkPink)), const SizedBox(height: 8),
        _idRow('Profile Photo', 'Clear face photo', _photo, 'Pick Photo', () => _pickFile((f) => _photo = f)),
        _idRow('Upload Certificate', 'Nursing certificate', _certificate, 'Pick Cert', () => _pickFile((f) => _certificate = f)),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: _loading ? null : _register, style: ElevatedButton.styleFrom(backgroundColor: kDarkPink, foregroundColor: Colors.white, minimumSize: const Size(0, 48)), child: Text(_loading ? 'Please wait...' : 'REGISTER AS NURSE')),
        const SizedBox(height: 8), const Text('You must wait for CEO approval after registration before you can login.', textAlign: TextAlign.center),
      ]))),
    );
  }
}
