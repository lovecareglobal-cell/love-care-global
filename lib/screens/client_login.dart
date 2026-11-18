import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'client_registration.dart';

class ClientLoginPage extends StatefulWidget {
  const ClientLoginPage({super.key});
  @override
  State<ClientLoginPage> createState() => _ClientLoginPageState();
}

class _ClientLoginPageState extends State<ClientLoginPage> {
  // CLIENT LOGIN: Phone Number + Password ONLY.
  // No Email box, No Username box, No SMS OTP, No Gmail link.
  // App finds hidden email by phone behind scene, then login with email + password.
  // Hidden email = real email OR 233...@phone.lovecare (saved during registration)
  // Auth user has phoneNumber saved (linked during OTP verify), so Console shows phone.
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String _status = '';

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

  @override
  void dispose() {
    _phone.dispose();
    _pass.dispose();
    _otherCode.dispose();
    super.dispose();
  }

  // Find hidden email by phone - 4 places: phones index, clients RTDB, CEO RTDB, Firestore
  // phones/<digits> = email is fastest. Registration file now saves it.
  Future<String?> _findEmailByPhone(String fullPhone, String digits) async {
    final db = FirebaseDatabase.instance;
    // 1. Fast index: phones/<digits> = hidden email
    try {
      final s = await db.ref('phones/$digits').get();
      if (s.exists) {
        final v = s.value;
        if (v is String && v.contains('@')) return v.toLowerCase();
        if (v is Map && v['email'] != null) return (v['email'] as String).toLowerCase();
      }
    } catch (_) {}
    // 2. Scan clients RTDB - for old clients wey no get phones/ index yet
    try {
      final s = await db.ref('clients').get();
      if (s.exists && s.value is Map) {
        for (final e in (s.value as Map).values) {
          if (e is! Map) continue;
          final p = (e['phone'] ?? e['phoneNumber'] ?? e['authPhone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
          final em = (e['email'] ?? e['clientEmail'] ?? '').toString().toLowerCase();
          if (p.isNotEmpty && (p == digits || p.endsWith(digits) || digits.endsWith(p)) && em.contains('@')) return em;
        }
      }
    } catch (_) {}
    // 3. Scan ceoRegistrationCenter/clients
    try {
      final s = await db.ref('ceoRegistrationCenter/clients').get();
      if (s.exists && s.value is Map) {
        for (final e in (s.value as Map).values) {
          if (e is! Map) continue;
          final p = (e['phone'] ?? e['phoneNumber'] ?? e['authPhone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
          final em = (e['email'] ?? e['clientEmail'] ?? '').toString().toLowerCase();
          if (p.isNotEmpty && (p == digits || p.endsWith(digits) || digits.endsWith(p)) && em.contains('@')) return em;
        }
      }
    } catch (_) {}
    // 4. Firestore fallback
    try {
      final q = await FirebaseFirestore.instance.collection('clients').where('phone', isEqualTo: fullPhone).limit(1).get();
      if (q.docs.isNotEmpty) return (q.docs.first.data()['email'] ?? '').toString().toLowerCase();
    } catch (_) {}
    // 5. Last fallback: hidden email pattern - if client registered with no real email
    // This lets phone-only clients login even if phones/ index missing
    return '$digits@phone.lovecare';
  }

  // CLIENT RULE: OTP verified = Approved. If DB still says pending but otpVerified true, auto-fix am here.
  // CEO does NOT approve Client.
  Future<void> _autoApproveIfOtpVerified(String uid) async {
    try {
      final s = await FirebaseDatabase.instance.ref('clients/$uid').get();
      if (s.exists) {
        final m = s.value as Map;
        if (m['otpVerified'] == true || m['emailVerified'] == true || m['phoneVerified'] == true) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final fix = <String, Object?>{
            'isApproved': true, 'approved': true, 'status': 'approved', 'approvalStatus': 'approved',
            'canLogin': true, 'isComplete': true, 'hasAll4': true, 'updatedAt': nowMs,
          };
          await FirebaseDatabase.instance.ref('clients/$uid').update(fix);
          await FirebaseDatabase.instance.ref('ceoRegistrationCenter/clients/$uid').update(fix).catchError((_) {});
          await FirebaseDatabase.instance.ref('client_registrations/$uid').update(fix).catchError((_) {});
          await FirebaseFirestore.instance.collection('clients').doc(uid).set(fix, SetOptions(merge: true)).catchError((_) {});
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _login() async {
    if (_phone.text.trim().isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter Phone Number + Password')));
      return;
    }
    setState(() { _loading = true; _status = 'Finding your account by phone...'; });
    try {
      final email = await _findEmailByPhone(_fullPhone, _phoneDigits);
      if (email == null || email.isEmpty) {
        throw Exception('No account found for phone $_fullPhone. Check country code + number, or Register first.');
      }
      // Block Nurse trying Client login - One Email = One Role
      final nurseCheck = await FirebaseFirestore.instance.collection('nurses').where('email', isEqualTo: email).limit(1).get();
      if (nurseCheck.docs.isNotEmpty) throw Exception('This phone belongs to a NURSE. Use Nurse Login.');

      // Login with hidden email + password behind scene - Client only sees Phone + Password
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: _pass.text.trim());
      final uid = cred.user!.uid;

      // AUTH SAVES PHONE CHECK - log if Auth phone missing (old accounts)
      try {
        final authPhone = cred.user?.phoneNumber;
        final dbPhoneSnap = await FirebaseDatabase.instance.ref('clients/$uid/phone').get();
        final dbPhone = dbPhoneSnap.exists ? dbPhoneSnap.value.toString() : '';
        if ((authPhone == null || authPhone.isEmpty) && dbPhone.isNotEmpty) {
          print('AUTH PHONE MISSING for $uid, DB phone = $dbPhone. Old account created before phone-link fix. New registers will have Auth phone.');
          // Keep DB phone + Auth in sync for CEO view - save authPhone field
          await FirebaseDatabase.instance.ref('clients/$uid').update({'authPhone': dbPhone}).catchError((_) {});
        } else {
          print('AUTH LOGIN OK: uid=$uid email=${cred.user?.email} phone=${authPhone ?? dbPhone}');
        }
      } catch (_) {}

      await _autoApproveIfOtpVerified(uid);

      // Check approved - OTP verified = approved
      bool approved = false;
      final snap = await FirebaseDatabase.instance.ref('clients/$uid').get();
      if (snap.exists) {
        final m = snap.value as Map;
        approved = m['isApproved'] == true || m['status'] == 'approved' || m['otpVerified'] == true || m['emailVerified'] == true || m['phoneVerified'] == true;
      }
      if (!approved) {
        final fs = await FirebaseFirestore.instance.collection('clients').doc(uid).get();
        if (fs.exists) {
          final d = fs.data()!;
          approved = d['isApproved'] == true || d['status'] == 'approved' || d['otpVerified'] == true || d['emailVerified'] == true || d['phoneVerified'] == true;
        }
      }
      if (!approved) {
        await FirebaseAuth.instance.signOut();
        throw Exception('Your account is still PENDING. Go to Register -> Enter SMS OTP to verify first.');
      }

      // Save phone index so next login is faster + Auth phone in sync
      try {
        await FirebaseDatabase.instance.ref('phones/$_phoneDigits').set(email);
        await FirebaseDatabase.instance.ref('clientsByPhone/$_phoneDigits').set(uid);
        // Also save phone for Auth user profile if missing - Firestore/RTDB already has it
        if (cred.user?.phoneNumber != null && cred.user!.phoneNumber!.isNotEmpty) {
          await FirebaseDatabase.instance.ref('clients/$uid').update({'authPhone': cred.user!.phoneNumber, 'phone': _fullPhone, 'phoneNumber': _fullPhone}).catchError((_) {});
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() { _loading = false; _status = ''; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Welcome! Logged in with phone $_fullPhone')));
      Navigator.of(context).pushReplacementNamed('/client-dashboard');
    } catch (e) {
      if (mounted) setState(() { _loading = false; _status = ''; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Client Login'), backgroundColor: Colors.purple, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.phone_android, size: 60, color: Colors.purple),
          const SizedBox(height: 10),
          const Text('Login with Phone Number', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Enter phone you registered with + your password.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: _selectedCountry,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Country'),
                items: [
                  ..._countries.map((c) => DropdownMenuItem<String>(value: '${c['name']}|${c['code']}', child: Text('${c['name']} (${c['code']})', overflow: TextOverflow.ellipsis))),
                  const DropdownMenuItem<String>(value: 'Other|', child: Text('Other')),
                ],
                onChanged: (v) { if (v != null) setState(() => _selectedCountry = v); },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number', hintText: 'e.g. 241234567')),
            ),
          ]),
          if (_isOtherCountry)
            Padding(padding: const EdgeInsets.only(top: 8), child: TextField(controller: _otherCode, keyboardType: TextInputType.phone, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Your Country Code', hintText: 'e.g. +999'))),
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerLeft, child: Text('Full number: ${_phone.text.trim().isEmpty ? '...' : _fullPhone}', style: const TextStyle(fontSize: 12, color: Colors.grey))),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscure = !_obscure)),
            ),
          ),
          const SizedBox(height: 16),
          if (_status.isNotEmpty) Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.purple)),
          const SizedBox(height: 8),
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  onPressed: _login,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('LOGIN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClientRegistrationPage())),
            child: const Text('No account? Register with Phone'),
          ),
        ]),
      ),
    );
  }
}
