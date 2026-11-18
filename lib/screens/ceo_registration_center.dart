import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';

// CEO REGISTRATION CENTER - FULL FILE - COMPLETE DELETE + WIPE + RECOVER ORPHAN FIX
// - Approve / Reject / Delete / Delete All / Export / Fix All Approved / Wipe All Auth + Storage / Recover Missing Clients
// - FIX for: Client verifies email, app goes fresh, CEO sees (0), Login says "not registered" / "Email NOT verified"
// - Root cause: Old registration saved profile AFTER verification. If Android kills app when user goes to Gmail, profile never saved.
//   Auth exists, RTDB does NOT exist. This file + new function recoverOrphanAuthUsers fixes that.
// - Delete COMPLETELY: RTDB + Firestore + Storage + Email/Username/Phone/PIN indexes + Firebase Auth + Orphan Storage
// NEED in pubspec: cloud_functions: ^5.6.2
// NEED Cloud Function: deleteAuthUser + wipeAllAuthAndStorage + recoverOrphanAuthUsers (see bottom)

class CEORegistrationCenterScreen extends StatefulWidget {
  const CEORegistrationCenterScreen({super.key});
  @override
  State<CEORegistrationCenterScreen> createState() => _CEORegistrationCenterScreenState();
}

class _CEORegistrationCenterScreenState extends State<CEORegistrationCenterScreen> {
  String currentTab = 'nursesPending';
  String search = '';
  String docFilter = 'all';
  List<Map> allRecords = [];
  List<String> logLines = [];
  bool showLog = false;
  bool isLoading = false;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _sanitizeEmail(String e) => e.toLowerCase().replaceAll(RegExp(r'[.#\$@\[\]]'), '_');

  dynamic _sanitizeForRtdb(dynamic v) {
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), _sanitizeForRtdb(val)));
    if (v is List) return v.map(_sanitizeForRtdb).toList();
    if (v != null) {
      try {
        final ms = (v as dynamic).millisecondsSinceEpoch;
        if (ms is num && v.runtimeType.toString().contains('Timestamp')) return ms.toInt();
      } catch (_) {}
    }
    return v;
  }

  void _log(String m) {
    if (!mounted) return;
    setState(() { showLog = true; logLines.add(m); });
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  num _createdAtMs(Object? raw) {
    if (raw is num) return raw;
    if (raw is String) return int.tryParse(raw) ?? 0;
    try {
      final ms = (raw as dynamic).millisecondsSinceEpoch;
      if (ms is num) return ms;
    } catch (_) {}
    return 0;
  }

  // ============ LOAD ALL ============
  Future<void> _loadAll() async {
    setState(() => isLoading = true);
    try {
      final db = FirebaseDatabase.instance;
      List<Map> out = [];
      Future<void> scan(String base, String type) async {
        try {
          final s = await db.ref(base).get();
          if (!s.exists) return;
          final val = s.value;
          if (val is! Map) return;
          for (final e in (val as Map).entries) {
            if (e.value is! Map) continue;
            final m = Map<String, dynamic>.from(e.value as Map);
            if (m['email'] == null && m['clientEmail'] == null && m['emailAddress'] == null && m['fullName'] == null && m['name'] == null) continue;
            final email = (m['email'] ?? m['clientEmail'] ?? m['emailAddress'] ?? '').toString();
            final name = (m['fullName'] ?? m['name'] ?? m['username'] ?? '').toString();
            final uid = (m['uid'] ?? m['id'] ?? e.key).toString();
            final isApproved = m['isApproved'] == true || m['approved'] == true || m['status'] == 'approved' || m['approvalStatus'] == 'approved';
            final exists = out.any((x) => x['uid'].toString() == uid && x['email'].toString().toLowerCase() == email.toLowerCase());
            if (exists) continue;
            out.add({
              'uid': uid, 'key': e.key.toString(), 'type': type,
              'email': email.toLowerCase(), 'fullName': name,
              'username': (m['username'] ?? m['userName'] ?? '').toString(),
              'phone': (m['phone'] ?? m['phoneNumber'] ?? '').toString(),
              'countryCode': (m['countryCode'] ?? '').toString(),
              'isApproved': isApproved,
              'emailVerified': m['emailVerified'] ?? false,
              'needsProfile': m['needsProfile'] == true,
              'hasPhoto': _hasDoc(m, ['photo', 'photoURL', 'photoUrl', 'image', 'profilePic']),
              'hasVideo': _hasDoc(m, ['video', 'videoURL', 'videoUrl', 'introVideo', 'introVideoUrl', 'profileVideo']),
              'hasId': _hasDoc(m, ['idURL', 'idUrl', 'idFront', 'idFrontURL', 'nationalId', 'ghanaCard']),
              'hasLicence': _hasDoc(m, ['licenceURL', 'licenceUrl', 'licenseURL', 'licence', 'license']),
              'hasCert': _hasDoc(m, ['certURL', 'certUrl', 'certificateURL', 'certificate']),
              'hasCv': _hasDoc(m, ['cvURL', 'cvUrl', 'cv']),
              'hasPin': (m['nursingPin'] ?? m['pin'] ?? '').toString().isNotEmpty,
              'qualification': (m['qualification'] ?? m['education'] ?? '').toString(),
              'services': (m['services'] ?? m['speciality'] ?? m['specialty'] ?? '').toString(),
              'referenceName': (m['referenceName'] ?? '').toString(),
              'referencePhone': (m['referencePhone'] ?? '').toString(),
              'gpsName': (m['gpsName'] ?? m['location'] ?? '').toString(),
              'lat': m['lat'] ?? m['latitude'] ?? m['gpsLat'],
              'lng': m['lng'] ?? m['longitude'] ?? m['gpsLng'],
              'createdAt': _createdAtMs(m['createdAt'] ?? m['timestamp'] ?? m['created_at']),
              'photo': (m['photo'] ?? m['photoURL'] ?? m['photoUrl'] ?? '').toString(),
              'idURL': (m['idURL'] ?? m['idUrl'] ?? m['idFrontURL'] ?? '').toString(),
              'licenceURL': (m['licenceURL'] ?? m['licenceUrl'] ?? '').toString(),
              'videoURL': (m['videoURL'] ?? m['videoUrl'] ?? m['introVideoUrl'] ?? m['video'] ?? m['introVideo'] ?? '').toString(),
              'certURL': (m['certURL'] ?? m['certUrl'] ?? m['certificateURL'] ?? '').toString(),
              'cvURL': (m['cvURL'] ?? m['cvUrl'] ?? '').toString(),
              'raw': m,
            });
          }
        } catch (_) {}
      }

      await scan('nurses', 'nurse');
      await scan('pending_nurses', 'nurse');
      await scan('pendingNurses', 'nurse');
      await scan('nurse_registrations', 'nurse');
      await scan('nurseApplications', 'nurse');
      await scan('allNurses', 'nurse');
      await scan('ceoRegistrationCenter/nurses', 'nurse');
      await scan('clients', 'client');
      await scan('client_registrations', 'client');
      await scan('allClients', 'client');
      await scan('pending_clients', 'client');
      await scan('pendingClients', 'client');
      await scan('pendingClientRegistrations', 'client');
      await scan('ceoRegistrationCenter/clients', 'client');

      if (out.isEmpty) {
        try {
          final qs = await FirebaseFirestore.instance.collection('nurses').get();
          for (final d in qs.docs) {
            final m = d.data();
            out.add({'uid': d.id, 'key': d.id, 'type': 'nurse', 'email': (m['email'] ?? '').toString().toLowerCase(), 'fullName': (m['fullName'] ?? m['name'] ?? '').toString(), 'username': '', 'phone': (m['phone'] ?? '').toString(), 'countryCode': '', 'isApproved': m['isApproved'] == true, 'emailVerified': false, 'needsProfile': false, 'hasPhoto': true, 'hasVideo': true, 'hasId': true, 'hasLicence': true, 'hasCert': true, 'hasCv': false, 'hasPin': false, 'qualification': '', 'services': '', 'referenceName': '', 'referencePhone': '', 'gpsName': '', 'lat': null, 'lng': null, 'createdAt': 0, 'photo': '', 'idURL': '', 'licenceURL': '', 'videoURL': '', 'certURL': '', 'cvURL': '', 'raw': m});
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() { allRecords = out; isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      _toast('Load failed: $e');
    }
  }

  bool _hasDoc(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().isNotEmpty && v.toString().startsWith('http')) return true;
      if (v is Map && v['url'] != null && v['url'].toString().startsWith('http')) return true;
    }
    return false;
  }

  List<Map> get filtered {
    var list = List<Map>.from(allRecords);
    if (currentTab == 'nursesPending') list = list.where((x) => x['type'] == 'nurse' && x['isApproved'] != true).toList();
    if (currentTab == 'nursesApproved') list = list.where((x) => x['type'] == 'nurse' && x['isApproved'] == true).toList();
    if (currentTab == 'clientsPending') list = list.where((x) => x['type'] == 'client' && x['isApproved'] != true).toList();
    if (currentTab == 'clientsApproved') list = list.where((x) => x['type'] == 'client' && x['isApproved'] == true).toList();
    if (search.trim().isNotEmpty) {
      final q = search.toLowerCase();
      list = list.where((x) => x['fullName'].toString().toLowerCase().contains(q) || x['email'].toString().toLowerCase().contains(q) || x['username'].toString().toLowerCase().contains(q) || x['phone'].toString().contains(q)).toList();
    }
    if (docFilter != 'all') {
      if (docFilter == 'noVideo') list = list.where((x) => x['hasVideo'] != true).toList();
      if (docFilter == 'noPhoto') list = list.where((x) => x['hasPhoto'] != true).toList();
      if (docFilter == 'noId') list = list.where((x) => x['hasId'] != true).toList();
    }
    return list;
  }

  int get nursesPendingCount => allRecords.where((x) => x['type'] == 'nurse' && x['isApproved'] != true).length;
  int get nursesApprovedCount => allRecords.where((x) => x['type'] == 'nurse' && x['isApproved'] == true).length;
  int get clientsPendingCount => allRecords.where((x) => x['type'] == 'client' && x['isApproved'] != true).length;
  int get clientsApprovedCount => allRecords.where((x) => x['type'] == 'client' && x['isApproved'] == true).length;

  // ============ RECOVER MISSING CLIENTS - NEW FIX FOR MICHAEL CASE ============
  // Why: Auth exists, RTDB does NOT exist (app killed after Gmail verification)
  // This calls Cloud Function recoverOrphanAuthUsers which lists Auth + creates missing RTDB records.
  // After this, Michael go appear for Clients Pending, and login go work (no more "not registered").
  Future<void> _recoverOrphans() async {
    final c = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Recover Missing Clients?'),
      content: const Text('This will scan Firebase Auth, find users like michaelallotey1005@gmail.com wey dey for Auth but no dey for CEO list, and create their record.\n\nThey will appear as Clients Pending with "Needs Profile" - you can then ask them to complete name/phone inside app, or Approve them.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Recover'))],
    ));
    if (c != true) return;
    setState(() { showLog = true; logLines = []; });
    _log('Recovering orphans: scanning Auth...');
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('recoverOrphanAuthUsers').call({});
      _log('✅ RECOVER DONE: ${res.data}');
      _toast('✅ Recovered - check Clients Pending');
      _loadAll();
    } catch (e) {
      _log('❌ Recover failed: $e');
      _toast('Recover failed: $e - Did you deploy recoverOrphanAuthUsers?');
    }
  }

  // ============ APPROVE ============
  Future<void> _approve(Map rec) async {
    final uid = rec['uid'].toString();
    final email = rec['email'].toString();
    final type = rec['type'].toString();
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Approve?'), content: Text('Approve $type $email?\n\nThis will update ALL database paths so $type moves to Approved and can login.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve'))]));
    if (confirm != true) return;
    setState(() { showLog = true; logLines = []; });
    _log('Approving $type $email ($uid) in ALL paths...');
    try {
      final emailKey = _sanitizeEmail(email);
      final now = DateTime.now().millisecondsSinceEpoch;
      final payload = {'isApproved': true, 'approved': true, 'status': 'approved', 'canLogin': true, 'isVerified': true, 'emailVerified': true, 'approvedAt': now, 'approvedBy': 'CEO', 'updatedAt': now};
      final db = FirebaseDatabase.instance;
      final paths = type == 'nurse'
          ? ['nurses/$uid', 'pending_nurses/$uid', 'pendingNurses/$uid', 'nurse_registrations/$uid', 'nurseApplications/$uid', 'allNurses/$uid', 'nurseUsers/$uid', 'ceoNurseUpdates/$uid', 'ceoRegistrationCenter/nurses/$uid', 'verified_nurses/$uid']
          : ['clients/$uid', 'client_registrations/$uid', 'allClients/$uid', 'clientUsers/$uid', 'ceoClientUpdates/$uid', 'ceoRegistrationCenter/clients/$uid', 'pendingClientRegistrations/$uid'];
      for (final p in paths) {
        try { final s = await db.ref(p).get(); if (s.exists) { await db.ref(p).update(payload); _log('✅ Updated $p → approved'); } } catch (e) { _log('⚠️ $p not exist or err: $e'); }
      }
      final whitelist = _sanitizeForRtdb({...Map<String, dynamic>.from(rec['raw'] as Map), 'uid': uid, 'email': email.toLowerCase(), ...payload}) as Map<String, dynamic>;
      if (type == 'nurse') {
        await db.ref('allowedNurses/$emailKey').set(whitelist);
        await db.ref('allowedNursesByUid/$uid').set(whitelist);
      } else {
        await db.ref('allowedClients/$emailKey').set(whitelist);
        await db.ref('allowedClientsByUid/$uid').set(whitelist);
      }
      try {
        final fsPayload = {'isApproved': true, 'approved': true, 'status': 'approved', 'approvalStatus': 'approved', 'canLogin': true, 'isVerified': true, 'emailVerified': true, 'approvedAt': now, 'approvedBy': 'CEO', 'updatedAt': now};
        final colls = type == 'nurse' ? ['nurses', 'nurse_registrations', 'ceo_registration', 'pending_nurses', 'nurseApplications'] : ['clients', 'client_registrations', 'ceo_registration', 'pending_clients'];
        for (final coll in colls) {
          try { await FirebaseFirestore.instance.collection(coll).doc(uid).set(fsPayload, SetOptions(merge: true)); } catch (_) {}
        }
      } catch (_) {}
      _toast('✅ $email APPROVED - now moves to Approved and can login!');
      _log('✅ DONE — $email approved');
      Future.delayed(const Duration(milliseconds: 1500), _loadAll);
    } catch (e) { _log('❌ Approve failed: $e'); _toast('Approve failed: $e'); }
  }

  // ============ REJECT ============
  Future<void> _reject(Map rec) async {
    final uid = rec['uid'].toString();
    final email = rec['email'].toString();
    final type = rec['type'].toString();
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Reject?'), content: Text('Reject $type $email?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject'))]));
    if (confirm != true) return;
    try {
      final db = FirebaseDatabase.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (type == 'nurse') {
        await db.ref('nurses/$uid').update({'isApproved': false, 'status': 'rejected', 'rejectedAt': now});
        await db.ref('ceoRegistrationCenter/nurses/$uid').update({'isApproved': false, 'status': 'rejected'});
      } else {
        await db.ref('clients/$uid').update({'isApproved': false, 'status': 'rejected'});
        await db.ref('ceoRegistrationCenter/clients/$uid').update({'isApproved': false, 'status': 'rejected'});
      }
      _toast('❌ $email rejected');
      Future.delayed(const Duration(milliseconds: 800), _loadAll);
    } catch (e) { _toast('Reject failed: $e'); }
  }

  // ============ FIX ALL APPROVED ============
  Future<void> _fixAllApproved() async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Fix All Approved?'), content: const Text('Scan allowedNurses whitelist and fix them to approved in ALL paths.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Fix All'))]));
    if (confirm != true) return;
    setState(() { showLog = true; logLines = []; });
    _log('Scanning allowedNurses...');
    try {
      final snap = await FirebaseDatabase.instance.ref('allowedNurses').get();
      if (!snap.exists) { _toast('No allowedNurses found'); return; }
      int fixed = 0;
      final db = FirebaseDatabase.instance;
      for (final entry in (snap.value as Map).entries) {
        final v = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : {};
        final uid = v['uid']?.toString();
        final email = v['email']?.toString();
        if (uid != null && email != null) {
          final payload = {'isApproved': true, 'approved': true, 'status': 'approved', 'canLogin': true, 'isVerified': true, 'approvedAt': DateTime.now().millisecondsSinceEpoch, 'updatedAt': DateTime.now().millisecondsSinceEpoch};
          for (final p in ['nurses/$uid', 'pending_nurses/$uid', 'pendingNurses/$uid', 'ceoRegistrationCenter/nurses/$uid', 'ceoNurseUpdates/$uid', 'nurse_registrations/$uid']) await db.ref(p).update(payload).catchError((_) {});
          fixed++;
        }
      }
      _toast('✅ Fixed $fixed nurses');
      Future.delayed(const Duration(milliseconds: 1500), _loadAll);
    } catch (e) { _toast('Fix failed: $e'); }
  }

  // ============ COMPLETE DELETE ============
  Future<void> _deleteFirestoreAndStorage({required String uid, required String email, required String type}) async {
    final eLower = email.toLowerCase().trim();
    final emailKey = _sanitizeEmail(email);
    final isNurse = type == 'nurse';
    final fsColls = isNurse
        ? ['nurses', 'nurse_registrations', 'ceo_registration', 'pending_nurses', 'nurseApplications', 'allNurses', 'nurseUsers', 'ceoNurseUpdates', 'verified_nurses', 'allowedNurses', 'allowedNursesByUid', 'users', 'registeredEmails', 'usedEmails', 'usersByEmail', 'emailIndex', 'nursesByEmail', 'clientsByEmail']
        : ['clients', 'client_registrations', 'pending_clients', 'clientApplications', 'allClients', 'clientUsers', 'ceoClientUpdates', 'verified_clients', 'allowedClients', 'allowedClientsByUid', 'users', 'pendingClients', 'registeredEmails', 'usedEmails', 'usersByEmail', 'emailIndex', 'nursesByEmail', 'clientsByEmail'];
    for (final coll in fsColls) {
      try { await FirebaseFirestore.instance.collection(coll).doc(uid).delete(); } catch (_) {}
      try { await FirebaseFirestore.instance.collection(coll).doc(emailKey).delete(); } catch (_) {}
      try { await FirebaseFirestore.instance.collection(coll).doc(eLower).delete(); } catch (_) {}
      if (eLower.isNotEmpty) {
        for (final field in ['email', 'clientEmail', 'emailAddress']) {
          try {
            final q = await FirebaseFirestore.instance.collection(coll).where(field, isEqualTo: eLower).get();
            for (final d in q.docs) { await d.reference.delete(); }
          } catch (_) {}
        }
      }
    }
    for (final folder in ['nurses/$uid', 'clients/$uid', 'ceo_registration/$uid', 'registrations/$uid', 'nurse_registrations/$uid', 'client_registrations/$uid']) {
      try { await _deleteStorageFolder(folder); } catch (_) {}
    }
  }

  Future<void> _deleteStorageFolder(String folderPath) async {
    try {
      final ref = FirebaseStorage.instance.ref(folderPath);
      final list = await ref.listAll();
      for (final item in list.items) { try { await item.delete(); } catch (_) {} }
      for (final prefix in list.prefixes) { await _deleteStorageFolder(prefix.fullPath); }
    } catch (_) {}
  }

  Future<void> _deleteEmailIndexes({required String uid, required String email, required String type, required Map rec}) async {
    final db = FirebaseDatabase.instance;
    final eLower = email.toLowerCase().trim();
    final emailKey = _sanitizeEmail(email);
    final raw = rec['raw'] is Map ? Map.from(rec['raw'] as Map) : {};
    final username = ((raw['username'] ?? raw['userName'] ?? '') as String).toLowerCase();
    final phoneRaw = (raw['phone'] ?? raw['phoneNumber'] ?? '').toString();
    final phoneDigits = phoneRaw.replaceAll(RegExp(r'[^0-9]'), '');
    final pin = (raw['nursingPin'] ?? raw['pin'] ?? '').toString();
    final indexPaths = [
      'registeredEmails/$emailKey', 'usedEmails/$emailKey', 'registered_emails/$emailKey', 'used_emails/$emailKey',
      'emailIndex/$emailKey', 'emails/$emailKey', 'emailToUid/$emailKey', 'usersByEmail/$emailKey',
      'nursesByEmail/$emailKey', 'clientsByEmail/$emailKey', 'allowedNurses/$emailKey', 'allowedClients/$emailKey',
      'allowedNursesByUid/$uid', 'allowedClientsByUid/$uid',
      if (username.isNotEmpty) 'usernames/$username',
      if (phoneDigits.isNotEmpty) 'phones/$phoneDigits',
      if (pin.isNotEmpty) 'nursingPins/$pin',
      'users/$uid', 'users/$emailKey',
    ];
    for (final p in indexPaths) { try { await db.ref(p).remove(); } catch (_) {} }
  }

  Future<void> _deleteAuthUser({required String uid, required String email}) async {
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('deleteAuthUser').call({'uid': uid, 'email': email.toLowerCase().trim()});
      _log('✅ Auth deleted: ${res.data}');
    } catch (e) {
      _log('⚠️ Auth NOT deleted via Function ($e) - Delete manually in Console');
      _toast('⚠️ Delete Auth manually in Console for $email');
    }
  }

  Future<void> _deleteStorageOrphansByUid({required String uid, required String email}) async {
    final eLower = email.toLowerCase().trim();
    try {
      final root = FirebaseStorage.instance.ref();
      final list = await root.listAll();
      for (final prefix in list.prefixes) {
        try {
          final sub = await prefix.listAll();
          for (final item in sub.items) {
            if (item.fullPath.toLowerCase().contains(uid.toLowerCase()) || item.fullPath.toLowerCase().contains(eLower)) {
              try { await item.delete(); } catch (_) {}
            }
          }
          for (final p2 in sub.prefixes) {
            try {
              final sub2 = await p2.listAll();
              for (final item in sub2.items) {
                if (item.fullPath.toLowerCase().contains(uid.toLowerCase()) || item.fullPath.toLowerCase().contains(eLower)) {
                  try { await item.delete(); } catch (_) {}
                }
              }
            } catch (_) {}
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _wipeAllAuthAndStorage() async {
    final c1 = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('WIPE EVERYTHING?'), content: const Text('This will DELETE ALL Auth users + ALL Storage files + ALL Database, even those CEO list no see.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Continue'))]));
    if (c1 != true) return;
    final ctrl = TextEditingController(text: 'joshouapee@gmail.com');
    final keep = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('CEO Email to KEEP'), content: TextField(controller: ctrl), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('WIPE ALL'))]));
    if (keep == null) return;
    final ctrl2 = TextEditingController();
    final confirmText = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Type WIPE to confirm'), content: TextField(controller: ctrl2), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, ctrl2.text), child: const Text('Confirm'))]));
    if (confirmText != 'WIPE') { _toast('Cancelled - you must type WIPE'); return; }
    setState(() { showLog = true; logLines = []; });
    _log('WIPE ALL START - Keep: $keep');
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('wipeAllAuthAndStorage').call({'keepEmail': keep.toLowerCase().trim()});
      _log('✅ WIPE DONE: ${res.data}');
      _toast('✅ Wipe done');
      _loadAll();
    } catch (e) { _log('❌ Wipe failed: $e'); _toast('Wipe failed: $e'); }
  }

  Future<void> _deleteAccount(Map rec) async {
    final uid = rec['uid'].toString();
    final email = rec['email'].toString();
    final type = rec['type'].toString();
    final c1 = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('DELETE COMPLETELY?'), content: Text('DELETE $type $email COMPLETELY?\n\nRTDB + Firestore + Storage + Indexes + Auth.\n\nThis cannot be undone!'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('DELETE'))]));
    if (c1 != true) return;
    final ctrl = TextEditingController();
    final confirmText = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: Text('Type DELETE to confirm $email'), content: TextField(controller: ctrl), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Confirm'))]));
    if (confirmText != 'DELETE') { _toast('Cancelled'); return; }
    setState(() { showLog = true; logLines = []; });
    _log('STARTING COMPLETE DELETE for $email ($uid)');
    try {
      final db = FirebaseDatabase.instance;
      final bases = type == 'nurse'
          ? ['nurses', 'pending_nurses', 'pendingNurses', 'allNurses', 'nurse_registrations', 'nurseApplications', 'nurseUsers', 'ceoNurseUpdates', 'ceoRegistrationCenter/nurses', 'verified_nurses']
          : ['clients', 'client_registrations', 'allClients', 'clientUsers', 'ceoClientUpdates', 'ceoRegistrationCenter/clients', 'allowedClients', 'pendingClientRegistrations', 'verified_clients'];
      for (final base in bases) { try { await db.ref('$base/$uid').remove(); } catch (_) {} }
      await _deleteEmailIndexes(uid: uid, email: email, type: type, rec: rec);
      await _deleteAuthUser(uid: uid, email: email);
      await _deleteFirestoreAndStorage(uid: uid, email: email, type: type);
      await _deleteStorageOrphansByUid(uid: uid, email: email);
      _toast('Deleted $email - Email fit re-register now');
      _loadAll();
    } catch (e) { _log('Delete failed: $e'); }
  }

  String _csvCell(String v) {
    final s = v.replaceAll('"', '""');
    if (s.contains(',') || s.contains('"') || s.contains('\n')) return '"$s"';
    return s;
  }

  String _buildCsv(List<Map> list) {
    final rows = <List<String>>[['Type', 'Full Name', 'Username', 'Email', 'Phone', 'Approved', 'UID', 'Created At']];
    for (final r in list) rows.add(['${r['type'] ?? ''}', '${r['fullName'] ?? ''}', '${r['username'] ?? ''}', '${r['email'] ?? ''}', '${r['phone'] ?? ''}', '${r['isApproved'] == true ? 'APPROVED' : 'PENDING'}', '${r['uid'] ?? ''}', '${r['createdAt'] ?? ''}']);
    return rows.map((r) => r.map(_csvCell).join(',')).join('\n');
  }

  Future<void> _export() async {
    final list = filtered;
    if (list.isEmpty) { _toast('Nothing to export'); return; }
    final csv = _buildCsv(list);
    await Clipboard.setData(ClipboardData(text: csv));
    _toast('Copied ${list.length} records');
  }

  Future<void> _deleteAllFiltered() async {
    final list = List<Map>.from(filtered);
    if (list.isEmpty) { _toast('Nothing to delete'); return; }
    final c1 = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Delete ALL ${list.length} in $currentTab?'), content: const Text('Deletes ALL in current tab from RTDB + Firestore + Auth. Cannot be undone. Export first.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Continue'))]));
    if (c1 != true) return;
    final ctrl = TextEditingController();
    final confirmText = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: Text('Type DELETE to delete ALL ${list.length}'), content: TextField(controller: ctrl), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Confirm'))]));
    if (confirmText != 'DELETE') { _toast('Cancelled'); return; }
    setState(() { showLog = true; logLines = []; });
    int done = 0;
    try {
      final db = FirebaseDatabase.instance;
      for (final rec in list) {
        final uid = (rec['uid'] ?? '').toString();
        final email = (rec['email'] ?? '').toString().toLowerCase();
        final type = rec['type']?.toString() ?? 'nurse';
        final bases = type == 'nurse' ? ['nurses', 'pending_nurses', 'pendingNurses', 'allNurses', 'nurse_registrations'] : ['clients', 'client_registrations', 'allClients', 'clientUsers', 'ceoClientUpdates', 'ceoRegistrationCenter/clients'];
        for (final base in bases) { try { await db.ref('$base/$uid').remove(); } catch (_) {} }
        await _deleteEmailIndexes(uid: uid, email: email, type: type, rec: rec);
        await _deleteAuthUser(uid: uid, email: email);
        await _deleteFirestoreAndStorage(uid: uid, email: email, type: type);
        await _deleteStorageOrphansByUid(uid: uid, email: email);
        done++;
      }
      _toast('Deleted $done records');
      _loadAll();
    } catch (e) { _toast('Delete All failed: $e'); }
  }

  void _viewDoc(String url, String label, String type) {
    if (url.isEmpty) { _toast('No $label'); return; }
    showDialog(context: context, builder: (_) => AlertDialog(title: Text(label), content: SingleChildScrollView(child: Column(children: [if (type == 'image') Image.network(url, errorBuilder: (_, __, ___) => const Text('Image no load')) else Text(url), const SizedBox(height: 10), SelectableText(url)])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')), ElevatedButton(onPressed: () { Clipboard.setData(ClipboardData(text: url)); Navigator.pop(context); _toast('Link copied'); }, child: const Text('Copy Link'))]));
  }

  Widget _docBox(String url, String label, bool has, String type) => InkWell(
        onTap: () => _viewDoc(url, label, type),
        child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10), border: Border.all(color: has ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3))), child: Column(children: [if (url.isNotEmpty && type == 'image') ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, height: 80, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 80, child: Center(child: Text('Photo'))))) else SizedBox(height: 80, child: Center(child: Text(has ? 'View $label' : 'No $label', style: const TextStyle(color: Colors.white60, fontSize: 11)))), const SizedBox(height: 4), Text('$label ${has ? '✅' : '❌'}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))])));

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1633),
        title: const Text('CEO Registration Center', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          TextButton(onPressed: _export, child: const Text('Export', style: TextStyle(color: Colors.amber))),
          TextButton(onPressed: _recoverOrphans, child: const Text('Recover Missing', style: TextStyle(color: Colors.yellow))),
          TextButton(onPressed: _deleteAllFiltered, child: const Text('Delete All', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: _wipeAllAuthAndStorage, child: const Text('Wipe All Auth + Storage', style: TextStyle(color: Colors.redAccent))),
          TextButton(onPressed: _fixAllApproved, child: const Text('Fix All Approved', style: TextStyle(color: Colors.greenAccent))),
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh, color: Colors.white)),
        ],
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(10), child: Wrap(spacing: 8, runSpacing: 8, children: [_tabBtn('Nurses Pending ($nursesPendingCount)', 'nursesPending', Colors.orange), _tabBtn('Nurses Approved ($nursesApprovedCount)', 'nursesApproved', Colors.green), _tabBtn('Clients Pending ($clientsPendingCount)', 'clientsPending', Colors.blue), _tabBtn('Clients Approved ($clientsApprovedCount)', 'clientsApproved', Colors.teal), _tabBtn('ALL (${allRecords.length})', 'all', Colors.purple)])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: [Expanded(child: TextField(controller: _searchCtrl, onChanged: (v) => setState(() => search = v), style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Search name / username / email / phone...', hintStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: const Color(0xFF1A1633), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.search, color: Colors.white54)))), const SizedBox(width: 8), DropdownButton<String>(value: docFilter, dropdownColor: const Color(0xFF1A1633), style: const TextStyle(color: Colors.white), items: const [DropdownMenuItem(value: 'all', child: Text('All Documents')), DropdownMenuItem(value: 'noVideo', child: Text('No Video')), DropdownMenuItem(value: 'noPhoto', child: Text('No Photo')), DropdownMenuItem(value: 'noId', child: Text('No ID'))], onChanged: (v) => setState(() => docFilter = v ?? 'all'))])),
        if (showLog) Container(margin: const EdgeInsets.all(10), padding: const EdgeInsets.all(10), height: 140, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: logLines.map((l) => Text(l, style: const TextStyle(color: Colors.greenAccent, fontSize: 11))).toList()))),
        Expanded(child: isLoading ? const Center(child: CircularProgressIndicator(color: Colors.purple)) : list.isEmpty ? const Center(child: Text('No records here', style: TextStyle(color: Colors.white54))) : ListView.builder(itemCount: list.length, itemBuilder: (_, i) {
          final r = list[i];
          final raw = r['raw'] is Map ? Map.from(r['raw'] as Map) : {};
          return Card(color: const Color(0xFF1A1633), margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [CircleAvatar(radius: 24, backgroundImage: r['photo'].toString().isNotEmpty ? NetworkImage(r['photo'].toString()) : null, backgroundColor: Colors.purple, child: r['photo'].toString().isEmpty ? Text(r['type'] == 'nurse' ? '👩‍⚕️' : '👤') : null), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r['fullName'].toString().isEmpty ? '(No name - Needs Profile)' : r['fullName'].toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)), Text('${r['email']} • ${r['phone']}', style: const TextStyle(color: Colors.white60, fontSize: 12)), Text('${r['type']} • ${r['isApproved'] == true ? '✅ APPROVED' : '⏳ PENDING'} • UID: ${r['uid']}${r['needsProfile'] == true ? ' • ⚠️ NEEDS PROFILE' : ''}', style: TextStyle(color: r['isApproved'] == true ? Colors.greenAccent : Colors.orange, fontSize: 11))]))) ]),
            const SizedBox(height: 10),
            GridView.count(crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 6, mainAxisSpacing: 6, children: [_docBox(r['photo'].toString(), 'Photo', r['hasPhoto'] == true, 'image'), _docBox(r['idURL'].toString(), 'ID', r['hasId'] == true, 'image'), _docBox(r['licenceURL'].toString(), 'Licence', r['hasLicence'] == true, 'image'), _docBox(r['videoURL'].toString(), 'Video', r['hasVideo'] == true, 'video'), _docBox(r['certURL'].toString(), 'Cert', r['hasCert'] == true, 'image'), _docBox(r['cvURL'].toString(), 'CV', r['hasCv'] == true, 'image'), _docBox('', 'PIN ${raw['nursingPin'] ?? raw['pin'] ?? '—'}', r['hasPin'] == true, 'text'), _docBox('', 'Phone ${r['phone']}', r['phone'].toString().isNotEmpty, 'text')]),
            const SizedBox(height: 10),
            Row(children: [Expanded(child: ElevatedButton(onPressed: () => _approve(r), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('Approve', style: TextStyle(color: Colors.white)))), const SizedBox(width: 8), Expanded(child: ElevatedButton(onPressed: () => _reject(r), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), child: const Text('Reject', style: TextStyle(color: Colors.white)))), const SizedBox(width: 8), Expanded(child: ElevatedButton(onPressed: () => _deleteAccount(r), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete Completely', style: TextStyle(color: Colors.white, fontSize: 12))))]),
          ])));
        })),
      ]),
    );
  }

  Widget _tabBtn(String label, String value, Color color) {
    final active = currentTab == value;
    return InkWell(onTap: () => setState(() => currentTab = value), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: active ? color : Colors.black26, borderRadius: BorderRadius.circular(20), border: Border.all(color: color)), child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))));
  }
}
