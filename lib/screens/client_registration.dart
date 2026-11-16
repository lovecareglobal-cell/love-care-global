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
  // ---- AUTO VERIFY (no 'I Verified' button) ----
  // Some phones kill the app when you go to Gmail. The old dialog was gone on return (fresh start).
  // So: we save pending data to SharedPreferences + poll reload() every 3s + resume check.
  // When emailVerified becomes true, we auto-save and open Login straight.
  bool _waitingVerification = false;
  String _verifyStatus = '';
  Timer? _verifyTimer;
  bool _finishingVerification = false;
  bool _loading = false;
  bool _obscurePassword = true;
  final _picker = ImagePicker();

  // ---- OTP (Firebase Phone Auth) ----
  String? _verificationId;
  int? _resendToken;
  bool _otpSending = false;
  bool _phoneVerified = false;
  PhoneAuthCredential? _pendingPhoneCredential;

  // ---- COUNTRY CODE (WORLD) ----
  // Full world list. Value is "Name|+code" so countries sharing a code
  // (e.g. USA +1 / Canada +1) stay unique in the dropdown.
  // "Other" lets anyone whose country is not listed type their own code.
  static const List<Map<String, String>> _countries = [
    {"name": "Afghanistan", "code": "+93"},
    {"name": "Albania", "code": "+355"},
    {"name": "Algeria", "code": "+213"},
    {"name": "Andorra", "code": "+376"},
    {"name": "Angola", "code": "+244"},
    {"name": "Antigua and Barbuda", "code": "+1268"},
    {"name": "Argentina", "code": "+54"},
    {"name": "Armenia", "code": "+374"},
    {"name": "Australia", "code": "+61"},
    {"name": "Austria", "code": "+43"},
    {"name": "Azerbaijan", "code": "+994"},
    {"name": "Bahamas", "code": "+1242"},
    {"name": "Bahrain", "code": "+973"},
    {"name": "Bangladesh", "code": "+880"},
    {"name": "Barbados", "code": "+1246"},
    {"name": "Belarus", "code": "+375"},
    {"name": "Belgium", "code": "+32"},
    {"name": "Belize", "code": "+501"},
    {"name": "Benin", "code": "+229"},
    {"name": "Bhutan", "code": "+975"},
    {"name": "Bolivia", "code": "+591"},
    {"name": "Bosnia and Herzegovina", "code": "+387"},
    {"name": "Botswana", "code": "+267"},
    {"name": "Brazil", "code": "+55"},
    {"name": "Brunei", "code": "+673"},
    {"name": "Bulgaria", "code": "+359"},
    {"name": "Burkina Faso", "code": "+226"},
    {"name": "Burundi", "code": "+257"},
    {"name": "Cambodia", "code": "+855"},
    {"name": "Cameroon", "code": "+237"},
    {"name": "Canada", "code": "+1"},
    {"name": "Cape Verde", "code": "+238"},
    {"name": "Central African Republic", "code": "+236"},
    {"name": "Chad", "code": "+235"},
    {"name": "Chile", "code": "+56"},
    {"name": "China", "code": "+86"},
    {"name": "Colombia", "code": "+57"},
    {"name": "Comoros", "code": "+269"},
    {"name": "Congo", "code": "+242"},
    {"name": "Congo (DRC)", "code": "+243"},
    {"name": "Costa Rica", "code": "+506"},
    {"name": "Côte d'Ivoire", "code": "+225"},
    {"name": "Croatia", "code": "+385"},
    {"name": "Cuba", "code": "+53"},
    {"name": "Cyprus", "code": "+357"},
    {"name": "Czechia", "code": "+420"},
    {"name": "Denmark", "code": "+45"},
    {"name": "Djibouti", "code": "+253"},
    {"name": "Dominica", "code": "+1767"},
    {"name": "Dominican Republic", "code": "+1809"},
    {"name": "Ecuador", "code": "+593"},
    {"name": "Egypt", "code": "+20"},
    {"name": "El Salvador", "code": "+503"},
    {"name": "Equatorial Guinea", "code": "+240"},
    {"name": "Eritrea", "code": "+291"},
    {"name": "Estonia", "code": "+372"},
    {"name": "Eswatini", "code": "+268"},
    {"name": "Ethiopia", "code": "+251"},
    {"name": "Fiji", "code": "+679"},
    {"name": "Finland", "code": "+358"},
    {"name": "France", "code": "+33"},
    {"name": "Gabon", "code": "+241"},
    {"name": "Gambia", "code": "+220"},
    {"name": "Georgia", "code": "+995"},
    {"name": "Germany", "code": "+49"},
    {"name": "Ghana", "code": "+233"},
    {"name": "Greece", "code": "+30"},
    {"name": "Grenada", "code": "+1473"},
    {"name": "Guatemala", "code": "+502"},
    {"name": "Guinea", "code": "+224"},
    {"name": "Guinea-Bissau", "code": "+245"},
    {"name": "Guyana", "code": "+592"},
    {"name": "Haiti", "code": "+509"},
    {"name": "Honduras", "code": "+504"},
    {"name": "Hungary", "code": "+36"},
    {"name": "Iceland", "code": "+354"},
    {"name": "India", "code": "+91"},
    {"name": "Indonesia", "code": "+62"},
    {"name": "Iran", "code": "+98"},
    {"name": "Iraq", "code": "+964"},
    {"name": "Ireland", "code": "+353"},
    {"name": "Israel", "code": "+972"},
    {"name": "Italy", "code": "+39"},
    {"name": "Jamaica", "code": "+1876"},
    {"name": "Japan", "code": "+81"},
    {"name": "Jordan", "code": "+962"},
    {"name": "Kazakhstan", "code": "+7"},
    {"name": "Kenya", "code": "+254"},
    {"name": "Kiribati", "code": "+686"},
    {"name": "Kuwait", "code": "+965"},
    {"name": "Kyrgyzstan", "code": "+996"},
    {"name": "Laos", "code": "+856"},
    {"name": "Latvia", "code": "+371"},
    {"name": "Lebanon", "code": "+961"},
    {"name": "Lesotho", "code": "+266"},
    {"name": "Liberia", "code": "+231"},
    {"name": "Libya", "code": "+218"},
    {"name": "Liechtenstein", "code": "+423"},
    {"name": "Lithuania", "code": "+370"},
    {"name": "Luxembourg", "code": "+352"},
    {"name": "Madagascar", "code": "+261"},
    {"name": "Malawi", "code": "+265"},
    {"name": "Malaysia", "code": "+60"},
    {"name": "Maldives", "code": "+960"},
    {"name": "Mali", "code": "+223"},
    {"name": "Malta", "code": "+356"},
    {"name": "Marshall Islands", "code": "+692"},
    {"name": "Mauritania", "code": "+222"},
    {"name": "Mauritius", "code": "+230"},
    {"name": "Mexico", "code": "+52"},
    {"name": "Micronesia", "code": "+691"},
    {"name": "Moldova", "code": "+373"},
    {"name": "Monaco", "code": "+377"},
    {"name": "Mongolia", "code": "+976"},
    {"name": "Montenegro", "code": "+382"},
    {"name": "Morocco", "code": "+212"},
    {"name": "Mozambique", "code": "+258"},
    {"name": "Myanmar", "code": "+95"},
    {"name": "Namibia", "code": "+264"},
    {"name": "Nauru", "code": "+674"},
    {"name": "Nepal", "code": "+977"},
    {"name": "Netherlands", "code": "+31"},
    {"name": "New Zealand", "code": "+64"},
    {"name": "Nicaragua", "code": "+505"},
    {"name": "Niger", "code": "+227"},
    {"name": "Nigeria", "code": "+234"},
    {"name": "North Korea", "code": "+850"},
    {"name": "North Macedonia", "code": "+389"},
    {"name": "Norway", "code": "+47"},
    {"name": "Oman", "code": "+968"},
    {"name": "Pakistan", "code": "+92"},
    {"name": "Palau", "code": "+680"},
    {"name": "Palestine", "code": "+970"},
    {"name": "Panama", "code": "+507"},
    {"name": "Papua New Guinea", "code": "+675"},
    {"name": "Paraguay", "code": "+595"},
    {"name": "Peru", "code": "+51"},
    {"name": "Philippines", "code": "+63"},
    {"name": "Poland", "code": "+48"},
    {"name": "Portugal", "code": "+351"},
    {"name": "Qatar", "code": "+974"},
    {"name": "Romania", "code": "+40"},
    {"name": "Russia", "code": "+7"},
    {"name": "Rwanda", "code": "+250"},
    {"name": "Saint Kitts and Nevis", "code": "+1869"},
    {"name": "Saint Lucia", "code": "+1758"},
    {"name": "Saint Vincent", "code": "+1784"},
    {"name": "Samoa", "code": "+685"},
    {"name": "San Marino", "code": "+378"},
    {"name": "Sao Tome and Principe", "code": "+239"},
    {"name": "Saudi Arabia", "code": "+966"},
    {"name": "Senegal", "code": "+221"},
    {"name": "Serbia", "code": "+381"},
    {"name": "Seychelles", "code": "+248"},
    {"name": "Sierra Leone", "code": "+232"},
    {"name": "Singapore", "code": "+65"},
    {"name": "Slovakia", "code": "+421"},
    {"name": "Slovenia", "code": "+386"},
    {"name": "Solomon Islands", "code": "+677"},
    {"name": "Somalia", "code": "+252"},
    {"name": "South Africa", "code": "+27"},
    {"name": "South Korea", "code": "+82"},
    {"name": "South Sudan", "code": "+211"},
    {"name": "Spain", "code": "+34"},
    {"name": "Sri Lanka", "code": "+94"},
    {"name": "Sudan", "code": "+249"},
    {"name": "Suriname", "code": "+597"},
    {"name": "Sweden", "code": "+46"},
    {"name": "Switzerland", "code": "+41"},
    {"name": "Syria", "code": "+963"},
    {"name": "Taiwan", "code": "+886"},
    {"name": "Tajikistan", "code": "+992"},
    {"name": "Tanzania", "code": "+255"},
    {"name": "Thailand", "code": "+66"},
    {"name": "Togo", "code": "+228"},
    {"name": "Tonga", "code": "+676"},
    {"name": "Trinidad and Tobago", "code": "+1868"},
    {"name": "Tunisia", "code": "+216"},
    {"name": "Turkey", "code": "+90"},
    {"name": "Turkmenistan", "code": "+993"},
    {"name": "Tuvalu", "code": "+688"},
    {"name": "Uganda", "code": "+256"},
    {"name": "Ukraine", "code": "+380"},
    {"name": "United Arab Emirates", "code": "+971"},
    {"name": "United Kingdom", "code": "+44"},
    {"name": "United States", "code": "+1"},
    {"name": "Uruguay", "code": "+598"},
    {"name": "Uzbekistan", "code": "+998"},
    {"name": "Vanuatu", "code": "+678"},
    {"name": "Vatican City", "code": "+379"},
    {"name": "Venezuela", "code": "+58"},
    {"name": "Vietnam", "code": "+84"},
    {"name": "Yemen", "code": "+967"},
    {"name": "Zambia", "code": "+260"},
    {"name": "Zimbabwe", "code": "+263"}
  ];
  String _selectedCountry = 'Ghana|+233'; // default: Ghana
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
  // Full international number: selected code + local number (leading 0 removed).
  // If the user already typed a full +... number, use it as-is (no double code).
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

  // ONE EMAIL = ONE ROLE - cross-role block.
  // Returns error message if this email is already used in the OTHER role or same role, else null.
  Future<String?> _checkEmailNotUsedAsNurse(String email) async {
    final e = email.trim().toLowerCase();
    final inNurses = await FirebaseFirestore.instance.collection('nurses').where('email', isEqualTo: e).limit(1).get();
    if (inNurses.docs.isNotEmpty) return 'BLOCKED: This email is already registered as a NURSE. One email cannot be both Nurse + Client. Use Nurse Login.';
    final inPending = await FirebaseFirestore.instance.collection('pending_nurses').where('email', isEqualTo: e).limit(1).get();
    if (inPending.docs.isNotEmpty) return 'BLOCKED: This email is already registered as a NURSE (waiting for CEO approval). One email cannot be both Nurse + Client.';
    final inClients = await FirebaseFirestore.instance.collection('clients').where('email', isEqualTo: e).limit(1).get();
    if (inClients.docs.isNotEmpty) return 'BLOCKED: This email is already registered as a CLIENT. Login as Client instead of registering again.';
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // If app was killed while user was in Gmail, resume: restore pending fields
    // and keep waiting - do NOT make them start fresh.
    _resumePendingVerification();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _verifyTimer?.cancel();
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _phone.dispose();
    _pass.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // User comes back from Gmail -> check immediately, don't wait for next poll.
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
      // Photo path survives restart if file still exists (gallery temp file).
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
      // Restore the form so user does NOT start fresh.
      if (_name.text.isEmpty) _name.text = prefs.getString('client_pending_name') ?? '';
      if (_username.text.isEmpty) _username.text = prefs.getString('client_pending_username') ?? '';
      if (_email.text.isEmpty) _email.text = prefs.getString('client_pending_email') ?? '';
      // Phone: pending phone is full e.g. +233201234567 - put local part back.
      // We keep it simple: if phone field empty, restore full phone digits after code.
      final photoPath = prefs.getString('client_pending_photo_path');
      if (_photo == null && photoPath != null && photoPath.isNotEmpty) {
        try { _photo = XFile(photoPath); } catch (_) {}
      }
      if (!mounted) return;
      setState(() { _waitingVerification = true; _verifyStatus = 'Welcome back! Still waiting for you to tap the link in Gmail...'; });
      _startVerifyPolling();
      // Check immediately - user may have already tapped link before app was killed.
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
  // No 'I Verified' tap needed. Saves profile, clears pending, opens Login straight.
  Future<void> _finishAfterVerified() async {
    if (_finishingVerification) return;
    _finishingVerification = true;
    _verifyTimer?.cancel();
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !user.emailVerified) { _finishingVerification = false; return; }
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
      final data = <String, Object?>{
        'uid': uid, 'id': uid,
        'name': name, 'fullName': name,
        'username': username, 'email': email,
        'phone': phone, 'countryCode': _selectedDialCode, 'country': _selectedCountryName,
        'role': 'client', 'type': 'client',
        'status': 'approved', 'isApproved': true, 'approved': true, 'hasAll4': true,
        'phoneVerified': false, 'otpVerified': false, 'emailVerified': true, 'verifiedByEmail': true,
        'photo': photoUrl ?? '', 'photoUrl': photoUrl ?? '', 'photoURL': photoUrl ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance.collection('clients').doc(uid).set(data);
      final rtdbData = Map<String, Object?>.from(data)..['createdAt'] = DateTime.now().millisecondsSinceEpoch;
      await FirebaseDatabase.instance.ref('ceoRegistrationCenter/clients/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('clients/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('client_registrations/$uid').set(rtdbData);
      await _clearPending();
      if (!mounted) return;
      setState(() { _waitingVerification = false; _verifyStatus = ''; _loading = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email verified! Login now.')));
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      // AUTO: Open Login page straight - user does NOT go back to fresh registration.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ClientLoginPage()),
      );
    } catch (e) {
      _finishingVerification = false;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      _startVerifyPolling();
    }
  }

  // Email Verification ONLY for Client (no OTP, no CEO approval): create account with email+password, send verification email,
  // wait for user to tap the link, then save the same client data as phone flow.
  Future<void> _registerWithEmailVerification() async {
    final email = _email.text.trim();
    // ONE EMAIL = ONE ROLE - re-check here too, user may have tapped fallback after OTP failed
    final blockedFb = await _checkEmailNotUsedAsNurse(email);
    if (blockedFb != null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blockedFb), backgroundColor: Colors.red)); return; }
    final pass = _pass.text.trim();
    final phone = _fullPhone;
    setState(() => _loading = true);
    try {
      // Create the email account (no phone yet)
      UserCredential cred;
      try {
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
      } on FirebaseAuthException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create account: ${e.message ?? e.code}'), backgroundColor: Colors.red));
        return;
      }
      await cred.user!.sendEmailVerification();
      if (!mounted) return;
      // AUTO-CONFIRM: No 'I Verified' button. Save pending (survives app kill/restart),
      // show waiting screen, poll reload() every 3s. When user taps link in Gmail,
      // _finishAfterVerified() auto-saves + opens Login straight.
      await _savePending();
      if (!mounted) return;
      setState(() { _loading = false; _waitingVerification = true; _verifyStatus = 'We sent a link to $email. Open Gmail and tap it - this page will auto-confirm, no button to tap.'; });
      _startVerifyPolling();
      return;
    } catch (e) {
      // If we are already waiting (link sent), don't delete - user is in Gmail.
      if (!_waitingVerification) {
        try { final u = FirebaseAuth.instance.currentUser; if (u != null) { final d = await FirebaseFirestore.instance.collection('clients').doc(u.uid).get(); if (!d.exists) await u.delete(); } } catch (_) {}
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted && !_waitingVerification) setState(() => _loading = false);
    }
  }

  Future<void> _cancelVerification() async {
    _verifyTimer?.cancel();
    try { await FirebaseAuth.instance.currentUser?.delete(); } catch (_) { await FirebaseAuth.instance.signOut(); }
    await _clearPending();
    if (!mounted) return;
    setState(() { _waitingVerification = false; _verifyStatus = ''; _loading = false; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification cancelled. That email cannot login. Register again.'), backgroundColor: Colors.red));
  }

  // ---- STRONG PASSWORD ----
  int get _passwordScore {
    final p = _pass.text;
    var score = 0;
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
    return p.length >= 8 && RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p) &&
        RegExp(r'[0-9]').hasMatch(p) && RegExp(r'[^A-Za-z0-9]').hasMatch(p) && !p.contains(' ');
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

  // NO OTP ANY MORE - Email Verification ONLY.
  // Phone OTP needed Play Integrity / SHA and kept failing.
  // Email verification needs no SHA, no SMS, no Play Integrity.
  Future<void> _register() async {
    if (_name.text.trim().isEmpty || _username.text.trim().isEmpty || _email.text.trim().isEmpty ||
        _phone.text.trim().isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill all fields - name, username, email, phone and password')));
      return;
    }
    if (!_isStrongPassword) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Password too weak. Missing: ${_passwordMissing.join(', ')}'), backgroundColor: Colors.red));
      return;
    }
    if (_isOtherCountry && !RegExp(r'^\+\d{1,4}$').hasMatch(_selectedDialCode)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid country code for Other, e.g. +999')));
      return;
    }
    // ONE EMAIL = ONE ROLE - checked again inside _registerWithEmailVerification
    await _registerWithEmailVerification();
  }

  @override
  Widget build(BuildContext context) {
    // WAITING SCREEN: shown while auto-verification polls. No 'I Verified' button.
    // If phone kills app when user goes to Gmail, initState restores this same screen.
    if (_waitingVerification) {
      return Scaffold(
        appBar: AppBar(title: const Text('Check your Email'), backgroundColor: Colors.purple, foregroundColor: Colors.white),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.mark_email_read, size: 80, color: Colors.purple),
              const SizedBox(height: 20),
              Text(_verifyStatus, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Waiting... This page will auto-confirm when you tap the link. Do not press back.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () async { try { await FirebaseAuth.instance.currentUser?.sendEmailVerification(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification email resent'))); } catch (_) {} },
                child: const Text('Resend Email'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _cancelVerification, child: const Text('Cancel Registration', style: TextStyle(color: Colors.red))),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Client Registration'), backgroundColor: Colors.purple, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name')),
            TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username')),
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _selectedCountry, isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Country Code'),
                    items: [
                      ..._countries.map((c) => DropdownMenuItem<String>(
                            value: '${c['name']}|${c['code']}',
                            child: Text('${c['name']} (${c['code']})', overflow: TextOverflow.ellipsis),
                          )),
                      const DropdownMenuItem<String>(value: 'Other|', child: Text('Other (type code)')),
                    ],
                    onChanged: (v) { if (v != null) setState(() => _selectedCountry = v); },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextField(controller: _phone, keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: 'Phone Number', hintText: _isOtherCountry ? 'Number without code' : 'e.g. 241234567 (no 0, no code)')),
                ),
              ],
            ),
            if (_isOtherCountry)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(controller: _otherCode, keyboardType: TextInputType.phone, onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Your Country Code', hintText: 'e.g. +999')),
              ),
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerLeft,
              child: Text('Full number: ${_phone.text.trim().isEmpty ? '...' : _fullPhone}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey))),
            TextField(
              controller: _pass, obscureText: _obscurePassword, onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Password', hintText: 'Min 8 chars, upper + lower + number + symbol',
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
                Expanded(child: LinearProgressIndicator(value: _passwordScore / 6, backgroundColor: Colors.grey.shade300, color: _passwordStrengthColor, minHeight: 6)),
                const SizedBox(width: 8),
                Text(_passwordStrengthLabel, style: TextStyle(color: _passwordStrengthColor, fontWeight: FontWeight.bold)),
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
