import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

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
  XFile? _photo;
  XFile? _video;
  bool _loading = false;
  final _picker = ImagePicker();

  Future<void> _pickPhoto() async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (f != null) setState(() => _photo = f);
  }

  Future<void> _pickVideo() async {
    final f = await _picker.pickVideo(source: ImageSource.gallery);
    if (f != null) setState(() => _video = f);
  }

  Future<String?> _upload(XFile file, String path) async {
    final ref = FirebaseStorage.instance.ref().child(path);
    // Web: use bytes, Mobile: use file
    final bytes = await file.readAsBytes();
    await ref.putData(bytes, SettableMetadata(contentType: file.mimeType ?? 'application/octet-stream'));
    return await ref.getDownloadURL();
  }

  Future<void> _register() async {
    if (_name.text.isEmpty || _email.text.isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill all fields')));
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

      // 2. Upload Photo + Video if dem select am
      String? photoUrl;
      String? videoUrl;
      if (_photo != null) {
        photoUrl = await _upload(_photo!, 'nurses/$uid/photo.jpg');
      }
      if (_video != null) {
        videoUrl = await _upload(_video!, 'nurses/$uid/video.mp4');
      }

      // 3. Save to Firestore - SAME place CEO reads
      await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).set({
        'uid': uid,
        'name': _name.text.trim(),
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'role': 'nurse',
        'status': 'pending',
        'isApproved': false,
        'photoUrl': photoUrl ?? '',
        'videoUrl': videoUrl ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });

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
            TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
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
            const SizedBox(height: 20),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(onPressed: _register, child: const Text('REGISTER AS NURSE')),
          ],
        ),
      ),
    );
  }
}
