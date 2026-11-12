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
  int _step = 1;
  bool _loading = false;
  bool _showPass = false;
  String _msg = '';

  // Files - stored as bytes so e work for Web + Mobile
  Uint8List? _photoBytes; String? _photoName;
  Uint8List? _videoBytes; String? _videoName;
  Uint8List? _pinBytes; String? _pinName;
  Uint8List? _certBytes; String? _certName;
  Uint8List? _cvBytes; String? _cvName;
  Uint8List? _cardFrontBytes; String? _cardFrontName;
  Uint8List? _cardBackBytes; String? _cardBackName;

  final _picker = ImagePicker();

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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: isDone ? Colors.green : Colors.grey.shade300), borderRadius: BorderRadius.circular(12), color: isDone ? Colors.green.shade50 : Colors.white),
      child: Row(children: [
        Icon(icon, color: isDone ? Colors.green : Colors.grey),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(fileName ?? 'No file yet - Required', style: TextStyle(fontSize: 11, color: isDone ? Colors.green : Colors.red)),
        ])),
        ElevatedButton(onPressed: onPick, child: Text(isDone ? 'Change' : 'Upload')),
      ]),
    );
  }

  // FIXED: No more hang - timeout + try/catch, no ceoRegistrationCenter query
  Future<String?> _checkExists(String email, String phone) async {
    try {
      final db = FirebaseFirestore.instance;
      final e = email.trim().toLowerCase(); final p = phone.trim();
      final n1 = await db.collection('nurses').where('email', isEqualTo: e).limit(1).get().timeout(const Duration(seconds: 8));
      if (n1.docs.isNotEmpty) return 'nurse';
      final n2 = await db.collection('pending_nurses').where('email', isEqualTo: e).limit(1).get().timeout(const Duration(seconds: 8));
      if (n2.docs.isNotEmpty) return 'pending_nurse';
      final c1 = await db.collection('clients').where('email', isEqualTo: e).limit(1).get().timeout(const Duration(seconds: 8));
      if (c1.docs.isNotEmpty) return 'client';
      final c2 = await db.collection('clients').where('phone', isEqualTo: p).limit(1).get().timeout(const Duration(seconds: 8));
      if (c2.docs.isNotEmpty) return 'client';
      return null;
    } catch (e) {
      return null; // If check fail, allow to continue, no hang
    }
  }

  Future<String?> _uploadFile(String uid, String path, Uint8List bytes) async {
    final ref = FirebaseStorage.instance.ref().child('nurses/$uid/$path');
    await ref.putData(bytes);
    return await ref.getDownloadURL();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final phone = _phoneCtrl.text.trim();
    final pass = _passCtrl.text;
    if (name.isEmpty || email.isEmpty || phone.isEmpty || pass.isEmpty) { setState(() => _msg = 'Fill all fields in Step 1'); return; }
    if (_photoBytes == null || _videoBytes == null || _pinBytes == null || _certBytes == null || _cvBytes == null || _cardFrontBytes == null || _cardBackBytes == null) {
      setState(() => _msg = 'Upload ALL 7 files: Photo, Video, PIN, Certificate, CV, Ghana Card Front + Back');
      return;
    }
    setState(() { _loading = true; _msg = 'Checking double account...'; });
    final exists = await _checkExists(email, phone);
    if (exists != null) { setState(() { _loading = false; _msg = 'BLOCKED: Already exists as $exists. Use Login.'; }); return; }

    String? uid;
    try {
      setState(() => _msg = 'Creating account...');
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
      uid = cred.user!.uid;
      setState(() => _msg = 'Uploading documents... please wait...');
      final photoUrl = await _uploadFile(uid, 'photo.jpg', _photoBytes!);
      final videoUrl = await _uploadFile(uid, 'video.mp4', _videoBytes!);
      final pinUrl = await _uploadFile(uid, 'pin.jpg', _pinBytes!);
      final certUrl = await _uploadFile(uid, 'certificate.pdf', _certBytes!);
      final cvUrl = await _uploadFile(uid, 'cv.pdf', _cvBytes!);
      final frontUrl = await _uploadFile(uid, 'ghana_card_front.jpg', _cardFrontBytes!);
      final backUrl = await _uploadFile(uid, 'ghana_card_back.jpg', _cardBackBytes!);

      final data = {
        'uid': uid, 'name': name, 'email': email, 'phone': phone, 'role': 'nurse',
        'photoUrl': photoUrl, 'videoUrl': videoUrl, 'pinUrl': pinUrl, 'certificateUrl': certUrl, 'cvUrl': cvUrl,
        'ghanaCardFrontUrl': frontUrl, 'ghanaCardBackUrl': backUrl,
        'hasPhoto': true, 'hasVideo': true, 'hasPhone': true, 'hasPin': true, 'hasCertificate': true, 'hasCv': true, 'hasGhanaCard': true,
        'isComplete': true, 'isApproved': false, 'approved': false, 'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).set(data);
      await FirebaseAuth.instance.signOut();
      setState(() { _loading = false; _msg = '✅ Submitted! All documents uploaded. Waiting for CEO Approval.'; });
    } catch (e) {
      try { if (uid != null) await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).delete(); } catch (_) {}
      try { final u = FirebaseAuth.instance.currentUser; if (u != null) await u.delete(); } catch (_) {}
      try { await FirebaseAuth.instance.signOut(); } catch (_) {}
      setState(() { _loading = false; _msg = 'Failed - cleaned up. Try again. $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nurse Registration')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Nurse Registration', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Text('CEO APPROVAL REQUIRED - Upload all documents', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 16),
        if (_step == 1) ...[
          TextField(controller: _nameCtrl, decoration: const InputDecoration(hintText: 'Full Name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _emailCtrl, decoration: const InputDecoration(hintText: 'Email', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _phoneCtrl, decoration: const InputDecoration(hintText: 'Phone', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _passCtrl, obscureText: !_showPass, decoration: InputDecoration(hintText: 'Password', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPass = !_showPass)))),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () => setState(() => _step = 2), child: const Text('Next - Upload Documents')),
        ],
        if (_step == 2) ...[
          const Text('WHERE TO UPLOAD - Tap Upload for each one:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _uploadTile('1. Profile Photo', _photoName, _photoBytes != null, () => _pickImage((b, n) => {_photoBytes = b, _photoName = n}), Icons.photo),
          _uploadTile('2. Intro Video (30 sec)', _videoName, _videoBytes != null, _pickVideo, Icons.videocam),
          _uploadTile('3. PIN Card / Nursing PIN', _pinName, _pinBytes != null, () => _pickImage((b, n) => {_pinBytes = b, _pinName = n}), Icons.badge),
          _uploadTile('4. Certificate', _certName, _certBytes != null, () => _pickFile((b, n) => {_certBytes = b, _certName = n}, ['pdf', 'jpg', 'png']), Icons.school),
          _uploadTile('5. CV / Resume', _cvName, _cvBytes != null, () => _pickFile((b, n) => {_cvBytes = b, _cvName = n}, ['pdf', 'doc', 'docx']), Icons.description),
          _uploadTile('6. Ghana Card - Front', _cardFrontName, _cardFrontBytes != null, () => _pickImage((b, n) => {_cardFrontBytes = b, _cardFrontName = n}), Icons.credit_card),
          _uploadTile('7. Ghana Card - Back', _cardBackName, _cardBackBytes != null, () => _pickImage((b, n) => {_cardBackBytes = b, _cardBackName = n}), Icons.credit_card),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _loading ? null : _submit, child: Text(_loading ? 'Uploading...' : 'Submit for CEO Approval')),
          TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Back')),
        ],
        if (_msg.isNotEmpty) ...[const SizedBox(height: 12), Text(_msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 13))],
      ])),
    );
  }
}
