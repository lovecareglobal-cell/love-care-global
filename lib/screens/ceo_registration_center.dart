import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

// CEO REGISTRATION CENTER - FULL FILE - FIXED
// CLIENT: Pending = NOT verified ONLY. CEO does NOT approve Client.
// NURSE: CEO approval STILL required.
// FIX: _loadAll scans RTDB + Firestore + users/nurseUsers
// FIX: _fixUploadsFromStorage - recovers URLs from Storage when nurse registration uploaded to Storage but no save URL to Database

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
    setState(() {
      showLog = true;
      logLines.add(m);
    });
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

  Future<void> _loadAll() async {
    setState(() => isLoading = true);
    try {
      final db = FirebaseDatabase.instance;
      List<Map> out = [];

      String pickEmail(Map m) {
        for (final k in ['email', 'clientEmail', 'emailAddress', 'nurseEmail', 'userEmail', 'mail']) {
          if (m[k] != null && m[k].toString().contains('@')) return m[k].toString();
        }
        return '';
      }

      String pickName(Map m) {
        for (final k in ['fullName', 'name', 'username', 'userName', 'nurseName', 'displayName', 'firstName']) {
          if (m[k] != null && m[k].toString().isNotEmpty) return m[k].toString();
        }
        return '';
      }

      Map<String, dynamic> buildRecord(String uid, String key, String type, Map m, String email, String name, String phone) {
        bool isApproved;
        if (type == 'client') {
          isApproved = m['isApproved'] == true || m['approved'] == true || m['status'] == 'approved' || m['approvalStatus'] == 'approved' || m['emailVerified'] == true;
        } else {
          isApproved = m['isApproved'] == true || m['approved'] == true || m['status'] == 'approved' || m['approvalStatus'] == 'approved';
        }
        return {
          'uid': uid,
          'key': key,
          'type': type,
          'email': email.toLowerCase(),
          'fullName': name,
          'username': (m['username'] ?? m['userName'] ?? '').toString(),
          'phone': phone,
          'countryCode': (m['countryCode'] ?? '').toString(),
          'isApproved': isApproved,
          'emailVerified': m['emailVerified'] == true || m['verifiedByEmail'] == true,
          'needsProfile': m['needsProfile'] == true,
          'hasPhoto': _hasDoc(m, ['photo', 'photoURL', 'photoUrl', 'image', 'profilePic']),
          'hasVideo': _hasDoc(m, ['video', 'videoURL', 'videoUrl', 'introVideo', 'introVideoUrl', 'profileVideo']),
          'hasId': _hasDoc(m, ['idURL', 'idUrl', 'idFront', 'idFrontURL', 'idBackURL', 'nationalId', 'ghanaCard', 'ghanaCardURL', 'ghanaCardFront', 'idCard', 'idCardURL', 'nationalIdURL', 'id']),
          'hasLicence': _hasDoc(m, ['licenceURL', 'licenceUrl', 'licenseURL', 'licenseUrl', 'licence', 'license', 'nursingLicence', 'nursingLicense', 'nmcLicence', 'nmcLicense', 'practiceLicence', 'practiceLicense']),
          'hasCert': _hasDoc(m, ['certURL', 'certUrl', 'certificateURL', 'certificate']),
          'hasCv': _hasDoc(m, ['cvURL', 'cvUrl', 'cv']),
          'hasPin': (m['nursingPin'] ?? m['pin'] ?? m['nmcPin'] ?? m['pinNumber'] ?? m['nursingPIN'] ?? m['nmcPIN'] ?? '').toString().isNotEmpty,
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
        };
      }

      Future<void> scan(String base, String type) async {
        try {
          final s = await db.ref(base).get();
          if (!s.exists) return;
          final val = s.value;
          if (val is! Map) return;
          for (final e in (val as Map).entries) {
            if (e.value is! Map) continue;
            final m = Map<String, dynamic>.from(e.value as Map);
            String email = pickEmail(m);
            if (email.isEmpty && e.key.toString().contains('_')) email = e.key.toString();
            final name = pickName(m);
            final phone = (m['phone'] ?? m['phoneNumber'] ?? m['nursePhone'] ?? '').toString();
            if (email.isEmpty && name.isEmpty && phone.isEmpty) continue;
            if (base == 'users') {
              final role = '${m['role'] ?? m['userType'] ?? ''}'.toLowerCase();
              if (type == 'nurse' && role.contains('client')) continue;
            }
            final uid = (m['uid'] ?? m['id'] ?? e.key).toString();
            final rec = buildRecord(uid, e.key.toString(), type, m, email, name, phone);
            final exists = out.any((x) => x['uid'].toString() == uid && x['email'].toString().toLowerCase() == email.toLowerCase());
            if (exists) continue;
            out.add(rec);
          }
        } catch (_) {}
      }

      Future<void> scanFirestore(String coll, String type) async {
        try {
          final qs = await FirebaseFirestore.instance.collection(coll).get();
          for (final d in qs.docs) {
            final m = d.data();
            String email = pickEmail(m);
            final name = pickName(m);
            final phone = (m['phone'] ?? m['phoneNumber'] ?? m['nursePhone'] ?? '').toString();
            if (email.isEmpty && name.isEmpty && phone.isEmpty) continue;
            final uid = (m['uid'] ?? m['id'] ?? d.id).toString();
            final rec = buildRecord(uid, d.id, type, m, email, name, phone);
            final exists = out.any((x) => x['uid'].toString() == uid && x['email'].toString().toLowerCase() == email.toLowerCase());
            if (exists) continue;
            out.add(rec);
          }
        } catch (_) {}
      }

      await scan('nurses', 'nurse');
      await scan('pending_nurses', 'nurse');
      await scan('pendingNurses', 'nurse');
      await scan('nurse_registrations', 'nurse');
      await scan('nurseApplications', 'nurse');
      await scan('allNurses', 'nurse');
      await scan('nurseUsers', 'nurse');
      await scan('ceoNurseUpdates', 'nurse');
      await scan('users', 'nurse');
      await scan('ceoRegistrationCenter/nurses', 'nurse');
      await scan('clients', 'client');
      await scan('client_registrations', 'client');
      await scan('allClients', 'client');
      await scan('pending_clients', 'client');
      await scan('pendingClients', 'client');
      await scan('pendingClientRegistrations', 'client');
      await scan('ceoRegistrationCenter/clients', 'client');

      await scanFirestore('nurses', 'nurse');
      await scanFirestore('nurse_registrations', 'nurse');
      await scanFirestore('pending_nurses', 'nurse');
      await scanFirestore('nurseApplications', 'nurse');
      await scanFirestore('ceo_registration', 'nurse');
      await scanFirestore('users', 'nurse');
      await scanFirestore('clients', 'client');
      await scanFirestore('client_registrations', 'client');

      if (!mounted) return;
      setState(() {
        allRecords = out;
        isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      _toast('Load failed: $e');
    }
  }

  bool _hasDoc(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().isNotEmpty) {
        if (v.toString().startsWith('http')) return true;
        if (k.toLowerCase().contains('pin')) return true;
        if (v is Map && v['url'] != null && v['url'].toString().isNotEmpty) return true;
        if (v.toString().contains('/') || v.toString().contains('.jpg') || v.toString().contains('.png') || v.toString().contains('.pdf')) return true;
      }
    }
    final raw = m['raw'] is Map ? Map<String, dynamic>.from(m['raw'] as Map) : m;
    for (final entry in raw.entries) {
      final keyLower = entry.key.toString().toLowerCase();
      final val = entry.value?.toString() ?? '';
      if (val.isEmpty) continue;
      if (keys.any((k) => k.toLowerCase().contains('id')) && (keyLower.contains('ghana') || keyLower.contains('nationalid') || keyLower.contains('idcard') || keyLower.contains('idfront') || keyLower.contains('id_back'))) {
        if (val.startsWith('http') || val.contains('/')) return true;
      }
      if (keys.any((k) => k.toLowerCase().contains('licen')) && (keyLower.contains('licen') || keyLower.contains('license') || keyLower.contains('nmc') || keyLower.contains('practice'))) {
        if (val.startsWith('http') || val.contains('/')) return true;
      }
    }
    return false;
  }

  List<Map> get filtered {
    var list = List<Map>.from(allRecords);
    if (currentTab == 'nursesPending') {
      list = list.where((x) => x['type'] == 'nurse' && x['isApproved'] != true).toList();
    }
    if (currentTab == 'nursesApproved') {
      list = list.where((x) => x['type'] == 'nurse' && x['isApproved'] == true).toList();
    }
    if (currentTab == 'clientsPending') {
      list = list.where((x) => x['type'] == 'client' && x['isApproved'] != true).toList();
    }
    if (currentTab == 'clientsApproved') {
      list = list.where((x) => x['type'] == 'client' && x['isApproved'] == true).toList();
    }
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

  // ============ NEW: FIX UPLOADS FROM STORAGE ============
  Future<void> _fixUploadsFromStorage(Map rec) async {
    final uid = rec['uid'].toString();
    final email = rec['email'].toString();
    setState(() {
      showLog = true;
      logLines = [];
    });
    _log('Fixing uploads from Storage for $email ($uid)...');
    try {
      final db = FirebaseDatabase.instance;
      final storageRef = FirebaseStorage.instance.ref('nurses/$uid');
      var list = await storageRef.listAll();
      _log('Found ${list.items.length} files in nurses/$uid');

      // Try other folders if empty
      if (list.items.isEmpty) {
        final altFolders = ['nurse_registrations/$uid', 'registrations/$uid', 'users/$uid', 'nurses/$email', 'ceo_registration/$uid'];
        for (final folder in altFolders) {
          try {
            final altList = await FirebaseStorage.instance.ref(folder).listAll();
            if (altList.items.isNotEmpty) {
              _log('Found ${altList.items.length} files in $folder');
              list.items.addAll(altList.items);
            }
          } catch (_) {}
        }
      }

      if (list.items.isEmpty) {
        _toast('No files found in Storage for this nurse. Check Storage folder name.');
        return;
      }

      String photoURL = '';
      String idURL = '';
      String licenceURL = '';
      String videoURL = '';
      String certURL = '';
      String cvURL = '';

      for (final item in list.items) {
        final name = item.name.toLowerCase();
        final fullPath = item.fullPath.toLowerCase();
        final url = await item.getDownloadURL();
        _log('File: ${item.name} -> $url');
        if (name.contains('photo') || name.contains('profile') || name.contains('pic')) {
          photoURL = url;
        } else if (name.contains('id') || name.contains('ghana') || name.contains('national') || name.contains('card')) {
          idURL = url;
        } else if (name.contains('licen') || name.contains('license') || name.contains('nmc') || name.contains('practice')) {
          licenceURL = url;
        } else if (name.contains('video') || name.contains('intro') || name.endsWith('.mp4') || name.endsWith('.mov')) {
          videoURL = url;
        } else if (name.contains('cert') || name.contains('certificate')) {
          certURL = url;
        } else if (name.contains('cv') || name.contains('resume')) {
          cvURL = url;
        }
        if (fullPath.contains('id') && idURL.isEmpty) idURL = url;
        if (fullPath.contains('licen') && licenceURL.isEmpty) licenceURL = url;
      }

      _log('Recovered: Photo=${photoURL.isNotEmpty} ID=${idURL.isNotEmpty} Licence=${licenceURL.isNotEmpty} Video=${videoURL.isNotEmpty} Cert=${certURL.isNotEmpty} CV=${cvURL.isNotEmpty}');

      final payload = <String, dynamic>{};
      if (photoURL.isNotEmpty) {
        payload['photo'] = photoURL;
        payload['photoURL'] = photoURL;
        payload['photoUrl'] = photoURL;
      }
      if (idURL.isNotEmpty) {
        payload['idURL'] = idURL;
        payload['idUrl'] = idURL;
        payload['idFrontURL'] = idURL;
        payload['ghanaCard'] = idURL;
        payload['nationalId'] = idURL;
      }
      if (licenceURL.isNotEmpty) {
        payload['licenceURL'] = licenceURL;
        payload['licenceUrl'] = licenceURL;
        payload['licenseURL'] = licenceURL;
        payload['licenseUrl'] = licenceURL;
        payload['licence'] = licenceURL;
        payload['license'] = licenceURL;
      }
      if (videoURL.isNotEmpty) {
        payload['videoURL'] = videoURL;
        payload['videoUrl'] = videoURL;
        payload['video'] = videoURL;
        payload['introVideoUrl'] = videoURL;
      }
      if (certURL.isNotEmpty) {
        payload['certURL'] = certURL;
        payload['certUrl'] = certURL;
        payload['certificateURL'] = certURL;
      }
      if (cvURL.isNotEmpty) {
        payload['cvURL'] = cvURL;
        payload['cvUrl'] = cvURL;
        payload['cv'] = cvURL;
      }

      if (payload.isEmpty) {
        _toast('Files found but names no match. Check log for file names.');
        return;
      }

      for (final p in ['nurses/$uid', 'pending_nurses/$uid', 'pendingNurses/$uid', 'ceoRegistrationCenter/nurses/$uid', 'nurse_registrations/$uid']) {
        try {
          await db.ref(p).update(payload);
          _log('Updated $p');
        } catch (_) {}
      }
      try {
        for (final coll in ['nurses', 'nurse_registrations', 'pending_nurses']) {
          await FirebaseFirestore.instance.collection(coll).doc(uid).set(payload, SetOptions(merge: true));
        }
      } catch (_) {}

      _toast('Fixed uploads from Storage! Press Refresh.');
      _loadAll();
    } catch (e) {
      _log('Fix uploads failed: $e');
      _toast('Fix failed: $e');
    }
  }

  Future<void> _recoverOrphans() async {
    final c = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Recover Missing Clients?'),
        content: const Text('Scan Auth, find users wey dey for Auth but no dey for CEO list, and create their record.\n\nIf Auth says Verified -> Created as APPROVED. If Not Verified -> Created as PENDING.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Recover')),
        ],
      ),
    );
    if (c != true) return;
    setState(() {
      showLog = true;
      logLines = [];
    });
    _log('Recovering orphans...');
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('recoverOrphanAuthUsers').call({});
      _log('RECOVER DONE: ${res.data}');
      _toast('Recovered - check Clients');
      _loadAll();
    } catch (e) {
      _log('Recover failed: $e');
      _toast('Recover failed: $e');
    }
  }

  Future<void> _fixAllClientsToNewRule() async {
    final c = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fix All Clients to New Rule?'),
        content: const Text('If emailVerified == true -> Set to APPROVED, can login.\nIf emailVerified == false -> Keep PENDING.\nCEO does NOT approve Clients.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Fix All Clients')),
        ],
      ),
    );
    if (c != true) return;
    setState(() {
      showLog = true;
      logLines = [];
    });
    _log('Fixing all Clients...');
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('fixAllClientsToNewRule').call({});
      _log('FIX DONE: ${res.data}');
      _toast('Fixed Clients');
      _loadAll();
    } catch (e) {
      _log('Fix failed: $e');
      _toast('Fix failed: $e');
    }
  }

  Future<void> _approve(Map rec) async {
    final type = rec['type'].toString();
    if (type == 'client') {
      _toast('Client does NOT need CEO approval. Pending = Not verified. Once verified, auto-approved.');
      return;
    }
    final uid = rec['uid'].toString();
    final email = rec['email'].toString();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve Nurse?'),
        content: Text('Approve NURSE $email?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      showLog = true;
      logLines = [];
    });
    _log('Approving nurse $email');
    try {
      final emailKey = _sanitizeEmail(email);
      final now = DateTime.now().millisecondsSinceEpoch;
      final payload = {'isApproved': true, 'approved': true, 'status': 'approved', 'approvalStatus': 'approved', 'canLogin': true, 'isVerified': true, 'emailVerified': true, 'approvedAt': now, 'approvedBy': 'CEO', 'updatedAt': now};
      final db = FirebaseDatabase.instance;
      final paths = ['nurses/$uid', 'pending_nurses/$uid', 'pendingNurses/$uid', 'nurse_registrations/$uid', 'nurseApplications/$uid', 'allNurses/$uid', 'nurseUsers/$uid', 'ceoNurseUpdates/$uid', 'ceoRegistrationCenter/nurses/$uid', 'verified_nurses/$uid'];
      for (final p in paths) {
        try {
          final s = await db.ref(p).get();
          if (s.exists) {
            await db.ref(p).update(payload);
            _log('Updated $p');
          }
        } catch (e) {
          _log('Skip $p: $e');
        }
      }
      final whitelist = _sanitizeForRtdb({...Map<String, dynamic>.from(rec['raw'] as Map), 'uid': uid, 'email': email.toLowerCase(), ...payload}) as Map<String, dynamic>;
      await db.ref('allowedNurses/$emailKey').set(whitelist);
      await db.ref('allowedNursesByUid/$uid').set(whitelist);
      try {
        final fsPayload = {'isApproved': true, 'approved': true, 'status': 'approved', 'approvalStatus': 'approved', 'canLogin': true, 'isVerified': true, 'emailVerified': true, 'approvedAt': now, 'approvedBy': 'CEO', 'updatedAt': now};
        for (final coll in ['nurses', 'nurse_registrations', 'ceo_registration', 'pending_nurses', 'nurseApplications']) {
          try {
            await FirebaseFirestore.instance.collection(coll).doc(uid).set(fsPayload, SetOptions(merge: true));
          } catch (_) {}
        }
      } catch (_) {}
      _toast('APPROVED $email');
      _loadAll();
    } catch (e) {
      _log('Approve failed: $e');
      _toast('Approve failed: $e');
    }
  }

  Future<void> _reject(Map rec) async {
    final uid = rec['uid'].toString();
    final email = rec['email'].toString();
    final type = rec['type'].toString();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject?'),
        content: Text('Reject $type $email?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final db = FirebaseDatabase.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (type == 'nurse') {
        await db.ref('nurses/$uid').update({'isApproved': false, 'status': 'rejected', 'rejectedAt': now});
        await db.ref('ceoRegistrationCenter/nurses/$uid').update({'isApproved': false, 'status': 'rejected'});
        await db.ref('pendingNurses/$uid').remove();
      } else {
        await db.ref('clients/$uid').update({'isApproved': false, 'status': 'rejected'});
        await db.ref('ceoRegistrationCenter/clients/$uid').update({'isApproved': false, 'status': 'rejected'});
      }
      _toast('Rejected $email');
      _loadAll();
    } catch (e) {
      _toast('Reject failed: $e');
    }
  }

  Future<void> _fixAllApproved() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fix All Approved Nurses?'),
        content: const Text('Scan allowedNurses and fix Nurses to approved. Nurses only, NOT Clients.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Fix All')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      showLog = true;
      logLines = [];
    });
    _log('Scanning allowedNurses...');
    try {
      final snap = await FirebaseDatabase.instance.ref('allowedNurses').get();
      if (!snap.exists) {
        _toast('No allowedNurses found');
        return;
      }
      int fixed = 0;
      final db = FirebaseDatabase.instance;
      for (final entry in (snap.value as Map).entries) {
        final v = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : {};
        final uid = v['uid']?.toString();
        final email = v['email']?.toString();
        if (uid != null && email != null) {
          final payload = {'isApproved': true, 'approved': true, 'status': 'approved', 'canLogin': true, 'isVerified': true, 'approvedAt': DateTime.now().millisecondsSinceEpoch, 'updatedAt': DateTime.now().millisecondsSinceEpoch};
          for (final p in ['nurses/$uid', 'pending_nurses/$uid', 'pendingNurses/$uid', 'ceoRegistrationCenter/nurses/$uid', 'ceoNurseUpdates/$uid', 'nurse_registrations/$uid']) {
            await db.ref(p).update(payload).catchError((_) {});
          }
          fixed++;
        }
      }
      _toast('Fixed $fixed nurses');
      _loadAll();
    } catch (e) {
      _toast('Fix failed: $e');
    }
  }

  Future<void> _deleteFirestoreAndStorage({required String uid, required String email, required String type}) async {
    final eLower = email.toLowerCase().trim();
    final emailKey = _sanitizeEmail(email);
    final isNurse = type == 'nurse';
    final fsColls = isNurse
        ? ['nurses', 'nurse_registrations', 'ceo_registration', 'pending_nurses', 'nurseApplications', 'allNurses', 'nurseUsers', 'ceoNurseUpdates', 'verified_nurses', 'allowedNurses', 'allowedNursesByUid', 'users', 'registeredEmails', 'usedEmails', 'usersByEmail', 'emailIndex', 'nursesByEmail', 'clientsByEmail']
        : ['clients', 'client_registrations', 'pending_clients', 'clientApplications', 'allClients', 'clientUsers', 'ceoClientUpdates', 'verified_clients', 'allowedClients', 'allowedClientsByUid', 'users', 'pendingClients', 'registeredEmails', 'usedEmails', 'usersByEmail', 'emailIndex', 'nursesByEmail', 'clientsByEmail'];
    for (final coll in fsColls) {
      try {
        await FirebaseFirestore.instance.collection(coll).doc(uid).delete();
      } catch (_) {}
      try {
        await FirebaseFirestore.instance.collection(coll).doc(emailKey).delete();
      } catch (_) {}
      try {
        await FirebaseFirestore.instance.collection(coll).doc(eLower).delete();
      } catch (_) {}
      if (eLower.isNotEmpty) {
        for (final field in ['email', 'clientEmail', 'emailAddress']) {
          try {
            final q = await FirebaseFirestore.instance.collection(coll).where(field, isEqualTo: eLower).get();
            for (final d in q.docs) {
              await d.reference.delete();
            }
          } catch (_) {}
        }
      }
    }
    for (final folder in ['nurses/$uid', 'clients/$uid', 'ceo_registration/$uid', 'registrations/$uid', 'nurse_registrations/$uid', 'client_registrations/$uid']) {
      try {
        await _deleteStorageFolder(folder);
      } catch (_) {}
    }
  }

  Future<void> _deleteStorageFolder(String folderPath) async {
    try {
      final ref = FirebaseStorage.instance.ref(folderPath);
      final list = await ref.listAll();
      for (final item in list.items) {
        try {
          await item.delete();
        } catch (_) {}
      }
      for (final prefix in list.prefixes) {
        await _deleteStorageFolder(prefix.fullPath);
      }
    } catch (_) {}
  }

  Future<void> _deleteEmailIndexes({required String uid, required String email, required String type, required Map rec}) async {
    final eLower = email.toLowerCase();
    final emailKey = _sanitizeEmail(email);
    final db = FirebaseDatabase.instance;
    for (final base in ['registeredEmails', 'usedEmails', 'usersByEmail', 'emailIndex', 'nursesByEmail', 'clientsByEmail', 'allowedNurses', 'allowedNursesByUid', 'allowedClients', 'allowedClientsByUid']) {
      try {
        await db.ref('$base/$emailKey').remove();
      } catch (_) {}
      try {
        await db.ref('$base/$uid').remove();
      } catch (_) {}
    }
    try {
      final snap = await db.ref('registeredEmails').get();
      if (snap.exists && snap.value is Map) {
        for (final e in (snap.value as Map).entries) {
          if (e.value is Map && (e.value as Map)['email']?.toString().toLowerCase() == eLower) {
            await db.ref('registeredEmails/${e.key}').remove();
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _deleteAuthUser({required String uid, required String email}) async {
    try {
      await FirebaseFunctions.instance.httpsCallable('deleteAuthUser').call({'uid': uid, 'email': email});
    } catch (e) {
      _log('Auth delete failed (may need Cloud Function): $e');
    }
  }

  Future<void> _deleteStorageOrphansByUid({required String uid, required String email}) async {
    try {
      await _deleteStorageFolder('users/$uid');
      await _deleteStorageFolder('nurses/$uid');
      await _deleteStorageFolder('clients/$uid');
    } catch (_) {}
  }

  Future<void> _deleteAccount(Map rec) async {
    final uid = rec['uid'].toString();
    final email = rec['email'].toString();
    final type = rec['type'].toString();
    final c1 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('DELETE COMPLETELY?'),
        content: Text('DELETE $type $email COMPLETELY?\n\nRTDB + Firestore + Storage + Indexes + Auth.\n\nThis cannot be undone!'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('DELETE')),
        ],
      ),
    );
    if (c1 != true) return;
    final ctrl = TextEditingController();
    final confirmText = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Type DELETE to confirm $email'),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmText != 'DELETE') {
      _toast('Cancelled');
      return;
    }
    setState(() {
      showLog = true;
      logLines = [];
    });
    _log('STARTING COMPLETE DELETE for $email ($uid)');
    try {
      final db = FirebaseDatabase.instance;
      final bases = type == 'nurse'
          ? ['nurses', 'pending_nurses', 'pendingNurses', 'allNurses', 'nurse_registrations', 'nurseApplications', 'nurseUsers', 'ceoNurseUpdates', 'ceoRegistrationCenter/nurses', 'verified_nurses']
          : ['clients', 'client_registrations', 'allClients', 'clientUsers', 'ceoClientUpdates', 'ceoRegistrationCenter/clients', 'allowedClients', 'pendingClientRegistrations', 'verified_clients'];
      for (final base in bases) {
        try {
          await db.ref('$base/$uid').remove();
        } catch (_) {}
      }
      await _deleteEmailIndexes(uid: uid, email: email, type: type, rec: rec);
      await _deleteAuthUser(uid: uid, email: email);
      await _deleteFirestoreAndStorage(uid: uid, email: email, type: type);
      await _deleteStorageOrphansByUid(uid: uid, email: email);
      _toast('Deleted $email');
      _loadAll();
    } catch (e) {
      _log('Delete failed: $e');
    }
  }

  String _csvCell(String v) {
    final s = v.replaceAll('"', '""');
    if (s.contains(',') || s.contains('"') || s.contains('\n')) return '"$s"';
    return s;
  }

  String _buildCsv(List<Map> list) {
    final rows = <List<String>>[
      ['Type', 'Full Name', 'Username', 'Email', 'Phone', 'Approved', 'EmailVerified', 'UID', 'Created At']
    ];
    for (final r in list) {
      rows.add(['${r['type'] ?? ''}', '${r['fullName'] ?? ''}', '${r['username'] ?? ''}', '${r['email'] ?? ''}', '${r['phone'] ?? ''}', '${r['isApproved'] == true ? 'APPROVED' : 'PENDING'}', '${r['emailVerified'] == true ? 'YES' : 'NO'}', '${r['uid'] ?? ''}', '${r['createdAt'] ?? ''}']);
    }
    return rows.map((r) => r.map(_csvCell).join(',')).join('\n');
  }

  Future<void> _export() async {
    final list = filtered;
    if (list.isEmpty) {
      _toast('Nothing to export');
      return;
    }
    final csv = _buildCsv(list);
    await Clipboard.setData(ClipboardData(text: csv));
    _toast('Copied ${list.length} records');
  }

  Future<void> _deleteAllFiltered() async {
    final list = List<Map>.from(filtered);
    if (list.isEmpty) {
      _toast('Nothing to delete');
      return;
    }
    final c1 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ALL ${list.length} in $currentTab?'),
        content: const Text('Deletes ALL in current tab from RTDB + Firestore + Auth. Cannot be undone. Export first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );
    if (c1 != true) return;
    final ctrl = TextEditingController();
    final confirmText = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Type DELETE to delete ALL ${list.length}'),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmText != 'DELETE') {
      _toast('Cancelled');
      return;
    }
    setState(() {
      showLog = true;
      logLines = [];
    });
    int done = 0;
    try {
      final db = FirebaseDatabase.instance;
      for (final rec in list) {
        final uid = (rec['uid'] ?? '').toString();
        final email = (rec['email'] ?? '').toString().toLowerCase();
        final type = rec['type']?.toString() ?? 'nurse';
        final bases = type == 'nurse'
            ? ['nurses', 'pending_nurses', 'pendingNurses', 'allNurses', 'nurse_registrations']
            : ['clients', 'client_registrations', 'allClients', 'clientUsers', 'ceoClientUpdates', 'ceoRegistrationCenter/clients'];
        for (final base in bases) {
          try {
            await db.ref('$base/$uid').remove();
          } catch (_) {}
        }
        try {
          await _deleteFirestoreAndStorage(uid: uid, email: email, type: type);
        } catch (_) {}
        done++;
      }
      _toast('Deleted $done');
      _loadAll();
    } catch (e) {
      _toast('Delete all failed: $e');
    }
  }

  Future<void> _wipeAllAuthAndStorage() async {
    final c = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('WIPE ALL?'),
        content: const Text('This will call Cloud Function to wipe Auth. Cannot be undone!'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('WIPE')),
        ],
      ),
    );
    if (c != true) return;
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('wipeAllAuthAndStorage').call({});
      _log('WIPE DONE: ${res.data}');
      _toast('Wiped');
      _loadAll();
    } catch (e) {
      _toast('Wipe failed: $e');
    }
  }

  Widget _tabBtn(String label, String tab, Color color) {
    final selected = currentTab == tab;
    return ElevatedButton(
      onPressed: () => setState(() => currentTab = tab),
      style: ElevatedButton.styleFrom(backgroundColor: selected ? color : Colors.white24),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  // ============ FIX: FILES NOW OPEN ON TAP ============
  Future<void> _openDoc(String url, String label, String type) async {
    final u = url.trim();
    if (u.isEmpty) { _toast('No $label uploaded'); return; }
    // PIN / Phone are text values, not files - show them, don't try to open
    if (type == 'text') {
      showDialog(context: context, builder: (_) => AlertDialog(
        title: Text(label),
        content: SelectableText(u),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ));
      return;
    }
    final lower = u.toLowerCase();
    final isImage = lower.contains('.jpg') || lower.contains('.jpeg') || lower.contains('.png') || lower.contains('.webp') || lower.contains('photo') || lower.contains('image') || type == 'image' && (label == 'Photo' || label == 'ID' || label == 'Licence');
    final isVideo = lower.contains('.mp4') || lower.contains('.mov') || lower.contains('.webm') || lower.contains('video') || label == 'Video';
    final isPdf = lower.contains('.pdf');

    // Images + PDFs + Videos open INSIDE the app so they always work,
    // even if no external viewer is installed.
    if (isVideo) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => _VideoViewerPage(url: u, title: label)));
      return;
    }
    if (isImage || isPdf) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => _DocViewerPage(url: u, title: label, isPdf: isPdf)));
      return;
    }
    // Fallback: anything else (doc/docx etc) -> open in browser / external app
    try {
      final uri = Uri.parse(u);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _toast('Cannot open $label');
      }
    } catch (e) { _toast('Cannot open $label: $e'); }
  }

  Widget _docBox(String url, String label, bool has, String type) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (!has || url.trim().isEmpty) { _toast('No $label uploaded'); return; }
          _openDoc(url, label, type);
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: has ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 80,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(has ? Icons.visibility : Icons.block, color: has ? Colors.white70 : Colors.white30, size: 22),
                      const SizedBox(height: 4),
                      Text(has ? 'View $label' : 'No $label', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                      if (has) const Text('Tap to open', style: TextStyle(color: Colors.greenAccent, fontSize: 9)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text('$label ${has ? 'OK' : 'NO'}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(Map r) {
    final bool isClient = r['type'] == 'client';
    final bool verified = r['emailVerified'] == true;
    final bool approved = r['isApproved'] == true;
    final String photoUrl = r['photo'].toString();
    final String statusText;
    if (isClient) {
      statusText = verified ? 'VERIFIED - Auto-Approved, Can Login' : 'PENDING - Not Verified Email Yet';
    } else {
      statusText = approved ? 'APPROVED BY CEO' : 'PENDING CEO APPROVAL';
    }
    return Card(
      color: const Color(0xFF1A1633),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.purple,
                  backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                  child: photoUrl.isEmpty ? Text(isClient ? 'C' : 'N') : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['fullName'].toString().isEmpty ? r['email'].toString() : r['fullName'].toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(r['email'].toString(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      Text(r['phone'].toString(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      Text(statusText, style: TextStyle(color: approved || verified ? Colors.greenAccent : Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _docBox(r['photo'].toString(), 'Photo', r['hasPhoto'] == true, 'image'),
                const SizedBox(width: 6),
                _docBox(r['idURL'].toString(), 'ID', r['hasId'] == true, 'image'),
                const SizedBox(width: 6),
                _docBox(r['licenceURL'].toString(), 'Licence', r['hasLicence'] == true, 'image'),
                const SizedBox(width: 6),
                _docBox(r['videoURL'].toString(), 'Video', r['hasVideo'] == true, 'image'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _docBox(r['certURL'].toString(), 'Cert', r['hasCert'] == true, 'image'),
                const SizedBox(width: 6),
                _docBox(r['cvURL'].toString(), 'CV', r['hasCv'] == true, 'image'),
                const SizedBox(width: 6),
                _docBox((r['raw'] is Map ? ((r['raw']['nursingPin'] ?? r['raw']['pin'] ?? r['raw']['nmcPin'] ?? '')).toString() : ''), 'PIN', r['hasPin'] == true, 'text'),
                const SizedBox(width: 6),
                _docBox(r['phone'].toString(), 'Phone', r['phone'].toString().isNotEmpty, 'text'),
              ],
            ),
            const SizedBox(height: 10),
            _buildButtons(r, isClient),
          ],
        ),
      ),
    );
  }

  Widget _buildButtons(Map r, bool isClient) {
    if (isClient) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: r['emailVerified'] == true ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              r['emailVerified'] == true ? 'Client Auto-Approved - No CEO Needed' : 'Client Pending - Waiting Gmail Verify',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _reject(r),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  child: const FittedBox(child: Text('Reject', style: TextStyle(color: Colors.white))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _deleteAccount(r),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const FittedBox(child: Text('Delete', style: TextStyle(color: Colors.white, fontSize: 12))),
                ),
              ),
            ],
          ),
        ],
      );
    }
    // NURSE - with Fix Uploads From Storage button on top
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _fixUploadsFromStorage(r),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Fix Uploads From Storage', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => _approve(r),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const FittedBox(child: Text('Approve', style: TextStyle(color: Colors.white))),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _reject(r),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const FittedBox(child: Text('Reject', style: TextStyle(color: Colors.white))),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _deleteAccount(r),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const FittedBox(child: Text('Delete', style: TextStyle(color: Colors.white, fontSize: 12))),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1633),
        title: const Text('CEO Registration Center', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: _export, child: const Text('Export', style: TextStyle(color: Colors.yellow))),
          TextButton(onPressed: _fixAllClientsToNewRule, child: const Text('Fix Clients', style: TextStyle(color: Colors.lightGreenAccent))),
          TextButton(onPressed: _deleteAllFiltered, child: const Text('Delete All', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: _wipeAllAuthAndStorage, child: const Text('Wipe', style: TextStyle(color: Colors.redAccent))),
          TextButton(onPressed: _fixAllApproved, child: const Text('Fix Nurses', style: TextStyle(color: Colors.greenAccent))),
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh, color: Colors.white)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tabBtn('Nurses Pending ($nursesPendingCount)', 'nursesPending', Colors.orange),
                _tabBtn('Nurses Approved ($nursesApprovedCount)', 'nursesApproved', Colors.green),
                _tabBtn('Clients Pending ($clientsPendingCount) - Not Verified', 'clientsPending', Colors.blue),
                _tabBtn('Clients Approved ($clientsApprovedCount) - Verified', 'clientsApproved', Colors.teal),
                _tabBtn('ALL (${allRecords.length})', 'all', Colors.purple),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => search = v),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search name / email / phone...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white12,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: docFilter,
                  dropdownColor: const Color(0xFF1A1633),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Docs')),
                    DropdownMenuItem(value: 'noVideo', child: Text('No Video')),
                    DropdownMenuItem(value: 'noPhoto', child: Text('No Photo')),
                    DropdownMenuItem(value: 'noId', child: Text('No ID')),
                  ],
                  onChanged: (v) => setState(() => docFilter = v ?? 'all'),
                ),
              ],
            ),
          ),
          if (showLog)
            Container(
              height: 120,
              width: double.infinity,
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(8),
              color: Colors.black,
              child: SingleChildScrollView(child: Text(logLines.join('\n'), style: const TextStyle(color: Colors.greenAccent, fontSize: 11))),
            ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : list.isEmpty
                    ? const Center(child: Text('No records in this tab.\n\nIf nurse just registered, press Refresh.\nCheck if nurse saved to Firestore or RTDB.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) => _buildCard(list[i]),
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: _recoverOrphans, child: const Text('Recover Orphans'))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(onPressed: _export, child: const Text('Export CSV'))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// ---- In-app viewers (put at bottom of file, outside the State class) ----
class _DocViewerPage extends StatelessWidget {
  final String url; final String title; final bool isPdf;
  const _DocViewerPage({required this.url, required this.title, required this.isPdf});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: const Color(0xFF1A1633)),
      backgroundColor: Colors.black,
      body: Center(
        child: isPdf
          ? _PdfFallback(url: url)
          : InteractiveViewer(
              child: Image.network(url,
                fit: BoxFit.contain,
                loadingBuilder: (_, c, p) => p == null ? c : const CircularProgressIndicator(color: Colors.white),
                errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(24), child: Text('Could not load image. Check Storage rules / URL.', style: TextStyle(color: Colors.white), textAlign: TextAlign.center)),
              ),
            ),
      ),
    );
  }
}

class _PdfFallback extends StatelessWidget {
  final String url; const _PdfFallback({required this.url});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.picture_as_pdf, size: 64, color: Colors.white54),
      const SizedBox(height: 16),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Text('PDF preview needs an external viewer on this device.', style: TextStyle(color: Colors.white), textAlign: TextAlign.center)),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: () async { final uri = Uri.parse(url); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }, child: const Text('Open PDF')),
    ]);
  }
}

class _VideoViewerPage extends StatefulWidget {
  final String url; final String title;
  const _VideoViewerPage({required this.url, required this.title});
  @override
  State<_VideoViewerPage> createState() => _VideoViewerPageState();
}
class _VideoViewerPageState extends State<_VideoViewerPage> {
  VideoPlayerController? _vc; ChewieController? _cc; String? _err;
  @override
  void initState() { super.initState(); _init(); }
  Future<void> _init() async {
    try {
      _vc = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await _vc!.initialize();
      _cc = ChewieController(videoPlayerController: _vc!, autoPlay: true, looping: false);
      if (mounted) setState(() {});
    } catch (e) { if (mounted) setState(() => _err = e.toString()); }
  }
  @override
  void dispose() { _cc?.dispose(); _vc?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), backgroundColor: const Color(0xFF1A1633)),
      backgroundColor: Colors.black,
      body: Center(
        child: _err != null ? Padding(padding: const EdgeInsets.all(24), child: Text('Could not play video: $_err', style: const TextStyle(color: Colors.white), textAlign: TextAlign.center))
        : _cc == null ? const CircularProgressIndicator(color: Colors.white)
        : AspectRatio(aspectRatio: _vc!.value.aspectRatio, child: Chewie(controller: _cc!)),
      ),
    );
  }
}
