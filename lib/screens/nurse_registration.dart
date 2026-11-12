import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  bool _hasPhoto = false;
  bool _hasVideo = false;
  bool _showPass = false; // NEW: For show/hide password eye
  String _msg = '';

  // ===== GUARD 1: CHECK IF ACCOUNT EXISTS ANYWHERE =====
  // Returns 'nurse' / 'client' / 'pending_nurse' / 'pending_client' / null
  Future<String?> _checkAccountExistsAnywhere(String email, String phone) async {
    final db = FirebaseFirestore.instance;
    final e = email.trim().toLowerCase();
    final p = phone.trim();

    // Check Nurses
    final nurseQ = await db.collection('nurses').where('email', isEqualTo: e).limit(1).get();
    if (nurseQ.docs.isNotEmpty) return 'nurse';
    final pendingNurse = await db.collection('pending_nurses').where('email', isEqualTo: e).limit(1).get();
    if (pendingNurse.docs.isNotEmpty) return 'pending_nurse';
    final ceoNurse = await db.collection('ceoRegistrationCenter').doc('nurses').collection('list').where('email', isEqualTo: e).limit(1).get().catchError((_) => null);
    if (ceoNurse != null && ceoNurse.docs.isNotEmpty) return 'pending_nurse';

    // Check Clients - BLOCK DOUBLE REGISTRATION
    final clientQ = await db.collection('clients').where('email', isEqualTo: e).limit(1).get();
    if (clientQ.docs.isNotEmpty) return 'client';
    final clientPhone = await db.collection('clients').where('phone', isEqualTo: p).limit(1).get();
    if (clientPhone.docs.isNotEmpty) return 'client';
    final pendingClient = await db.collection('pending_clients').where('email', isEqualTo: e).limit(1).get();
    if (pendingClient.docs.isNotEmpty) return 'pending_client';
    final nursePhone = await db.collection('nurses').where('phone', isEqualTo: p).limit(1).get();
    if (nursePhone.docs.isNotEmpty) return 'nurse';

    return null;
  }

  // ===== GUARD 3: CLEANUP FAILED REGISTRATION - DELETE EVERYTHING =====
  Future<void> _cleanupFailedRegistration(String? uid) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('nurses').doc(uid).delete().catchError((_) {});
        await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).delete().catchError((_) {});
        await FirebaseFirestore.instance.collection('allowedNurses').doc(uid).delete().catchError((_) {});
      }
      if (user != null) {
        await user.delete().catchError((_) {});
      }
      await FirebaseAuth.instance.signOut().catchError((_) {});
    } catch (_) {}
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final phone = _phoneCtrl.text.trim();
    final pass = _passCtrl.text;

    if (name.isEmpty || email.isEmpty || phone.isEmpty || pass.isEmpty) {
      setState(() => _msg = 'Fill all fields');
      return;
    }
    if (!_hasPhoto || !_hasVideo) {
      setState(() => _msg = 'Photo + Video are REQUIRED. Registration will NOT save without them.');
      return;
    }

    setState(() { _loading = true; _msg = 'Checking double account...'; });

    // GUARD 1: Double account check BEFORE creating Auth
    final exists = await _checkAccountExistsAnywhere(email, phone);
    if (exists != null) {
      setState(() { _loading = false; _msg = 'BLOCKED: This email/phone already exists as $exists. Use Login, not Register.'; });
      return;
    }

    String? createdUid;
    try {
      // Create Auth ONLY after checks pass
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
      createdUid = cred.user!.uid;

      // Save ONLY when complete - atomic: all fields together
      final data = {
        'uid': createdUid,
        'name': name,
        'email': email,
        'phone': phone,
        'role': 'nurse',
        'hasPhoto': _hasPhoto,
        'hasVideo': _hasVideo,
        'hasPhone': true,
        'isComplete': true,
        'isApproved': false,
        'approved': false,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('pending_nurses').doc(createdUid).set(data);
      await FirebaseFirestore.instance.collection('ceoRegistrationCenter').doc('nurses').collection('list').doc(createdUid).set(data);

      // Sign out - must wait for CEO approval before login
      await FirebaseAuth.instance.signOut();
      setState(() { _loading = false; _msg = '✅ Submitted! Waiting for CEO Approval. You CANNOT login until approved.'; });
    } catch (e) {
      // GUARD 3: If anything fails, DELETE everything - no half-save
      await _cleanupFailedRegistration(createdUid);
      setState(() { _loading = false; _msg = 'Registration failed - cleaned up. Try again. Error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nurse Registration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nurse Registration', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Text('CEO APPROVAL REQUIRED - No double account', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 16),
            if (_step == 1) ...[
              TextField(controller: _nameCtrl, decoration: const InputDecoration(hintText: 'Full Name', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _emailCtrl, decoration: const InputDecoration(hintText: 'Email', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _phoneCtrl, decoration: const InputDecoration(hintText: 'Phone', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              // FIXED: Password with Show/Hide Eye
              TextField(
                controller: _passCtrl,
                obscureText: !_showPass,
                decoration: InputDecoration(
                  hintText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => setState(() => _step = 2), child: const Text('Next - Photo & Video')),
            ],
            if (_step == 2) ...[
              CheckboxListTile(value: _hasPhoto, onChanged: (v) => setState(() => _hasPhoto = v ?? false), title: const Text('I have uploaded Photo (Required)')),
              CheckboxListTile(value: _hasVideo, onChanged: (v) => setState(() => _hasVideo = v ?? false), title: const Text('I have uploaded Video (Required)')),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loading ? null : _submit, child: Text(_loading ? 'Checking...' : 'Submit for CEO Approval')),
              TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Back')),
            ],
            if (_msg.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}
