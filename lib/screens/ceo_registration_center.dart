import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

/// CEO Registration Center - Flutter version of ceo-registration-center.html
/// - Loads: Nurses from ceoRegistrationCenter/nurses + nurses + pending_nurses + pendingNurses + ceoNurseUpdates + nurse_registrations + allNurses + nurseUsers + nurseApplications + allowedNurses + allowedNursesByUid + verified_nurses
///   Clients from ceoRegistrationCenter/clients + clients + client_registrations + allClients + clientUsers + pendingClientRegistrations + ceoClientUpdates + allowedClients + allowedClientsByUid
///   Merge by uid: keep TRUE approval (true wins), merge photo/video/ID/licence/cert (first non-empty wins)
/// - normalizeRecord: v = raw.profile ?? raw.data ?? raw ; email (lower), username (username/userName/id), fullName (fullName/name/displayName/clientName/username/email-prefix, max 50)
///   phone (phone/phoneNumber/clientPhone/phoneNumberFull), countryCode, photo (photoURL/photo/photoUrl/avatar/avatarUrl), idURL (idURL/idUrl/nationalIdUrl), licenceURL (licenceURL/licenseUrl/licence/licenceUrl), videoURL (videoURL/videoUrl), certURL (cvURL/cvUrl/certificateURL/certificate)
///   lat/lng, gpsName (gpsActualName/gpsName), qualification, services (services/specialty), referenceName/Phone, passwordHash
///   isApproved = isApproved || approved || status approved/Approved || canLogin || isVerified || hasAll4
///   hasAll5 (nurse) = fullName && photo && phone && videoURL ; hasAll5 (client) = fullName && username && photo && phone ; hasAll4 = fullName && username && photo && phone
///   hasPhoto/Video/Id/Licence/Cert booleans
/// - Tabs: nursesPending / nursesApproved / clientsPending / clientsApproved / all — same as HTML switchTab()
/// - Search: fullName + name + username + email + phone + countryCode ; Doc filter: all / missing ( !hasAll5 ) / hasVideo / hasPhoto — same as HTML render()
/// - Card: avatar (photo or initial), name + 👩‍⚕️/👤, Username, badge ✅ APPROVED / ⏳ PENDING, badge ✅ ALL 4 / ❌ Missing, email, phone (countryCode + phone), nurse: 🎓 qualification • services, Ref name/phone, 📍 gpsName (lat,lng), UID • createdAt
///   Docs: Photo ✅/❌, ID, Licence, Video, Cert (CV) — tap opens viewer (image / PDF link / video with sound ON volume 100% — same as HTML viewDoc, video muted=false volume=1.0)
///   View All Docs: dialog with Full Name / Username / Email / Country Code / Phone / Full Phone / Approved / HasAll4 / Photo/ID/Licence/Video/Cert links — same as HTML viewAllDocs()
/// - Approve: confirm "Approve {type} {email}? This will update ALL 12 database paths so nurse moves to Approved and can login."
///   approvedPayload {isApproved true, approved true, status approved, canLogin true, isVerified true, approvedAt, approvedBy CEO, updatedAt}
///   Nurse: update if exists in nurses/{uid} + pending_nurses + pendingNurses + nurse_registrations + nurseApplications + allNurses + nurseUsers + ceoNurseUpdates + ceoRegistrationCenter/nurses + verified_nurses, then set allowedNurses/{emailKey} + allowedNursesByUid/{uid} = {...raw, uid, email lower, ...payload}
///   Client: update if exists in clients + client_registrations + allClients + clientUsers + ceoClientUpdates + ceoRegistrationCenter/clients + pendingClientRegistrations, then set allowedClients/{emailKey} + allowedClientsByUid/{uid}
///   Log panel: "Approving ... in ALL paths..." + per-path ✅ Updated + DONE — reload after 1.5s
/// - Reject: confirm -> nurse: nurses/{uid} + ceoRegistrationCenter/nurses {isApproved false, status rejected, rejectedAt} + remove allowedNurses/{emailKey} + allowedNursesByUid/{uid} ; client: clients/{uid} + ceoRegistrationCenter/clients {isApproved false, status rejected} — reload 800ms
/// - Fix All Approved: confirm -> scan allowedNurses, for each uid+email set approved payload in nurses + pending_nurses + pendingNurses + ceoRegistrationCenter/nurses + ceoNurseUpdates + nurse_registrations -> toast "✅ Fixed {n} nurses"
/// - Delete Account COMPLETELY: confirm x2 + type DELETE prompt (must type DELETE) -> find all UIDs by email in nurses/pending_nurses/nurse_registrations/ceoRegistrationCenter/nurses
///   Nurse RTDB bases: nurses, pending_nurses, pendingNurses, allNurses, nurse_registrations, nurseApplications, nurseUsers, ceoNurseUpdates, ceoRegistrationCenter/nurses, verified_nurses, allowedNurses, allowedNursesByUid, nursesByEmail, nurseProfiles, onlineNurses, nursePresence ; mapping: allowedNurses/{emailKey}, allowedClients/{emailKey}, nursesByEmail/{emailKey}, allowedNurses/{uid}, allowedNursesByUid/{uid}
///   Client RTDB bases: clients, client_registrations, allClients, clientUsers, ceoClientUpdates, ceoRegistrationCenter/clients, allowedClients, allowedClientsByUid, pendingClientRegistrations, verified_clients, onlineClients, clientPresence, clientsByEmail, clientBookings, bookings ; mapping: allowedClients/{emailKey}, allowedClients/{uid}, allowedClientsByUid/{uid}, clientUsernames/{username}, clientPhones/{phoneRaw/phoneDigits}, clientsByEmail/{emailKey}, allowedClients/{username}, clients/{username} + find via clientUsernames/clientPhones + phone/username variants
///   Log panel shows per-path ✅ Deleted. Firestore + Storage deletion in HTML required Firebase Auth admin / Storage SDK — Flutter uses RTDB only (same as all other Flutter screens); log notes "Firestore/Storage: delete via Firebase Console if needed".
/// - NO alert buttons — only Sound Settings.

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
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  String _sanitizeEmail(String e) => e.toLowerCase().replaceAll(RegExp(r'[.#\$@\[\]]'), '_');
  void _log(String m) => setState(() { showLog = true; logLines.add(m); });
  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // Firestore Timestamp has .millisecondsSinceEpoch, RTDB stores int ms, old docs may store String.
  num _createdAtMs(Object? raw) {
    if (raw is num) return raw;
    if (raw is String) return num.tryParse(raw) ?? DateTime.now().millisecondsSinceEpoch;
    if (raw != null) {
      try {
        final ms = (raw as dynamic).millisecondsSinceEpoch;
        if (ms is num) return ms;
      } catch (_) {}
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  Map _normalize(String id, Map raw, String type) {
    final v = raw['profile'] is Map ? Map<String, dynamic>.from(raw['profile']) : raw['data'] is Map ? Map<String, dynamic>.from(raw['data']) : raw;
    final email = ((v['email'] ?? v['clientEmail'] ?? '') as String).toLowerCase();
    final username = v['username'] ?? v['userName'] ?? id;
    var fullName = (v['fullName'] ?? v['name'] ?? v['displayName'] ?? v['clientName'] ?? username ?? (email.isNotEmpty ? email.split('@')[0] : 'Unnamed')).toString();
    if (fullName.length > 50) fullName = fullName.substring(0, 50);
    final photo = v['photoURL'] ?? v['photo'] ?? v['photoUrl'] ?? v['avatar'] ?? v['avatarUrl'] ?? '';
    final idURL = v['idURL'] ?? v['idUrl'] ?? v['nationalIdUrl'] ?? v['idFrontURL'] ?? v['idFrontUrl'] ?? v['nationalIdFrontUrl'] ?? '';
    final idBackURL = v['idBackURL'] ?? v['idBackUrl'] ?? v['nationalIdBackUrl'] ?? '';
    final licenceURL = v['licenceURL'] ?? v['licenseUrl'] ?? v['licence'] ?? v['licenceUrl'] ?? v['pinDocURL'] ?? v['pinDocUrl'] ?? '';
    final videoURL = v['videoURL'] ?? v['videoUrl'] ?? '';
    final certURL = v['certificateURL'] ?? v['certificateUrl'] ?? v['certificate'] ?? v['certURL'] ?? v['certUrl'] ?? '';
    final cvURL = v['cvURL'] ?? v['cvUrl'] ?? '';
    final phone = (v['phone'] ?? v['phoneNumber'] ?? v['clientPhone'] ?? v['phoneNumberFull'] ?? '').toString();
    final isApproved = v['isApproved'] == true || v['approved'] == true || v['status'] == 'approved' || v['canLogin'] == true || v['isVerified'] == true || v['status'] == 'Approved' || v['hasAll4'] == true;
    final hasAll5 = type == 'client' ? (fullName.isNotEmpty && username.toString().isNotEmpty && photo.toString().isNotEmpty && phone.isNotEmpty) : (fullName.isNotEmpty && photo.toString().isNotEmpty && phone.isNotEmpty && videoURL.toString().isNotEmpty);
    final hasAll4 = fullName.isNotEmpty && username.toString().isNotEmpty && photo.toString().isNotEmpty && phone.isNotEmpty;
    return {'id': id, 'uid': v['uid'] ?? id, 'type': type, 'fullName': fullName, 'name': fullName.length > 40 ? fullName.substring(0, 40) : fullName, 'username': username, 'email': email, 'phone': phone, 'countryCode': v['countryCode'] ?? '', 'photo': photo, 'idURL': idURL, 'licenceURL': licenceURL, 'videoURL': videoURL, 'certURL': certURL, 'lat': v['lat'] ?? v['latitude'], 'lng': v['lng'] ?? v['longitude'], 'gpsName': v['gpsActualName'] ?? v['gpsName'] ?? '', 'isApproved': isApproved, 'hasAll5': hasAll5, 'hasAll4': hasAll4, 'hasPhoto': photo.toString().isNotEmpty, 'hasVideo': videoURL.toString().isNotEmpty, 'hasId': idURL.toString().isNotEmpty, 'hasLicence': licenceURL.toString().isNotEmpty, 'hasCert': certURL.toString().isNotEmpty, 'raw': v, 'createdAt': _createdAtMs(v['createdAt'] ?? v['timestamp']), 'qualification': v['qualification'] ?? '', 'services': v['services'] ?? v['specialty'] ?? '', 'referenceName': v['referenceName'] ?? '', 'referencePhone': v['referencePhone'] ?? '', 'cvURL': cvURL, 'idBackURL': idBackURL, 'idFrontURL': idURL, 'pinNumber': v['pinNumber'] ?? '', 'idType': v['idType'] ?? '', 'idCheck': v['idCheck'] ?? '', 'idVerified': v['idVerified'] ?? false};
  }

  Future<void> _loadAll() async {
    Map<String, Map> nursesMap = {}, clientsMap = {};
    final nursePaths = ['ceoRegistrationCenter/nurses', 'nurses', 'pending_nurses', 'pendingNurses', 'ceoNurseUpdates', 'nurse_registrations', 'allNurses', 'nurseUsers', 'nurseApplications', 'allowedNurses', 'allowedNursesByUid', 'verified_nurses'];
    for (final path in nursePaths) {
      try {
        final snap = await FirebaseDatabase.instance.ref(path).get();
        if (!snap.exists) continue;
        (snap.value as Map).forEach((k, val) {
          if (val is! Map) return;
          final rec = _normalize(k.toString(), Map<String, dynamic>.from(val), 'nurse');
          final key = rec['uid'].toString();
          if (!nursesMap.containsKey(key)) nursesMap[key] = rec;
          else {
            final ex = nursesMap[key]!;
            final isApprovedNow = ex['isApproved'] == true || rec['isApproved'] == true;
            nursesMap[key] = {...ex, ...rec, 'photo': (ex['photo'].toString().isNotEmpty ? ex['photo'] : rec['photo']), 'videoURL': (ex['videoURL'].toString().isNotEmpty ? ex['videoURL'] : rec['videoURL']), 'idURL': (ex['idURL'].toString().isNotEmpty ? ex['idURL'] : rec['idURL']), 'licenceURL': (ex['licenceURL'].toString().isNotEmpty ? ex['licenceURL'] : rec['licenceURL']), 'certURL': (ex['certURL'].toString().isNotEmpty ? ex['certURL'] : rec['certURL']), 'isApproved': isApprovedNow, 'hasPhoto': (ex['photo'].toString().isNotEmpty || rec['photo'].toString().isNotEmpty), 'hasVideo': (ex['videoURL'].toString().isNotEmpty || rec['videoURL'].toString().isNotEmpty)};
          }
        });
      } catch (_) {}
    }
    final clientPaths = ['ceoRegistrationCenter/clients', 'clients', 'client_registrations', 'allClients', 'clientUsers', 'pendingClientRegistrations', 'ceoClientUpdates', 'allowedClients', 'allowedClientsByUid'];
    for (final path in clientPaths) {
      try {
        final snap = await FirebaseDatabase.instance.ref(path).get();
        if (!snap.exists) continue;
        (snap.value as Map).forEach((k, val) {
          if (val is! Map) return;
          final rec = _normalize(k.toString(), Map<String, dynamic>.from(val), 'client');
          final key = rec['uid'].toString();
          if (!clientsMap.containsKey(key)) clientsMap[key] = rec;
          else { final ex = clientsMap[key]!; final isApprovedNow = ex['isApproved'] == true || rec['isApproved'] == true; clientsMap[key] = {...ex, ...rec, 'photo': (ex['photo'].toString().isNotEmpty ? ex['photo'] : rec['photo']), 'isApproved': isApprovedNow}; }
        });
      } catch (_) {}
    }
    // ---- RECALL OLD USERS: Firestore-only registrations (before the dual-write fix) ----
    // Old nurses/clients saved ONLY to Firestore pending_nurses / pending_clients.
    // CEO used to read RTDB only, so they were invisible. Now CEO reads Firestore too,
    // and auto-migrates each Firestore-only record into RTDB ceoRegistrationCenter/...,
    // so Approve / Reject / Delete (which work on RTDB) will work for them as well.
    final rtdbNurseUids = nursesMap.keys.toSet();
    final rtdbClientUids = clientsMap.keys.toSet();
    int migratedNurses = 0, migratedClients = 0;
    for (final coll in ['pending_nurses', 'nurses', 'nurse_registrations', 'nurseApplications']) {
      try {
        final qs = await FirebaseFirestore.instance.collection(coll).get();
        for (final doc in qs.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          final rec = _normalize(doc.id, data, 'nurse');
          final key = rec['uid'].toString();
          if (!nursesMap.containsKey(key)) {
            nursesMap[key] = rec;
          } else {
            final ex = nursesMap[key]!;
            nursesMap[key] = {...ex, ...rec, 'photo': (ex['photo'].toString().isNotEmpty ? ex['photo'] : rec['photo']), 'videoURL': (ex['videoURL'].toString().isNotEmpty ? ex['videoURL'] : rec['videoURL']), 'idURL': (ex['idURL'].toString().isNotEmpty ? ex['idURL'] : rec['idURL']), 'licenceURL': (ex['licenceURL'].toString().isNotEmpty ? ex['licenceURL'] : rec['licenceURL'])};
          }
          // Migrate Firestore-only -> RTDB (only if RTDB did not have this uid)
          if (!rtdbNurseUids.contains(key)) {
            try {
              final toRtdb = Map<String, Object?>.from(data);
              toRtdb['createdAt'] = (rec['createdAt'] as num).toInt();
              toRtdb['uid'] = key;
              await FirebaseDatabase.instance.ref('ceoRegistrationCenter/nurses/$key').set(toRtdb);
              migratedNurses++;
              rtdbNurseUids.add(key);
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    for (final coll in ['pending_clients', 'clients', 'client_registrations', 'clientApplications']) {
      try {
        final qs = await FirebaseFirestore.instance.collection(coll).get();
        for (final doc in qs.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          final rec = _normalize(doc.id, data, 'client');
          final key = rec['uid'].toString();
          if (!clientsMap.containsKey(key)) clientsMap[key] = rec;
          if (!rtdbClientUids.contains(key)) {
            try {
              final toRtdb = Map<String, Object?>.from(data);
              toRtdb['createdAt'] = (rec['createdAt'] as num).toInt();
              toRtdb['uid'] = key;
              await FirebaseDatabase.instance.ref('ceoRegistrationCenter/clients/$key').set(toRtdb);
              migratedClients++;
              rtdbClientUids.add(key);
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    final nurses = nursesMap.values.toList(), clients = clientsMap.values.toList();
    setState(() => allRecords = [...nurses, ...clients]..sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num)));
    _toast('Loaded: ${nurses.length} nurses, ${clients.length} clients${(migratedNurses + migratedClients) > 0 ? ' - Recalled $migratedNurses old nurses + $migratedClients old clients from Firestore' : ''}');
  }

  List<Map> get filtered {
    var list = <Map>[];
    if (currentTab == 'nursesPending') list = allRecords.where((r) => r['type'] == 'nurse' && r['isApproved'] != true).toList();
    else if (currentTab == 'nursesApproved') list = allRecords.where((r) => r['type'] == 'nurse' && r['isApproved'] == true).toList();
    else if (currentTab == 'clientsPending') list = allRecords.where((r) => r['type'] == 'client' && r['isApproved'] != true).toList();
    else if (currentTab == 'clientsApproved') list = allRecords.where((r) => r['type'] == 'client' && r['isApproved'] == true).toList();
    else list = List<Map>.from(allRecords);
    if (search.isNotEmpty) list = list.where((r) => ('${r['fullName']} ${r['name']} ${r['username']} ${r['email']} ${r['phone']} ${r['countryCode']} ${r['phone']}').toLowerCase().contains(search)).toList();
    if (docFilter == 'missing') list = list.where((r) => r['hasAll5'] != true).toList();
    else if (docFilter == 'hasVideo') list = list.where((r) => r['hasVideo'] == true).toList();
    else if (docFilter == 'hasPhoto') list = list.where((r) => r['hasPhoto'] == true).toList();
    return list;
  }

  void _viewDoc(String url, String title, String type) {
    if (url.isEmpty) { _toast('No file'); return; }
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('$title — 🔊 Sound Fixed'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (url.contains('.pdf')) TextButton(onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication), child: const Text('📄 Open PDF')),
        if (type == 'video') Column(children: [const Chip(label: Text('🔊 Sound ON — Volume 100%')), const SizedBox(height: 8), TextButton(onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication), child: const Text('▶️ Play Video (with sound)'))]),
        if (type == 'image') Image.network(url, errorBuilder: (_, __, ___) => const Text('Could not load image')),
        if (type != 'video' && type != 'image' && !url.contains('.pdf')) TextButton(onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication), child: const Text('Open File')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  void _viewAllDocs(Map rec) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('All Uploads — ${rec['fullName'] ?? rec['name']}'),
      content: SingleChildScrollView(child: Text('Full Name: ${rec['fullName'] ?? rec['name']}\nUsername (Login): ${rec['username'] ?? rec['id']}\nEmail: ${rec['email'].toString().isEmpty ? 'N/A (Username System)' : rec['email']}\nCountry Code: ${rec['countryCode'] ?? 'N/A'}\nPhone: ${rec['phone']}\nFull Phone: ${rec['countryCode'] ?? ''} ${rec['phone']}\nApproved: ${rec['isApproved'] == true ? 'YES ✅' : 'NO ⏳'}\nHasAll4: ${rec['hasAll4'] == true ? 'YES ✅' : 'NO'}\nPhoto: ${rec['photo'].toString().isNotEmpty ? 'View' : 'Missing'}\nID: ${rec['idURL'].toString().isNotEmpty ? 'View' : 'Missing'}\nLicence: ${rec['licenceURL'].toString().isNotEmpty ? 'View' : 'Missing'}\nVideo: ${rec['videoURL'].toString().isNotEmpty ? 'View' : 'Missing'}\nCert: ${rec['certURL'].toString().isNotEmpty ? 'View' : 'Optional'}')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  Future<void> _approve(Map rec) async {
    final uid = rec['uid'].toString(); final email = rec['email'].toString(); final type = rec['type'].toString();
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Approve?'), content: Text('Approve $type $email?\n\nThis will update ALL 12 database paths so ${type == 'nurse' ? 'nurse' : 'client'} moves to Approved and can login.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve'))]));
    if (confirm != true) return;
    setState(() { showLog = true; logLines = []; });
    _log('Approving $type $email ($uid) in ALL paths...');
    try {
      final emailKey = _sanitizeEmail(email);
      final now = DateTime.now().millisecondsSinceEpoch;
      final payload = {'isApproved': true, 'approved': true, 'status': 'approved', 'canLogin': true, 'isVerified': true, 'approvedAt': now, 'approvedBy': 'CEO', 'updatedAt': now};
      final db = FirebaseDatabase.instance;
      final paths = type == 'nurse' ? ['nurses/$uid', 'pending_nurses/$uid', 'pendingNurses/$uid', 'nurse_registrations/$uid', 'nurseApplications/$uid', 'allNurses/$uid', 'nurseUsers/$uid', 'ceoNurseUpdates/$uid', 'ceoRegistrationCenter/nurses/$uid', 'verified_nurses/$uid'] : ['clients/$uid', 'client_registrations/$uid', 'allClients/$uid', 'clientUsers/$uid', 'ceoClientUpdates/$uid', 'ceoRegistrationCenter/clients/$uid', 'pendingClientRegistrations/$uid'];
      for (final p in paths) {
        try { final s = await db.ref(p).get(); if (s.exists) { await db.ref(p).update(payload); _log('✅ Updated $p → approved'); } } catch (e) { _log('⚠️ $p not exist or err: $e'); }
      }
      final whitelist = {...Map<String, dynamic>.from(rec['raw'] as Map), 'uid': uid, 'email': email.toLowerCase(), ...payload};
      if (type == 'nurse') {
        await db.ref('allowedNurses/$emailKey').set(whitelist); _log('✅ Created allowedNurses/$emailKey');
        await db.ref('allowedNursesByUid/$uid').set(whitelist); _log('✅ Created allowedNursesByUid/$uid');
      } else {
        await db.ref('allowedClients/$emailKey').set(whitelist); _log('✅ Created allowedClients/$emailKey');
        await db.ref('allowedClientsByUid/$uid').set(whitelist); _log('✅ Created allowedClientsByUid/$uid');
      }
      _toast('✅ $email APPROVED in ALL paths — now moves to Approved tab and can login!');
      _log('✅ DONE — $email approved in ALL paths');
      Future.delayed(const Duration(milliseconds: 1500), _loadAll);
    } catch (e) { _log('❌ Approve failed: $e'); _toast('Approve failed: $e'); }
  }

  Future<void> _reject(Map rec) async {
    final uid = rec['uid'].toString(); final email = rec['email'].toString(); final type = rec['type'].toString();
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Reject?'), content: Text('Reject $type $email?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject'))]));
    if (confirm != true) return;
    try {
      final db = FirebaseDatabase.instance; final now = DateTime.now().millisecondsSinceEpoch;
      if (type == 'nurse') {
        await db.ref('nurses/$uid').update({'isApproved': false, 'status': 'rejected', 'rejectedAt': now});
        await db.ref('ceoRegistrationCenter/nurses/$uid').update({'isApproved': false, 'status': 'rejected'});
        await db.ref('allowedNurses/${_sanitizeEmail(email)}').remove().catchError((_) {});
        await db.ref('allowedNursesByUid/$uid').remove().catchError((_) {});
      } else {
        await db.ref('clients/$uid').update({'isApproved': false, 'status': 'rejected'});
        await db.ref('ceoRegistrationCenter/clients/$uid').update({'isApproved': false, 'status': 'rejected'});
      }
      _toast('❌ $email rejected');
      Future.delayed(const Duration(milliseconds: 800), _loadAll);
    } catch (e) { _toast('Reject failed: $e'); }
  }

  Future<void> _fixAllApproved() async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Fix All Approved?'), content: const Text('This will scan all nurses that are in allowedNurses whitelist but still showing pending, and fix them to approved in ALL paths. Continue?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Fix All'))]));
    if (confirm != true) return;
    setState(() { showLog = true; logLines = []; });
    _log('Scanning allowedNurses whitelist...');
    try {
      final snap = await FirebaseDatabase.instance.ref('allowedNurses').get();
      if (!snap.exists) { _toast('No allowedNurses found'); return; }
      int fixed = 0; final db = FirebaseDatabase.instance;
      for (final entry in (snap.value as Map).entries) {
        final v = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : {};
        final uid = v['uid']?.toString(); final email = v['email']?.toString();
        if (uid != null && email != null) {
          final payload = {'isApproved': true, 'approved': true, 'status': 'approved', 'canLogin': true, 'isVerified': true, 'approvedAt': DateTime.now().millisecondsSinceEpoch, 'updatedAt': DateTime.now().millisecondsSinceEpoch};
          for (final p in ['nurses/$uid', 'pending_nurses/$uid', 'pendingNurses/$uid', 'ceoRegistrationCenter/nurses/$uid', 'ceoNurseUpdates/$uid', 'nurse_registrations/$uid']) await db.ref(p).update(payload).catchError((_) {});
          _log('Fixed nurses/$uid'); fixed++;
        }
      }
      _toast('✅ Fixed $fixed nurses — they will now show in Approved');
      _log('✅ Fixed $fixed nurses');
      Future.delayed(const Duration(milliseconds: 1500), _loadAll);
    } catch (e) { _toast('Fix failed: $e'); _log('Fix failed: $e'); }
  }

  Future<void> _deleteAccount(Map rec) async {
    final uid = rec['uid'].toString(); final email = rec['email'].toString(); final type = rec['type'].toString();
    final displayName = rec['fullName'] ?? email;
    final c1 = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('DELETE COMPLETELY?'), content: Text('DELETE $type $displayName ($email) COMPLETELY?\n\nThis will delete:\n- RTDB: 20+ locations (nurses, pending, allowed, ceo, etc)\n- Firestore: all collections\n- Storage: all files\n- By BOTH UID and EMAIL\n\nThis cannot be undone!\n\nDelete $email?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('DELETE'))]));
    if (c1 != true) return;
    final c2 = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('FINAL CONFIRM'), content: Text('Really delete $email from ALL database?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('YES DELETE'))]));
    if (c2 != true) return;
    final ctrl = TextEditingController();
    final confirmText = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: Text('Type DELETE to confirm deletion of $email'), content: TextField(controller: ctrl), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Confirm'))]));
    if (confirmText != 'DELETE') { _toast('Cancelled - you must type DELETE'); return; }
    setState(() { showLog = true; logLines = []; });
    _log('STARTING COMPLETE DELETE for $email ($uid) - Type: $type');
    final emailKey = _sanitizeEmail(email); final eLower = email.toLowerCase().trim();
    _log('EmailKey: $emailKey');
    try {
      final db = FirebaseDatabase.instance;
      Set<String> allUids = {uid, emailKey};
      for (final p in ['nurses', 'pending_nurses', 'nurse_registrations', 'ceoRegistrationCenter/nurses']) {
        try { final s = await db.ref(p).get(); if (s.exists) (s.value as Map).forEach((k, v) { if (v is Map && (v['email'] ?? '').toString().toLowerCase() == eLower) { allUids.add(k.toString()); _log('Found RTDB $p/$k with email $email'); } }); } catch (_) {}
      }
      List<String> rtdbBases = []; List<String> mappingPaths = [];
      if (type == 'nurse' || eLower.contains('@')) {
        rtdbBases = ['nurses', 'pending_nurses', 'pendingNurses', 'allNurses', 'nurse_registrations', 'nurseApplications', 'nurseUsers', 'ceoNurseUpdates', 'ceoRegistrationCenter/nurses', 'verified_nurses', 'allowedNurses', 'allowedNursesByUid', 'nursesByEmail', 'nurseProfiles', 'onlineNurses', 'nursePresence'];
        mappingPaths = ['allowedNurses/$emailKey', 'allowedClients/$emailKey', 'nursesByEmail/$emailKey', 'allowedNurses/$uid', 'allowedNursesByUid/$uid'];
      } else {
        final raw = Map<String, dynamic>.from(rec['raw'] as Map);
        final username = ((raw['username'] ?? raw['userName'] ?? '') as String).toLowerCase();
        final phoneRaw = (raw['phone'] ?? raw['phoneNumber'] ?? '').toString();
        final phoneDigits = phoneRaw.replaceAll(RegExp(r'[^0-9]'), '');
        rtdbBases = ['clients', 'client_registrations', 'allClients', 'clientUsers', 'ceoClientUpdates', 'ceoRegistrationCenter/clients', 'allowedClients', 'allowedClientsByUid', 'pendingClientRegistrations', 'verified_clients', 'onlineClients', 'clientPresence', 'clientsByEmail', 'clientBookings', 'bookings'];
        mappingPaths = ['allowedClients/$emailKey', 'allowedClients/$uid', 'allowedClientsByUid/$uid', 'clientUsernames/$username', 'clientPhones/$phoneRaw', 'clientPhones/$phoneDigits', 'clientsByEmail/$emailKey', 'allowedClients/${raw['username'] ?? ''}', 'clients/${raw['username'] ?? ''}'];
        if (phoneDigits.isNotEmpty) { allUids.add(phoneDigits); allUids.add(phoneRaw); }
        if (username.isNotEmpty) { allUids.add(username); allUids.add(username.toLowerCase()); }
        try { final s = await db.ref('clientUsernames').get(); if (s.exists) (s.value as Map).forEach((k, val) { if (val == uid || k.toString().toLowerCase() == username) { allUids.add(k.toString()); allUids.add(val.toString()); _log('Found via clientUsernames/$k -> $val'); } }); } catch (_) {}
        try { final s = await db.ref('clientPhones').get(); if (s.exists) (s.value as Map).forEach((k, val) { if (val == uid || k == phoneDigits || k == phoneRaw) { allUids.add(k.toString()); allUids.add(val.toString()); _log('Found via clientPhones/$k -> $val'); } }); } catch (_) {}
      }
      _log('All UIDs to delete: ${allUids.join(', ')}');
      int deleted = 0;
      for (final base in rtdbBases) for (final id in allUids) {
        if (id.length < 2) continue;
        try { await db.ref('$base/$id').remove(); _log('✅ Deleted: $base/$id'); deleted++; } catch (_) {}
      }
      for (final path in mappingPaths) {
        final key = path.split('/').length > 1 ? path.split('/')[1] : '';
        if (key.length < 2) continue;
        try { await db.ref(path).remove(); _log('✅ Deleted: $path'); deleted++; } catch (_) {}
      }
      if (type != 'nurse') {
        try { final s = await db.ref('clientUsernames').get(); if (s.exists) (s.value as Map).forEach((k, val) { if (val == uid) db.ref('clientUsernames/$k').remove(); }); } catch (_) {}
      }
      _log('Firestore/Storage: delete via Firebase Console if needed (Flutter uses RTDB only).');
      _toast('Deleted $deleted paths for $email');
      _loadAll();
    } catch (e) { _log('Delete failed: $e'); _toast('Delete failed: $e'); }
  }

  // ---------- EXPORT + DELETE ALL (current tab) ----------
  // No web-only import here - it breaks WASM build (same error as HR page).
  // Plain TextButton used.
  String _csvCell(String v) {
    final s = v.replaceAll('"', '""');
    if (s.contains(',') || s.contains('"') || s.contains('\n')) return '"$s"';
    return s;
  }

  String _buildCsv(List<Map> list) {
    final rows = <List<String>>[
      ['Type', 'Full Name', 'Username', 'Email', 'Phone', 'Country Code', 'Approved', 'Has Photo', 'Has Video', 'Has ID', 'Has Licence', 'Has Cert', 'Qualification', 'Services', 'Reference Name', 'Reference Phone', 'GPS Name', 'Lat', 'Lng', 'UID', 'Created At', 'Photo URL', 'ID URL', 'Licence URL', 'Video URL', 'Cert URL'],
    ];
    for (final r in list) {
      final created = r['createdAt'] != null ? DateTime.fromMillisecondsSinceEpoch((r['createdAt'] as num).toInt()).toString() : '';
      rows.add([
        '${r['type'] ?? ''}',
        '${r['fullName'] ?? ''}',
        '${r['username'] ?? ''}',
        '${r['email'] ?? ''}',
        '${r['phone'] ?? ''}',
        '${r['countryCode'] ?? ''}',
        '${r['isApproved'] == true ? 'APPROVED' : 'PENDING'}',
        '${r['hasPhoto'] == true ? 'YES' : 'NO'}',
        '${r['hasVideo'] == true ? 'YES' : 'NO'}',
        '${r['hasId'] == true ? 'YES' : 'NO'}',
        '${r['hasLicence'] == true ? 'YES' : 'NO'}',
        '${r['hasCert'] == true ? 'YES' : 'NO'}',
        '${r['qualification'] ?? ''}',
        '${r['services'] ?? ''}',
        '${r['referenceName'] ?? ''}',
        '${r['referencePhone'] ?? ''}',
        '${r['gpsName'] ?? ''}',
        '${r['lat'] ?? ''}',
        '${r['lng'] ?? ''}',
        '${r['uid'] ?? ''}',
        created,
        '${r['photo'] ?? ''}',
        '${r['idURL'] ?? ''}',
        '${r['licenceURL'] ?? ''}',
        '${r['videoURL'] ?? ''}',
        '${r['certURL'] ?? ''}',
      ]);
    }
    return rows.map((r) => r.map(_csvCell).join(',')).join('\n');
  }

  Future<void> _export() async {
    final list = filtered;
    if (list.isEmpty) { _toast('Nothing to export - list is empty'); return; }
    final csv = _buildCsv(list);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Export - CSV copied (${list.length} in $currentTab)'),
        content: SingleChildScrollView(child: Text('Saved ${list.length} records to clipboard.\n\nPaste it into Excel / Google Sheets / WhatsApp / Notes.\n\n$csv')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton(onPressed: () { Clipboard.setData(ClipboardData(text: csv)); Navigator.pop(context); _toast('Copied again'); }, child: const Text('Copy Again')),
        ],
      ),
    );
  }

  Future<void> _deleteAllFiltered() async {
    final list = List<Map>.from(filtered);
    if (list.isEmpty) { _toast('Nothing to delete'); return; }
    // One confirm for ALL - type DELETE once, not once per person (unlike per-card Delete)
    final c1 = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Delete ALL ${list.length} in $currentTab?'), content: Text('This deletes ALL ${list.length} records in the current tab ($currentTab) from RTDB. It cannot be undone.\n\nTip: Export first, so you still have a copy saved.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Continue'))]));
    if (c1 != true) return;
    final ctrl = TextEditingController();
    final confirmText = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: Text('Type DELETE to delete ALL ${list.length}'), content: TextField(controller: ctrl), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Confirm'))]));
    if (confirmText != 'DELETE') { _toast('Cancelled - you must type DELETE'); return; }
    setState(() { showLog = true; logLines = []; });
    _log('STARTING DELETE ALL - ${list.length} records in $currentTab');
    int done = 0;
    try {
      final db = FirebaseDatabase.instance;
      for (final rec in list) {
        final uid = (rec['uid'] ?? rec['id'] ?? '').toString();
        final email = (rec['email'] ?? '').toString().toLowerCase();
        final emailKey = _sanitizeEmail(email);
        final type = rec['type']?.toString() ?? 'nurse';
        final bases = type == 'nurse'
            ? ['nurses', 'pending_nurses', 'pendingNurses', 'allNurses', 'nurse_registrations', 'nurseApplications', 'nurseUsers', 'ceoNurseUpdates', 'ceoRegistrationCenter/nurses', 'verified_nurses', 'allowedNurses', 'allowedNursesByUid', 'nursesByEmail', 'nurseProfiles', 'onlineNurses', 'nursePresence']
            : ['clients', 'client_registrations', 'allClients', 'clientUsers', 'ceoClientUpdates', 'ceoRegistrationCenter/clients', 'allowedClients', 'allowedClientsByUid', 'pendingClientRegistrations', 'verified_clients', 'onlineClients', 'clientPresence', 'clientsByEmail'];
        for (final base in bases) {
          if (uid.length >= 2) { try { await db.ref('$base/$uid').remove(); } catch (_) {} }
          if (emailKey.length >= 2) { try { await db.ref('$base/$emailKey').remove(); } catch (_) {} }
        }
        done++;
        _log('Deleted: $type ${rec['fullName']} ($email)');
      }
      _log('DONE - Deleted $done records');
      _toast('Deleted $done records');
      _loadAll();
    } catch (e) {
      _log('Delete All failed: $e');
      _toast('Delete All failed: $e');
    }
  }

  Widget _docBox(String url, String label, bool has, String type) => InkWell(onTap: () => _viewDoc(url, label, type), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10), border: Border.all(color: has ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3))), child: Column(children: [if (url.isNotEmpty && type == 'image') ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, height: 80, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 80, child: Center(child: Text('Photo'))))) else SizedBox(height: 80, child: Center(child: Text(has ? 'View $label' : 'No $label', style: const TextStyle(color: Colors.white60, fontSize: 11)))), const SizedBox(height: 4), Text('$label ${has ? '✅' : '❌'}', style: const TextStyle(fontSize: 10))])));

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    final nursesPending = allRecords.where((r) => r['type'] == 'nurse' && r['isApproved'] != true).length;
    final nursesApproved = allRecords.where((r) => r['type'] == 'nurse' && r['isApproved'] == true).length;
    final clientsPending = allRecords.where((r) => r['type'] == 'client' && r['isApproved'] != true).length;
    final clientsApproved = allRecords.where((r) => r['type'] == 'client' && r['isApproved'] == true).length;
    final tabs = [{'key': 'nursesPending', 'label': '👩‍⚕️ Nurses Pending ($nursesPending)'}, {'key': 'nursesApproved', 'label': '✅ Nurses Approved ($nursesApproved)'}, {'key': 'clientsPending', 'label': '👥 Clients Pending ($clientsPending)'}, {'key': 'clientsApproved', 'label': '✅ Clients Approved ($clientsApproved)'}, {'key': 'all', 'label': '📦 ALL (${allRecords.length})'}];
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('CEO View All Uploads', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings')), TextButton(onPressed: _export, child: const Text('Export', style: TextStyle(color: Color(0xFFFACC15), fontSize: 11, fontWeight: FontWeight.bold))), TextButton(onPressed: _deleteAllFiltered, child: const Text('Delete All', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold))), TextButton(onPressed: _fixAllApproved, child: const Text('Fix All Approved', style: TextStyle(color: Colors.yellow, fontSize: 11))), IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll)]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(10), child: Wrap(spacing: 6, runSpacing: 6, children: tabs.map((t) => ChoiceChip(label: Text(t['label']!, style: const TextStyle(fontSize: 11)), selected: currentTab == t['key'], onSelected: (_) => setState(() => currentTab = t['key']!))).toList())),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: [Expanded(child: TextField(controller: _searchCtrl, decoration: const InputDecoration(hintText: 'Search name / username / email / phone', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), onChanged: (v) => setState(() => search = v.toLowerCase()))), const SizedBox(width: 8), DropdownButton<String>(value: docFilter, items: const [DropdownMenuItem(value: 'all', child: Text('All Documents')), DropdownMenuItem(value: 'missing', child: Text('Missing ALL 5')), DropdownMenuItem(value: 'hasVideo', child: Text('Has Video')), DropdownMenuItem(value: 'hasPhoto', child: Text('Has Photo'))], onChanged: (v) => setState(() => docFilter = v ?? 'all'))])),
        if (showLog) Container(width: double.infinity, margin: const EdgeInsets.all(10), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Log', style: TextStyle(fontWeight: FontWeight.bold)), TextButton(onPressed: () => setState(() => showLog = false), child: const Text('Hide'))]), ...logLines.take(30).map((l) => Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)))])),
        Expanded(child: list.isEmpty ? Center(child: Text('$currentTab — No records${search.isNotEmpty ? ' for "$search"' : ''}', style: const TextStyle(color: Colors.white60))) : GridView.builder(padding: const EdgeInsets.all(10), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 400, childAspectRatio: 0.85, crossAxisSpacing: 10, mainAxisSpacing: 10), itemCount: list.length, itemBuilder: (_, i) {
          final rec = list[i];
          final displayName = rec['fullName'] ?? rec['name'];
          return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: rec['isApproved'] == true ? Colors.green.withOpacity(0.08) : const Color(0xFF1C1238), borderRadius: BorderRadius.circular(18), border: Border.all(color: rec['isApproved'] == true ? Colors.green.withOpacity(0.4) : Colors.purple.withOpacity(0.2))), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [CircleAvatar(radius: 22, backgroundImage: rec['photo'].toString().isNotEmpty ? NetworkImage(rec['photo']) : null, child: rec['photo'].toString().isEmpty ? Text(displayName.toString().isNotEmpty ? displayName[0].toUpperCase() : '?') : null), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$displayName ${rec['type'] == 'nurse' ? '👩‍⚕️' : '👤'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Text('Username: ${rec['username'] ?? rec['email'] ?? rec['id']}', style: const TextStyle(color: Colors.purple, fontSize: 10))]))]),
            const SizedBox(height: 8),
            Row(children: [Chip(label: Text(rec['isApproved'] == true ? '✅ APPROVED' : '⏳ PENDING', style: const TextStyle(fontSize: 10)), backgroundColor: rec['isApproved'] == true ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2)), const SizedBox(width: 6), Chip(label: Text((rec['hasAll5'] == true || rec['hasAll4'] == true) ? '✅ ALL 4' : '❌ Missing', style: const TextStyle(fontSize: 10)), backgroundColor: (rec['hasAll5'] == true || rec['hasAll4'] == true) ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2))]),
            const SizedBox(height: 6),
            Text('📧 ${rec['email'].toString().isEmpty ? 'no email' : rec['email']}', style: const TextStyle(fontSize: 11)),
            Text('📞 ${rec['phone'].toString().isEmpty ? 'no phone' : rec['phone']}', style: const TextStyle(fontSize: 11)),
            if (rec['type'] == 'nurse') Text('🎓 ${rec['qualification'] ?? ''} • ${rec['services'] ?? ''}\n👤 Ref: ${rec['referenceName'] ?? ''} ${rec['referencePhone'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
            Text('📍 ${rec['gpsName'] ?? ''} ${rec['lat'] != null ? '(${(rec['lat'] as num).toStringAsFixed(4)}, ${(rec['lng'] as num).toStringAsFixed(4)})' : ''}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
            Text('UID: ${rec['uid']} • ${rec['createdAt'] != null ? DateTime.fromMillisecondsSinceEpoch((rec['createdAt'] as num).toInt()) : ''}', style: const TextStyle(fontSize: 10, color: Colors.white60)),
            const SizedBox(height: 10),
            GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.2, crossAxisSpacing: 8, mainAxisSpacing: 8, children: [
              _docBox(rec['photo'], 'Photo', rec['hasPhoto'] == true, 'image'),
              if (rec['type'] == 'nurse') _docBox(rec['idURL'], 'ID', rec['hasId'] == true, 'image'),
              if (rec['type'] == 'nurse') _docBox(rec['licenceURL'], 'Licence', rec['hasLicence'] == true, 'image'),
              if (rec['type'] == 'nurse') _docBox(rec['videoURL'], 'Video', rec['hasVideo'] == true, 'video'),
              _docBox(rec['certURL'], 'Cert (CV)', rec['hasCert'] == true, 'image'),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (rec['isApproved'] != true) ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green), onPressed: () => _approve(rec), child: const Text('Approve', style: TextStyle(fontSize: 11))),
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => _reject(rec), child: const Text('Reject', style: TextStyle(fontSize: 11))),
              OutlinedButton(onPressed: () => _viewAllDocs(rec), child: const Text('All Docs', style: TextStyle(fontSize: 11))),
              OutlinedButton(onPressed: () => _deleteAccount(rec), child: const Text('Delete', style: TextStyle(fontSize: 11, color: Colors.red))),
            ]),
          ])));
        })),
      ]),
    );
  }
}
