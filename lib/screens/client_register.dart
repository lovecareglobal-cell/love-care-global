import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Client Registration - Flutter version of client-registration.html
/// Flow: Full Name + Username + Country Code + REAL Phone + Strong Password + Photo
/// -> Check username & phone not taken -> Send SMS OTP via Firebase Phone Auth
/// -> Verify 6-digit OTP -> Save to allowedClients + clients + verifiedPhones
/// -> Redirect to client-login

class ClientRegisterScreen extends StatefulWidget {
  const ClientRegisterScreen({super.key});
  @override
  State<ClientRegisterScreen> createState() => _ClientRegisterScreenState();
}

class _ClientRegisterScreenState extends State<ClientRegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String countryCode = '+233'; // Ghana default, same as HTML
  File? photoFile;
  String? verificationId;
  int? resendToken;
  bool showOtpBox = false;
  bool isLoading = false;
  bool showPass = false;
  String status = '';
  bool isStatusOk = true;
  final _otpCtrl = TextEditingController();
  final picker = ImagePicker();

  final List<Map<String,String>> countries = [
    {'code': '+233', 'name': 'Ghana 🇬🇭'},
    {'code': '+234', 'name': 'Nigeria 🇳🇬'},
    {'code': '+254', 'name': 'Kenya 🇰🇪'},
    {'code': '+27', 'name': 'South Africa 🇿🇦'},
    {'code': '+1', 'name': 'USA 🇺🇸'},
    {'code': '+44', 'name': 'UK 🇬🇧'},
    {'code': '+971', 'name': 'UAE 🇦🇪'},
    {'code': '+91', 'name': 'India 🇮🇳'},
  ];

  String get fullPhone => '$countryCode${_phoneCtrl.text.trim().replaceAll(RegExp(r'^0+'), '')}';

  void _setStatus(String msg, bool ok) {
    setState(() { status = msg; isStatusOk = ok; });
  }

  bool _isStrongPassword(String p) {
    // Same as HTML: min 8, upper, lower, number, special
    if (p.length < 8) return false;
    if (!RegExp(r'[A-Z]').hasMatch(p)) return false;
    if (!RegExp(r'[a-z]').hasMatch(p)) return false;
    if (!RegExp(r'[0-9]').hasMatch(p)) return false;
    if (!RegExp(r'[!@#\$%^&*]').hasMatch(p)) return false;
    return true;
  }

  Future<void> _pickPhoto() async {
    final XFile? f = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (f != null) setState(() => photoFile = File(f.path));
  }

  Future<void> _startRegistration() async {
    final fullName = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    final phone = fullPhone;

    if (fullName.isEmpty) { _setStatus('Full Name is required - for traceability', false); return; }
    if (username.isEmpty || phone.isEmpty || pass.isEmpty) { _setStatus('Fill Full Name, Username, Phone, Password', false); return; }
    if (username.length < 3) { _setStatus('Username min 3 chars', false); return; }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) { _setStatus('Username only letters, numbers, _', false); return; }
    if (!_isStrongPassword(pass)) { _setStatus('Weak password - Min 8 chars, Upper + Lower + Number + Special (!@#)', false); return; }
    if (pass != confirm) { _setStatus('Passwords mismatch', false); return; }
    if (photoFile == null) { _setStatus('Upload photo - real face required', false); return; }
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) { _setStatus('Invalid phone: $phone - Must be REAL number', false); return; }

    setState(() => isLoading = true);
    _setStatus('Checking username & REAL phone...', true);
    try {
      // Check username taken - same as HTML: allowedClients/username
      final snap = await FirebaseDatabase.instance.ref('allowedClients/$username').get();
      if (snap.exists) { _setStatus('Username taken - choose another', false); setState(() => isLoading = false); return; }
      // Check phone taken
      final phoneSnap = await FirebaseDatabase.instance.ref('allowedClients').orderByChild('phone').equalTo(phone).get();
      if (phoneSnap.exists) { _setStatus('This REAL phone already registered - cannot fake', false); setState(() => isLoading = false); return; }

      _setStatus('Sending SMS to REAL number $phone...', true);
      // Flutter Phone Auth - no reCAPTCHA needed like web, uses native verification
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential cred) async {
          // Auto-verification on Android - skip OTP box
          await _verifyWithCredential(cred);
        },
        verificationFailed: (FirebaseAuthException e) {
          _setStatus('SMS failed: ${e.message} - Ensure phone is REAL and has signal. If Ghana +233 not enabled, enable in Firebase Console → Auth → SMS Region Policy → Allow +233', false);
          setState(() => isLoading = false);
        },
        codeSent: (String verId, int? token) {
          setState(() { verificationId = verId; resendToken = token; showOtpBox = true; isLoading = false; });
          _setStatus('✅ SMS sent to REAL phone $phone - If you fake number, you cannot receive code!', true);
        },
        codeAutoRetrievalTimeout: (String verId) { verificationId = verId; },
        timeout: const Duration(seconds: 60),
        forceResendingToken: resendToken,
      );
    } catch (e) {
      _setStatus('SMS failed: $e', false);
      setState(() => isLoading = false);
    }
  }

  Future<void> _verifyWithCredential(PhoneAuthCredential cred) async {
    try {
      final userCred = await FirebaseAuth.instance.signInWithCredential(cred);
      await _saveClient(userCred.user!.uid);
    } catch (e) {
      _setStatus('Verification failed: $e', false);
    }
  }

  Future<void> _verifyOTP() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) { _setStatus('Enter 6-digit REAL SMS code', false); return; }
    if (verificationId == null) { _setStatus('No verification - Send SMS first', false); return; }
    _setStatus('Verifying REAL person...', true);
    try {
      final cred = PhoneAuthProvider.credential(verificationId: verificationId!, smsCode: code);
      final userCred = await FirebaseAuth.instance.signInWithCredential(cred);
      await _saveClient(userCred.user!.uid);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-verification-code') _setStatus('Wrong code - Only REAL owner of phone can get correct code', false);
      else _setStatus('Failed: ${e.message}', false);
    }
  }

  Future<void> _saveClient(String phoneUid) async {
    final fullName = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim().toLowerCase();
    final phone = fullPhone;
    _setStatus('✅ Phone verified - REAL person confirmed! Creating...', true);
    String photoUrl = '';
    try {
      final ref = FirebaseStorage.instance.ref().child('clientPhotos/$username.jpg');
      await ref.putFile(photoFile!);
      photoUrl = await ref.getDownloadURL();
    } catch (e) { print('Photo upload failed, using local: $e'); }

    final clientData = {
      'fullName': fullName, 'name': fullName,
      'username': username, 'phone': phone, 'countryCode': countryCode,
      'phoneVerified': true, 'phoneVerifiedReal': true, 'phoneUid': phoneUid,
      'photoUrl': photoUrl, 'photo': photoUrl, 'avatarUrl': photoUrl,
      'hasAll4': true, 'isApproved': true, 'isBlocked': false, 'isRealPerson': true,
      'verificationMethod': 'SMS_OTP_REAL',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'registrationMethod': 'fullName+username+countryCode+REAL_PHONE_SMS',
    };
    // Same paths as HTML
    await FirebaseDatabase.instance.ref('allowedClients/$username').set(clientData);
    await FirebaseDatabase.instance.ref('clients/$username').set(clientData);
    await FirebaseDatabase.instance.ref('ceoRegistrations/clients/$username').set(clientData);
    await FirebaseDatabase.instance.ref('clientRegistrations/$username').set(clientData);
    await FirebaseDatabase.instance.ref('verifiedPhones/${phone.replaceAll(RegExp(r'[^0-9]'), '')}').set({
      'username': username, 'fullName': fullName, 'phone': phone, 'countryCode': countryCode,
      'verifiedAt': DateTime.now().millisecondsSinceEpoch, 'isReal': true,
    });

    _setStatus('SUCCESS! REAL person $fullName ($username) verified - CEO can trace via phone $phone', true);
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('✅ Verified!'),
      content: Text('Welcome $fullName! Your phone is verified. Login with username $username'),
      actions: [TextButton(onPressed: () => Navigator.popUntil(context, (r) => r.isFirst), child: const Text('Go to Login'))],
    ));
  }

  Future<void> _resendOTP() async {
    _setStatus('Resending SMS...', true);
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: fullPhone,
      verificationCompleted: (c) async => await _verifyWithCredential(c),
      verificationFailed: (e) => _setStatus('Resend failed: ${e.message}', false),
      codeSent: (verId, token) { setState(() { verificationId = verId; resendToken = token; }); _setStatus('✅ SMS resent', true); },
      codeAutoRetrievalTimeout: (verId) => verificationId = verId,
      forceResendingToken: resendToken,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(title: const Text('Client Registration - SMS Verification'), backgroundColor: const Color(0xFF1E1A3A)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          const Text('Your health, our heart.\nRegister with REAL phone - SMS OTP verifies you are a real person.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          GestureDetector(onTap: _pickPhoto, child: CircleAvatar(radius: 40, backgroundImage: photoFile != null ? FileImage(photoFile!) : null, child: photoFile == null ? const Icon(Icons.camera_alt, size: 32) : null)),
          const SizedBox(height: 6),
          const Text('Tap to upload photo - real face required', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 10)),
          const SizedBox(height: 16),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Full Name *', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _usernameCtrl, decoration: const InputDecoration(labelText: 'Username * (letters, numbers, _)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(flex: 2, child: DropdownButtonFormField<String>(value: countryCode, decoration: const InputDecoration(labelText: 'Country', border: OutlineInputBorder()), items: countries.map((c) => DropdownMenuItem(value: c['code'], child: Text('${c['code']} ${c['name']}'))).toList(), onChanged: (v) => setState(() => countryCode = v ?? '+233'))),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone (without 0) *', border: OutlineInputBorder(), hintText: '544121814'), keyboardType: TextInputType.phone)),
          ]),
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerLeft, child: Text('Full phone: $fullPhone', style: const TextStyle(color: Colors.white60, fontSize: 11))),
          const SizedBox(height: 10),
          TextField(controller: _passCtrl, obscureText: !showPass, decoration: InputDecoration(labelText: 'Password * (Min 8, Upper+Lower+Number+Special)', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(showPass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => showPass = !showPass)))),
          const SizedBox(height: 10),
          TextField(controller: _confirmCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm Password *', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          if (status.isNotEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isStatusOk ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: isStatusOk ? Colors.green : Colors.red)), child: Text(status, textAlign: TextAlign.center, style: TextStyle(color: isStatusOk ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5), fontSize: 11))),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: isLoading ? null : _startRegistration, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(isLoading ? 'Sending SMS...' : 'SEND SMS OTP → VERIFY REAL PERSON', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))),
          // OTP Box - same as HTML otpBox
          if (showOtpBox) ...[
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF0E0A1C), border: Border.all(color: const Color(0xFFFACC15)), borderRadius: BorderRadius.circular(12)), child: Column(children: [
              Text('Enter 6-digit code sent to $fullPhone', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextField(controller: _otpCtrl, keyboardType: TextInputType.number, maxLength: 6, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold), decoration: const InputDecoration(hintText: '______', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _verifyOTP, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)), child: const Text('✅ VERIFY OTP'))),
              TextButton(onPressed: _resendOTP, child: const Text('Resend OTP')),
            ])),
          ],
          const SizedBox(height: 12),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Already have account? Login')),
        ]),
      ),
    );
  }
}
