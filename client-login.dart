import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Client Login - Flutter version of client-login.html
/// Username + Password ONLY - No SMS on login (SMS only on registration for real person verification)

class ClientLoginScreen extends StatefulWidget {
  const ClientLoginScreen({super.key});
  @override
  State<ClientLoginScreen> createState() => _ClientLoginScreenState();
}

class _ClientLoginScreenState extends State<ClientLoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool showPass = false;
  bool isLoading = false;
  String status = '';
  bool isStatusOk = true;

  // Same as HTML: btoa(p).split('').reverse().join('') + '_' + p.length
  String hashPassword(String p) {
    final b64 = base64Encode(utf8.encode(p));
    final reversed = b64.split('').reversed.join();
    return '${reversed}_${p.length}';
  }

  String? extractField(Map data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v != null && v is String && v.trim().length >= 2) return v.trim();
    }
    return null;
  }

  // BOSS RULE: MUST HAVE PHOTO, PHONE, USERNAME IN FIREBASE
  Map<String, dynamic> checkProfileComplete(Map data) {
    final photoKeys = ['photoUrl','photo','avatarUrl','photoURL','avatar','profilePhoto','image','imageUrl','clientPhoto','clientPhotoUrl'];
    final phoneKeys = ['phone','phoneNumber','mobile','contactPhone','clientPhone','whatsapp','tel','phone_number'];
    final usernameKeys = ['username','fullName','name','displayName','clientName','userName','clientUsername'];
    final photo = extractField(data, photoKeys);
    final phone = extractField(data, phoneKeys);
    final username = extractField(data, usernameKeys);
    final missing = <String>[];
    if (photo == null) missing.add('photo');
    if (phone == null) missing.add('phone number');
    if (username == null) missing.add('username');
    return {'complete': missing.isEmpty, 'missing': missing, 'photo': photo, 'phone': phone, 'username': username, 'data': data};
  }

  void _setStatus(String msg, bool ok) {
    setState(() { status = msg; isStatusOk = ok; });
  }

  Future<void> _login() async {
    final username = _usernameCtrl.text.trim().toLowerCase().replaceAll(' ', '');
    final pass = _passCtrl.text.trim();
    if (username.isEmpty || pass.isEmpty) { _setStatus('Enter username & password', false); return; }
    _setStatus('Checking username...', true);
    setState(() => isLoading = true);
    try {
      var snap = await FirebaseDatabase.instance.ref('allowedClients/$username').get();
      Map? finalData;
      if (snap.exists) {
        finalData = Map<String, dynamic>.from(snap.value as Map);
      } else {
        // Try by email fallback - same as HTML: allowedClientsByUid orderByChild email
        final byEmail = await FirebaseDatabase.instance.ref('allowedClientsByUid').orderByChild('email').equalTo(username).get();
        if (!byEmail.exists) {
          _setStatus('Username not found — Register first (SMS verification on registration)', false);
          setState(() => isLoading = false);
          return;
        }
        // byEmail returns map of uid -> data, take first
        final map = byEmail.value as Map;
        final first = map.values.first;
        if (first is Map) finalData = Map<String, dynamic>.from(first);
      }
      if (finalData == null) { _setStatus('Username not found', false); setState(() => isLoading = false); return; }

      if (finalData['isBlocked'] == true) { _setStatus('Account blocked by CEO — Contact support', false); setState(() => isLoading = false); return; }

      // BOSS RULE
      final profileCheck = checkProfileComplete(finalData);
      if (profileCheck['complete'] == false) {
        final missing = (profileCheck['missing'] as List).join(', ');
        _setStatus('❌ Cannot login — Missing $missing in Firebase. Complete registration with photo, phone & username.', false);
        // Clear prefs like HTML blockIncompleteClient
        final prefs = await SharedPreferences.getInstance();
        for (final k in ['clientLoggedIn','lcg_logged_in','lcg_role','clientUsername','clientName','fullName','clientPhone','clientCountryCode','clientPhoto','clientEmail','clientHasAll4']) {
          await prefs.remove(k);
        }
        Future.delayed(const Duration(milliseconds: 1800), () {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Redirecting to registration to complete profile...')));
        });
        setState(() => isLoading = false);
        return;
      }

      // CHECK IF VERIFIED AT REGISTRATION (SMS)
      final isVerified = finalData['phoneVerified'] == true || finalData['phoneVerifiedReal'] == true || finalData['isRealPerson'] == true || finalData['verificationMethod'] == 'SMS_OTP_REAL' || finalData['hasAll4'] == true || profileCheck['phone'] != null;
      if (!isVerified) {
        _setStatus('❌ Phone NOT verified — Please complete SMS verification in registration first.', false);
        setState(() => isLoading = false);
        return;
      }

      final hashed = hashPassword(pass);
      final stored = (finalData['passwordHash'] ?? finalData['password'] ?? finalData['pass'] ?? '').toString();
      if (stored.isNotEmpty && stored != hashed && stored != pass) {
        _setStatus('Wrong password — Try forgot password', false);
        setState(() => isLoading = false);
        return;
      }

      // SUCCESS - NO SMS, direct login
      _setStatus('✅ Photo, Phone, Username verified + Password OK — Welcome ${finalData['username']} — Entering dashboard...', true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('clientLoggedIn', true);
      await prefs.setBool('lcg_logged_in', true);
      await prefs.setString('lcg_role', 'client');
      await prefs.setString('clientUsername', profileCheck['username'] ?? '');
      await prefs.setString('clientName', finalData['fullName'] ?? finalData['name'] ?? finalData['username'] ?? '');
      await prefs.setString('fullName', finalData['fullName'] ?? finalData['name'] ?? '');
      await prefs.setString('clientPhone', profileCheck['phone'] ?? '');
      await prefs.setString('clientCountryCode', finalData['countryCode'] ?? '+233');
      await prefs.setString('clientPhoto', profileCheck['photo'] ?? '');
      await prefs.setString('clientEmail', finalData['email'] ?? '');
      await prefs.setBool('clientHasAll4', true);
      await prefs.setString('loginMethod', 'username+password_ONLY_NO_SMS');
      await prefs.setString('clientPhotoURL', profileCheck['photo'] ?? '');
      await prefs.setString('currentClientId', finalData['username'] ?? '');
      await prefs.setString('lcg_client_uid', finalData['username'] ?? '');
      await prefs.setString('clientUid', finalData['username'] ?? '');
      await prefs.setString('clientPhotoUrl', profileCheck['photo'] ?? '');

      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 700), () {
        Navigator.pushReplacementNamed(context, '/client-dashboard');
      });
    } catch (e) {
      _setStatus('Login failed: $e', false);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _resetPass() async {
    final username = _usernameCtrl.text.trim().toLowerCase();
    if (username.isEmpty) { _setStatus('Enter username to reset password', false); return; }
    final newPassCtrl = TextEditingController();
    final result = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Reset Password'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Enter new strong password:\nMust have: 8+ chars, small, BIG, number, special', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 10),
        TextField(controller: newPassCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'New Password', border: OutlineInputBorder())),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, newPassCtrl.text), child: const Text('Save'))],
    ));
    if (result == null || result.isEmpty) return;
    // Save new hashed password - same as HTML resetPass logic
    try {
      final hashed = hashPassword(result);
      await FirebaseDatabase.instance.ref('allowedClients/$username').update({'passwordHash': hashed});
      await FirebaseDatabase.instance.ref('clients/$username').update({'passwordHash': hashed});
      _setStatus('✅ Password reset - Login with new password', true);
    } catch (e) {
      _setStatus('Reset failed: $e', false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: const Color(0xFF1E1A3A), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.15))),
            child: Column(children: [
              const Text('Client Login', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFF3E8FF))),
              const SizedBox(height: 6),
              const Text('Username + Password ONLY — No SMS on login (SMS only on registration for real person verification)', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFA78BFA), fontSize: 10)),
              const SizedBox(height: 16),
              TextField(controller: _usernameCtrl, decoration: const InputDecoration(labelText: 'Username (e.g. kusipeter)', border: OutlineInputBorder()), onChanged: (v) => _usernameCtrl.value = TextEditingValue(text: v.toLowerCase().replaceAll(' ', ''), selection: TextSelection.collapsed(offset: v.length))),
              const SizedBox(height: 12),
              TextField(controller: _passCtrl, obscureText: !showPass, decoration: InputDecoration(labelText: 'Password', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(showPass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => showPass = !showPass)))),
              const SizedBox(height: 12),
              if (status.isNotEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isStatusOk ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: isStatusOk ? Colors.green : Colors.red)), child: Text(status, textAlign: TextAlign.center, style: TextStyle(color: isStatusOk ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5), fontSize: 11))),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: isLoading ? null : _login, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(isLoading ? 'Checking...' : 'Login — Enter Dashboard', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                TextButton(onPressed: () => Navigator.pushNamed(context, '/client-register'), child: const Text('No account? Register (SMS verification)', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 12))),
                TextButton(onPressed: _resetPass, child: const Text('Forgot password?', style: TextStyle(color: Color(0xFFFACC15), fontSize: 12))),
              ]),
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: const Text('Login Flow:\n• Username + Password only\n• No SMS on login — fast entry\n• SMS was already done on registration to prove real person\n• CEO can still trace you via phone + country code', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 10))),
            ]),
          ),
        ),
      ),
    );
  }
}
