import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'ceo_login.dart';

/// Create Access - converted from ceo-create-access.html
/// CEO creates staff who can login to CEO Dashboard.
/// NEW: Staff Password field. This is the password the staff uses in CEO Login.
///
/// How to use (CEO only):
///   1. Enter staff Full Name + Phone + Email + Staff Password.
///   2. Tap Create. Staff is saved to:
///        ceoAllowedUsers/<phoneNorm>, ceoAccessList/<phoneNorm>,
///        ceoDashboardAccess/<phoneNorm>, allowedCEOs (push)
///   3. Give the staff their phone + name + staff password. They login in CEO Login.
///   4. To remove a staff: tap Delete next to their name. They can no longer login.
///      Deleting here removes them from ceoAllowedUsers / ceoAccessList /
///      ceoDashboardAccess. It does NOT delete their Firebase Auth account
///      (they never had one - login is phone + name + staff password, not Auth).
///
/// ⚠️ Security note: this stores the staff password in RTDB in plain text,
/// exactly like the HTML stored phone/name. Use STAFF-ONLY passwords -
/// never your personal email / bank / CEO password. If a staff leaves,
/// Delete them here AND change any password they knew.
///
/// NEVER BLANK: always shows form + list. Errors show in status box.
/// NO pushNamed for Go to Login: goes to CEOLoginPage directly.

class CEOCreateAccessPage extends StatefulWidget {
  const CEOCreateAccessPage({super.key});
  @override
  State<CEOCreateAccessPage> createState() => _CEOCreateAccessPageState();
}

class _CEOCreateAccessPageState extends State<CEOCreateAccessPage> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  bool _showPass = false;
  String? _status;
  bool _statusOk = false;
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  static FirebaseDatabase? _cachedDb;
  FirebaseDatabase get _db {
    _cachedDb ??= FirebaseDatabase.instance;
    return _cachedDb!;
  }

  @override
  void initState() {
    super.initState();
    _loadAccess();
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

  Future<void> _createAccess() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;
    if (name.isEmpty || phone.isEmpty) {
      _setStatus('Enter name & phone', false);
      return;
    }
    final phoneNorm = _normPhone(phone);
    if (phoneNorm.length < 9) {
      _setStatus('Enter valid phone', false);
      return;
    }
    if (pass.isEmpty) {
      _setStatus('Enter a staff password for this staff', false);
      return;
    }
    if (pass.length < 4) {
      _setStatus('Staff password must be at least 4 characters', false);
      return;
    }
    setState(() => _busy = true);
    try {
      await _ensureAuth();
      final data = <String, Object?>{
        'name': name,
        'fullName': name,
        'phone': phone,
        'phoneNorm': phoneNorm,
        'phoneNumber': phone,
        'email': email,
        // Staff password - the password staff uses to login to CEO Dashboard
        'password': pass,
        'staffPassword': pass,
        'role': 'staff',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isAllowed': true,
        'canAccessDashboard': true,
      };
      await _db.ref('ceoAllowedUsers/$phoneNorm').set(data);
      await _db.ref('ceoAccessList/$phoneNorm').set(data);
      await _db.ref('ceoDashboardAccess/$phoneNorm').set(data);
      await _db.ref('allowedCEOs').push().set(data);
      _setStatus('Created — $name can now login with staff password', true);
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _emailCtrl.clear();
      _passCtrl.clear();
      await _loadAccess();
    } catch (e) {
      _setStatus('Create failed: $e', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadAccess() async {
    if (mounted) setState(() => _loading = true);
    try {
      await _ensureAuth();
      final snap = await _db.ref('ceoAllowedUsers').get();
      final list = <Map<String, dynamic>>[];
      if (snap.exists && snap.value is Map) {
        (snap.value as Map).forEach((k, v) {
          if (v is Map) list.add({'id': k.toString(), ...Map<String, dynamic>.from(v)});
        });
      }
      list.sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
      if (mounted) setState(() { _users = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _setStatus('Load failed: $e', false);
    }
  }

  Future<void> _deleteAccess(Map user) async {
    final name = user['name'] ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete staff access?'),
        content: Text('Delete $name?\n\nThey will NO LONGER be able to login to CEO Dashboard with their staff password. This cannot be undone - you would have to Create them again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _ensureAuth();
      final id = user['id'].toString();
      await _db.ref('ceoAllowedUsers/$id').remove();
      await _db.ref('ceoAccessList/$id').remove();
      await _db.ref('ceoDashboardAccess/$id').remove();
      // allowedCEOs is a push-list (no phone key), so also remove any entry with same phone
      final snap = await _db.ref('allowedCEOs').get();
      if (snap.exists && snap.value is Map) {
        for (final e in (snap.value as Map).entries) {
          if (e.value is Map && _normPhone((e.value as Map)['phone']?.toString() ?? '') == _normPhone(user['phone']?.toString() ?? '')) {
            await _db.ref('allowedCEOs/${e.key}').remove();
          }
        }
      }
      _setStatus('Deleted $name - they can no longer login', true);
      await _loadAccess();
    } catch (e) {
      _setStatus('Delete failed: $e', false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(backgroundColor: const Color(0xFF0C0A1E), title: const Text('Create Access', style: TextStyle(fontWeight: FontWeight.w800))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.08))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _field('Full Name', _nameCtrl, 'Asabere Peter', TextInputType.name),
                      const SizedBox(height: 12),
                      _field('Phone Number', _phoneCtrl, '0544121814', TextInputType.phone),
                      const SizedBox(height: 12),
                      _field('Email', _emailCtrl, 'ceo@lovecareglobal.com', TextInputType.emailAddress),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Staff Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _passCtrl,
                            obscureText: !_showPass,
                            decoration: InputDecoration(
                              hintText: 'Create a password for this staff',
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
                          const SizedBox(height: 4),
                          const Text('Staff uses this password in CEO Login. Use a staff-only password, never your personal password.', style: TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_status != null)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: _statusOk ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: _statusOk ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3))),
                          child: Text(_status!, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: _statusOk ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5))),
                        ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _busy ? null : _createAccess,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                        child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Text('Create', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CEOLoginPage())),
                        child: const Text('Go to Login'),
                      ),
                      const SizedBox(height: 16),
                      const Text('Allowed Users', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFF0C0A1E), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.08))),
                        child: _loading
                            ? const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Loading...', style: TextStyle(color: Color(0xFF6B6788), fontSize: 11))))
                            : _users.isEmpty
                                ? const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No users', style: TextStyle(color: Color(0xFF6B6788), fontSize: 11))))
                                : Column(
                                    children: _users.map((u) => Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.08))),
                                      child: Row(
                                        children: [
                                          CircleAvatar(backgroundColor: const Color(0xFFFACC15), child: Text(((u['name'] ?? 'C').toString().isNotEmpty ? (u['name'] as String)[0].toUpperCase() : 'C'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900))),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('${u['name'] ?? ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                Text('${u['phone'] ?? ''} • ${u['email'] ?? ''}', style: const TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
                                                Text('Password: ${((u['password'] ?? u['staffPassword'] ?? '') as Object).toString().isEmpty ? 'Not set (old user)' : 'Set • staff uses it to login'}', style: const TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
                                              ],
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () => _deleteAccess(u),
                                            child: const Text('Delete', style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 10)),
                                          ),
                                        ],
                                      ),
                                    )).toList(),
                                  ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint, TextInputType type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: type,
          decoration: InputDecoration(hintText: hint, filled: true, fillColor: const Color(0xFF0C0A1E), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}

// Aliases
typedef CreateAccessPage = CEOCreateAccessPage;
typedef CEOCreateAccessScreen = CEOCreateAccessPage;
