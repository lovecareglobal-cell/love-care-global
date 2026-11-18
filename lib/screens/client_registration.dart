import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'client_login.dart';

class ClientRegistrationPage extends StatefulWidget {
  const ClientRegistrationPage({super.key});
  @override
  State<ClientRegistrationPage> createState() => _ClientRegistrationPageState();
}

class _ClientRegistrationPageState extends State<ClientRegistrationPage> with WidgetsBindingObserver {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _otp = TextEditingController();
  XFile? _photo;

  // AUTO VERIFY - SAVE BEFORE VERIFICATION (FIX FOR MICHAEL CASE)
  // OLD: save AFTER verify -> app kill = Auth exists, DB missing, CEO (0)
  // NEW: save IMMEDIATELY after createUser -> CEO sees Pending even before verify
  // On verify, we only UPDATE emailVerified:true, we no create again.
  bool _waitingVerification = false;
  String _verifyStatus = '';
  Timer? _verifyTimer;
  bool _finishingVerification = false;
  bool _loading = false;
  bool _obscurePassword = true;
  final _picker = ImagePicker();

  String? _verificationId;
  int? _resendToken;
  bool _otpSending = false;
  bool _phoneVerified = false;
  PhoneAuthCredential? _pendingPhoneCredential;

  // Country list - keep your full list if you get am, this short list still works
  // Default Ghana. Other lets anyone type code.
  static const List<Map<String, String>> _countries = [
    {"name": "Ghana", "code": "+233"},
    {"name": "Nigeria", "code": "+234"},
    {"name": "Kenya", "code": "+254"},
    {"name": "South Africa", "code": "+27"},
    {"name": "United States", "code": "+1"},
    {"name": "Canada", "code": "+1"},
    {"name": "United Kingdom", "code": "+44"},
    {"name": "India", "code": "+91"},
    {"name": "Australia", "code": "+61"},
    {"name": "Germany", "code": "+49"},
    {"name": "France", "code": "+33"},
    {"name": "Togo", "code": "+228"},
    {"name": "Benin", "code": "+229"},
    {"name": "Côte d'Ivoire", "code": "+225"},
    {"name": "Senegal", "code": "+221"},
    {"name": "Mali", "code": "+223"},
    {"name": "Burkina Faso", "code": "+226"},
    {"name": "Niger", "code": "+227"},
    {"name": "Cameroon", "code": "+237"},
    {"name": "Uganda", "code": "+256"},
    {"name": "Tanzania", "code": "+255"},
    {"name": "Ethiopia", "code": "+251"},
    {"name": "Egypt", "code": "+20"},
    {"name": "Morocco", "code": "+212"},
    {"name": "Brazil", "code": "+55"},
    {"name": "Mexico", "code": "+52"},
    {"name": "Spain", "code": "+34"},
    {"name": "Italy", "code": "+39"},
    {"name": "Netherlands", "code": "+31"},
    {"name": "Belgium", "code": "+32"},
    {"name": "Switzerland", "code": "+41"},
    {"name": "Sweden", "code": "+46"},
    {"name": "Norway", "code": "+47"},
    {"name": "Denmark", "code": "+45"},
    {"name": "Portugal", "code": "+351"},
    {"name": "Turkey", "code": "+90"},
    {"name": "UAE", "code": "+971"},
    {"name": "Saudi Arabia", "code": "+966"},
    {"name": "Qatar", "code": "+974"},
    {"name": "China", "code": "+86"},
    {"name": "Japan", "code": "+81"},
    {"name": "South Korea", "code": "+82"},
    {"name": "Singapore", "code": "+65"},
    {"name": "Malaysia", "code": "+60"},
    {"name": "Indonesia", "code": "+62"},
    {"name": "Philippines", "code": "+63"},
    {"name": "Pakistan", "code": "+92"},
    {"name": "Bangladesh", "code": "+880"},
  ];
  String _selectedCountry = 'Ghana|+233';
  final _otherCode = TextEditingController();
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
  String get _fullPhone {
    var local = _phone.text.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (local.startsWith('+')) return local;
    if (local.startsWith('00')) return '+${local.substring(2)}';
    if (local.startsWith('0')) local = local.substring(1);
    return _selectedDialCode.replaceAll(' ', '') + local;
  }

  Future<void> _pickPhoto() async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (f != null) setState(() => _photo = f);
  }

  Future<String?> _upload(XFile file, String path) async {
    final ref = FirebaseStorage.instance.ref().child(path);
    final bytes = await file.readAsBytes();
    await ref.putData(bytes, SettableMetadata(contentType: file.mimeType ?? 'application/octet-stream'));
    return await ref.getDownloadURL();
  }

  // ONE EMAIL = ONE ROLE - but allow RESUME if same email already has pending client profile
  Future<String?> _checkEmailNotUsedAsNurse(String email) async {
    final e = email.trim().toLowerCase();
    final inNurses = await FirebaseFirestore.instance.collection('nurses').where('email', isEqualTo: e).limit(1).get();
    if (inNurses.docs.isNotEmpty) return 'BLOCKED: This email is already registered as a NURSE. Use Nurse Login.';
    final inPending = await FirebaseFirestore.instance.collection('pending_nurses').where('email', isEqualTo: e).limit(1).get();
    if (inPending.docs.isNotEmpty) return 'BLOCKED: This email is already registered as a NURSE (waiting approval).';
    // For clients: if Firestore client exists AND emailVerified == true + approved, block re-register.
    // If pending / not verified, allow RESUME - do not block.
    final inClients = await FirebaseFirestore.instance.collection('clients').where('email', isEqualTo: e).limit(1).get();
    if (inClients.docs.isNotEmpty) {
      final d = inClients.docs.first.data();
      if (d['emailVerified'] == true && d['isApproved'] == true) {
        return 'BLOCKED: This email is already registered as a CLIENT. Login as Client instead.';
      }
      // Else: pending orphan - allow resume, _register will handle it
      return null;
    }
    return null;
  }

  // ===== NEW: SAVE PROFILE IMMEDIATELY - BEFORE VERIFICATION =====
  // Called right after createUser. CEO sees Pending instantly.
  // If called again (resume), it uses SetOptions(merge:true) so it no overwrite.
  Future<void> _saveProfileImmediately({required String uid, required String email, required String name, required String username, required String phone, String photoUrl = '', bool emailVerified = false}) async {
    final data = <String, Object?>{
      'uid': uid, 'id': uid,
      'name': name, 'fullName': name,
      'username': username, 'email': email.toLowerCase(),
      'phone': phone, 'countryCode': _selectedDialCode, 'country': _selectedCountryName,
      'role': 'client', 'type': 'client',
      // CLIENTS ARE PENDING - CEO must Approve. Do NOT set approved:true here.
      'status': 'pending', 'isApproved': false, 'approved': false,
      'approvalStatus': 'pending', 'canLogin': false,
      'phoneVerified': false, 'otpVerified': false,
      'emailVerified': emailVerified, 'verifiedByEmail': emailVerified,
      'photo': photoUrl, 'photoUrl': photoUrl, 'photoURL': photoUrl,
      'createdAt': FieldValue.serverTimestamp(),
    };
    // Firestore
    await FirebaseFirestore.instance.collection('clients').doc(uid).set(data, SetOptions(merge: true));
    // RTDB - CEO reads from here
    final rtdbData = Map<String, Object?>.from(data)..['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    await FirebaseDatabase.instance.ref('ceoRegistrationCenter/clients/$uid').set(rtdbData);
    await FirebaseDatabase.instance.ref('clients/$uid').set(rtdbData);
    await FirebaseDatabase.instance.ref('client_registrations/$uid').set(rtdbData);
    // Also save to allowed index? NO - only after CEO approves. Keep pending only.
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumePendingVerification();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _verifyTimer?.cancel();
    _name.dispose(); _username.dispose(); _email.dispose(); _phone.dispose(); _pass.dispose(); _otp.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingVerification) _checkVerificationOnce();
  }

  Future<void> _savePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('client_pending_verification', true);
      await prefs.setString('client_pending_name', _name.text.trim());
      await prefs.setString('client_pending_username', _username.text.trim());
      await prefs.setString('client_pending_email', _email.text.trim().toLowerCase());
      await prefs.setString('client_pending_phone', _fullPhone);
      await prefs.setString('client_pending_countryCode', _selectedDialCode);
      await prefs.setString('client_pending_country', _selectedCountryName);
      if (_photo != null) await prefs.setString('client_pending_photo_path', _photo!.path);
    } catch (_) {}
  }

  Future<void> _clearPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('client_pending_verification');
      await prefs.remove('client_pending_name');
      await prefs.remove('client_pending_username');
      await prefs.remove('client_pending_email');
      await prefs.remove('client_pending_phone');
      await prefs.remove('client_pending_countryCode');
      await prefs.remove('client_pending_country');
      await prefs.remove('client_pending_photo_path');
    } catch (_) {}
  }

  Future<void> _resumePendingVerification() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('client_pending_verification') != true) return;
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) { await _clearPending(); return; }
      if (_name.text.isEmpty) _name.text = prefs.getString('client_pending_name') ?? '';
      if (_username.text.isEmpty) _username.text = prefs.getString('client_pending_username') ?? '';
      if (_email.text.isEmpty) _email.text = prefs.getString('client_pending_email') ?? '';
      final photoPath = prefs.getString('client_pending_photo_path');
      if (_photo == null && photoPath != null && photoPath.isNotEmpty) {
        try { _photo = XFile(photoPath); } catch (_) {}
      }
      // FIX: If DB missing (old bug), re-save immediately from prefs - no fresh start
      try {
        final snap = await FirebaseDatabase.instance.ref('clients/${u.uid}').get();
        if (!snap.exists) {
          await _saveProfileImmediately(
            uid: u.uid,
            email: _email.text.trim().isNotEmpty ? _email.text.trim() : (u.email ?? ''),
            name: _name.text.trim(),
            username: _username.text.trim(),
            phone: prefs.getString('client_pending_phone') ?? '',
            emailVerified: false,
          );
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() { _waitingVerification = true; _verifyStatus = 'Welcome back! Still waiting for you to tap the link in Gmail...'; });
      _startVerifyPolling();
      _checkVerificationOnce();
    } catch (_) {}
  }

  void _startVerifyPolling() {
    _verifyTimer?.cancel();
    _verifyTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkVerificationOnce());
  }

  Future<void> _checkVerificationOnce() async {
    if (_finishingVerification || !_waitingVerification) return;
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;
      await u.reload();
      final fresh = FirebaseAuth.instance.currentUser;
      if (fresh != null && fresh.emailVerified) {
        await _finishAfterVerified();
      }
    } catch (_) {}
  }

  // Called AUTOMATICALLY when reload() says emailVerified == true.
  // NEW: Only UPDATE emailVerified, do NOT create profile again.
  Future<void> _finishAfterVerified() async {
    if (_finishingVerification) return;
    _finishingVerification = true;
    _verifyTimer?.cancel();
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !user.emailVerified) { _finishingVerification = false; return; }
      final uid = user.uid;
      // Upload photo if any - if upload fails, do NOT fail whole verification
      String? photoUrl;
      if (_photo != null) {
        try { photoUrl = await _upload(_photo!, 'clients/$uid/photo.jpg'); } catch (_) {}
      }
      final prefs = await SharedPreferences.getInstance();
      final name = _name.text.trim().isNotEmpty ? _name.text.trim() : (prefs.getString('client_pending_name') ?? '');
      final username = _username.text.trim().isNotEmpty ? _username.text.trim() : (prefs.getString('client_pending_username') ?? '');
      final email = _email.text.trim().isNotEmpty ? _email.text.trim().toLowerCase() : (prefs.getString('client_pending_email') ?? user.email?.toLowerCase() ?? '');
      final phone = _fullPhone.isNotEmpty ? _fullPhone : (prefs.getString('client_pending_phone') ?? '');

      // If profile was already saved immediately, just update it
      final update = <String, Object?>{
        'uid': uid, 'fullName': name, 'name': name, 'username': username, 'email': email, 'phone': phone,
        'emailVerified': true, 'verifiedByEmail': true,
        // Still PENDING for CEO - CEO must approve before canLogin
        'status': 'pending', 'isApproved': false, 'approved': false, 'approvalStatus': 'pending',
        if (photoUrl != null && photoUrl.isNotEmpty) 'photo': photoUrl,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoURL': photoUrl,
      };
      await FirebaseFirestore.instance.collection('clients').doc(uid).set(update, SetOptions(merge: true));
      final rtdbUpdate = Map<String, Object?>.from(update)..['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
      await FirebaseDatabase.instance.ref('ceoRegistrationCenter/clients/$uid').update(rtdbUpdate);
      await FirebaseDatabase.instance.ref('clients/$uid').update(rtdbUpdate);
      await FirebaseDatabase.instance.ref('client_registrations/$uid').update(rtdbUpdate);

      await _clearPending();
      if (!mounted) return;
      setState(() { _waitingVerification = false; _verifyStatus = ''; _loading = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email verified! Your account is now Pending for CEO approval. Login now.')));
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ClientLoginPage()));
    } catch (e) {
      _finishingVerification = false;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      _startVerifyPolling();
    }
  }

  // Email Verification ONLY - FIXED FLOW
  Future<void> _registerWithEmailVerification() async {
    final email = _email.text.trim().toLowerCase();
    final blockedFb = await _checkEmailNotUsedAsNurse(email);
    if (blockedFb != null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blockedFb), backgroundColor: Colors.red)); return; }
    final pass = _pass.text.trim();
    final phone = _fullPhone;
    final name = _name.text.trim();
    final username = _username.text.trim();
    setState(() => _loading = true);
    try {
      UserCredential cred;
      try {
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
      } on FirebaseAuthException catch (e) {
        // ===== FIX FOR MICHAEL CASE: email-already-in-use =====
        // Do NOT delete. User already has Auth. Resume verification + re-save DB if missing.
        if (e.code == 'email-already-in-use') {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This email already has an account. We will resume verification - check Gmail, no need to register again.'), backgroundColor: Colors.orange));
          // Try to sign in with same password to resume, else ask to login
          try {
            cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
            final uid = cred.user!.uid;
            // Re-save if DB missing - this is what fixes CEO (0)
            await _saveProfileImmediately(uid: uid, email: email, name: name, username: username, phone: phone, emailVerified: cred.user!.emailVerified);
            await cred.user!.sendEmailVerification().catchError((_) {});
            await _savePending();
            if (!mounted) return;
            setState(() { _loading = false; _waitingVerification = true; _verifyStatus = 'We resumed your account. Open Gmail and tap the link - this page will auto-confirm.'; });
            _startVerifyPolling();
            return;
          } catch (_) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email already exists. Go to Login and use "I Have Verified" / Forgot Password if you forgot password.'), backgroundColor: Colors.red));
            if (mounted) setState(() => _loading = false);
            return;
          }
        }
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create account: ${e.message ?? e.code}'), backgroundColor: Colors.red));
        if (mounted) setState(() => _loading = false);
        return;
      }

      final uid = cred.user!.uid;

      // ===== CRITICAL FIX: SAVE IMMEDIATELY, BEFORE verification =====
      // Even if app is killed in Gmail, CEO will see Pending, Login will find profile.
      await _saveProfileImmediately(uid: uid, email: email, name: name, username: username, phone: phone, emailVerified: false);

      await cred.user!.sendEmailVerification();
      if (!mounted) return;
      await _savePending();
      if (!mounted) return;
      setState(() { _loading = false; _waitingVerification = true; _verifyStatus = 'We sent a link to $email. Open Gmail and tap it - this page will auto-confirm, no button to tap. Your account is already saved as Pending for CEO.'; });
      _startVerifyPolling();
      return;
    } catch (e) {
      if (!_waitingVerification) {
        // Do NOT delete Auth here - DB already saved, deleting would create orphan again
        // Only clear loading
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted && !_waitingVerification) setState(() => _loading = false);
    }
  }

  Future<void> _cancelVerification() async {
    _verifyTimer?.cancel();
    // FIX: Do NOT delete Auth + DB on Cancel if user already verified? 
    // Cancel means user wants to start over - delete both Auth + DB so email is free
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        await FirebaseDatabase.instance.ref('clients/${u.uid}').remove().catchError((_) {});
        await FirebaseDatabase.instance.ref('ceoRegistrationCenter/clients/${u.uid}').remove().catchError((_) {});
        await FirebaseDatabase.instance.ref('client_registrations/${u.uid}').remove().catchError((_) {});
        await FirebaseFirestore.instance.collection('clients').doc(u.uid).delete().catchError((_) {});
        await u.delete();
      }
    } catch (_) { await FirebaseAuth.instance.signOut(); }
    await _clearPending();
    if (!mounted) return;
    setState(() { _waitingVerification = false; _verifyStatus = ''; _loading = false; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification cancelled. That email cannot login. Register again.'), backgroundColor: Colors.red));
  }

  int get _passwordScore {
    final p = _pass.text; var score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    return score;
  }
  bool get _isStrongPassword {
    final p = _pass.text;
    return p.length >= 8 && RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[0-9]').hasMatch(p) && RegExp(r'[^A-Za-z0-9]').hasMatch(p) && !p.contains(' ');
  }
  String get _passwordStrengthLabel {
    if (_pass.text.isEmpty) return '';
    final s = _passwordScore;
    if (s <= 2) return 'Weak';
    if (s <= 4) return 'Medium';
    if (s == 5) return 'Strong';
    return 'Very strong';
  }
  Color get _passwordStrengthColor {
    if (_pass.text.isEmpty) return Colors.grey;
    final s = _passwordScore;
    if (s <= 2) return Colors.red;
    if (s <= 4) return Colors.orange;
    if (s == 5) return Colors.lightGreen;
    return Colors.green;
  }
  List<String> get _passwordMissing {
    final p = _pass.text; final missing = <String>[];
    if (p.length < 8) missing.add('At least 8 characters');
    if (!RegExp(r'[A-Z]').hasMatch(p)) missing.add('One UPPERCASE letter (A-Z)');
    if (!RegExp(r'[a-z]').hasMatch(p)) missing.add('One lowercase letter (a-z)');
    if (!RegExp(r'[0-9]').hasMatch(p)) missing.add('One number (0-9)');
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(p)) missing.add('One special character (! @ # \$ % etc.)');
    if (p.contains(' ')) missing.add('No spaces');
    return missing;
  }

  Future<void> _register() async {
    if (_name.text.trim().isEmpty || _username.text.trim().isEmpty || _email.text.trim().isEmpty || _phone.text.trim().isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill all fields - name, username, email, phone and password')));
      return;
    }
    if (!_isStrongPassword) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Password too weak. Missing: ${_passwordMissing.join(', ')}'), backgroundColor: Colors.red));
      return;
    }
    if (_isOtherCountry && !RegExp(r'^\+\\d{1,4}$').hasMatch(_selectedDialCode)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid country code for Other, e.g. +999')));
      return;
    }
    await _registerWithEmailVerification();
  }

  @override
  Widget build(BuildContext context) {
    if (_waitingVerification) {
      return Scaffold(
        appBar: AppBar(title: const Text('Check your Email'), backgroundColor: Colors.purple, foregroundColor: Colors.white),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.mark_email_read, size: 80, color: Colors.purple),
            const SizedBox(height: 20),
            Text(_verifyStatus, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Waiting... This page will auto-confirm when you tap the link. Do not press back.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: () async { try { await FirebaseAuth.instance.currentUser?.sendEmailVerification(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification email resent'))); } catch (_) {} }, child: const Text('Resend Email')),
            const SizedBox(height: 8),
            TextButton(onPressed: _cancelVerification, child: const Text('Cancel Registration', style: TextStyle(color: Colors.red))),
          ]),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Client Registration'), backgroundColor: Colors.purple, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name')),
          TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username')),
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: DropdownButtonFormField<String>(value: _selectedCountry, isExpanded: true, decoration: const InputDecoration(labelText: 'Country Code'), items: [..._countries.map((c) => DropdownMenuItem<String>(value: '${c['name']}|${c['code']}', child: Text('${c['name']} (${c['code']})', overflow: TextOverflow.ellipsis))), const DropdownMenuItem<String>(value: 'Other|', child: Text('Other (type code)'))], onChanged: (v) { if (v != null) setState(() => _selectedCountry = v); })),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Phone Number', hintText: _isOtherCountry ? 'Number without code' : 'e.g. 241234567 (no 0, no code)'))),
          ]),
          if (_isOtherCountry) Padding(padding: const EdgeInsets.only(top: 8), child: TextField(controller: _otherCode, keyboardType: TextInputType.phone, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Your Country Code', hintText: 'e.g. +999'))),
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerLeft, child: Text('Full number: ${_phone.text.trim().isEmpty ? '...' : _fullPhone}', style: const TextStyle(fontSize: 12, color: Colors.grey))),
          TextField(controller: _pass, obscureText: _obscurePassword, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'Password', hintText: 'Min 8 chars, upper + lower + number + symbol', suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)))),
          const SizedBox(height: 8),
          if (_pass.text.isNotEmpty) ...[
            Row(children: [Expanded(child: LinearProgressIndicator(value: _passwordScore / 6, backgroundColor: Colors.grey.shade300, color: _passwordStrengthColor, minHeight: 6)), const SizedBox(width: 8), Text(_passwordStrengthLabel, style: TextStyle(color: _passwordStrengthColor, fontWeight: FontWeight.bold))]),
            const SizedBox(height: 6),
            ..._passwordMissing.map((m) => Row(children: [const Icon(Icons.close, size: 14, color: Colors.red), const SizedBox(width: 4), Expanded(child: Text(m, style: const TextStyle(fontSize: 12, color: Colors.red)))])),
            if (_isStrongPassword) const Row(children: [Icon(Icons.check_circle, size: 14, color: Colors.green), SizedBox(width: 4), Text('Strong password ✓', style: TextStyle(fontSize: 12, color: Colors.green))]),
          ],
          const SizedBox(height: 16),
          ListTile(leading: const Icon(Icons.photo), title: Text(_photo == null ? 'Upload Photo (optional)' : 'Photo Selected: ${_photo!.name}'), trailing: ElevatedButton(onPressed: _pickPhoto, child: const Text('Pick Photo'))),
          const SizedBox(height: 20),
          _loading || _otpSending ? const CircularProgressIndicator() : ElevatedButton(onPressed: _register, child: const Text('REGISTER AS CLIENT')),
        ]),
      ),
    );
  }
}
