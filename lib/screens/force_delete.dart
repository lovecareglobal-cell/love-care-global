import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// CEO Force Wipe Email - V2
/// File: force_delete.dart
/// Converted from ceo-force-wipe-email.html
/// This is the page the CEO Dashboard "Force Delete" card (11) points to.
///
/// What it does:
///   Step 1: WIPE DB + Firestore - deletes EVERY record for one email
///           from ALL RTDB paths + Firestore collections.
///   Step 2: DELETE FROM FIREBASE AUTH - signs in as that email (using the
///           password you type) and deletes the Auth user, so the email
///           becomes 100% NEW and MUST register again.
///           V1 only wiped DB -> Auth still existed -> person could login
///           without registering. V2 fixes that.
///
/// ⚠️ DANGER - READ BEFORE YOU USE:
///   - This is PERMANENT. There is no undo. No recycle bin.
///   - Only use it for a TEST account, or a person who asked to be fully deleted.
///   - After Step 2, YOU (the CEO) will be signed OUT, because the app just
///     signed in as the wiped user to delete them. You must log back in as CEO.
///   - If Step 2 fails (wrong password / you don't know the password),
///     use the yellow "Open Firebase Console -> Auth -> Users" button and
///     delete the user manually there.
///
/// Safety locks in this Flutter version (the HTML did NOT have these):
///   - You must type WIPE in the confirm dialog to run Step 1.
///   - You must type DELETE in the confirm dialog to run Step 2.
///   - Step 1 will NOT run if the email field is empty.
///   - The log shows every path it removed, so you can see what it did.
///
/// NEVER BLANK: always shows the form + log. Firebase errors are shown
/// in the log instead of a white page.

class ForceDeletePage extends StatefulWidget {
  const ForceDeletePage({super.key});
  @override
  State<ForceDeletePage> createState() => _ForceDeletePageState();
}

class _ForceDeletePageState extends State<ForceDeletePage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final List<String> _logLines = ['Logs...'];
  bool _busy = false;

  // ONE cached database instance - never mix .instance and .instanceFor()
  static FirebaseDatabase? _cachedDb;
  FirebaseDatabase get _database {
    _cachedDb ??= FirebaseDatabase.instance;
    return _cachedDb!;
  }

  void _log(String m) {
    if (!mounted) return;
    setState(() => _logLines.add(m));
  }

  String get _email => _emailCtrl.text.trim().toLowerCase();
  String get _emailKey => _email.replaceAll(RegExp(r'[^a-z0-9]'), '_');

  // Ask the user to type a word (WIPE / DELETE) to confirm a dangerous action.
  Future<bool> _confirmDanger(String title, String body, String mustType) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body),
            const SizedBox(height: 12),
            Text('Type "$mustType" to confirm. This is PERMANENT.', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(controller: ctrl, decoration: InputDecoration(hintText: 'Type $mustType here'), textCapitalization: TextCapitalization.characters),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, ctrl.text.trim().toUpperCase() == mustType),
            child: const Text('CONFIRM WIPE'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ---------- STEP 1: WIPE DB + Firestore ----------
  Future<void> _forceWipeDB() async {
    if (_email.isEmpty) {
      _log('❌ Enter email first');
      return;
    }
    final confirmed = await _confirmDanger(
      'WIPE DB for $_email?',
      'This deletes EVERY database record for $_email from RTDB + Firestore. No undo.',
      'WIPE',
    );
    if (!confirmed) {
      _log('Cancelled - you did not type WIPE');
      return;
    }
    setState(() => _busy = true);
    try {
      _log('Wiping DB for $_email...');

      // RTDB paths - same list as the HTML, + CEO + allowed lists (so approval is also wiped)
      const rtPaths = [
        'nurses', 'clients', 'users', 'googleClients', 'googleUsers',
        'clientUsers', 'nurseUsers',
        'client_registrations', 'nurse_registrations',
        'clientRegistrations', 'nurseRegistrations',
        'allClients', 'allNurses',
        'pendingClientRegistrations', 'pendingNurseRegistrations',
        'pendingNurses', 'pending_nurses', 'pending_clients', 'pendingClients',
        'verifiedNurses', 'blockedClients', 'blockedNurses', 'blockedUsers',
        'authUsers', 'clientsGoogle', 'googleLogins', 'clientGoogleLogins',
        'staffAccounts', 'ceoAccounts',
        'ceoRegistrationCenter/nurses', 'ceoRegistrationCenter/clients',
        'allowedNurses', 'allowedClients',
        'allowedNursesByUid', 'allowedClientsByUid',
        'nurseWithdrawals', 'clientBookings',
      ];
      for (final p in rtPaths) {
        try {
          final snap = await _database.ref(p).get();
          if (!snap.exists) continue;
          final val = snap.value;
          if (val is! Map) continue;
          for (final entry in val.entries) {
            final key = entry.key.toString();
            final v = entry.value;
            if (v is! Map) continue;
            final real = (v['profile'] is Map)
                ? v['profile'] as Map
                : (v['data'] is Map)
                    ? v['data'] as Map
                    : (v['clientData'] is Map)
                        ? v['clientData'] as Map
                        : v;
            final em = ((real['email'] ?? real['clientEmail'] ?? v['email'] ?? '') as Object).toString().toLowerCase();
            final uid = (v['uid'] ?? '').toString();
            if (em == _email || key.toLowerCase() == _emailKey || uid.toLowerCase() == _emailKey) {
              await _database.ref('$p/$key').remove();
              _log('Removed RT $p/$key');
            }
          }
        } catch (e) {
          _log('Error $p: $e');
        }
      }

      // Firestore collections - same list as HTML, + pending collections
      const fsCols = [
        'users', 'clients', 'nurses', 'googleClients',
        'client_registrations', 'nurse_registrations',
        'pending_clients', 'pending_nurses',
        'pendingClientRegistrations', 'pendingNurseRegistrations',
      ];
      for (final col in fsCols) {
        try {
          final q = await FirebaseFirestore.instance.collection(col).where('email', isEqualTo: _email).get();
          final batch = FirebaseFirestore.instance.batch();
          for (final d in q.docs) {
            batch.delete(d.reference);
          }
          await batch.commit();
          _log('Wiped Firestore $col: ${q.size}');
        } catch (e) {
          _log('FS $col error: $e');
        }
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
      } catch (_) {}
      _log('✅ DB Wiped! Now Step 2: Delete Auth');
    } catch (e) {
      _log('Wipe failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- STEP 2: DELETE FROM FIREBASE AUTH ----------
  Future<void> _deleteAuthUser() async {
    if (_email.isEmpty) {
      _log('❌ Enter email first');
      return;
    }
    final pwd = _passCtrl.text;
    if (pwd.isEmpty) {
      _log('❌ Enter password for that email to delete Auth. If you don\'t know it, use the Console link below.');
      await _openConsole();
      return;
    }
    final confirmed = await _confirmDanger(
      'DELETE $_email FROM AUTH?',
      'This signs in as $_email and deletes their Auth account. They become 100% NEW and MUST register again. YOU will be signed out and must log back in as CEO.',
      'DELETE',
    );
    if (!confirmed) {
      _log('Cancelled - you did not type DELETE');
      return;
    }
    setState(() => _busy = true);
    try {
      _log('Trying to login as $_email to delete Auth...');
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: _email, password: pwd);
      _log('Logged in as $_email, now deleting Auth user...');
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No current user after login');
      await user.delete();
      _log('✅ AUTH DELETED! $_email is now 100% NEW - Must register!');
      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('✅ Deleted from Auth'),
            content: Text('$_email is now 100% NEW - Must register!\n\nYou will now be signed out. Log back in as CEO.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
      } catch (_) {}
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      _log('Auth delete failed: $e');
      _log('Manual delete needed: Firebase Console -> Auth -> Users');
      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Failed'),
            content: Text('Failed: $e\n\nGo to Firebase Console -> Auth -> Users -> Delete $_email manually.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(onPressed: () { Navigator.pop(context); _openConsole(); }, child: const Text('Open Console')),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openConsole() async {
    final uri = Uri.parse('https://console.firebase.google.com/project/web-care-618e8/authentication/users');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _log('Could not open Console: $e');
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0A1C),
        title: const Text('🗑️ V2 Force Wipe — DB + Auth', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'V2 Force Wipe — DB + Firestore + Auth — 100% NEW',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'V1 only wiped DB → Auth still exists → Login without register. V2 also deletes Firebase Authentication → Must register as NEW!',
                  style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'Enter email to make 100% NEW',
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.3),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1)),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: "Enter that email's password (needed to delete Auth)",
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.3),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1)),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _busy ? null : _forceWipeDB,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: _busy ? const CircularProgressIndicator(color: Colors.white) : const Text('Step 1: WIPE DB + Firestore (All paths)', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _busy ? null : _deleteAuthUser,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black, side: const BorderSide(color: Color(0xFFEF4444)), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Step 2: DELETE FROM FIREBASE AUTH (Make 100% NEW)', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFACC15).withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.3))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('If Step 2 fails (because you are not logged in as that email):', style: TextStyle(fontSize: 11, color: Color(0xFFFDE68A))),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: _openConsole,
                      child: const Text('Go to: Firebase Console → Auth → Users → Find email → Delete', style: TextStyle(fontSize: 11, color: Color(0xFFFACC15), decoration: TextDecoration.underline)),
                    ),
                    const SizedBox(height: 6),
                    const Text('After both steps, email MUST register — Cannot login without register!', style: TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
                  ]),
                ),
                const SizedBox(height: 14),
                Container(
                  constraints: const BoxConstraints(maxHeight: 500),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                  child: SingleChildScrollView(
                    child: Text(
                      _logLines.join('\n'),
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Aliases so ANY name your main.dart uses will work:
// ForceDeletePage, CEOForceWipeEmailPage, ForceWipeEmailPage, CEOForceWipePage
typedef CEOForceWipeEmailPage = ForceDeletePage;
typedef ForceWipeEmailPage = ForceDeletePage;
typedef CEOForceWipePage = ForceDeletePage;
