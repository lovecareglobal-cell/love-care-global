import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocus = List.generate(6, (_) => FocusNode());
  XFile? _photo;

  // CLIENT OTP RULE:
  // Pending = OTP NOT verified. CEO does NOT approve Client.
  // OTP verified -> isApproved = true, canLogin = true, status = approved -> Login with Phone + Password straight.
  // NO Gmail link. Client stays inside app, types 6-digit OTP from Gmail.
  bool _waitingOtp = false;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _otpSending = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  String _otpStatus = '';
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

  Future<String?> _checkEmailNotUsedAsNurse(String email) async {
    final e = email.trim().toLowerCase();
    final inNurses = await FirebaseFirestore.instance.collection('nurses').where('email', isEqualTo: e).limit(1).get();
    if (inNurses.docs.isNotEmpty) return 'BLOCKED: This email is already registered as a NURSE. Use Nurse Login.';
    final inPending = await FirebaseFirestore.instance.collection('pending_nurses').where('email', isEqualTo: e).limit(1).get();
    if (inPending.docs.isNotEmpty) return 'BLOCKED: This email is already registered as a NURSE (waiting approval).';
    final inClients = await FirebaseFirestore.instance.collection('clients').where('email', isEqualTo: e).limit(1).get();
    if (inClients.docs.isNotEmpty) {
      final d = inClients.docs.first.data();
      if ((d['otpVerified'] == true || d['emailVerified'] == true) && d['isApproved'] == true) {
        return 'BLOCKED: This email is already registered as a CLIENT. Login with Phone + Password instead.';
      }
      return null;
    }
    return null;
  }

  // SAVE IMMEDIATELY + PHONE INDEX - so Phone Login can find this client later
  // Firestore gets FieldValue, RTDB gets int ONLY. Never send FieldValue to RTDB.
  Future<void> _saveProfileImmediately({required String uid, required String email, required String name, required String username, required String phone, String photoUrl = ''}) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final firestoreData = <String, Object?>{
      'uid': uid, 'id': uid, 'name': name, 'fullName': name, 'username': username, 'email': email.toLowerCase(),
      'phone': phone, 'countryCode': _selectedDialCode, 'country': _selectedCountryName,
      'role': 'client', 'type': 'client', 'status': 'pending', 'isApproved': false, 'approved': false,
      'approvalStatus': 'pending', 'canLogin': false, 'phoneVerified': false, 'otpVerified': false,
      'emailVerified': false, 'verifiedByEmail': false, 'isComplete': false, 'hasAll4': false,
      'photo': photoUrl, 'photoUrl': photoUrl, 'photoURL': photoUrl, 'createdAt': FieldValue.serverTimestamp(),
    };
    final rtdbData = <String, Object?>{
      'uid': uid, 'id': uid, 'name': name, 'fullName': name, 'username': username, 'email': email.toLowerCase(),
      'phone': phone, 'countryCode': _selectedDialCode, 'country': _selectedCountryName,
      'role': 'client', 'type': 'client', 'status': 'pending', 'isApproved': false, 'approved': false,
      'approvalStatus': 'pending', 'canLogin': false, 'phoneVerified': false, 'otpVerified': false,
      'emailVerified': false, 'verifiedByEmail': false, 'isComplete': false, 'hasAll4': false,
      'photo': photoUrl, 'photoUrl': photoUrl, 'photoURL': photoUrl, 'createdAt': nowMs,
    };
    await FirebaseFirestore.instance.collection('clients').doc(uid).set(firestoreData, SetOptions(merge: true));
    await FirebaseDatabase.instance.ref('ceoRegistrationCenter/clients/$uid').set(rtdbData);
    await FirebaseDatabase.instance.ref('clients/$uid').set(rtdbData);
    await FirebaseDatabase.instance.ref('client_registrations/$uid').set(rtdbData);
    // PHONE INDEX - THIS MAKES PHONE + PASSWORD LOGIN WORK
    if (digits.isNotEmpty) {
      await FirebaseDatabase.instance.ref('phones/$digits').set(email.toLowerCase());
      await FirebaseDatabase.instance.ref('clientsByPhone/$digits').set(uid);
    }
  }

  Future<void> _savePendingOtp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('client_pending_otp', true);
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
      await prefs.remove('client_pending_otp');
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

  // If app close for OTP screen, come back -> go straight to OTP screen, no disappear
  Future<void> _resumePendingOtp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('client_pending_otp') != true && prefs.getBool('client_pending_verification') != true) return;
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) {
        await _clearPending();
        return;
      }
      if (_name.text.isEmpty) _name.text = prefs.getString('client_pending_name') ?? '';
      if (_username.text.isEmpty) _username.text = prefs.getString('client_pending_username') ?? '';
      if (_email.text.isEmpty) _email.text = prefs.getString('client_pending_email') ?? '';
      final photoPath = prefs.getString('client_pending_photo_path');
      if (_photo == null && photoPath != null && photoPath.isNotEmpty) {
        try { _photo = XFile(photoPath); } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _waitingOtp = true;
        _otpStatus = 'Welcome back! Your OTP still dey. Check Gmail for 6-digit code.';
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
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty) return;
    setState(() { _otpSending = true; _otpStatus = 'Sending OTP to $email...'; });
    try {
      await FirebaseFunctions.instance.httpsCallable('sendClientEmailOtp').call({'email': email});
      if (mounted) setState(() { _otpStatus = 'OTP sent to $email. Check Gmail / Spam. Valid for 10 minutes.'; });
      _startResendCountdown();
    } catch (e) {
      if (mounted) setState(() => _otpStatus = 'Failed to send OTP: $e. Tap Resend.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send OTP: $e')));
    } finally {
      if (mounted) setState(() => _otpSending = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter complete 6-digit OTP')));
      return;
    }
    setState(() => _loading = true);
    try {
      final email = _email.text.trim().toLowerCase();
      final res = await FirebaseFunctions.instance.httpsCallable('verifyClientEmailOtp').call({'email': email, 'otp': _otpCode});
      final ok = res.data is Map ? res.data['ok'] == true : true;
      if (!ok) throw Exception(res.data is Map ? res.data['message'] ?? 'Wrong OTP' : 'Wrong OTP');
      await _finishAfterOtpVerified();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OTP failed: $e'), backgroundColor: Colors.red));
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finishAfterOtpVerified() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No user. Register again.');
      final uid = user.uid;
      String? photoUrl;
      if (_photo != null) {
        try { photoUrl = await _upload(_photo!, 'clients/$uid/photo.jpg'); } catch (_) {}
      }
      final prefs = await SharedPreferences.getInstance();
      final name = _name.text.trim().isNotEmpty ? _name.text.trim() : (prefs.getString('client_pending_name') ?? '');
      final username = _username.text.trim().isNotEmpty ? _username.text.trim() : (prefs.getString('client_pending_username') ?? '');
      final email = _email.text.trim().isNotEmpty ? _email.text.trim().toLowerCase() : (prefs.getString('client_pending_email') ?? user.email?.toLowerCase() ?? '');
      final phone = _fullPhone.isNotEmpty ? _fullPhone : (prefs.getString('client_pending_phone') ?? '');
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

      final firestoreUpdate = <String, Object?>{
        'uid': uid, 'fullName': name, 'name': name, 'username': username, 'email': email, 'phone': phone,
        'emailVerified': true, 'verifiedByEmail': true, 'otpVerified': true,
        'status': 'approved', 'isApproved': true, 'approved': true, 'approvalStatus': 'approved',
        'canLogin': true, 'isVerified': true, 'isComplete': true, 'hasAll4': true,
        'approvedAt': FieldValue.serverTimestamp(),
        if (photoUrl != null && photoUrl.isNotEmpty) 'photo': photoUrl,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoURL': photoUrl,
      };
      final rtdbUpdate = <String, Object?>{
        'uid': uid, 'fullName': name, 'name': name, 'username': username, 'email': email, 'phone': phone,
        'emailVerified': true, 'verifiedByEmail': true, 'otpVerified': true,
        'status': 'approved', 'isApproved': true, 'approved': true, 'approvalStatus': 'approved',
        'canLogin': true, 'isVerified': true, 'isComplete': true, 'hasAll4': true,
        'approvedAt': nowMs, 'updatedAt': nowMs,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photo': photoUrl,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoURL': photoUrl,
      };

      await FirebaseFirestore.instance.collection('clients').doc(uid).set(firestoreUpdate, SetOptions(merge: true));
      await FirebaseDatabase.instance.ref('ceoRegistrationCenter/clients/$uid').update(rtdbUpdate);
      await FirebaseDatabase.instance.ref('clients/$uid').update(rtdbUpdate);
      await FirebaseDatabase.instance.ref('client_registrations/$uid').update(rtdbUpdate);
      await FirebaseDatabase.instance.ref('allowedClients/${email.replaceAll(RegExp(r'[.#\$@\[\]]'), '_')}').set({...rtdbUpdate, 'uid': uid});
      await FirebaseDatabase.instance.ref('allowedClientsByUid/$uid').set({...rtdbUpdate, 'uid': uid});
      // PHONE INDEX - again after verify, so Phone Login must work
      if (digits.isNotEmpty) {
        await FirebaseDatabase.instance.ref('phones/$digits').set(email);
        await FirebaseDatabase.instance.ref('clientsByPhone/$digits').set(uid);
      }

      await _clearPending();
      if (!mounted) return;
      setState(() { _waitingOtp = false; _loading = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP verified! You are approved. Login with Phone + Password now - no CEO approval needed.')));
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ClientLoginPage()));
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
    }
  }

  Future<void> _cancelOtp() async {
    _resendTimer?.cancel();
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
    setState(() { _waitingOtp = false; _loading = false; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP cancelled. Register again.'), backgroundColor: Colors.red));
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
    final email = _email.text.trim().toLowerCase();
    final blocked = await _checkEmailNotUsedAsNurse(email);
    if (blocked != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blocked), backgroundColor: Colors.red));
      return;
    }
    setState(() => _loading = true);
    try {
      UserCredential cred;
      try {
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: _pass.text.trim());
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This email already has an account. We will resume OTP - check Gmail for code.'), backgroundColor: Colors.orange));
          try {
            cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: _pass.text.trim());
            final uid = cred.user!.uid;
            await _saveProfileImmediately(uid: uid, email: email, name: _name.text.trim(), username: _username.text.trim(), phone: _fullPhone);
            await _savePendingOtp();
            if (!mounted) return;
            setState(() { _loading = false; _waitingOtp = true; _otpStatus = 'We resumed your account. Enter OTP sent to $email.'; });
            await _sendOtp();
            return;
          } catch (_) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email already exists. Go to Login with Phone + Password.'), backgroundColor: Colors.red));
            if (mounted) setState(() => _loading = false);
            return;
          }
        }
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create account: ${e.message ?? e.code}'), backgroundColor: Colors.red));
        if (mounted) setState(() => _loading = false);
        return;
      }
      final uid = cred.user!.uid;
      await _saveProfileImmediately(uid: uid, email: email, name: _name.text.trim(), username: _username.text.trim(), phone: _fullPhone);
      await _savePendingOtp();
      if (!mounted) return;
      setState(() { _loading = false; _waitingOtp = true; _otpStatus = 'Sending OTP to $email...'; });
      await _sendOtp();
      return;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted && !_waitingOtp) setState(() => _loading = false);
    }
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
        appBar: AppBar(title: const Text('Enter OTP Code'), backgroundColor: Colors.purple, foregroundColor: Colors.white),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.lock_outline, size: 70, color: Colors.purple),
            const SizedBox(height: 16),
            Text('We sent 6-digit code to\n${_email.text.trim().toLowerCase()}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Check Gmail / Spam. Enter code below. You stay inside app, no need to leave.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(6, (i) => _otpBox(i))),
            const SizedBox(height: 16),
            if (_otpStatus.isNotEmpty) Text(_otpStatus, textAlign: TextAlign.center, style: const TextStyle(color: Colors.purple)),
            const SizedBox(height: 20),
            _loading ? const Center(child: CircularProgressIndicator()) : ElevatedButton(
              onPressed: _verifyOtp,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('VERIFY OTP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            _resendSeconds > 0
                ? Center(child: Text('Resend in $_resendSeconds s', style: const TextStyle(color: Colors.grey)))
                : OutlinedButton(onPressed: _otpSending ? null : _sendOtp, child: Text(_otpSending ? 'Sending...' : 'Resend OTP')),
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
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email - for OTP only')),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: DropdownButtonFormField<String>(value: _selectedCountry, isExpanded: true, decoration: const InputDecoration(labelText: 'Country Code'), items: [..._countries.map((c) => DropdownMenuItem<String>(value: '${c['name']}|${c['code']}', child: Text('${c['name']} (${c['code']})', overflow: TextOverflow.ellipsis))), const DropdownMenuItem<String>(value: 'Other|', child: Text('Other (type code)'))], onChanged: (v) { if (v != null) setState(() => _selectedCountry = v); })),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Phone Number - you will login with this', hintText: _isOtherCountry ? 'Number without code' : 'e.g. 241234567 (no 0, no code)'))),
          ]),
          if (_isOtherCountry) Padding(padding: const EdgeInsets.only(top: 8), child: TextField(controller: _otherCode, keyboardType: TextInputType.phone, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Your Country Code', hintText: 'e.g. +999'))),
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerLeft, child: Text('Full number for login: ${_phone.text.trim().isEmpty ? '...' : _fullPhone}', style: const TextStyle(fontSize: 12, color: Colors.grey))),
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
          _loading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _register, child: const Text('REGISTER AS CLIENT - SEND OTP')),
          const SizedBox(height: 8),
          const Text('After OTP, login with Phone Number + Password. No CEO approval needed.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ),
    );
  }
}
