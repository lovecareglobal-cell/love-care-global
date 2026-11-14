import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';

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
  final _otp = TextEditingController();
  XFile? _photo;
  bool _loading = false;
  bool _obscurePassword = true;
  final _picker = ImagePicker();

  // ---- OTP (Firebase Phone Auth) ----
  String? _verificationId;
  int? _resendToken;
  bool _otpSending = false;
  bool _phoneVerified = false;
  PhoneAuthCredential? _pendingPhoneCredential;

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

  // ---- PHONE (E.164) ----
  // Type +233..., +234..., etc. If they type 0XXXXXXXXX (Ghana style)
  // or 10 digits with no +, we assume Ghana +233.
  String _normalizePhone(String raw) {
    var p = raw.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (p.startsWith('00')) p = '+${p.substring(2)}';
    if (p.startsWith('+')) return p;
    if (p.startsWith('0')) return '+233${p.substring(1)}';
    if (RegExp(r'^\d{10}$').hasMatch(p)) return '+233$p';
    if (RegExp(r'^\d+$').hasMatch(p)) return '+$p';
    return p;
  }

  // ---- OTP: send + verify ----
  // OTP is verified BEFORE any email account is created.
  // If OTP fails / is cancelled, NO account exists, so NO login is possible.
  Future<bool> _sendOtp(String phone) async {
    setState(() { _otpSending = true; _otp.clear(); });
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential cred) {
          // Auto-retrieval (Android SMS auto-read) - counts as verified.
          _phoneVerified = true;
          _pendingPhoneCredential = cred;
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not send OTP: ${e.message ?? e.code}'), backgroundColor: Colors.red));
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('OTP sent to $phone. Enter the 6-digit code.')));
        },
        codeAutoRetrievalTimeout: (String verificationId) { _verificationId = verificationId; },
      );
      return true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send OTP: $e'), backgroundColor: Colors.red));
      return false;
    } finally {
      if (mounted) setState(() => _otpSending = false);
    }
  }

  // Shows OTP dialog. Returns verified credential, or null on fail/cancel.
  // Max 3 wrong attempts -> blocked, no login.
  Future<PhoneAuthCredential?> _askAndVerifyOtp(String phone) async {
    if (_pendingPhoneCredential != null) return _pendingPhoneCredential;
    if (_verificationId == null) return null;
    int attempts = 0;
    while (attempts < 3) {
      final code = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Enter OTP'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('We sent a 6-digit code to\n$phone', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextField(
              controller: _otp, keyboardType: TextInputType.number, maxLength: 6,
              decoration: const InputDecoration(labelText: 'OTP code', hintText: '123456'),
            ),
            if (attempts > 0) Text('Wrong code. ${3 - attempts} attempt(s) left.',
                style: const TextStyle(color: Colors.red)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => _sendOtp(phone), child: const Text('Resend')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, _otp.text.trim()), child: const Text('Verify')),
          ],
        ),
      );
      if (code == null || code.isEmpty) return null; // cancelled -> NO login
      try {
        final cred = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: code);
        await FirebaseAuth.instance.signInWithCredential(cred);
        _phoneVerified = true;
        _pendingPhoneCredential = cred;
        return cred;
      } on FirebaseAuthException catch (e) {
        attempts++;
        await FirebaseAuth.instance.signOut();
        if (attempts >= 3) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Too many wrong OTP attempts. Registration blocked. No login.'), backgroundColor: Colors.red));
          return null;
        }
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Wrong OTP (${e.message ?? 'invalid code'}). Try again.'), backgroundColor: Colors.red));
      }
    }
    return null;
  }

  // ---- STRONG PASSWORD ----
  // Strong = at least 8 chars + upper + lower + digit + special. No spaces.
  int get _passwordScore {
    final p = _pass.text;
    var score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    return score; // 0-6
  }

  bool get _isStrongPassword {
    final p = _pass.text;
    return p.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(p) &&
        RegExp(r'[a-z]').hasMatch(p) &&
        RegExp(r'[0-9]').hasMatch(p) &&
        RegExp(r'[^A-Za-z0-9]').hasMatch(p) &&
        !p.contains(' ');
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
    final p = _pass.text;
    final missing = <String>[];
    if (p.length < 8) missing.add('At least 8 characters');
    if (!RegExp(r'[A-Z]').hasMatch(p)) missing.add('One UPPERCASE letter (A-Z)');
    if (!RegExp(r'[a-z]').hasMatch(p)) missing.add('One lowercase letter (a-z)');
    if (!RegExp(r'[0-9]').hasMatch(p)) missing.add('One number (0-9)');
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(p)) missing.add('One special character (! @ # \$ % etc.)');
    if (p.contains(' ')) missing.add('No spaces');
    return missing;
  }

  Future<void> _register() async {
    if (_name.text.isEmpty || _email.text.isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill all fields')));
      return;
    }
    if (!_isStrongPassword) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Password too weak. Missing: ${_passwordMissing.join(', ')}'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    if (_phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your phone number (e.g. +233XXXXXXXXX)')));
      return;
    }
    final phone = _normalizePhone(_phone.text);
    // 1) OTP TO PHONE - must PASS before any account is created. No ID needed.
    _pendingPhoneCredential = null; _phoneVerified = false;
    await _sendOtp(phone);
    if (_verificationId == null && _pendingPhoneCredential == null) return; // SMS failed
    final phoneCred = await _askAndVerifyOtp(phone);
    if (phoneCred == null || !_phoneVerified) {
      await FirebaseAuth.instance.signOut();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('OTP not verified. Registration cancelled. You cannot login.'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _loading = true);
    try {
      // 2) Create email account LINKED to the verified phone number.
      // User is already signed in with the phone credential from OTP.
      final emailCred = EmailAuthProvider.credential(email: _email.text.trim(), password: _pass.text.trim());
      try {
        await FirebaseAuth.instance.currentUser!.linkWithCredential(emailCred);
      } on FirebaseAuthException catch (e) {
        await FirebaseAuth.instance.signOut();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not create account: ${e.message ?? e.code}'), backgroundColor: Colors.red));
        return;
      }
      final uid = FirebaseAuth.instance.currentUser!.uid;

      String? photoUrl;
      if (_photo != null) photoUrl = await _upload(_photo!, 'clients/$uid/photo.jpg');

      // CLIENTS DO NOT NEED CEO APPROVAL: status=approved, can login immediately.
      // NO ID fields - ID removed from client registration.
      final data = <String, Object?>{
        'uid': uid,
        'id': uid,
        'name': _name.text.trim(),
        'fullName': _name.text.trim(),
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'phone': phone,
        'role': 'client',
        'type': 'client',
        'status': 'approved',
        'isApproved': true,
        'approved': true,
        'hasAll4': true,
        'phoneVerified': true,
        'otpVerified': true,
        'photo': photoUrl ?? '',
        'photoUrl': photoUrl ?? '',
        'photoURL': photoUrl ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance.collection('clients').doc(uid).set(data);

      // RTDB - INFO ONLY for CEO records. CEO does NOT approve clients.
      final rtdbData = Map<String, Object?>.from(data)
        ..['createdAt'] = DateTime.now().millisecondsSinceEpoch;
      await FirebaseDatabase.instance.ref('ceoRegistrationCenter/clients/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('clients/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('client_registrations/$uid').set(rtdbData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registered! Phone verified. You can login now.')));
      await FirebaseAuth.instance.signOut(); // back to login screen, login works immediately
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
      appBar: AppBar(title: const Text('Client Registration'), backgroundColor: Colors.purple, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name')),
            TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username')),
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', hintText: '+233XXXXXXXXX - OTP will be sent here')),
            TextField(
              controller: _pass,
              obscureText: _obscurePassword,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Min 8 chars, upper + lower + number + symbol',
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_pass.text.isNotEmpty) ...[
              Row(children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: _passwordScore / 6,
                    backgroundColor: Colors.grey.shade300,
                    color: _passwordStrengthColor,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_passwordStrengthLabel,
                    style: TextStyle(color: _passwordStrengthColor, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 6),
              ..._passwordMissing.map((m) => Row(children: [
                    const Icon(Icons.close, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Expanded(child: Text(m, style: const TextStyle(fontSize: 12, color: Colors.red))),
                  ])),
              if (_isStrongPassword)
                const Row(children: [
                  Icon(Icons.check_circle, size: 14, color: Colors.green),
                  SizedBox(width: 4),
                  Text('Strong password ✓', style: TextStyle(fontSize: 12, color: Colors.green)),
                ]),
            ],
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo),
              title: Text(_photo == null ? 'Upload Photo (optional)' : 'Photo Selected: ${_photo!.name}'),
              trailing: ElevatedButton(onPressed: _pickPhoto, child: const Text('Pick Photo')),
            ),
            const SizedBox(height: 20),
            _loading || _otpSending
                ? const CircularProgressIndicator()
                : ElevatedButton(onPressed: _register, child: const Text('REGISTER AS CLIENT')),
          ],
        ),
      ),
    );
  }
}
