import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:http/http.dart' as http;

// CEO REGISTRATION CENTER - FULL FILE - FIXED v3
// CLIENT: Pending = NOT verified ONLY. CEO does NOT approve Client.
// NURSE: CEO approval STILL required.
// FIX v3:
//  - _pickUrl/_pickText: check ALL spellings - idFrontUrl/idFrontURL/idUrl, certificateUrl/certURL/certUrl,
//    pinCardUrl/pinUrl, licenceUrl/licenceURL/licenseUrl, nested {url:...}, + fallback scan by key name.
//    This fixes ID/Cert/PIN showing NO even though nurse uploaded them.
//  - buildRecord now saves ALL written words: specialty, experience, country, idType, idNumber,
//    pinNumber, licenceNumber, location, gpsLat/gpsLng, idCheckPassed, idBackURL, pinCardURL.
//  - Merge on dedupe: RTDB empty copy + Firestore full copy MERGE, no longer "first wins, rest ignored".
//  - _fixUploadsFromStorage: RECURSIVE - walks nurses/$uid/photo/, id_front/, id_back/, certificate/,
//    licence/, pin/, cv/, video/ subfolders. Old version only listed top folder = 0 files.
//  - _docBox: FittedBox - "View ID" never cuts to "ew ID" again.
//  - Card: NEW Details box (Specialty/Experience/Country/ID/PIN/Licence No/Location/ID Verified)
//    + NEW 3rd doc row: ID Back + PIN Card + Licence No + Location.

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

  // ============ NEW v3: UNIVERSAL PICKERS - fix key-name mismatch ============
  // Nurse saves idFrontUrl, CEO used to look for idFrontURL only -> missed.
  // Now we check EVERY spelling, nested {url:...}, and fallback by key name.
  String _pickUrl(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is Map && v['url'] != null && v['url'].toString().isNotEmpty) return v['url'].toString();
      if (v is Map && v['downloadUrl'] != null && v['downloadUrl'].toString().isNotEmpty) return v['downloadUrl'].toString();
      if (v is Map && v['downloadURL'] != null && v['downloadURL'].toString().isNotEmpty) return v['downloadURL'].toString();
    }
    return '';
  }

  String _pickUrlFallback(Map m, List<String> contains) {
    for (final e in m.entries) {
      final keyLower = e.key.toString().toLowerCase();
      final v = e.value;
      if (v is! String || v.trim().isEmpty) continue;
      if (!v.startsWith('http') && !v.contains('/')) continue;
      for (final c in contains) {
        if (keyLower.contains(c)) return v.trim();
      }
    }
    return '';
  }

  String _pickText(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return '';
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
        // --- URLs: ALL spellings + fallback ---
        final photoUrl = _pickUrl(m, ['photo', 'photoURL', 'photoUrl', 'image', 'profilePic', 'profilePhoto', 'avatar']);
        final idUrl = _pickUrl(m, ['idFrontUrl', 'idFrontURL', 'idURL', 'idUrl', 'idFront', 'idCardUrl', 'idCardURL', 'idCardFrontUrl', 'idCardFrontURL', 'nationalId', 'nationalIdURL', 'nationalIdUrl', 'ghanaCard', 'ghanaCardURL', 'ghanaCardUrl', 'id']);
        final idBackUrl = _pickUrl(m, ['idBackUrl', 'idBackURL', 'idBack', 'idCardBackUrl', 'idCardBackURL']);
        final idUrlFinal = idUrl.isNotEmpty ? idUrl : _pickUrlFallback(m, ['idfront', 'id_front', 'idcard', 'nationalid', 'ghanacard']);
        final licenceUrl = _pickUrl(m, ['licenceUrl', 'licenceURL', 'licenseUrl', 'licenseURL', 'licence', 'license', 'nursingLicence', 'nursingLicense', 'nmcLicence', 'nmcLicense', 'practiceLicence', 'practiceLicense']);
        final licenceUrlFinal = licenceUrl.isNotEmpty ? licenceUrl : _pickUrlFallback(m, ['licen', 'license', 'nmc', 'practice']);
        final certUrl = _pickUrl(m, ['certificateUrl', 'certificateURL', 'certUrl', 'certURL', 'certificate', 'cert']);
        final certUrlFinal = certUrl.isNotEmpty ? certUrl : _pickUrlFallback(m, ['certificat', 'cert']);
        final cvUrl = _pickUrl(m, ['cvUrl', 'cvURL', 'cv', 'resume', 'resumeUrl']);
        final videoUrl = _pickUrl(m, ['videoUrl', 'videoURL', 'video', 'introVideo', 'introVideoUrl', 'introVideoURL', 'profileVideo', 'profileVideoUrl']);
        final pinCardUrl = _pickUrl(m, ['pinCardUrl', 'pinCardURL', 'pinUrl', 'pinURL', 'pinCard', 'pin']);
        final pinCardUrlFinal = (pinCardUrl.isNotEmpty && pinCardUrl.startsWith('http')) ? pinCardUrl : _pickUrlFallback(m, ['pincard', 'pin_card']);

        // --- Written words: ALL nurse fields ---
        final pinNumber = _pickText(m, ['pinNumber', 'pinNo', 'nursingPin', 'nmcPin', 'nursingPIN', 'nmcPIN', 'pin']);
        // pin field may be URL (new nurse saves pin=pinUrl) - if it looks like URL, it is NOT the number
        final pinNumberFinal = (pinNumber.startsWith('http')) ? _pickText(m, ['pinNumber', 'pinNo', 'nursingPin', 'nmcPin']) : pinNumber;
        final idNumber = _pickText(m, ['idNumber', 'idNo', 'nationalIdNumber', 'ghanaCardNumber']);
        final licenceNumber = _pickText(m, ['licenceNumber', 'licenseNumber', 'licenceNo', 'licenseNo', 'licence', 'license']);
        final licenceNumberFinal = (licenceNumber.startsWith('http')) ? '' : licenceNumber;
        final specialty = _pickText(m, ['specialty', 'speciality', 'services']);
        final experience = _pickText(m, ['experience', 'yearsOfExperience', 'yearsExperience']);
        final country = _pickText(m, ['country', 'workCountry', 'residenceCountry', 'idCountry']);
        final idType = _pickText(m, ['idType', 'idTypeLabel']);
        final location = _pickText(m, ['location', 'placeName', 'address', 'gpsName']);
        final lat = m['lat'] ?? m['latitude'] ?? m['gpsLat'] ?? m['locationLat'];
        final lng = m['lng'] ?? m['longitude'] ?? m['gpsLng'] ?? m['locationLng'];
        final idCheckPassed = m['idCheckPassed'] == true || m['idVerified'] == true;

        // --- has* - use picked URLs + text, not raw key names ---
        final hasPhoto = photoUrl.isNotEmpty;
        final hasVideo = videoUrl.isNotEmpty;
        final hasId = idUrlFinal.isNotEmpty;
        final hasIdBack = idBackUrl.isNotEmpty;
        final hasLicence = licenceUrlFinal.isNotEmpty;
        final hasCert = certUrlFinal.isNotEmpty;
        final hasCv = cvUrl.isNotEmpty;
        final hasPin = pinNumberFinal.isNotEmpty || pinCardUrlFinal.isNotEmpty;
        final hasPinCard = pinCardUrlFinal.isNotEmpty;

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
          'hasPhoto': hasPhoto,
          'hasVideo': hasVideo,
          'hasId': hasId,
          'hasIdBack': hasIdBack,
          'hasLicence': hasLicence,
          'hasCert': hasCert,
          'hasCv': hasCv,
          'hasPin': hasPin,
          'hasPinCard': hasPinCard,
          'qualification': (m['qualification'] ?? m['education'] ?? '').toString(),
          'services': (m['services'] ?? m['speciality'] ?? m['specialty'] ?? '').toString(),
          'referenceName': (m['referenceName'] ?? '').toString(),
          'referencePhone': (m['referencePhone'] ?? '').toString(),
          'gpsName': location,
          'lat': lat,
          'lng': lng,
          'createdAt': _createdAtMs(m['createdAt'] ?? m['timestamp'] ?? m['created_at']),
          'photo': photoUrl,
          'photoURL': photoUrl,
          'idURL': idUrlFinal,
          'idBackURL': idBackUrl,
          'licenceURL': licenceUrlFinal,
          'videoURL': videoUrl,
          'certURL': certUrlFinal,
          'cvURL': cvUrl,
          'pinCardURL': pinCardUrlFinal,
          // NEW: written words - shown in Details box
          'specialty': specialty,
          'experience': experience,
          'country': country,
          'idType': idType,
          'idNumber': idNumber,
          'pinNumber': pinNumberFinal,
          'licenceNumber': licenceNumberFinal,
          'location': location,
          'gpsLat': lat,
          'gpsLng': lng,
          'idCheckPassed': idCheckPassed,
          'idVerified': idCheckPassed,
          'raw': m,
        };
      }

      // NEW v3: MERGE - if same nurse already in list, merge raw maps and rebuild.
      // Old code did "if exists continue" -> Firestore full record thrown away if RTDB empty came first.
      void upsertRecord(String uid, String key, String type, Map m, String email, String name, String phone) {
        final idx = out.indexWhere((x) => x['uid'].toString() == uid && x['email'].toString().toLowerCase() == email.toLowerCase());
        if (idx == -1) {
          out.add(buildRecord(uid, key, type, m, email, name, phone));
          return;
        }
        final existing = out[idx];
        final mergedRaw = Map<String, dynamic>.from(existing['raw'] as Map);
        // Only fill empty fields from new source, never overwrite a good URL with empty
        for (final e in m.entries) {
          final k = e.key.toString();
          final v = e.value;
          if (v == null) continue;
          if (v is String && v.trim().isEmpty) continue;
          if (mergedRaw[k] == null || (mergedRaw[k] is String && mergedRaw[k].toString().trim().isEmpty)) {
            mergedRaw[k] = v;
          }
        }
        final mergedEmail = existing['email'].toString().isNotEmpty ? existing['email'].toString() : email;
        final mergedName = existing['fullName'].toString().isNotEmpty ? existing['fullName'].toString() : name;
        final mergedPhone = existing['phone'].toString().isNotEmpty ? existing['phone'].toString() : phone;
        out[idx] = buildRecord(uid, existing['key'].toString(), type, mergedRaw, mergedEmail, mergedName, mergedPhone);
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
            upsertRecord(uid, e.key.toString(), type, m, email, name, phone);
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
            upsertRecord(uid, d.id, type, m, email, name, phone);
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

  // ============ FIXED v3: FIX UPLOADS FROM STORAGE - RECURSIVE ============
  // Old: listAll(nurses/$uid) -> 0 items, because files live in subfolders.
  // New: walk every subfolder recursively, match by FOLDER name first, then file name.
  Future<void> _collectStorageItems(Reference ref, List<Reference> out) async {
    try {
      final list = await ref.listAll();
      out.addAll(list.items);
      for (final prefix in list.prefixes) {
        await _collectStorageItems(prefix, out);
      }
    } catch (_) {}
  }

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
      final List<Reference> allItems = [];
      await _collectStorageItems(FirebaseStorage.instance.ref('nurses/$uid'), allItems);
      // Also try other roots
      for (final root in ['nurse_registrations/$uid', 'registrations/$uid', 'users/$uid', 'nurses/$email', 'ceo_registration/$uid', 'clients/$uid']) {
        await _collectStorageItems(FirebaseStorage.instance.ref(root), allItems);
      }
      // Dedupe by fullPath
      final seen = <String>{};
      final items = allItems.where((it) => seen.add(it.fullPath)).toList();
      _log('Found ${items.length} files (recursive) for $uid');

      if (items.isEmpty) {
        _toast('No files found in Storage for this nurse. Check Storage folder name.');
        return;
      }

      String photoURL = '';
      String idURL = '';
      String idBackURL = '';
      String licenceURL = '';
      String videoURL = '';
      String certURL = '';
      String cvURL = '';
      String pinURL = '';

      for (final item in items) {
        final name = item.name.toLowerCase();
        final fullPath = item.fullPath.toLowerCase();
        final url = await item.getDownloadURL();
        _log('File: ${item.fullPath} -> $url');
        // Folder first - most reliable: nurses/$uid/id_front/xxx.jpg
        if (fullPath.contains('/photo/') || fullPath.contains('/profile')) {
          photoURL = url;
        } else if (fullPath.contains('id_front') || fullPath.contains('idfront') || (fullPath.contains('/id/') && fullPath.contains('front'))) {
          idURL = url;
        } else if (fullPath.contains('id_back') || fullPath.contains('idback') || (fullPath.contains('/id/') && fullPath.contains('back'))) {
          idBackURL = url;
        } else if (fullPath.contains('licen') || fullPath.contains('license')) {
          licenceURL = url;
        } else if (fullPath.contains('/pin/') || fullPath.contains('pincard') || fullPath.contains('pin_card')) {
          pinURL = url;
        } else if (fullPath.contains('certificate') || fullPath.contains('/cert/')) {
          certURL = url;
        } else if (fullPath.contains('/cv/') || fullPath.contains('resume')) {
          cvURL = url;
        } else if (fullPath.contains('/video/') || fullPath.contains('intro')) {
          videoURL = url;
        } else if (name.contains('photo') || name.contains('profile') || name.contains('pic')) {
          photoURL = url;
        } else if (name.contains('id') || name.contains('ghana') || name.contains('national') || name.contains('card')) {
          if (name.contains('back')) { idBackURL = url; } else { idURL = url; }
        } else if (name.contains('licen') || name.contains('license') || name.contains('nmc') || name.contains('practice')) {
          licenceURL = url;
        } else if (name.contains('pin')) {
          pinURL = url;
        } else if (name.contains('video') || name.contains('intro') || name.endsWith('.mp4') || name.endsWith('.mov')) {
          videoURL = url;
        } else if (name.contains('cert') || name.contains('certificate')) {
          certURL = url;
        } else if (name.contains('cv') || name.contains('resume')) {
          cvURL = url;
        }
      }

      _log('Recovered: Photo=${photoURL.isNotEmpty} ID=${idURL.isNotEmpty} ID Back=${idBackURL.isNotEmpty} Licence=${licenceURL.isNotEmpty} Video=${videoURL.isNotEmpty} Cert=${certURL.isNotEmpty} CV=${cvURL.isNotEmpty} PIN Card=${pinURL.isNotEmpty}');

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
        payload['idFrontUrl'] = idURL;
        payload['idFront'] = idURL;
        payload['ghanaCard'] = idURL;
        payload['nationalId'] = idURL;
      }
      if (idBackURL.isNotEmpty) {
        payload['idBackURL'] = idBackURL;
        payload['idBackUrl'] = idBackURL;
        payload['idBack'] = idBackURL;
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
        payload['certificateUrl'] = certURL;
        payload['certificate'] = certURL;
      }
      if (cvURL.isNotEmpty) {
        payload['cvURL'] = cvURL;
        payload['cvUrl'] = cvURL;
        payload['cv'] = cvURL;
      }
      if (pinURL.isNotEmpty) {
        payload['pinCardURL'] = pinURL;
        payload['pinCardUrl'] = pinURL;
        payload['pinUrl'] = pinURL;
        payload['pinURL'] = pinURL;
        payload['pinCard'] = pinURL;
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
        for (final coll in ['nurses', 'nurse_registrations', 'pending_nurses', 'ceo_registration']) {
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

  // ============ FIX v2: DETECT REAL FILE TYPE, NOT URL EXTENSION ============
  // Firebase Storage URLs look like .../o/file?alt=media&token=xxx - NO .pdf / .jpg
  // So we ask the server for Content-Type, and fall back to the label.
  Future<void> _openDoc(String url, String label, String type) async {
    final u = url.trim();
    if (u.isEmpty) { _toast('No $label uploaded'); return; }
    if (type == 'text') {
      showDialog(context: context, builder: (_) => AlertDialog(
        title: Text(label),
        content: SelectableText(u),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ));
      return;
    }
    if (label == 'Video') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => _VideoViewerPage(url: u, title: label)));
      return;
    }
    // Show loading while we detect type
    _toast('Opening $label...');
    String kind = 'unknown'; // pdf | image | video | other
    try {
      final res = await http.head(Uri.parse(u)).timeout(const Duration(seconds: 8));
      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (ct.contains('pdf')) kind = 'pdf';
      else if (ct.contains('image')) kind = 'image';
      else if (ct.contains('video')) kind = 'video';
      else if (ct.contains('word') || ct.contains('msword') || ct.contains('officedocument') || ct.contains('octet')) kind = 'office';
    } catch (_) {}
    // Fallback 1: URL extension, if present
    if (kind == 'unknown') {
      final lower = u.toLowerCase();
      if (lower.contains('.pdf')) kind = 'pdf';
      else if (lower.contains('.jpg') || lower.contains('.jpeg') || lower.contains('.png') || lower.contains('.webp')) kind = 'image';
      else if (lower.contains('.mp4') || lower.contains('.mov') || lower.contains('.webm')) kind = 'video';
    }
    // Fallback 2: label heuristic - Cert / CV / Licence are ALMOST ALWAYS PDFs
    // in nurse registration, even when uploaded without an extension.
    if (kind == 'unknown' || kind == 'office') {
      if (label == 'Cert' || label == 'CV' || label == 'Licence') kind = 'pdf';
      else if (label == 'Photo') kind = 'image';
    }
    if (!mounted) return;
    if (kind == 'video') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => _VideoViewerPage(url: u, title: label)));
    } else if (kind == 'pdf' || kind == 'office') {
      // Smart viewer: tries REAL PDF first, with "View as Image" + "Open externally" fallbacks
      Navigator.push(context, MaterialPageRoute(builder: (_) => _SmartDocViewerPage(url: u, title: label)));
    } else {
      // Image, or still unknown -> smart viewer will try image, then offer PDF view
      Navigator.push(context, MaterialPageRoute(builder: (_) => _SmartDocViewerPage(url: u, title: label)));
    }
  }

  // FIXED v3: FittedBox so "View ID" never cuts to "ew ID"
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
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(has ? 'View $label' : 'No $label', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 11), maxLines: 1),
                      ),
                      if (has) const FittedBox(fit: BoxFit.scaleDown, child: Text('Tap to open', style: TextStyle(color: Colors.greenAccent, fontSize: 9))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('$label ${has ? 'OK' : 'NO'}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11))),
          Expanded(child: SelectableText(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500))),
        ],
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
            // NEW v3: Details - ALL written words from nurse registration
            if (!isClient) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📋 Nurse Details - as entered during registration', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    _detailRow('Specialty', r['specialty'].toString()),
                    _detailRow('Experience', r['experience'].toString()),
                    _detailRow('Country', r['country'].toString()),
                    _detailRow('ID Type', r['idType'].toString()),
                    _detailRow('ID Number', r['idNumber'].toString()),
                    _detailRow('ID Verified', (r['idCheckPassed'] == true) ? '✅ YES - OCR matched' : '❌ NO / Not checked'),
                    _detailRow('PIN Number', r['pinNumber'].toString()),
                    _detailRow('Licence No', r['licenceNumber'].toString()),
                    _detailRow('Location', r['location'].toString()),
                    _detailRow('GPS', (r['gpsLat'] != null && r['gpsLng'] != null) ? '${r['gpsLat']}, ${r['gpsLng']}' : ''),
                  ],
                ),
              ),
            ],
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
                _docBox(r['pinCardURL'].toString(), 'PIN Card', r['hasPinCard'] == true, 'image'),
                const SizedBox(width: 6),
                _docBox(r['phone'].toString(), 'Phone', r['phone'].toString().isNotEmpty, 'text'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _docBox(r['idBackURL'].toString(), 'ID Back', r['hasIdBack'] == true, 'image'),
                const SizedBox(width: 6),
                _docBox(r['pinNumber'].toString(), 'PIN No', r['hasPin'] == true, 'text'),
                const SizedBox(width: 6),
                _docBox(r['licenceNumber'].toString(), 'Lic No', (r['licenceNumber'] ?? '').toString().isNotEmpty, 'text'),
                const SizedBox(width: 6),
                _docBox(r['location'].toString(), 'Location', (r['location'] ?? '').toString().isNotEmpty, 'text'),
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
class _SmartDocViewerPage extends StatefulWidget {
  final String url; final String title;
  const _SmartDocViewerPage({required this.url, required this.title});
  @override
  State<_SmartDocViewerPage> createState() => _SmartDocViewerPageState();
}
class _SmartDocViewerPageState extends State<_SmartDocViewerPage> {
  // 'auto' = try PDF if it looks like a doc, else image. User can switch.
  String _mode = 'auto';
  @override
  Widget build(BuildContext context) {
    final isDocLabel = widget.title == 'Cert' || widget.title == 'CV' || widget.title == 'Licence' || widget.title == 'ID';
    final showPdf = _mode == 'pdf' || (_mode == 'auto' && isDocLabel);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFF1A1633),
        actions: [
          // Let CEO switch if detection was wrong - this is what fixes "CV can't be read"
          TextButton(onPressed: () => setState(() => _mode = 'pdf'), child: Text('PDF', style: TextStyle(color: _mode == 'pdf' || showPdf ? Colors.greenAccent : Colors.white70))),
          TextButton(onPressed: () => setState(() => _mode = 'image'), child: Text('IMAGE', style: TextStyle(color: _mode == 'image' ? Colors.greenAccent : Colors.white70))),
          IconButton(icon: const Icon(Icons.open_in_new, size: 20), tooltip: 'Open externally', onPressed: () async { final uri = Uri.parse(widget.url); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }),
        ],
      ),
      backgroundColor: Colors.black,
      body: showPdf
        ? _PdfOpenPage(url: widget.url, title: widget.title)
        : InteractiveViewer(
            child: Center(
              child: Image.network(widget.url,
                fit: BoxFit.contain,
                loadingBuilder: (_, c, p) => p == null ? c : Column(mainAxisAlignment: MainAxisAlignment.center, children: [const CircularProgressIndicator(color: Colors.white), const SizedBox(height: 12), Text('Loading ${widget.title}...', style: const TextStyle(color: Colors.white70))]),
                errorBuilder: (_, __, ___) => Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('Could not load as image. Trying as PDF...', style: TextStyle(color: Colors.white), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () => setState(() => _mode = 'pdf'), child: const Text('View as PDF')),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: () async { final uri = Uri.parse(widget.url); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }, child: const Text('Open externally')),
                ])),
              ),
            ),
          ),
    );
  }
}

// PDF viewer with ZERO new packages: opens the PDF in Google Docs Viewer
// inside the phone browser - it renders + scrolls + zooms, no external PDF app needed.
class _PdfOpenPage extends StatelessWidget {
  final String url; final String title;
  const _PdfOpenPage({required this.url, required this.title});
  Future<void> _open(BuildContext context, String link) async {
    final uri = Uri.parse(link);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open PDF - no browser found')));
    }
  }
  @override
  Widget build(BuildContext context) {
    final docsViewer = 'https://docs.google.com/viewer?url=${Uri.encodeComponent(url)}&embedded=true';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.picture_as_pdf, size: 72, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Tap below to read this PDF. It opens in your browser where you can scroll, zoom and read every page.', style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.visibility), label: const Text('Read PDF in Browser'), onPressed: () => _open(context, docsViewer))),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.download), label: const Text('Download / Open Directly'), onPressed: () => _open(context, url))),
          const SizedBox(height: 12),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Go back')),
        ]),
      ),
    );
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
        child: _err != null ? Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('Could not play video: $_err', style: const TextStyle(color: Colors.white), textAlign: TextAlign.center), const SizedBox(height: 16), ElevatedButton(onPressed: () async { final uri = Uri.parse(widget.url); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }, child: const Text('Open externally'))]))
        : _cc == null ? const CircularProgressIndicator(color: Colors.white)
        : AspectRatio(aspectRatio: _vc!.value.aspectRatio, child: Chewie(controller: _cc!)),
      ),
    );
  }
}
