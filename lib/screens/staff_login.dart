import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ceo_dashboard.dart';
import 'ceo_create_access.dart';

/// STAFF LOGIN - renamed from CEO Login.
/// Staff login with: Username + Staff Password
/// Username is the one YOU created for them in Create Access (e.g. kwaku.osei).
///
/// OLD WAY still works: if a staff has no username yet (old user),
/// they can still login with Phone + Full Name + Staff Password.
///
/// WHEN STAFF LOGS IN, CEO IS NOTIFIED:
///   Writes to BOTH:
///     staffVisits (push) - full visit log
///     ceoNotifications (push) - CEO alert
///     ceoLoginHistory (push) - same as before
///   Each entry has: name, username, phone, role, loginTime, timestamp.
///   CEO sees it in Create Access -> Recent Staff Visits,
///   and in CEO Dashboard -> Staff Visits (if you add the card).
///
/// NEVER BLANK: always shows form + status.
/// NO pushNamed to dashboard: goes to CEODashboardScreen directly.

class StaffLoginPage extends StatefulWidget {
  const StaffLoginPage({super.key});
  @override
  State<StaffLoginPage> createState() => _StaffLoginPageState();
}

class _StaffLoginPageState extends State<StaffLoginPage> {
  final _userCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  bool _showPass = false;
  bool _useOldWay = false; // Phone + Name, for old users with no username
  String? _status;
  bool _statusOk = false;

  static FirebaseDatabase? _cachedDb;
  FirebaseDatabase get _db {
    _cachedDb ??= FirebaseDatabase.instance;
    return _cachedDb!;
  }

  @override
  void initState() {
    super.initState();
    // Direct link: .../#/staff-login?username=kwaku.osei  or  ?phone=...&name=...
    try {
      final q = Uri.base.queryParameters;
      if ((q['username'] ?? '').isNotEmpty) _userCtrl.text = q['username']!;
      if ((q['phone'] ?? '').isNotEmpty) _phoneCtrl.text = q['phone']!;
      if ((q['name'] ?? '').isNotEmpty) _nameCtrl.text = q['name']!;
    } catch (_) {}
  }

  String _normPhone(String p) {
    final digits = p.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  Future<void> _ensureAuth() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (_) {}
  }

  void _setStatus(String msg, bool ok) {
    if (!mounted) return;
    setState(() {
      _status = msg;
      _statusOk = ok;
    });
  }

  Future<void> _staffLogin() async {
    final username = _userCtrl.text.trim().toLowerCase();
    final phoneRaw = _phoneCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final pass = _passCtrl.text;
    if (!_useOldWay) {
      if (username.isEmpty) { _setStatus('Enter your username', false); return; }
      if (pass.isEmpty) { _setStatus('Enter staff password', false); return; }
    } else {
      if (phoneRaw.isEmpty || name.isEmpty) { _setStatus('Enter phone & name', false); return; }
      if (pass.isEmpty) { _setStatus('Enter staff password', false); return; }
    }
    _setStatus('Checking...', true);
    setState(() => _busy = true);
    try {
      await _ensureAuth();
      Map<String, dynamic>? staff;

      // 1. ceoAllowedUsers - match by username OR phone+name
      final snap = await _db.ref('ceoAllowedUsers').get();
      if (snap.exists && snap.value is Map) {
        (snap.value as Map).forEach((k, v) {
          if (v is! Map) return;
          final m = Map<String, dynamic>.from(v);
          final u = (m['username'] ?? '').toString().toLowerCase();
          final uphone = _normPhone((m['phone'] ?? k).toString());
          final uname = (m['name'] ?? '').toString().toLowerCase();
          if (!_useOldWay && u.isNotEmpty && u == username) staff = m;
          if (_useOldWay && uphone == _normPhone(phoneRaw) && uname == name.toLowerCase()) staff = m;
        });
      }
      // 2. Fallback: allowedCEOs
      if (staff == null) {
        final snap2 = await _db.ref('allowedCEOs').get();
        if (snap2.exists && snap2.value is Map) {
          (snap2.value as Map).forEach((_, v) {
            if (v is! Map) return;
            final m = Map<String, dynamic>.from(v);
            final u = (m['username'] ?? '').toString().toLowerCase();
            final uphone = _normPhone((m['phone'] ?? '').toString());
            final uname = (m['name'] ?? '').toString().toLowerCase();
            if (!_useOldWay && u.isNotEmpty && u == username) staff = m;
            if (_useOldWay && uphone == _normPhone(phoneRaw) && uname == name.toLowerCase()) staff = m;
          });
        }
      }
      if (staff == null) {
        _setStatus(_useOldWay ? 'Access denied' : 'Username not found - check with CEO', false);
        return;
      }
      // 3. Staff password - only if one was set. Old users with no password still pass.
      final storedPass = (staff!['password'] ?? staff!['staffPassword'] ?? '').toString();
      if (storedPass.isNotEmpty && storedPass != pass) {
        _setStatus('Wrong staff password', false);
        return;
      }
      final finalName = (staff!['name'] ?? name).toString();
      final finalUsername = (staff!['username'] ?? username).toString();
      final finalPhone = (staff!['phone'] ?? phoneRaw).toString();
      final finalEmail = (staff!['email'] ?? '').toString();
      final now = DateTime.now();
      final loginTime = '${now.day}/${now.month}/${now.year}  ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('ceo_logged_in', true);
      await prefs.setString('ceo_name', finalName);
      await prefs.setString('ceo_username', finalUsername);
      await prefs.setString('ceo_phone', finalPhone);
      await prefs.setString('ceo_email', finalEmail);
      await prefs.setInt('ceo_login_time', now.millisecondsSinceEpoch);
      await prefs.setString('ceo_role', (staff!['role'] ?? 'staff').toString());

      final visit = <String, Object?>{
        'name': finalName,
        'username': finalUsername,
        'phone': finalPhone,
        'email': finalEmail,
        'role': staff!['role'] ?? 'staff',
        'action': 'visited CEO Dashboard',
        'message': '$finalName ($finalUsername) visited CEO Dashboard',
        'loginAt': now.millisecondsSinceEpoch,
        'loginTime': loginTime,
        'timestamp': now.millisecondsSinceEpoch,
        'read': false,
      };
      // CEO SEES THIS: visit log + notification + login history
      await _db.ref('staffVisits').push().set(visit);
      await _db.ref('ceoNotifications').push().set(visit);
      await _db.ref('ceoLoginHistory').push().set(visit);

      _setStatus('Welcome $finalName', true);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CEODashboardScreen()));
    } catch (e) {
      _setStatus('Login failed: $e', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.08))),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Staff Login', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_useOldWay) ...[
                          _field('Username', _userCtrl, 'e.g. kwaku.osei', TextInputType.text, false),
                          const SizedBox(height: 6),
                          const Text('Username is the one CEO gave you in Create Access.', style: TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
                          const SizedBox(height: 14),
                        ] else ...[
                          _field('Phone Number', _phoneCtrl, 'Enter phone number', TextInputType.phone, false),
                          const SizedBox(height: 14),
                          _field('Full Name', _nameCtrl, 'Enter full name', TextInputType.name, false),
                          const SizedBox(height: 14),
                        ],
                        TextField(
                          controller: _passCtrl,
                          obscureText: !_showPass,
                          decoration: InputDecoration(
                            labelText: 'Staff Password',
                            hintText: 'Password CEO gave you',
                            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            filled: true,
                            fillColor: const Color(0xFF0C0A1E),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            suffixIcon: IconButton(
                              icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _showPass = !_showPass),
                            ),
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 14),
                        if (_status != null)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: _statusOk ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: _statusOk ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3))),
                            child: Text(_status!, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: _statusOk ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5))),
                          ),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          onPressed: _busy ? null : _staffLogin,
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                          child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Text('Login', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => setState(() => _useOldWay = !_useOldWay),
                          child: Text(_useOldWay ? 'Use Username login instead' : 'No username yet? Use Phone + Name', style: const TextStyle(fontSize: 11, color: Color(0xFFC4B5FD))),
                        ),
                        OutlinedButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CEOCreateAccessPage())),
                          child: const Text('CEO: Create Access'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => Navigator.pushNamed(context, '/home'),
                          child: const Text('Home'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint, TextInputType type, bool obscure) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: type,
          obscureText: obscure,
          decoration: InputDecoration(hintText: hint, filled: true, fillColor: const Color(0xFF0C0A1E), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}

// Aliases - old names still work
typedef CEOLoginPage = StaffLoginPage;
typedef CeoLoginPage = StaffLoginPage;
typedef CEOLoginScreen = StaffLoginPage;
