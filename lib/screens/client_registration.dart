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

  // Shows OTP dialog. Returns verified credential, or null on fail/cancel. Max 3 wrong attempts.
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
            TextField(controller: _otp, keyboardType: TextInputType.number, maxLength: 6,
              decoration: const InputDecoration(labelText: 'OTP code', hintText: '123456')),
            if (attempts > 0) Text('Wrong code. ${3 - attempts} attempt(s) left.', style: const TextStyle(color: Colors.red)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => _sendOtp(phone), child: const Text('Resend')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, _otp.text.trim()), child: const Text('Verify')),
          ],
        ),
      );
      if (code == null || code.isEmpty) return null;
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

  Future<void> _register() async {
    // ALL fields must be filled.
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
    final phone = _fullPhone;
    // 1) OTP TO PHONE - must PASS before any account is created. No ID needed.
    _pendingPhoneCredential = null; _phoneVerified = false;
    await _sendOtp(phone);
    if (_verificationId == null && _pendingPhoneCredential == null) return;
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
        'uid': uid, 'id': uid,
        'name': _name.text.trim(), 'fullName': _name.text.trim(),
        'username': _username.text.trim(), 'email': _email.text.trim(),
        'phone': phone, 'countryCode': _selectedDialCode, 'country': _selectedCountryName,
        'role': 'client', 'type': 'client',
        'status': 'approved', 'isApproved': true, 'approved': true, 'hasAll4': true,
        'phoneVerified': true, 'otpVerified': true,
        'photo': photoUrl ?? '', 'photoUrl': photoUrl ?? '', 'photoURL': photoUrl ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance.collection('clients').doc(uid).set(data);
      final rtdbData = Map<String, Object?>.from(data)..['createdAt'] = DateTime.now().millisecondsSinceEpoch;
      await FirebaseDatabase.instance.ref('ceoRegistrationCenter/clients/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('clients/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('client_registrations/$uid').set(rtdbData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registered! Phone verified. You can login now.')));
      await FirebaseAuth.instance.signOut();
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
