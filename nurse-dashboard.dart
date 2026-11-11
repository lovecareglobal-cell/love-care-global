import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';

/// Nurse Dashboard - Flutter version of nurse-dashboard.html
/// - loadNurse: SharedPreferences + RTDB nurses/{uid} (HTML also used Firestore — RTDB is source of truth in Flutter)
/// - ONLINE / OFFLINE broadcast (same as HTML setOnlineNow / setOfflineNow):
///   ONLINE: onlineNurses + nursePresence + liveNurseLocations + liveNurses + liveTracking + nurseLocations + nurses + allNurses + pending_nurses + pendingNurses
///   OFFLINE: removes onlineNurses / live* , sets nursePresence offline, nurses/allNurses offline
///   GPS fast (3s timeout, don't block online if GPS slow), onDisconnect cancels
/// - Receiver-only sound: bookings child_changed shouldRing (lastChangedBy != nurse, not my own change, isMyBooking, within 2 min)
///   + soundTriggers/{nurse, phone9, uid, emailKey} limit 5, delete after 5s
/// - Stats: My bookings (pending / accepted / completed), Earnings = 80% of completed amount
/// - Booking cards: Accept / Reject (reject writes rejectedBy + sound trigger to client)

class NurseDashboardScreen extends StatefulWidget {
  const NurseDashboardScreen({super.key});
  @override
  State<NurseDashboardScreen> createState() => _NurseDashboardScreenState();
}

class _NurseDashboardScreenState extends State<NurseDashboardScreen> {
  String currentNurseId = 'demo-nurse';
  String nurseName = 'Nurse', nurseEmail = '', nursePhone = '', nurseSpecialty = 'General Nursing', photoUrl = '';
  bool isOnline = false;
  String saveStatus = '';
  List<Map> myBookings = [];
  final AudioPlayer _player = AudioPlayer();
  final Set<String> _seenRing = {};

  @override
  void initState() {
    super.initState();
    _loadNurse();
    _startSoundListener();
  }

  Future<void> _loadNurse() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('lcg_nurse_uid') ?? prefs.getString('uid') ?? '';
    if (uid.isEmpty) { setState(() => currentNurseId = 'demo-nurse'); return; }
    setState(() => currentNurseId = uid);
    var photo = prefs.getString('nursePhotoURL') ?? prefs.getString('nursePhoto') ?? prefs.getString('photoUrl') ?? '';
    var name = prefs.getString('nurseName') ?? prefs.getString('fullName') ?? prefs.getString('displayName') ?? '';
    var email = prefs.getString('nurseEmail') ?? prefs.getString('email') ?? prefs.getString('currentNurseEmail') ?? '';
    var phone = prefs.getString('nursePhone') ?? prefs.getString('phone') ?? '';
    var spec = prefs.getString('nurseSpecialty') ?? '';
    try {
      final snap = await FirebaseDatabase.instance.ref('nurses/$uid').get();
      if (snap.exists) {
        final d = Map<String, dynamic>.from(snap.value as Map);
        if (d['photoURL'] != null || d['photo'] != null) photo = d['photoURL'] ?? d['photo'] ?? photo;
        if (d['fullName'] != null || d['name'] != null) name = d['fullName'] ?? d['name'] ?? name;
        if (d['email'] != null) email = d['email'] ?? email;
        if (d['phone'] != null) phone = d['phone'] ?? phone;
        if (d['specialty'] != null) spec = d['specialty'] ?? spec;
      }
    } catch (_) {}
    setState(() {
      nurseName = name.isEmpty ? 'Nurse' : name;
      nurseEmail = email; nursePhone = phone; nurseSpecialty = spec.isEmpty ? 'General Nursing' : spec; photoUrl = photo;
    });
    await _checkOnlineStatus(uid);
    _loadMyBookings();
  }

  Future<void> _checkOnlineStatus(String uid) async {
    try {
      final snap = await FirebaseDatabase.instance.ref('onlineNurses/$uid').get();
      final snap2 = await FirebaseDatabase.instance.ref('nursePresence/$uid').get();
      final online = (snap.exists && (snap.value as Map)['isOnline'] == true) || (snap2.exists && (snap2.value as Map)['isOnline'] == true);
      setState(() => isOnline = online);
    } catch (_) {}
  }

  Future<Map<String, double>> _getLocationFast() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 3));
      return {'lat': pos.latitude, 'lng': pos.longitude};
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      return {'lat': prefs.getDouble('nurseLat') ?? 0, 'lng': prefs.getDouble('nurseLng') ?? 0};
    }
  }

  Future<void> _setOnlineNow() async {
    final uid = currentNurseId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final timeStr = DateTime.now().toString();
    setState(() { isOnline = true; saveStatus = '🟢 Going ONLINE... Broadcasting to all clients...'; });
    final loc = await _getLocationFast();
    final payload = {
      'isOnline': true, 'online': true, 'isAvailable': true, 'available': true, 'status': 'online', 'presence': 'online',
      'lastSeen': now, 'lastActive': now, 'lastOnline': now, 'onlineAt': now, 'updatedAt': now, 'lastUpdate': now, 'timeStr': timeStr,
      'fullName': nurseName, 'name': nurseName, 'photoURL': photoUrl, 'photo': photoUrl, 'email': nurseEmail, 'phone': nursePhone, 'specialty': nurseSpecialty,
      'lat': loc['lat'], 'lng': loc['lng'], 'latitude': loc['lat'], 'longitude': loc['lng'],
      'uid': uid, 'id': uid, 'isApproved': true, 'instantOnline': true, 'broadcastAt': now,
    };
    final db = FirebaseDatabase.instance;
    try {
      await Future.wait([
        db.ref('onlineNurses/$uid').set(payload),
        db.ref('nursePresence/$uid').set({'status': 'online', 'isOnline': true, 'lastSeen': now, 'onlineAt': now, 'timeStr': timeStr}),
        db.ref('liveNurseLocations/$uid').set(payload),
        db.ref('liveNurses/$uid').set(payload),
        db.ref('liveTracking/$uid').set(payload),
        db.ref('nurseLocations/$uid').update({'isLive': true, 'isOnline': true, 'status': 'online', 'lat': loc['lat'], 'lng': loc['lng'], 'lastSeen': now, 'updatedAt': now}),
        db.ref('nurses/$uid').update({'isOnline': true, 'online': true, 'isAvailable': true, 'status': 'online', 'lastSeen': now, 'lastOnline': now, 'onlineAt': now, 'timeStr': timeStr}),
        db.ref('allNurses/$uid').update({'isOnline': true, 'status': 'online', 'lastSeen': now, 'onlineAt': now}),
        db.ref('pending_nurses/$uid').update({'isOnline': true, 'status': 'online'}),
        db.ref('pendingNurses/$uid').update({'isOnline': true, 'status': 'online'}),
      ]);
      db.ref('onlineNurses/$uid').onDisconnect().remove();
      db.ref('nursePresence/$uid').onDisconnect().set({'status': 'offline', 'isOnline': false, 'lastSeen': now});
      setState(() => saveStatus = '🟢 ONLINE NOW — Visible to clients — Clients can see you in book-nurse');
    } catch (e) { setState(() => saveStatus = 'Online failed: $e'); }
  }

  Future<void> _setOfflineNow() async {
    final uid = currentNurseId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final timeStr = DateTime.now().toString();
    setState(() { isOnline = false; saveStatus = '🔴 Going OFFLINE... Hiding from all clients...'; });
    final db = FirebaseDatabase.instance;
    try {
      await Future.wait([
        db.ref('onlineNurses/$uid').remove(),
        db.ref('liveNurseLocations/$uid').remove(),
        db.ref('liveNurses/$uid').remove(),
        db.ref('liveTracking/$uid').remove(),
        db.ref('nurseLocations/$uid').update({'isLive': false, 'isOnline': false, 'status': 'offline', 'lastSeen': now, 'updatedAt': now}).catchError((_) async { await db.ref('nurseLocations/$uid').remove(); }),
        db.ref('nursePresence/$uid').set({'status': 'offline', 'isOnline': false, 'lastSeen': now, 'offlineAt': now, 'timeStr': timeStr}),
        db.ref('nurses/$uid').update({'isOnline': false, 'online': false, 'isAvailable': false, 'status': 'offline', 'lastSeen': now, 'lastOffline': now, 'offlineAt': now, 'timeStr': timeStr}),
        db.ref('allNurses/$uid').update({'isOnline': false, 'status': 'offline', 'lastSeen': now, 'offlineAt': now}),
        db.ref('pending_nurses/$uid').update({'isOnline': false, 'status': 'offline'}),
        db.ref('pendingNurses/$uid').update({'isOnline': false, 'status': 'offline'}),
      ]);
      db.ref('onlineNurses/$uid').onDisconnect().cancel();
      db.ref('nursePresence/$uid').onDisconnect().cancel();
      setState(() => saveStatus = '🔴 OFFLINE NOW — Hidden from all clients — Clients will NOT see you');
    } catch (e) { setState(() => saveStatus = 'Offline failed: $e'); }
  }

  void _toggleOnline(bool v) { if (v) _setOnlineNow(); else _setOfflineNow(); }

  // ---- My Bookings ----
  Future<Map<String, String>> _getMyIds() async {
    final prefs = await SharedPreferences.getInstance();
    final phones = <String>[];
    final emails = <String>[];
    final uids = <String>[];
    for (final k in prefs.getKeys()) {
      final v = prefs.getString(k) ?? '';
      final kl = k.toLowerCase();
      if (kl.contains('phone')) { final p = v.replaceAll(RegExp(r'[^0-9]'), ''); if (p.length >= 9) phones.add(p.substring(p.length - 9)); }
      if (kl.contains('email')) emails.add(v.toLowerCase().trim());
      if (kl.contains('uid') || k == 'id') uids.add(v);
    }
    return {'phones': phones.join(','), 'emails': emails.join(','), 'uids': uids.join(',')};
  }

  bool _isMyBooking(Map v) {
    final nurseId = (v['nurseId'] ?? v['selectedNurseId'] ?? '').toString();
    if (nurseId == currentNurseId) return true;
    final phone = (v['nursePhone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isNotEmpty && nursePhone.isNotEmpty && phone.endsWith(nursePhone.replaceAll(RegExp(r'[^0-9]'), '').substring(nursePhone.replaceAll(RegExp(r'[^0-9]'), '').length - 9))) return true;
    final email = (v['nurseEmail'] ?? '').toString().toLowerCase();
    if (email.isNotEmpty && email == nurseEmail.toLowerCase()) return true;
    return false;
  }

  void _loadMyBookings() {
    FirebaseDatabase.instance.ref('bookings').onValue.listen((e) {
      if (!e.snapshot.exists) { setState(() => myBookings = []); return; }
      final map = e.snapshot.value as Map;
      List<Map> list = [];
      map.forEach((k, val) {
        final v = Map<String, dynamic>.from(val as Map);
        if (_isMyBooking(v)) list.add({...v, 'id': k});
      });
      list.sort((a, b) => ((b['createdAt'] ?? b['time'] ?? 0) as num).compareTo((a['createdAt'] ?? a['time'] ?? 0) as num));
      setState(() => myBookings = list);
    });
  }

  // ---- Receiver-only sound ----
  bool _shouldRing(Map v) {
    if (v['lastChangedBy'] == 'nurse') return false;
    if (v['lastChangedUid'] == currentNurseId) return false;
    if (!_isMyBooking(v)) return false;
    final t = (v['lastChangedAt'] ?? v['time'] ?? v['createdAt'] ?? 0) as num;
    if (DateTime.now().millisecondsSinceEpoch - t > 120000) return false;
    return true;
  }

  void _startSoundListener() {
    FirebaseDatabase.instance.ref('bookings').onChildChanged.listen((e) {
      if (!e.snapshot.exists) return;
      final v = Map<String, dynamic>.from(e.snapshot.value as Map);
      final k = '${e.snapshot.key}_${v['status']}_${v['lastChangedAt'] ?? 0}';
      if (_seenRing.contains(k)) return;
      _seenRing.add(k);
      if (_shouldRing(v)) {
        _playCustomSound();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🔔 New reply - ${v['status'] ?? ''}')));
      }
    });
    // soundTriggers/{nurse, phone9, uid, emailKey}
    _getMyIds().then((ids) {
      final keys = <String>['nurse'];
      final phone9 = nursePhone.replaceAll(RegExp(r'[^0-9]'), '');
      if (phone9.length >= 9) keys.add(phone9.substring(phone9.length - 9));
      keys.add(currentNurseId);
      if (nurseEmail.isNotEmpty) keys.add(nurseEmail.replaceAll(RegExp(r'[.@]'), '_'));
      for (final key in keys) {
        if (key.isEmpty) continue;
        FirebaseDatabase.instance.ref('soundTriggers/$key').limitToLast(5).onChildAdded.listen((e) {
          if (!e.snapshot.exists) return;
          final v = Map<String, dynamic>.from(e.snapshot.value as Map);
          if (DateTime.now().millisecondsSinceEpoch - ((v['time'] ?? 0) as num) > 120000) return;
          if (v['fromRole'] == 'nurse') return;
          if (v['fromUid'] == currentNurseId) return;
          _playCustomSound();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🔔 ${v['title'] ?? v['status'] ?? 'New reply'}')));
          Future.delayed(const Duration(seconds: 5), () => FirebaseDatabase.instance.ref('soundTriggers/$key/${e.snapshot.key}').remove().catchError((_) {}));
        });
      }
    });
  }

  Future<void> _playCustomSound() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString('lcg_custom_song');
    if (custom != null && custom.isNotEmpty) {
      try { await _player.play(UrlSource(custom)); return; } catch (_) {}
    }
    try { await _player.play(AssetSource('sounds/default.mp3')); } catch (_) {}
  }

  Future<void> _sendSoundTrigger(String toRole, Map data) async {
    try {
      await FirebaseDatabase.instance.ref('soundTriggers/$toRole').push().set({'fromRole': 'nurse', 'fromUid': currentNurseId, 'time': DateTime.now().millisecondsSinceEpoch, ...data});
    } catch (_) {}
  }

  Future<void> _acceptBooking(Map b) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await FirebaseDatabase.instance.ref('bookings/${b['id']}').update({'status': 'accepted', 'acceptedAt': now, 'acceptedBy': currentNurseId, 'lastChangedBy': 'nurse', 'lastChangedUid': currentNurseId, 'lastChangedAt': now});
    await _sendSoundTrigger('client', {'bookingId': b['id'], 'status': 'accepted', 'title': '✅ Nurse Don Accept!'});
    await FirebaseDatabase.instance.ref('nurseNotifications/${b['clientUid'] ?? b['clientId'] ?? ''}').push().set({'title': '✅ Nurse Accepted', 'message': 'Nurse $nurseName accepted booking ${b['id']}', 'bookingId': b['id'], 'type': 'accepted', 'createdAt': now}).catchError((_) {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Booking accepted')));
  }

  Future<void> _rejectBooking(Map b) async {
    final reason = await showDialog<String>(context: context, builder: (_) {
      final c = TextEditingController();
      return AlertDialog(title: const Text('Reject Booking — Reason?'), content: TextField(controller: c, decoration: const InputDecoration(hintText: 'e.g. Too far, busy')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Reject'))]);
    });
    if (reason == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await FirebaseDatabase.instance.ref('bookings/${b['id']}').update({'status': 'rejected', 'rejectedAt': now, 'rejectedBy': currentNurseId, 'rejectedByNurseId': currentNurseId, 'rejectedByNurseName': nurseName, 'rejectReason': reason, 'lastChangedBy': 'nurse', 'lastChangedUid': currentNurseId, 'lastChangedAt': now});
    await _sendSoundTrigger('client', {'bookingId': b['id'], 'status': 'rejected', 'title': 'Nurse rejected — Increase payment?'});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking rejected — Client can increase payment')));
  }

  @override
  Widget build(BuildContext context) {
    final pending = myBookings.where((b) => (b['status'] ?? '').toString().toLowerCase() == 'pending').length;
    final accepted = myBookings.where((b) => (b['status'] ?? '').toString().toLowerCase() == 'accepted').length;
    final completed = myBookings.where((b) => (b['status'] ?? '').toString().toLowerCase() == 'completed' || (b['status'] ?? '').toString().toLowerCase() == 'done').length;
    double earnings = 0;
    for (final b in myBookings) {
      final s = (b['status'] ?? '').toString().toLowerCase();
      if (s == 'completed' || s == 'done') earnings += (double.tryParse((b['amount'] ?? 0).toString()) ?? 0) * 0.8;
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('Nurse Dashboard', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.pushNamed(context, '/nurse-settings')), IconButton(icon: const Icon(Icons.notifications), onPressed: () => Navigator.pushNamed(context, '/sound-settings'))]),
      drawer: Drawer(child: Container(color: const Color(0xFF120E26), child: ListView(padding: EdgeInsets.zero, children: [
        DrawerHeader(decoration: const BoxDecoration(color: Color(0xFF1C1238)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [CircleAvatar(radius: 28, backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null, child: photoUrl.isEmpty ? Text(nurseName.isNotEmpty ? nurseName[0] : 'N') : null), const SizedBox(height: 8), Text(nurseName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), Text(nurseEmail, style: const TextStyle(color: Colors.white60, fontSize: 11))])),
        ListTile(title: const Text('My Job Offers', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pushNamed(context, '/my-job-offers')),
        ListTile(title: const Text('Withdraw Earnings', style: TextStyle(color: Color(0xFFFACC15))), onTap: () => Navigator.pushNamed(context, '/nurse-withdrawal')),
        ListTile(title: const Text('Nurse Group Chat', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pushNamed(context, '/nurse-group-chat')),
        ListTile(title: const Text('Sound Settings', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pushNamed(context, '/sound-settings')),
        ListTile(title: const Text('Nurse Settings', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pushNamed(context, '/nurse-settings')),
        ListTile(title: const Text('🚨 SOS', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pushNamed(context, '/sos')),
      ]))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          // Profile
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Row(children: [
            Stack(children: [CircleAvatar(radius: 32, backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null, child: photoUrl.isEmpty ? Text(nurseName.isNotEmpty ? nurseName[0] : 'N', style: const TextStyle(fontSize: 24)) : null), Positioned(right: 0, bottom: 0, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: isOnline ? Colors.green : Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))))]),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Welcome, $nurseName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), const Text('Welcome back', style: TextStyle(color: Color(0xFFC4B5FD), fontSize: 13)), Text(nurseEmail, style: const TextStyle(color: Colors.white60, fontSize: 11)), Text(nursePhone, style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11)), Text(nurseSpecialty, style: const TextStyle(color: Colors.white60, fontSize: 11))])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.green.withOpacity(0.2))), child: const Text('♾️ Long session', style: TextStyle(color: Color(0xFF86EFAC), fontSize: 10))),
          ])),
          const SizedBox(height: 12),
          // Online Toggle
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(isOnline ? '🟢 ONLINE — Visible to clients' : '🔴 OFFLINE — Hidden from clients', style: TextStyle(fontWeight: FontWeight.bold, color: isOnline ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5))), Text(isOnline ? 'Clients can see you in book-nurse and book you!' : 'Clients CANNOT see you in book-nurse. Turn ON to appear.', style: const TextStyle(color: Colors.white60, fontSize: 11))]), Switch(value: isOnline, onChanged: _toggleOnline)]),
            if (saveStatus.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(saveStatus, style: const TextStyle(color: Colors.white60, fontSize: 11))),
          ])),
          const SizedBox(height: 12),
          // Stats
          Row(children: [
            Expanded(child: _stat('📅 Pending', '$pending', Colors.orange)),
            const SizedBox(width: 8),
            Expanded(child: _stat('✅ Accepted', '$accepted', Colors.green)),
            const SizedBox(width: 8),
            Expanded(child: _stat('🎉 Completed', '$completed', Colors.blue)),
          ]),
          const SizedBox(height: 8),
          Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFFACC15).withOpacity(0.12), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.3))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('💰 Earnings (80% of Completed)', style: TextStyle(fontWeight: FontWeight.bold)), Text('GHS ${earnings.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFFACC15))), const SizedBox(height: 6), SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pushNamed(context, '/nurse-withdrawal'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15)), child: const Text('Withdraw Earnings', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))))])),
          const SizedBox(height: 12),
          // My Bookings
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('📋 My Bookings (${myBookings.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (myBookings.isEmpty) const Text('No bookings yet. Go ONLINE to appear to clients.', style: TextStyle(color: Colors.white60)),
            ...myBookings.take(20).map((b) {
              final s = (b['status'] ?? '').toString().toLowerCase();
              return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text('${b['id']} — ${b['clientName'] ?? 'Client'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: s == 'pending' ? Colors.orange.withOpacity(0.2) : s == 'accepted' ? Colors.green.withOpacity(0.2) : s == 'completed' ? Colors.blue.withOpacity(0.2) : Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(999)), child: Text(s.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))]),
                const SizedBox(height: 4),
                Text('Service: ${b['service'] ?? b['serviceType'] ?? ''} • Amount: GHS ${b['amount'] ?? ''} • Location: ${b['location'] ?? ''}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                if (s == 'pending') Row(children: [Expanded(child: ElevatedButton(onPressed: () => _acceptBooking(b), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('✅ Accept'))), const SizedBox(width: 8), Expanded(child: ElevatedButton(onPressed: () => _rejectBooking(b), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('❌ Reject')))]),
              ]));
            }),
          ])),
          const SizedBox(height: 20),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => Navigator.pushNamed(context, '/nurse-withdrawal'), backgroundColor: const Color(0xFFFACC15), label: const Text('Withdraw Earnings', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
    );
  }

  Widget _stat(String label, String value, Color color) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16)), child: Column(children: [Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11), textAlign: TextAlign.center)]));
}
