import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';

/// My Job Offer - Flutter version of my-job-offer.html
/// - Loads from: bookings + allBookings + ceoBookings + bookingsByFull + clientBookings/myBookings/bookingsByClient (by uid/emailKey) + bookingsByPhone/{phone9} + SharedPreferences myBookings
///   Dedupe by bookingId (same as HTML loadAll map)
/// - Matching: matchesBooking(v, myIds) — phone last 9 + email + UID from ALL prefs keys (same as HTML getAllIdentities)
///   If 0 matched but bookings exist -> show recent 5 so nurse can see pending + Claim (same as HTML)
///   showMode recent -> recent 10 non-terminal non-history
/// - Terminal / History: isTerminal + isHistory filtered out (completed/paid/cancelled etc are in History)
/// - Actions (same as HTML, each sends sound trigger to client):
///   Accept: bookings/{id} status accepted, lastChangedBy nurse, acceptedAt, acceptedAtStr, trigger client {status accepted, title Nurse accepted}
///   Reject: status rejected_by_nurse, rejectedAt, rejectedByNurseName, trigger client {rejected_by_nurse}
///   On Way: status on_the_way, lastChangedUid/Phone, trigger client
///   Close: status close, trigger client {title Nurse is close}
///   Completed: status completed, trigger client {title Nurse completed} — 'Completed - Collect CASH from client'
///   Confirm Done (client side in HTML, kept here): nurseBookingHistory/{key}/{id} {status client_confirmed_finished, clientConfirmed, clientConfirmedAt} + bookings/{id} status client_confirmed_finished, then remove bookings/{id} after 800ms
///   Cancel: bookings/{id} status cancelled_by_client
///   Claim: save nursePhone / nurseEmail to prefs, reload
/// - History: nurseBookingHistory/{key} for uid/phone/email keys, sorted by clientConfirmedAt desc, Delete / Delete All, View Receipt
/// - Receiver-only sound: same as nurse-dashboard (bookings child_changed shouldRing + soundTriggers)
/// - NEW 20/80 RULE (Nov 2026): Nurse sees ONLY her cash (80%). NEVER total, NEVER CEO fee (20%).
///   _nurseCash(b) = nurseCash / nurseCashAmount / amountYouWillCollectCash / 80% of total (fallback).
///   Accept: nurse stays Busy/Locked. Reject: nurse -> Available, booking rejected_by_nurse, client gets FULL 20% refund.
///   Completed: nurse collects CASH from client, confirms cash received, then nurse -> Available. CEO NEVER pays nurse.

class MyJobOfferScreen extends StatefulWidget {
  const MyJobOfferScreen({super.key});
  @override
  State<MyJobOfferScreen> createState() => _MyJobOfferScreenState();
}

class _MyJobOfferScreenState extends State<MyJobOfferScreen> {
  List<Map> all = [];
  List<Map> historyData = [];
  List<String> myPhones = [], myEmails = [], myUids = [];
  String showMode = 'mine'; // mine | recent
  bool showHistory = false;
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadHistory();
    _startSound();
  }

  Future<void> _getAllIdentities() async {
    final prefs = await SharedPreferences.getInstance();
    myPhones = []; myEmails = []; myUids = [];
    for (final k in prefs.getKeys()) {
      final v = prefs.getString(k) ?? '';
      final kl = k.toLowerCase();
      if (kl.contains('phone')) { final p = v.replaceAll(RegExp(r'[^0-9]'), ''); if (p.length >= 9) myPhones.add(p.substring(p.length - 9)); }
      if (kl.contains('email')) myEmails.add(v.toLowerCase().trim());
      if (kl.contains('uid') || k == 'id') myUids.add(v);
    }
    // Auth is truth - login saves NO prefs, so prefs-only = NONE / 'Login again'.
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (user.uid.isNotEmpty) myUids.add(user.uid);
        if (user.email != null && user.email!.isNotEmpty) myEmails.add(_normEmail(user.email!));
        try {
          final doc = await FirebaseFirestore.instance.collection('nurses').doc(user.uid).get();
          if (doc.exists && doc.data() != null) {
            final d = doc.data()!;
            if (d['phone'] != null) { final p = _normPhone(d['phone'].toString()); if (p.isNotEmpty) myPhones.add(p); }
            if (d['email'] != null) myEmails.add(_normEmail(d['email'].toString()));
          }
        } catch (_) {}
      }
    } catch (_) {}
    // Dedupe
    myPhones = myPhones.toSet().toList(); myEmails = myEmails.toSet().toList(); myUids = myUids.toSet().toList();
  }

  String _normPhone(String s) { final p = s.replaceAll(RegExp(r'[^0-9]'), ''); return p.length >= 9 ? p.substring(p.length - 9) : p; }
  String _normEmail(String s) => s.toLowerCase().trim();

  // Time may be num (ms) or String (ISO / digits) - 'as num' crashes on String.
  int _toMillis(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
    return 0;
  }

  String _formatTime(dynamic v) {
    final ms = _toMillis(v);
    if (ms <= 0) return '';
    return DateTime.fromMillisecondsSinceEpoch(ms).toString();
  }

  // RTDB KEY, not bookingId. bookingId != key in _loadAll, so updating
  // bookings/<bookingId> created a duplicate node and the real booking never changed.
  String _rtKey(Map b) => (b['id'] ?? b['bookingId'] ?? '').toString();

  // NEW 20/80: Nurse sees ONLY her cash. Never total / CEO fee.
  double _nurseCash(Map b) {
    double v(dynamic x) {
      if (x == null) return 0;
      if (x is num) return x.toDouble();
      return double.tryParse(x.toString()) ?? 0;
    }
    double c = v(b['nurseCash']);
    if (c > 0) return c;
    c = v(b['nurseCashAmount']);
    if (c > 0) return c;
    c = v(b['amountYouWillCollectCash']);
    if (c > 0) return c;
    final total = v(b['totalAmount'] ?? b['total'] ?? b['amount']);
    if (total > 0) return total * 0.80;
    return 0;
  }
  String _nurseCashStr(Map b) {
    final cur = (b['currency'] ?? 'GHS').toString();
    return '$cur ${_nurseCash(b).toStringAsFixed(2)}';
  }
  Future<void> _unlockNurse(Map b) async {
    final nid = (b['nurseId'] ?? '').toString();
    if (nid.isEmpty) return;
    try {
      await FirebaseDatabase.instance.ref('nurses/$nid').update({'isAvailable': true, 'isBooked': false, 'isBusy': false, 'status': 'available', 'currentBookingId': null, 'currentBookingStatus': null});
    } catch (_) {}
    try {
      await FirebaseDatabase.instance.ref('onlineNurses/$nid').update({'isAvailable': true, 'isBooked': false, 'currentBookingId': null});
    } catch (_) {}
  }
  Future<void> _lockNurse(Map b) async {
    final nid = (b['nurseId'] ?? '').toString();
    if (nid.isEmpty) return;
    final bid = (b['bookingId'] ?? b['id'] ?? '').toString();
    try {
      await FirebaseDatabase.instance.ref('nurses/$nid').update({'isAvailable': false, 'isBooked': true, 'isBusy': true, 'status': 'busy', 'currentBookingId': bid, 'currentBookingStatus': 'accepted'});
    } catch (_) {}
  }

  bool _matchesBooking(Map v) {
    if (myPhones.isEmpty && myEmails.isEmpty && myUids.isEmpty) return true;
    final bPhones = [(v['clientPhone'] ?? ''), (v['phone'] ?? ''), (v['nursePhone'] ?? '')].map((e) => _normPhone(e.toString())).toList();
    final bEmails = [(v['clientEmail'] ?? ''), (v['email'] ?? ''), (v['nurseEmail'] ?? '')].map((e) => _normEmail(e.toString())).toList();
    final bUids = [v['clientUid'], v['clientId'], v['uid'], v['nurseId'], v['nurseUid']].map((e) => e?.toString() ?? '').toList();
    if (myPhones.any((p) => bPhones.contains(p))) return true;
    if (myEmails.any((e) => bEmails.contains(e))) return true;
    if (myUids.any((u) => bUids.contains(u))) return true;
    return false;
  }

  bool _isTerminal(Map v) {
    final s = (v['status'] ?? '').toString().toLowerCase();
    return s.contains('cancelled') || s == 'rejected' || s == 'rejected_by_nurse' || s == 'ceo_paid' || s == 'paid' || v['paid'] == true;
  }

  bool _isHistory(Map v) => (v['status'] ?? '').toString().toLowerCase() == 'client_confirmed_finished' || v['clientConfirmed'] == true;

  List<Map> get filtered {
    var arr = List<Map>.from(all);
    if (showMode == 'recent') {
      arr.sort((a, b) => _toMillis(b['time'] ?? b['createdAt']).compareTo(_toMillis(a['time'] ?? a['createdAt'])));
      return arr.where((v) => !_isTerminal(v) && !_isHistory(v)).take(10).toList();
    }
    var f = arr.where((v) => !_isTerminal(v) && !_isHistory(v) && _matchesBooking(v)).toList();
    if (f.isEmpty && arr.isNotEmpty) {
      arr.sort((a, b) => _toMillis(b['time'] ?? b['createdAt']).compareTo(_toMillis(a['time'] ?? a['createdAt'])));
      f = arr.where((v) => !_isTerminal(v) && !_isHistory(v)).take(5).toList();
    }
    f.sort((a, b) => _toMillis(b['time'] ?? b['createdAt']).compareTo(_toMillis(a['time'] ?? a['createdAt'])));
    return f;
  }

  Future<void> _loadAll() async {
    await _getAllIdentities();
    final db = FirebaseDatabase.instance;
    Map<String, Map> map = {};
    for (final p in ['bookings', 'allBookings', 'ceoBookings', 'bookingsByFull']) {
      try {
        final s = await db.ref(p).get();
        if (s.exists) (s.value as Map).forEach((k, v) { final val = Map<String, dynamic>.from(v as Map); final bid = val['bookingId'] ?? k; if (!map.containsKey(bid)) map[bid] = {...val, 'id': k, 'bookingId': bid}; });
      } catch (_) {}
    }
    for (final uk in [...myUids, ...myEmails.map((e) => e.replaceAll(RegExp(r'[.@]'), '_'))]) {
      for (final base in ['clientBookings', 'myBookings', 'bookingsByClient']) {
        try {
          final s = await db.ref('$base/$uk').get();
          if (s.exists) (s.value as Map).forEach((k, v) { final val = Map<String, dynamic>.from(v as Map); final bid = val['bookingId'] ?? k; if (!map.containsKey(bid)) map[bid] = {...val, 'id': k, 'bookingId': bid}; });
        } catch (_) {}
      }
    }
    for (final ph in myPhones) {
      try {
        final s = await db.ref('bookingsByPhone/$ph').get();
        if (s.exists) (s.value as Map).forEach((k, v) { final val = Map<String, dynamic>.from(v as Map); final bid = val['bookingId'] ?? k; if (!map.containsKey(bid)) map[bid] = {...val, 'id': k, 'bookingId': bid}; });
      } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getString('myBookings');
      if (local != null) {
        // myBookings stored as JSON string in prefs (if any) — parse loosely
      }
    } catch (_) {}
    setState(() => all = map.values.toList());
  }

  Future<void> _sendSoundTrigger(String toRole, Map data) async {
    try { await FirebaseDatabase.instance.ref('soundTriggers/$toRole').push().set({'fromRole': 'nurse', 'time': DateTime.now().millisecondsSinceEpoch, ...data}); } catch (_) {}
  }

  Future<void> _updateBooking(String id, Map data, String? triggerTitle, String? triggerStatus) async {
    final b = all.firstWhere((x) => x['id'] == id || x['bookingId'] == id, orElse: () => {});
    await FirebaseDatabase.instance.ref('bookings/$id').update(Map<String, Object?>.from(data));
    if (triggerTitle != null) {
      await _sendSoundTrigger('client', {'bookingId': id, 'status': triggerStatus ?? data['status'], 'title': triggerTitle, 'toPhone': b['clientPhone'], 'toUid': b['clientUid'] ?? b['clientId'], 'toEmail': b['clientEmail']});
    }
    await _loadAll();
  }

  Future<void> _acceptOffer(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final b = all.firstWhere((x) => x['id'] == id || x['bookingId'] == id, orElse: () => {});
    await _updateBooking(id, {'status': 'accepted', 'lastChangedBy': 'nurse', 'lastChangedAt': now, 'acceptedAt': now, 'acceptedAtStr': DateTime.now().toString()}, 'Nurse accepted', 'accepted');
    await _lockNurse(b);
    _toast('Accepted - Client will hear HIS song');
  }

  Future<void> _rejectOffer(String id) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Reject $id?'), content: const Text('Client gets FULL 20% refund and can book another nurse. You become Available again immediately.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject'))]));
    if (confirm != true) return;
    final b = all.firstWhere((x) => x['id'] == id || x['bookingId'] == id, orElse: () => {});
    final now = DateTime.now().millisecondsSinceEpoch;
    await _updateBooking(id, {'status': 'rejected_by_nurse', 'lastChangedBy': 'nurse', 'lastChangedAt': now, 'rejectedAt': now, 'rejectedByNurseName': b['nurseName'], 'refundCeoFee': true, 'refundStatus': 'refund_due_full_20', 'cancelTermsApplied': 'nurse_rejects_refund_full_20'}, 'Nurse rejected your offer', 'rejected_by_nurse');
    await _unlockNurse(b);
    _toast('Rejected - Client gets full 20% refund - You are Available again');
  }

  Future<void> _markOnWay(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _updateBooking(id, {'status': 'on_the_way', 'lastChangedBy': 'nurse', 'lastChangedAt': now, 'lastChangedUid': prefs.getString('nurseUid') ?? prefs.getString('uid') ?? '', 'lastChangedPhone': prefs.getString('nursePhone') ?? prefs.getString('phone') ?? ''}, 'Nurse is on the way', 'on_the_way');
    _toast('On the way');
  }

  Future<void> _markClose(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _updateBooking(id, {'status': 'close', 'lastChangedBy': 'nurse', 'lastChangedAt': now}, 'Nurse is close', 'close');
    _toast('Close - Near client');
  }

  Future<void> _confirmCashReceived(String id) async {
    final b = all.firstWhere((x) => x['id'] == id || x['bookingId'] == id, orElse: () => {});
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Confirm Cash Received?'), content: Text('Confirm client paid you CASH: ${_nurseCashStr(b)}\nCEO does NOT pay you. After this you become Available again.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not Yet')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Cash Received'))]));
    if (confirm != true) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _updateBooking(id, {'status': 'cash_received_by_nurse', 'lastChangedBy': 'nurse', 'lastChangedAt': now, 'cashPaidToNurse': true, 'nurseCashPaid': true, 'cashConfirmedByNurse': true, 'cashConfirmedAt': now}, 'Nurse confirmed cash received', 'cash_received_by_nurse');
    await _unlockNurse(b);
    _toast('Cash confirmed - You are Available again');
  }

  Future<void> _markCompleted(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _updateBooking(id, {'status': 'completed', 'lastChangedBy': 'nurse', 'lastChangedAt': now}, 'Nurse completed', 'completed');
    _toast('Completed - Collect CASH from client, then Confirm Cash Received');
  }

  Future<void> _confirmDone(String id) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Confirm work done for $id?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm'))]));
    if (confirm != true) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = myUids.isNotEmpty ? myUids[0] : (myPhones.isNotEmpty ? myPhones[0] : (myEmails.isNotEmpty ? myEmails[0] : 'unknown'));
    final b = all.firstWhere((x) => x['id'] == id || x['bookingId'] == id, orElse: () => {});
    await FirebaseDatabase.instance.ref('nurseBookingHistory/$key/$id').set({...b, 'status': 'client_confirmed_finished', 'clientConfirmed': true, 'clientConfirmedAt': now, 'clientConfirmedAtStr': DateTime.now().toString(), 'nurseCash': _nurseCash(b)});
    await _unlockNurse(b);
    await FirebaseDatabase.instance.ref('bookings/$id').update({'status': 'client_confirmed_finished', 'clientConfirmed': true, 'clientConfirmedAt': now});
    Future.delayed(const Duration(milliseconds: 800), () async { await FirebaseDatabase.instance.ref('bookings/$id').remove().catchError((_) {}); _toast('Confirmed - Moved to history'); _loadHistory(); _loadAll(); });
  }

  Future<void> _cancelBooking(String id) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Cancel $id?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel'))]));
    if (confirm != true) return;
    await FirebaseDatabase.instance.ref('bookings/$id').update({'status': 'cancelled_by_client', 'cancelledAt': DateTime.now().millisecondsSinceEpoch});
    _toast('Cancelled');
    _loadAll();
  }

  Future<void> _claimBooking(String id) async {
    final phoneCtrl = TextEditingController(text: myPhones.isNotEmpty ? myPhones[0] : '');
    final emailCtrl = TextEditingController(text: myEmails.isNotEmpty ? myEmails[0] : '');
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Claim This Booking'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Your phone')), TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Your email'))]), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))]));
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    if (phoneCtrl.text.isNotEmpty) await prefs.setString('nursePhone', phoneCtrl.text);
    if (emailCtrl.text.isNotEmpty) await prefs.setString('nurseEmail', emailCtrl.text);
    _toast('Saved - Reloading');
    _loadAll();
  }

  Future<void> _loadHistory() async {
    List<Map> arr = [];
    for (final k in [...myUids, ...myPhones, ...myEmails]) {
      try {
        final s = await FirebaseDatabase.instance.ref('nurseBookingHistory/$k').get();
        if (s.exists) (s.value as Map).forEach((key, v) { final val = Map<String, dynamic>.from(v as Map); arr.add({...val, 'id': key, 'bookingId': val['bookingId'] ?? key}); });
      } catch (_) {}
    }
    arr.sort((a, b) => _toMillis(b['clientConfirmedAt']).compareTo(_toMillis(a['clientConfirmedAt'])));
    setState(() => historyData = arr);
  }

  Future<void> _deleteHistory(String id) async {
    if (myUids.isEmpty && myPhones.isEmpty && myEmails.isEmpty) { _toast('Login again - no identity'); return; }
    final key = myUids.isNotEmpty ? myUids[0] : (myPhones.isNotEmpty ? myPhones[0] : myEmails[0]);
    await FirebaseDatabase.instance.ref('nurseBookingHistory/$key/$id').remove().catchError((_) {});
    _loadHistory();
  }

  Future<void> _deleteAllHistory() async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Delete ALL history?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes'))]));
    if (confirm != true) return;
    for (final k in [...myUids, ...myPhones, ...myEmails]) await FirebaseDatabase.instance.ref('nurseBookingHistory/$k').remove().catchError((_) {});
    _loadHistory();
  }

  void _startSound() {
    FirebaseDatabase.instance.ref('bookings').onChildChanged.listen((e) {
      if (!e.snapshot.exists) return;
      final v = Map<String, dynamic>.from(e.snapshot.value as Map);
      if (v['lastChangedBy'] == 'nurse') return;
      if (!_matchesBooking(v)) return;
      final t = _toMillis(v['lastChangedAt'] ?? v['time'] ?? v['createdAt']);
      if (DateTime.now().millisecondsSinceEpoch - t > 120000) return;
      _playCustomSound();
      _toast('🔔 New reply - ${v['status'] ?? ''}');
    });
  }

  Future<void> _playCustomSound() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString('alert_custom_song') ?? prefs.getString('nurse_custom_song');
    if (custom != null && custom.isNotEmpty) { try { await _player.play(UrlSource(custom)); return; } catch (_) {} }
    try { await _player.play(AssetSource('sounds/default.mp3')); } catch (_) {}
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _showDetails(Map b) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('Booking ID ${b['bookingId']}'),
      content: SingleChildScrollView(child: Text('ID: ${b['bookingId']}\nStatus: ${b['status'] ?? 'pending'}\nClient: ${b['clientName'] ?? ''} - ${b['clientPhone'] ?? ''}\nNurse: ${b['nurseName'] ?? ''} - ${b['nursePhone'] ?? ''}\nYou will collect CASH after work: ${_nurseCashStr(b)}\nService: ${b['serviceType'] ?? b['service'] ?? ''}\nLocation: ${b['location'] ?? ''}\nTime: ${_formatTime(b['time'])}')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')), ElevatedButton(onPressed: () { Navigator.pop(context); _claimBooking(_rtKey(b)); }, child: const Text('Claim This Booking'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('My Job Offers', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [TextButton(onPressed: () async { await _loadHistory(); setState(() => showHistory = !showHistory); }, child: Text(showHistory ? 'Hide History' : 'History (${historyData.length})', style: const TextStyle(color: Colors.white)))]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your identity:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Phones: ${myPhones.isEmpty ? 'NONE - Login again' : myPhones.join(', ')} | Emails: ${myEmails.isEmpty ? 'NONE' : myEmails.join(', ')} | UIDs: ${myUids.isEmpty ? 'NONE' : myUids.join(', ')}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
            const Text('Matching by phone last 9 + email + UID from ALL prefs keys - If NONE, use Show Recent 10', style: TextStyle(color: Colors.white60, fontSize: 10)),
            const SizedBox(height: 8),
            Row(children: [
              ChoiceChip(label: const Text('My Offers'), selected: showMode == 'mine', onSelected: (_) { setState(() => showMode = 'mine'); }),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('Show Recent 10'), selected: showMode == 'recent', onSelected: (_) { setState(() => showMode = 'recent'); }),
              const Spacer(),
              TextButton(onPressed: _loadAll, child: const Text('Refresh')),
            ]),
          ])),
          const SizedBox(height: 12),
          if (showHistory) ...[
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('📜 History — Cash Collected / Confirmed', style: TextStyle(fontWeight: FontWeight.bold)), TextButton(onPressed: _deleteAllHistory, child: const Text('Delete All', style: TextStyle(color: Colors.red)))]),
              if (historyData.isEmpty) const Text('No history yet', style: TextStyle(color: Colors.white60, fontSize: 11)),
              ...historyData.map((b) {
                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showDetails(b),
                          child: Text(
                            'Booking ID ${b['bookingId']} - ${b['paidAtStr'] ?? b['clientConfirmedAtStr'] ?? ''} - ${b['cashPaidToNurse'] == true || b['cashConfirmedByNurse'] == true ? '✅ CASH COLLECTED' : ''} - ${b['status']} - Cash: ${_nurseCashStr(b)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      if (b['receipt'] != null)
                        TextButton(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Receipt'),
                              content: Image.network(b['receipt'].toString()),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          ),
                          child: const Text('Receipt'),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                        onPressed: () => _deleteHistory(_rtKey(b)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ])),
            const SizedBox(height: 12),
          ],
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No job offers yet. Go ONLINE to appear to clients.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60))),
          if (list.isNotEmpty && showMode == 'mine' && all.isNotEmpty && list.length == 5 && all.length > 5) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('0 matched but bookings exist - Showing recent 5 so you can see pending - Tap to claim', style: TextStyle(color: Color(0xFFFACC15), fontSize: 11))),
          ...list.map((b) {
            final s = (b['status'] ?? 'pending').toString().toLowerCase();
            return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text('Booking ID ${b['bookingId']}', style: const TextStyle(fontWeight: FontWeight.bold))), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(999)), child: Text(s.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))]),
              const SizedBox(height: 6),
              Text('Client: ${b['clientName'] ?? ''} - ${b['clientPhone'] ?? ''}', style: const TextStyle(fontSize: 12)),
              Text('Service: ${b['serviceType'] ?? b['service'] ?? ''}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
              Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4))), child: Row(children: [const Icon(Icons.money, color: Colors.greenAccent, size: 18), const SizedBox(width: 6), Expanded(child: Text('You will collect CASH after work: ${_nurseCashStr(b)}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)))])),
              Text('Location: ${b['location'] ?? ''}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
              Text('Time: ${_formatTime(b['time'])}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (s == 'pending' || s == 'new') ...[
                  ElevatedButton(onPressed: () => _acceptOffer(_rtKey(b)), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('✅ Accept', style: TextStyle(fontSize: 11))),
                  ElevatedButton(onPressed: () => _rejectOffer(_rtKey(b)), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('❌ Reject', style: TextStyle(fontSize: 11))),
                ],
                if (s == 'accepted') ...[
                  ElevatedButton(onPressed: () => _markOnWay(_rtKey(b)), child: const Text('🚗 On Way', style: TextStyle(fontSize: 11))),
                  ElevatedButton(onPressed: () => _markClose(_rtKey(b)), child: const Text('📍 Close', style: TextStyle(fontSize: 11))),
                  ElevatedButton(onPressed: () => _markCompleted(_rtKey(b)), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), child: const Text('🎉 Completed', style: TextStyle(fontSize: 11))),
                  ElevatedButton(onPressed: () => _confirmCashReceived(_rtKey(b)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)), child: Text('💵 Confirm Cash Received - ${_nurseCashStr(b)}', style: const TextStyle(fontSize: 11))),
                ],
                if (s == 'on_the_way') ElevatedButton(onPressed: () => _markClose(_rtKey(b)), child: const Text('📍 Close', style: TextStyle(fontSize: 11))),
                if (s == 'close' || s == 'completed') ElevatedButton(onPressed: () => _markCompleted(_rtKey(b)), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), child: const Text('🎉 Completed', style: TextStyle(fontSize: 11))),
                if (s == 'completed' || s == 'close') ElevatedButton(onPressed: () => _confirmCashReceived(_rtKey(b)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)), child: Text('💵 Confirm Cash Received - ${_nurseCashStr(b)}', style: const TextStyle(fontSize: 11))),
                ElevatedButton(onPressed: () => _confirmDone(_rtKey(b)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)), child: const Text('✅ Confirm Done', style: TextStyle(fontSize: 11))),
                OutlinedButton(onPressed: () => _showDetails(b), child: const Text('Details', style: TextStyle(fontSize: 11))),
                OutlinedButton(onPressed: () => _claimBooking(_rtKey(b)), child: const Text('Claim', style: TextStyle(fontSize: 11))),
                OutlinedButton(onPressed: () => _cancelBooking(_rtKey(b)), style: OutlinedButton.styleFrom(foregroundColor: Colors.red), child: const Text('Cancel', style: TextStyle(fontSize: 11))),
                OutlinedButton(onPressed: () => Navigator.pushNamed(context, '/nurse-complaint', arguments: {'bookingId': b['bookingId'], 'id': _rtKey(b), 'clientName': b['clientName'], 'clientId': b['clientUid'] ?? b['clientId'], 'nurseName': b['nurseName'], 'nurseId': b['nurseId'], 'service': b['serviceType'] ?? b['service'], 'amount': _nurseCash(b), 'nurseCash': _nurseCash(b)}), child: const Text('😡 Complaint', style: TextStyle(fontSize: 11))),
              ]),
            ]));
          }),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
