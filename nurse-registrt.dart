import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Nurse Register - Same logic as PWA nurse-registration.html
/// STRICT CEO APPROVAL: Photo + Phone + ID + Licence + Video REQUIRED, CV optional
/// After register: canLogin=false, isApproved=false -> CEO must approve in CEO Registration Center
class NurseRegisterScreen extends StatefulWidget {
  const NurseRegisterScreen({super.key});
  @override
  State<NurseRegisterScreen> createState() => _NurseRegisterScreenState();
}

class _NurseRegisterScreenState extends State<NurseRegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _countryCtrl = TextEditingController(text: 'Ghana');
  File? photoFile, idFile, licenceFile, videoFile, cvFile;
  bool isLoading = false;
  double progress = 0;
  String status = '';

  final picker = ImagePicker();

  Future<void> _pick(ImageSource src, String type, {bool isVideo = false}) async {
    final XFile? picked = isVideo
        ? await picker.pickVideo(source: src)
        : await picker.pickImage(source: src, imageQuality: 80);
    if (picked == null) return;
    setState(() {
      if (type == 'photo') photoFile = File(picked.path);
      if (type == 'id') idFile = File(picked.path);
      if (type == 'licence') licenceFile = File(picked.path);
      if (type == 'video') videoFile = File(picked.path);
      if (type == 'cv') cvFile = File(picked.path);
    });
  }

  Future<String> _uploadFile(File file, String path) async {
    final ref = FirebaseStorage.instance.ref().child(path);
    final task = ref.putFile(file, SettableMetadata(contentType: file.path.endsWith('.mp4') ? 'video/mp4' : 'image/jpeg'));
    task.snapshotEvents.listen((s) {
      setState(() => progress = s.bytesTransferred / s.totalBytes);
    });
    await task;
    return await ref.getDownloadURL();
  }

  Future<void> _register() async {
    if (_nameCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _phoneCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill all fields')));
      return;
    }
    if (photoFile == null || idFile == null || licenceFile == null || videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo + ID + Licence + Video are REQUIRED. CV is optional.')));
      return;
    }
    setState(() { isLoading = true; status = 'Creating account...'; });
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      final uid = cred.user!.uid;
      setState(() => status = 'Uploading photo...');
      final photoUrl = await _uploadFile(photoFile!, 'nurses/$uid/photo.jpg');
      setState(() => status = 'Uploading ID...');
      final idUrl = await _uploadFile(idFile!, 'nurses/$uid/id.jpg');
      setState(() => status = 'Uploading Licence...');
      final licenceUrl = await _uploadFile(licenceFile!, 'nurses/$uid/licence.jpg');
      setState(() => status = 'Uploading Video (with sound)...');
      final videoUrl = await _uploadFile(videoFile!, 'nurses/$uid/video.mp4');
      String? cvUrl;
      if (cvFile != null) {
        setState(() => status = 'Uploading CV...');
        try { cvUrl = await _uploadFile(cvFile!, 'nurses/$uid/cv.pdf'); } catch (e) { print('CV failed, continuing: $e'); }
      }

      final emailKey = _emailCtrl.text.trim().toLowerCase().replaceAll('.', '_').replaceAll('@', '_');
      final data = {
        'uid': uid,
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'country': _countryCtrl.text.trim(),
        'photoURL': photoUrl, 'photo': photoUrl,
        'idURL': idUrl, 'nationalIdURL': idUrl,
        'licenceURL': licenceUrl, 'licenseURL': licenceUrl,
        'videoURL': videoUrl, 'videoUrl': videoUrl, 'video': videoUrl, 'introVideo': videoUrl,
        'cvURL': cvUrl ?? '',
        'canLogin': false, 'isApproved': false, 'approved': false,
        'status': 'pending', 'needsCEOApproval': true,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      // Save to same RTDB paths as PWA - CEO sees it in CEO Registration Center
      await FirebaseDatabase.instance.ref('nurses/$uid').set(data);
      await FirebaseDatabase.instance.ref('ceoRegistrationCenter/nurses/$uid').set(data);
      await FirebaseDatabase.instance.ref('allowedNurses/$emailKey').set(data);
      await FirebaseDatabase.instance.ref('pending_nurses/$uid').set(data);

      if (!mounted) return;
      showDialog(context: context, builder: (_) => AlertDialog(
        title: const Text('✅ Registered!'),
        content: const Text('Your application is sent to CEO. You CANNOT login until CEO approves you. You will get a notification when approved.'),
        actions: [TextButton(onPressed: () => Navigator.popUntil(context, (r) => r.isFirst), child: const Text('OK'))],
      ));
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Registration failed')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() { isLoading = false; status = ''; });
    }
  }

  Widget _fileTile(String label, File? file, VoidCallback onTap, {bool required = true}) {
    return ListTile(
      leading: Icon(file != null ? Icons.check_circle : Icons.upload_file, color: file != null ? Colors.green : Colors.grey),
      title: Text('$label ${required ? '(REQUIRED)' : '(Optional)'}'),
      subtitle: Text(file != null ? file.path.split('/').last : 'Tap to select'),
      onTap: onTap,
      tileColor: Colors.white10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('👩‍⚕️ Nurse Register')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()), keyboardType: TextInputType.phone),
          const SizedBox(height: 10),
          TextField(controller: _passCtrl, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()), obscureText: true),
          const SizedBox(height: 10),
          TextField(controller: _countryCtrl, decoration: const InputDecoration(labelText: 'Country', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          _fileTile('📸 Photo', photoFile, () => _pick(ImageSource.gallery, 'photo')),
          const SizedBox(height: 8),
          _fileTile('🪪 National ID', idFile, () => _pick(ImageSource.gallery, 'id')),
          const SizedBox(height: 8),
          _fileTile('📜 Licence', licenceFile, () => _pick(ImageSource.gallery, 'licence')),
          const SizedBox(height: 8),
          _fileTile('🎥 Intro Video (with sound)', videoFile, () => _pick(ImageSource.gallery, 'video', isVideo: true)),
          const SizedBox(height: 8),
          _fileTile('📄 CV', cvFile, () => _pick(ImageSource.gallery, 'cv'), required: false),
          const SizedBox(height: 16),
          if (isLoading) ...[LinearProgressIndicator(value: progress), const SizedBox(height: 8), Text(status)],
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: isLoading ? null : _register, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), padding: const EdgeInsets.symmetric(vertical: 16)), child: Text(isLoading ? 'Uploading... ${(progress * 100).toStringAsFixed(0)}%' : 'REGISTER - Send to CEO'))),
          const SizedBox(height: 10),
          TextButton(onPressed: () => Navigator.pushNamed(context, '/login'), child: const Text('Already have account? Login')),
        ]),
      ),
    );
  }
}
