import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _ClientRegistrationPageState extends State<ClientRegistrationPage> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController(); // OPTIONAL - for recovery only, not for OTP
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocus = List.generate(6, (_) => FocusNode());
  XFile? _photo;

  // CLIENT PHONE OTP RULE:
  // Pending = SMS OTP NOT verified. CEO does NOT approve Client.
  // SMS OTP verified -> isApproved = true, canLogin = true, status = approved -> Login with Phone + Password straight.
  // NO Gmail link. NO Email OTP. OTP comes as SMS to Phone.
  // AUTH SAVES PHONE: After OTP, we link Phone + Email/Password to SAME Auth user, so Firebase Console shows phone + email.
  bool _waitingOtp = false;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _otpSending = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  String _otpStatus = '';
  String _verificationId = '';
  int? _resendToken;
  final _picker = ImagePicker();

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
  String get _phoneDigits => _fullPhone.replaceAll(RegExp(r'[^0-9]'), '');
  String get _otpCode => _otpControllers.map((c) => c.text).join();
  String get _hiddenEmail {
    final real = _email.text.trim().toLowerCase();
    if (real.isNotEmpty && real.contains('@')) return real;
    return '${_phoneDigits}@phone.lovecare';
  }

  @override
  void initState() {
    super.initState();
    _resumePendingOtp();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (var c in _otpControllers) c.dispose();
    for (var f in _otpFocus) f.dispose();
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _phone.dispose();
    _pass.dispose();
    _otherCode.dispose();
    super.dispose();
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

  Future<String?> _checkPhoneNotUsedAsNurse(String phone, String digits) async {
    try {
      final s = await FirebaseDatabase.instance.ref('nurses').get();
      if (s.exists && s.value is Map) {
        for (final e in (s.value as Map).values) {
          if (e is! Map) continue;
          final p = (e['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
          if (p.isNotEmpty && (p == digits || p.endsWith(digits) || digits.endsWith(p))) {
            return 'BLOCKED: This phone is already registered as a NURSE. Use Nurse Login.';
          }
        }
      }
    } catch (_) {}
    try {
      final q = await FirebaseFirestore.instance.collection('nurses').where('phone', isEqualTo: phone).limit(1).get();
      if (q.docs.isNotEmpty) return 'BLOCKED: This phone is already registered as a NURSE.';
    } catch (_) {}
    return null;
  }

  Future<void> _savePendingOtp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('client_pending_otp', true);
      await prefs.setString('client_pending_name', _name.text.trim());
      await prefs.setString('client_pending_username', _username.text.trim());
      await prefs.setString('client_pending_email', _email.text.trim().toLowerCase());
      await prefs.setString('client_pending_phone', _fullPhone);
      await prefs.setString('client_pending_countryCode', _selectedDialCode);
      await prefs.setString('client_pending_country', _selectedCountryName);
      await prefs.setString('client_pending_password', _pass.text);
      await prefs.setString('client_pending_verificationId', _verificationId);
      if (_photo != null) await prefs.setString('client_pending_photo_path', _photo!.path);
    } catch (_) {}
  }

  Future<void> _clearPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('client_pending_otp');
      await prefs.remove('client_pending_verification');
      await prefs.remove('client_pending_name');
      await prefs.remove('client_pending_username');
      await prefs.remove('client_pending_email');
      await prefs.remove('client_pending_phone');
      await prefs.remove('client_pending_countryCode');
      await prefs.remove('client_pending_country');
      await prefs.remove('client_pending_password');
      await prefs.remove('client_pending_verificationId');
      await prefs.remove('client_pending_photo_path');
    } catch (_) {}
  }

  Future<void> _resumePendingOtp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('client_pending_otp') != true) return;
      if (_name.text.isEmpty) _name.text = prefs.getString('client_pending_name') ?? '';
      if (_username.text.isEmpty) _username.text = prefs.getString('client_pending_username') ?? '';
      if (_email.text.isEmpty) _email.text = prefs.getString('client_pending_email') ?? '';
      if (_phone.text.isEmpty) {
        final saved = prefs.getString('client_pending_phone') ?? '';
        if (saved.isNotEmpty) {
          var local = saved.replaceAll(RegExp(r'[^0-9]'), '');
          if (local.startsWith(_selectedDialCode.replaceAll('+', ''))) local = local.substring(_selectedDialCode.replaceAll('+', '').length);
          if (local.startsWith('0')) local = local.substring(1);
          _phone.text = local;
        }
      }
      if (_pass.text.isEmpty) _pass.text = prefs.getString('client_pending_password') ?? '';
      _verificationId = prefs.getString('client_pending_verificationId') ?? '';
      final photoPath = prefs.getString('client_pending_photo_path');
      if (_photo == null && photoPath != null && photoPath.isNotEmpty) {
        try { _photo = XFile(photoPath); } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _waitingOtp = true;
        _otpStatus = 'Welcome back! Enter SMS OTP sent to $_fullPhone. If expired, tap Resend.';
      });
      _startResendCountdown();
    } catch (_) {}
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds <= 0) { t.cancel(); if (mounted) setState(() {}); return; }
      if (mounted) setState(() => _resendSeconds--);
    });
  }

  Future<void> _sendOtp() async {
    if (_fullPhone.isEmpty || _phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter Phone Number first')));
      return;
    }
    setState(() { _otpSending = true; _otpStatus = 'Sending SMS OTP to $_fullPhone...'; });
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _fullPhone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential cred) async {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SMS auto-detected! Verifying...')));
          await _finishWithPhoneCredential(cred);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() { _otpSending = false; _otpStatus = 'Failed to send SMS: ${e.message}'; });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('SMS failed: ${e.message}'), backgroundColor: Colors.red));
        },
        codeSent: (String verId, int? token) async {
          _verificationId = verId;
          _resendToken = token;
          await _savePendingOtp();
          if (!mounted) return;
          setState(() { _otpSending = false; _waitingOtp = true; _otpStatus = 'SMS OTP sent to $_fullPhone. Enter 6-digit code.'; });
          _startResendCountdown();
        },
        codeAutoRetrievalTimeout: (String verId) { _verificationId = verId; },
      );
    } catch (e) {
      if (mounted) setState(() { _otpSending = false; _otpStatus = 'Failed: $e'; });
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter complete 6-digit SMS code')));
      return;
    }
    if (_verificationId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No OTP sent yet. Tap Resend OTP first.'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _loading = true);
    try {
      final cred = PhoneAuthProvider.credential(verificationId: _verificationId, smsCode: _otpCode);
      await _finishWithPhoneCredential(cred);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Wrong OTP: $e'), backgroundColor: Colors.red));
      if (mounted) setState(() => _loading = false);
    }
  }

  // After SMS OTP verified -> Auth user MUST have phoneNumber saved
  // We link Phone + Email/Password to SAME Auth user, so Firebase Console shows phone + email
  Future<void> _finishWithPhoneCredential(PhoneAuthCredential phoneCred) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = _name.text.trim().isNotEmpty ? _name.text.trim() : (prefs.getString('client_pending_name') ?? '');
      final username = _username.text.trim().isNotEmpty ? _username.text.trim() : (prefs.getString('client_pending_username') ?? '');
      final realEmail = _email.text.trim().isNotEmpty ? _email.text.trim().toLowerCase() : (prefs.getString('client_pending_email') ?? '');
      final phone = _fullPhone.isNotEmpty && _phone.text.trim().isNotEmpty ? _fullPhone : (prefs.getString('client_pending_phone') ?? '');
      final password = _pass.text.isNotEmpty ? _pass.text : (prefs.getString('client_pending_password') ?? '');
      final emailForAuth = realEmail.isNotEmpty && realEmail.contains('@') ? realEmail : '${phone.replaceAll(RegExp(r'[^0-9]'), '')}@phone.lovecare';
      final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

      if (password.isEmpty) throw Exception('Password missing. Go back and enter password again.');

      // 1. Sign in with Phone OTP first - this user ALREADY has phoneNumber in Auth
      try {
        await FirebaseAuth.instance.signInWithCredential(phoneCred);
      } catch (e) {
        final cur = FirebaseAuth.instance.currentUser;
        if (cur == null) rethrow;
      }

      // 2. Try link Email/Password to this Phone user - BEST CASE: Same user gets phone + email
      bool linked = false;
      try {
        final emailCred = EmailAuthProvider.credential(email: emailForAuth, password: password);
        await FirebaseAuth.instance.currentUser!.linkWithCredential(emailCred);
        linked = true;
      } catch (linkErr) {
        // Email already exists - sign in with Email, then LINK PHONE to Email user
        try {
          await FirebaseAuth.instance.signOut();
          await FirebaseAuth.instance.signInWithEmailAndPassword(email: emailForAuth, password: password);
          try {
            await FirebaseAuth.instance.currentUser!.linkWithCredential(phoneCred);
            linked = true;
          } catch (phoneLinkErr) {
            print('Phone link failed (already linked elsewhere): $phoneLinkErr');
            linked = false;
          }
        } catch (_) {
          try {
            await FirebaseAuth.instance.signOut();
            await FirebaseAuth.instance.createUserWithEmailAndPassword(email: emailForAuth, password: password);
            try {
              await FirebaseAuth.instance.currentUser!.linkWithCredential(phoneCred);
              linked = true;
            } catch (_) {}
          } catch (createErr) {
            await FirebaseAuth.instance.signInWithCredential(phoneCred);
          }
        }
      }

      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;

      // 3. FORCE Auth to save phone + name + photo - this is what shows for Firebase Console
      try {
        if ((user.phoneNumber == null || user.phoneNumber!.isEmpty) && linked == false) {
          try {
            await user.updatePhoneNumber(phoneCred);
          } catch (_) {}
        }
      } catch (_) {}
      try {
        await user.updateDisplayName(name);
      } catch (_) {}

      String? photoUrl;
      if (_photo != null) {
        try { photoUrl = await _upload(_photo!, 'clients/$uid/photo.jpg'); } catch (_) {}
      }
      if (photoUrl != null && photoUrl.isNotEmpty) {
        try { await user.updatePhotoURL(photoUrl); } catch (_) {}
      }
      try { await user.reload(); } catch (_) {}

      final finalUser = FirebaseAuth.instance.currentUser!;
      print('AUTH SAVED: uid=$uid email=${finalUser.email} phone=${finalUser.phoneNumber} name=${finalUser.displayName}');

      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final firestoreData = <String, Object?>{
        'uid': uid, 'id': uid, 'name': name, 'fullName': name, 'username': username,
        'email': emailForAuth, 'realEmail': realEmail, 'phone': phone, 'phoneNumber': phone,
        'authPhone': finalUser.phoneNumber ?? phone,
        'countryCode': _selectedDialCode, 'country': _selectedCountryName,
        'role': 'client', 'type': 'client', 'status': 'approved', 'isApproved': true, 'approved': true,
        'approvalStatus': 'approved', 'canLogin': true, 'phoneVerified': true, 'otpVerified': true,
        'emailVerified': true, 'verifiedByEmail': false, 'verifiedByPhone': true, 'isVerified': true,
        'isComplete': true, 'hasAll4': true, 'approvedAt': FieldValue.serverTimestamp(),
        if (photoUrl != null && photoUrl.isNotEmpty) 'photo': photoUrl,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoURL': photoUrl,
      };
      final rtdbData = <String, Object?>{
        'uid': uid, 'id': uid, 'name': name, 'fullName': name, 'username': username,
        'email': emailForAuth, 'realEmail': realEmail, 'phone': phone, 'phoneNumber': phone,
        'authPhone': finalUser.phoneNumber ?? phone,
        'countryCode': _selectedDialCode, 'country': _selectedCountryName,
        'role': 'client', 'type': 'client', 'status': 'approved', 'isApproved': true, 'approved': true,
        'approvalStatus': 'approved', 'canLogin': true, 'phoneVerified': true, 'otpVerified': true,
        'emailVerified': true, 'verifiedByEmail': false, 'verifiedByPhone': true, 'isVerified': true,
        'isComplete': true, 'hasAll4': true, 'approvedAt': nowMs, 'updatedAt': nowMs,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photo': photoUrl,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoURL': photoUrl,
      };

      await FirebaseFirestore.instance.collection('clients').doc(uid).set(firestoreData, SetOptions(merge: true));
      await FirebaseDatabase.instance.ref('ceoRegistrationCenter/clients/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('clients/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('client_registrations/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('allowedClients/${emailForAuth.replaceAll(RegExp(r'[.#\$@\[\]]'), '_')}').set({...rtdbData, 'uid': uid});
      await FirebaseDatabase.instance.ref('allowedClientsByUid/$uid').set({...rtdbData, 'uid': uid});
      if (digits.isNotEmpty) {
        await FirebaseDatabase.instance.ref('phones/$digits').set(emailForAuth);
        await FirebaseDatabase.instance.ref('clientsByPhone/$digits').set(uid);
      }

      await _clearPending();
      if (!mounted) return;
      setState(() { _waitingOtp = false; _loading = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Phone OTP verified! Auth saved phone ${finalUser.phoneNumber ?? phone}. Login with Phone + Password now.')));
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ClientLoginPage()));
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _cancelOtp() async {
    _resendTimer?.cancel();
    try { await FirebaseAuth.instance.signOut(); } catch (_) {}
    await _clearPending();
    if (!mounted) return;
    setState(() { _waitingOtp = false; _loading = false; _otpSending = false; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP cancelled. Register again.'), backgroundColor: Colors.red));
  }

  Future<void> _register() async {
    if (_name.text.trim().isEmpty || _username.text.trim().isEmpty || _phone.text.trim().isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill Name, Username, Phone and Password. Email is optional.')));
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
    try {
      final s = await FirebaseDatabase.instance.ref('phones/$_phoneDigits').get();
      if (s.exists) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This phone already has an account. Login with Phone + Password instead.'), backgroundColor: Colors.orange));
        return;
      }
    } catch (_) {}
    final blocked = await _checkPhoneNotUsedAsNurse(_fullPhone, _phoneDigits);
    if (blocked != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blocked), backgroundColor: Colors.red));
      return;
    }
    setState(() => _loading = true);
    await _savePendingOtp();
    await _sendOtp();
    if (mounted) setState(() => _loading = false);
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
    if (s <= 2) return 'Weak'; if (s <= 4) return 'Medium'; if (s == 5) return 'Strong'; return 'Very strong';
  }
  Color get _passwordStrengthColor {
    if (_pass.text.isEmpty) return Colors.grey;
    final s = _passwordScore;
    if (s <= 2) return Colors.red; if (s <= 4) return Colors.orange; if (s == 5) return Colors.lightGreen; return Colors.green;
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

  Widget _otpBox(int i) {
    return SizedBox(
      width: 48, height: 56,
      child: TextField(
        controller: _otpControllers[i], focusNode: _otpFocus[i],
        keyboardType: TextInputType.number, textAlign: TextAlign.center,
        maxLength: 1, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(counterText: '', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        onChanged: (v) {
          if (v.isNotEmpty && i < 5) _otpFocus[i + 1].requestFocus();
          if (v.isEmpty && i > 0) _otpFocus[i - 1].requestFocus();
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_waitingOtp) {
      return Scaffold(
        appBar: AppBar(title: const Text('Enter SMS OTP'), backgroundColor: Colors.purple, foregroundColor: Colors.white),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.sms_outlined, size: 70, color: Colors.purple),
            const SizedBox(height: 16),
            Text('We sent 6-digit SMS code to\n$_fullPhone', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Check your SMS. Enter code below. You stay inside app.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(6, (i) => _otpBox(i))),
            const SizedBox(height: 16),
            if (_otpStatus.isNotEmpty) Text(_otpStatus, textAlign: TextAlign.center, style: const TextStyle(color: Colors.purple)),
            const SizedBox(height: 20),
            _loading ? const Center(child: CircularProgressIndicator()) : ElevatedButton(
              onPressed: _verifyOtp,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('VERIFY SMS OTP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            _resendSeconds > 0
                ? Center(child: Text('Resend SMS in $_resendSeconds s', style: const TextStyle(color: Colors.grey)))
                : OutlinedButton(onPressed: _otpSending ? null : _sendOtp, child: Text(_otpSending ? 'Sending SMS...' : 'Resend SMS OTP')),
            const SizedBox(height: 12),
            TextButton(onPressed: _cancelOtp, child: const Text('Cancel Registration', style: TextStyle(color: Colors.red))),
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
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email (optional - for recovery only)')),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: DropdownButtonFormField<String>(value: _selectedCountry, isExpanded: true, decoration: const InputDecoration(labelText: 'Country Code'), items: [..._countries.map((c) => DropdownMenuItem<String>(value: '${c['name']}|${c['code']}', child: Text('${c['name']} (${c['code']})', overflow: TextOverflow.ellipsis))), const DropdownMenuItem<String>(value: 'Other|', child: Text('Other (type code)'))], onChanged: (v) { if (v != null) setState(() => _selectedCountry = v); })),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Phone Number - OTP comes here', hintText: _isOtherCountry ? 'Number without code' : 'e.g. 241234567 (no 0, no code)'))),
          ]),
          if (_isOtherCountry) Padding(padding: const EdgeInsets.only(top: 8), child: TextField(controller: _otherCode, keyboardType: TextInputType.phone, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Your Country Code', hintText: 'e.g. +999'))),
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerLeft, child: Text('OTP will be sent to: ${_phone.text.trim().isEmpty ? '...' : _fullPhone}', style: const TextStyle(fontSize: 12, color: Colors.grey))),
          TextField(controller: _pass, obscureText: _obscurePassword, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'Password - you will login with this', hintText: 'Min 8 chars, upper + lower + number + symbol', suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)))),
          const SizedBox(height: 8),
          if (_pass.text.isNotEmpty) ...[
            Row(children: [Expanded(child: LinearProgressIndicator(value: _passwordScore / 6, backgroundColor: Colors.grey.shade300, color: _passwordStrengthColor, minHeight: 6)), const SizedBox(width: 8), Text(_passwordStrengthLabel, style: TextStyle(color: _passwordStrengthColor, fontWeight: FontWeight.bold))]),
            const SizedBox(height: 6),
            ..._passwordMissing.map((m) => Row(children: [const Icon(Icons.close, size: 14, color: Colors.red), const SizedBox(width: 4), Expanded(child: Text(m, style: const TextStyle(fontSize: 12, color: Colors.red)))])),
            if (_isStrongPassword) const Row(children: [Icon(Icons.check_circle, size: 14, color: Colors.green), SizedBox(width: 4), Text('Strong password', style: TextStyle(fontSize: 12, color: Colors.green))]),
          ],
          const SizedBox(height: 16),
          ListTile(leading: const Icon(Icons.photo), title: Text(_photo == null ? 'Upload Photo (optional)' : 'Photo Selected: ${_photo!.name}'), trailing: ElevatedButton(onPressed: _pickPhoto, child: const Text('Pick Photo'))),
          const SizedBox(height: 20),
          _loading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _register, child: const Text('REGISTER - SEND SMS OTP')),
          const SizedBox(height: 8),
          const Text('After SMS OTP, login with Phone Number + Password. No CEO approval needed.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ),
    );
  }
}
