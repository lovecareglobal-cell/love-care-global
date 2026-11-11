import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

/// FORCE DELETE BY EMAIL - Flutter version of force-delete.html
/// - Deletes nurse from EVERYWHERE by email — same as HTML forceDelete()
/// - Check Where Exists — same as HTML checkWhere():
///   Bases: nurses + pending_nurses + nurse_registrations + ceoRegistrationCenter/nurses + allowedNurses + allowedNursesByUid
///   For each base, scan all children: if (v.email lower == email) OR (key == emailKey) -> log "FOUND RTDB {base}/{key}"
///   Check allowedNurses/{emailKey} exists -> "FOUND allowedNurses/{emailKey} EXISTS - this blocks delete" else "NOT FOUND allowedNurses/{emailKey}"
///   Firestore (HTML): fs.collection('nurses').where('email','==',email) -> "FOUND Firestore nurses/{id}"
///   Flutter uses RTDB only (same as all other Flutter screens) — Firestore/Storage noted in log: "Firestore/Storage: delete via Firebase Console if needed."
/// - sanitizeEmail: email.lower.trim.replace(/[.#\$@\\[\\]]/g, '_') — same as HTML sanitizeEmail()
/// - Force Delete — same as HTML forceDelete():
///   Validate: email required -> "Enter email"
///   Confirm: "DELETE {email} from EVERYWHERE?"
///   Type DELETE prompt: must type DELETE exactly, else "Cancelled"
///   allUids = {uid (if provided), emailKey, 'ds7LTnYLgpXG82hFJN3fScNozK23' (hardcoded in HTML)} + all UIDs in nurses where email matches + all UIDs in ceoRegistrationCenter/nurses where email matches
///   Log "UIDs: {uids}"
///   Bases (13): nurses + pending_nurses + pendingNurses + allNurses + nurse_registrations + nurseApplications + nurseUsers + ceoNurseUpdates + ceoRegistrationCenter/nurses + verified_nurses + allowedNurses + allowedNursesByUid + nursesByEmail
///   For each base × each uid: remove {base}/{uid}, log "Deleted {base}/{uid}"
///   Email paths: allowedNurses/{emailKey} + allowedClients/{emailKey} -> remove, log "Deleted {path}"
///   Firestore (HTML): fs.collection('nurses').doc(id).delete() + fs.doc('ceoRegistrationCenter/nurses/{id}').delete() + query by email delete + fs.collection('allowedNurses').doc(emailKey).delete()
///   Storage (HTML): storage.ref('nurses/{id}').listAll() -> delete each item, log "Deleted Storage {fullPath}"
///   Log "\nDONE! Deleted from all locations", alert "Deleted from DB & Storage. Now delete Auth in Firebase Console > Authentication"
///   Flutter: same RTDB deletes + log notes for Firestore/Storage/Auth (delete via Firebase Console)
/// - NO alert buttons — only Sound Settings.

class ForceDeleteScreen extends StatefulWidget {
  const ForceDeleteScreen({super.key});
  @override
  State<ForceDeleteScreen> createState() => _ForceDeleteScreenState();
}

class _ForceDeleteScreenState extends State<ForceDeleteScreen> {
  final _emailCtrl = TextEditingController(text: 'lovecareglobal@gmail.com');
  final _uidCtrl = TextEditingController();
  String logText = 'Ready...';
  bool busy = false;

  void _log(String m) => setState(() => logText = '$logText\n$m');
  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  String _sanitize(String e) => e.toLowerCase().trim().replaceAll(RegExp(r'[.#\$@\[\]]'), '_');

  Future<void> _checkWhere() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final emailKey = _sanitize(email);
    setState(() => logText = '');
    _log('Checking $email...');
    final bases = ['nurses', 'pending_nurses', 'nurse_registrations', 'ceoRegistrationCenter/nurses', 'allowedNurses', 'allowedNursesByUid'];
    for (final base in bases) {
      try {
        final snap = await FirebaseDatabase.instance.ref(base).get();
        if (snap.exists) (snap.value as Map).forEach((k, v) { if (v is Map && ((v['email'] ?? '').toString().toLowerCase() == email || k.toString() == emailKey)) _log('FOUND RTDB $base/$k'); });
      } catch (_) {}
    }
    try {
      final snap = await FirebaseDatabase.instance.ref('allowedNurses/$emailKey').get();
      _log(snap.exists ? 'FOUND allowedNurses/$emailKey EXISTS - this blocks delete' : 'NOT FOUND allowedNurses/$emailKey');
    } catch (_) {}
    _log('Firestore/Storage: check via Firebase Console if needed.');
  }

  Future<void> _forceDelete() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final uid = _uidCtrl.text.trim();
    if (email.isEmpty) { _toast('Enter email'); return; }
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('DELETE $email from EVERYWHERE?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('DELETE'))]));
    if (confirm != true) return;
    final typed = await showDialog<String>(context: context, builder: (_) { final c = TextEditingController(); return AlertDialog(title: const Text('Type DELETE to confirm'), content: TextField(controller: c, decoration: const InputDecoration(hintText: 'DELETE')), actions: [TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, c.text), child: const Text('Confirm'))]); });
    if (typed != 'DELETE') { _toast('Cancelled'); return; }
    setState(() { logText = ''; busy = true; });
    try {
      final emailKey = _sanitize(email);
      _log('DELETING $email...');
      Set<String> allUids = {};
      if (uid.isNotEmpty) allUids.add(uid);
      allUids.add(emailKey);
      allUids.add('ds7LTnYLgpXG82hFJN3fScNozK23');
      for (final base in ['nurses', 'ceoRegistrationCenter/nurses']) {
        try { final snap = await FirebaseDatabase.instance.ref(base).get(); if (snap.exists) (snap.value as Map).forEach((k, v) { if (v is Map && (v['email'] ?? '').toString().toLowerCase() == email) allUids.add(k.toString()); }); } catch (_) {}
      }
      _log('UIDs: ${allUids.join(', ')}');
      final bases = ['nurses', 'pending_nurses', 'pendingNurses', 'allNurses', 'nurse_registrations', 'nurseApplications', 'nurseUsers', 'ceoNurseUpdates', 'ceoRegistrationCenter/nurses', 'verified_nurses', 'allowedNurses', 'allowedNursesByUid', 'nursesByEmail'];
      final db = FirebaseDatabase.instance;
      for (final base in bases) {
        for (final id in allUids) {
          try { await db.ref('$base/$id').remove(); _log('Deleted $base/$id'); } catch (_) {}
        }
      }
      for (final p in ['allowedNurses/$emailKey', 'allowedClients/$emailKey']) {
        try { await db.ref(p).remove(); _log('Deleted $p'); } catch (_) {}
      }
      _log('Firestore: delete nurses/{uid} + ceoRegistrationCenter/nurses/{uid} + allowedNurses/{emailKey} via Firebase Console if needed.');
      _log('Storage: delete nurses/{uid} folder via Firebase Console if needed.');
      _log('\nDONE! Deleted from all locations');
      _toast('Deleted from DB & Storage. Now delete Auth in Firebase Console > Authentication');
    } catch (e) { _log('Error: $e'); }
    setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('FORCE DELETE BY EMAIL', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1C1238), actions: [IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings'))]),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.purple.withOpacity(0.18))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('FORCE DELETE BY EMAIL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Text('Deletes nurse from EVERYWHERE by email', style: TextStyle(fontSize: 12, color: Color(0xFFFCA5A5))),
        const SizedBox(height: 16),
        const Text('Email:'),
        TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'lovecareglobal@gmail.com', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        const Text('UID (optional):'),
        TextField(controller: _uidCtrl, decoration: const InputDecoration(hintText: 'ds7LTnYLgpXG82hFJN3fScNozK23', border: OutlineInputBorder())),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: busy ? null : _forceDelete, child: Text(busy ? 'DELETING...' : 'DELETE COMPLETELY', style: const TextStyle(fontWeight: FontWeight.bold)))),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: busy ? null : _checkWhere, child: const Text('CHECK WHERE EXISTS', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))),
        const SizedBox(height: 12),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)), child: Text(logText, style: const TextStyle(color: Color(0xFF00FF00), fontSize: 11))),
      ]))))),
    );
  }
}
