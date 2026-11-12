import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

class NurseRegistrationPage extends StatefulWidget {
  const NurseRegistrationPage({super.key});
  @override
  State<NurseRegistrationPage> createState() => _NurseRegistrationPageState();
}

class _NurseRegistrationPageState extends State<NurseRegistrationPage> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _cardNumberCtrl = TextEditingController();
  final _cardNameCtrl = TextEditingController();
  int _step = 1;
  bool _loading = false;
  bool _showPass = false;
  String _msg = '';
  String _passMsg = '';

  // 1. COUNTRY CODE
  String _countryCode = '+233';
  final _codes = ['+233', '+234', '+225', '+228', '+44', '+1', '+33', '+49', '+27'];
  final _codeNames = {'+233': 'Ghana', '+234': 'Nigeria', '+225': "Côte d'Ivoire", '+228': 'Togo', '+44': 'UK', '+1': 'USA/Canada', '+33': 'France', '+49': 'Germany', '+27': 'South Africa'};

  Uint8List? _photoBytes; String? _photoName;
  Uint8List? _videoBytes; String? _videoName;
  Uint8List? _pinBytes; String? _pinName;
  Uint8List? _certBytes; String? _certName;
  Uint8List? _cvBytes; String? _cvName;
  Uint8List? _cardFrontBytes; String? _cardFrontName;
  Uint8List? _cardBackBytes; String? _cardBackName;

  final _picker = ImagePicker();

  // 3. STRONG PASSWORD CHECK
  String _checkPassword(String p) {
    if (p.isEmpty) return '';
    if (p.length < 8) return '❌ Too short - Need 8+ characters';
    if (!RegExp(r'[A-Z]').hasMatch(p)) return '❌ Add 1 CAPITAL letter (A-Z)';
    if (!RegExp(r'[a-z]').hasMatch(p)) return '❌ Add 1 small letter (a-z)';
    if (!RegExp(r'[0-9]').hasMatch(p)) return '❌ Add 1 number (0-9)';
    if (!RegExp(r'[!@#\$%^&*]').hasMatch(p)) return '❌ Add 1 symbol (!@#\$ etc)';
    return '✅ Strong Password - Good!';
  }
  bool get _isStrong => _checkPassword(_passCtrl.text).startsWith('✅');
  Color get _passColor => _isStrong ? Colors.green : (_passCtrl.text.length < 4 ? Colors.red : Colors.orange);
  double get _passStrength {
    var s = 0.0;
    if (_passCtrl.text.length >= 8) s += 0.2;
    if (RegExp(r'[A-Z]').hasMatch(_passCtrl.text)) s += 0.2;
    if (RegExp(r'[a-z]').hasMatch(_passCtrl.text)) s += 0.2;
    if (RegExp(r'[0-9]').hasMatch(_passCtrl.text)) s += 0.2;
    if (RegExp(r'[!@#\$%^&*]').hasMatch(_passCtrl.text)) s += 0.2;
    return s;
  }

  // 2. GHANA CARD AUTO-CHECK
  String _checkGhanaCard() {
    final num = _cardNumberCtrl.text.trim().toUpperCase();
    final nameOnCard = _cardNameCtrl.text.trim().toLowerCase();
    final regName = _nameCtrl.text.trim().toLowerCase();
    if (num.isEmpty || nameOnCard.isEmpty) return 'Enter Card Number + Name on Card';
    if (!RegExp(r'^GHA-\d{9}-\d$').hasMatch(num)) return '❌ Wrong format! Use GHA-123456789-0';
    if (nameOnCard != regName) return '❌ Name on Card ($nameOnCard) no match Registration Name ($regName)! Check am.';
    if (_cardFrontBytes == null || _cardBackBytes == null) return '❌ Upload Ghana Card Front + Back';
    return '✅ ID Check PASSED - Name + Format Match. CEO go do final check.';
  }

  Future<void> _pickImage(Function(Uint8List?, String?) setFile) async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (x == null) return;
    final b = await x.readAsBytes();
    setState(() => setFile(b, x.name));
  }
  Future<void> _pickFile(Function(Uint8List?, String?) setFile, List<String> ext) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ext, withData: true);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    if (f.bytes == null) return;
    setState(() => setFile(f.bytes, f.name));
  }
  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    final b = await x.readAsBytes();
    setState(() { _videoBytes = b; _videoName = x.name; });
  }
  Widget _uploadTile(String title, String? fileName, bool isDone, VoidCallback onPick, IconData icon) {
    return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: isDone ? Colors.green : Colors.grey.shade300), borderRadius: BorderRadius.circular(12), color: isDone ? Colors.green.shade50 : Colors.white),
      child: Row(children: [Icon(icon, color: isDone ? Colors.green : Colors.grey), const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Text(fileName ?? 'No file yet - Required', style: TextStyle(fontSize: 11, color: isDone ? Colors.green : Colors.red))])),
        ElevatedButton(onPressed: onPick, child: Text(isDone ? 'Change' : 'Upload'))]));
  }
  Future<String?> _checkExists(String email, String phone) async {
    try {
      final db = FirebaseFirestore.instance; final e = email.trim().toLowerCase(); final p = phone.trim();
      final n1 = await db.collection('nurses').where('email', isEqualTo: e).limit(1).get().timeout(const Duration(seconds: 8));
      if (n1.docs.isNotEmpty) return 'nurse';
      final n2 = await db.collection('pending_nurses').where('email', isEqualTo: e).limit(1).get().timeout(const Duration(seconds: 8));
      if (n2.docs.isNotEmpty) return 'pending_nurse';
      final c1 = await db.collection('clients').where('email', isEqualTo: e).limit(1).get().timeout(const Duration(seconds: 8));
      if (c1.docs.isNotEmpty) return 'client';
      return null;
    } catch (_) { return null; }
  }
  Future<String?> _uploadFile(String uid, String path, Uint8List bytes) async {
    final ref = FirebaseStorage.instance.ref().child('nurses/$uid/$path');
    await ref.putData(bytes);
    return await ref.getDownloadURL();
  }
  Future<void> _submit() async {
    final name = _nameCtrl.text.trim(); final email = _emailCtrl.text.trim().toLowerCase();
    final phone = '$_countryCode${_phoneCtrl.text.trim()}'; // Full number with code
    final pass = _passCtrl.text;
    if (name.isEmpty || email.isEmpty || _phoneCtrl.text.trim().isEmpty || pass.isEmpty) { setState(() => _msg = 'Fill all fields in Step 1'); return; }
    if (!_isStrong) { setState(() => _msg = 'Password too weak! Fix am: $_passMsg'); return; }
    final idCheck = _checkGhanaCard();
    if (!idCheck.startsWith('✅')) { setState(() => _msg = idCheck); return; }
    if (_photoBytes == null || _videoBytes == null || _pinBytes == null || _certBytes == null || _cvBytes == null) { setState(() => _msg = 'Upload ALL files: Photo, Video, PIN, Certificate, CV'); return; }
    setState(() { _loading = true; _msg = 'Checking double account...'; });
    final exists = await _checkExists(email, phone);
    if (exists != null) { setState(() { _loading = false; _msg = 'BLOCKED: Already exists as $exists. Use Login.'; }); return; }
    String? uid;
    try {
      setState(() => _msg = 'Creating account...');
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
      uid = cred.user!.uid;
      setState(() => _msg = 'Uploading documents...');
      final photoUrl = await _uploadFile(uid, 'photo.jpg', _photoBytes!);
      final videoUrl = await _uploadFile(uid, 'video.mp4', _videoBytes!);
      final pinUrl = await _uploadFile(uid, 'pin.jpg', _pinBytes!);
      final certUrl = await _uploadFile(uid, 'certificate.pdf', _certBytes!);
      final cvUrl = await _uploadFile(uid, 'cv.pdf', _cvBytes!);
      final frontUrl = await _uploadFile(uid, 'ghana_card_front.jpg', _cardFrontBytes!);
      final backUrl = await _uploadFile(uid, 'ghana_card_back.jpg', _cardBackBytes!);
      final data = {'uid': uid, 'name': name, 'email': email, 'phone': phone, 'countryCode': _countryCode, 'role': 'nurse',
        'photoUrl': photoUrl, 'videoUrl': videoUrl, 'pinUrl': pinUrl, 'certificateUrl': certUrl, 'cvUrl': cvUrl,
        'ghanaCardFrontUrl': frontUrl, 'ghanaCardBackUrl': backUrl, 'ghanaCardNumber': _cardNumberCtrl.text.trim().toUpperCase(), 'ghanaCardName': _cardNameCtrl.text.trim(),
        'idAutoCheck': 'PASSED - Name + Format Match', 'idAutoCheckAt': FieldValue.serverTimestamp(),
        'hasPhoto': true, 'hasVideo': true, 'hasPhone': true, 'hasPin': true, 'hasCertificate': true, 'hasCv': true, 'hasGhanaCard': true,
        'isComplete': true, 'isApproved': false, 'approved': false, 'status': 'pending', 'createdAt': FieldValue.serverTimestamp()};
      await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).set(data);
      await FirebaseAuth.instance.signOut();
      setState(() { _loading = false; _msg = '✅ Submitted! Strong password + ID Check PASSED. Waiting CEO Approval.'; });
    } catch (e) {
      try { if (uid != null) await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).delete(); } catch (_) {}
      try { final u = FirebaseAuth.instance.currentUser; if (u != null) await u.delete(); } catch (_) {}
      try { await FirebaseAuth.instance.signOut(); } catch (_) {}
      setState(() { _loading = false; _msg = 'Failed - cleaned up. Try again. $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Nurse Registration')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Nurse Registration', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Text('CEO APPROVAL REQUIRED - Upload all documents', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 16),
        if (_step == 1) ...[
          TextField(controller: _nameCtrl, decoration: const InputDecoration(hintText: 'Full Name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _emailCtrl, decoration: const InputDecoration(hintText: 'Email', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          // COUNTRY CODE + PHONE
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
              child: DropdownButton<String>(value: _countryCode, underline: const SizedBox(), items: _codes.map((c) => DropdownMenuItem(value: c, child: Text('$c ${_codeNames[c]}'))).toList(), onChanged: (v) => setState(() => _countryCode = v ?? '+233'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: 'Phone e.g. 241234567', border: OutlineInputBorder()))),
          ]),
          Text('Saved as: $_countryCode${_phoneCtrl.text}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 12),
          // STRONG PASSWORD
          TextField(controller: _passCtrl, obscureText: !_showPass, onChanged: (v) => setState(() => _passMsg = _checkPassword(v)),
            decoration: InputDecoration(hintText: 'Password - Strong Required', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPass = !_showPass)))),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: _passStrength, backgroundColor: Colors.grey.shade200, color: _passColor, minHeight: 6),
          const SizedBox(height: 4),
          Text(_passMsg.isEmpty ? 'Need: 8+ chars, 1 CAPITAL, 1 small, 1 number, 1 symbol (!@#)' : _passMsg, style: TextStyle(fontSize: 12, color: _passColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () {
            if (!_isStrong) { setState(() => _msg = 'Fix password first! $_passMsg'); return; }
            if (_nameCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) { setState(() => _msg = 'Fill Name, Email, Phone'); return; }
            setState(() { _msg = ''; _step = 2; });
          }, child: const Text('Next - Upload Documents')),
        ],
        if (_step == 2) ...[
          const Text('WHERE TO UPLOAD - Tap Upload for each one:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _uploadTile('1. Profile Photo', _photoName, _photoBytes != null, () => _pickImage((b, n) => {_photoBytes = b, _photoName = n}), Icons.photo),
          _uploadTile('2. Intro Video (30 sec)', _videoName, _videoBytes != null, _pickVideo, Icons.videocam),
          _uploadTile('3. PIN Card / Nursing PIN', _pinName, _pinBytes != null, () => _pickImage((b, n) => {_pinBytes = b, _pinName = n}), Icons.badge),
          _uploadTile('4. Certificate', _certName, _certBytes != null, () => _pickFile((b, n) => {_certBytes = b, _certName = n}, ['pdf', 'jpg', 'png']), Icons.school),
          _uploadTile('5. CV / Resume', _cvName, _cvBytes != null, () => _pickFile((b, n) => {_cvBytes = b, _cvName = n}, ['pdf', 'doc', 'docx']), Icons.description),
          const SizedBox(height: 8),
          const Text('6 + 7. GHANA CARD - AUTO CHECK', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _cardNameCtrl, decoration: const InputDecoration(hintText: 'Name Exactly As On Ghana Card', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _cardNumberCtrl, decoration: const InputDecoration(hintText: 'Ghana Card No: GHA-123456789-0', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          _uploadTile('6. Ghana Card - Front', _cardFrontName, _cardFrontBytes != null, () => _pickImage((b, n) => {_cardFrontBytes = b, _cardFrontName = n}), Icons.credit_card),
          _uploadTile('7. Ghana Card - Back', _cardBackName, _cardBackBytes != null, () => _pickImage((b, n) => {_cardBackBytes = b, _cardBackName = n}), Icons.credit_card),
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)), child: Text(_checkGhanaCard(), style: const TextStyle(fontSize: 12))),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _loading ? null : _submit, child: Text(_loading ? 'Uploading...' : 'Submit for CEO Approval')),
          TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Back')),
        ],
        if (_msg.isNotEmpty) ...[const SizedBox(height: 12), Text(_msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 13))],
      ])),
    );
  }
}
