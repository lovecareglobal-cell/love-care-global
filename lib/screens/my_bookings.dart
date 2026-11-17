import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// My Bookings - FIXED VERSION
/// FIXED CRASHES:
/// 1. (b['time'] as num) / (as int) threw if time is String/double -> app closed on open
/// 2. (s.value as Map) / (val as Map) threw if one booking is String/List -> hid all bookings
/// 3. setState after dispose

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});
  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List<Map> bookings = [];
  List<Map> history = [];
  String showMode = 'all';
  String clientName = '', clientPhone = '', clientEmail = '', clientPhoto = '';
  Set<String> myPhones = {}, myEmails = {}, myUids = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadHistory();
  }

  // ===== SAFE HELPERS - these stop all crashes =====
  double _asNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  int _asInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is! Map) return null;
    try { return Map<String, dynamic>.from(v); } catch (_) { return null; }
  }

  DateTime _safeDate(dynamic v) {
    final ms = _asInt(v, 0);
    if (ms <= 0) return DateTime.now();
    // If time was saved as seconds (10 digits) not milliseconds (13 digits), fix it
    if (ms < 100000000000) return DateTime.fromMillisecondsSinceEpoch(ms * 1000);
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  String normPhone(String? v) {
    if (v == null) return '';
    final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9) return '';
    return digits.substring(digits.length - 9);
  }

  String normEmail(String? v) => (v ?? '').trim().toLowerCase();

  Future<void> _collectIdentities() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final k in keys) {
      final v = prefs.getString(k) ?? '';
      final kl = k.toLowerCase();
      if (kl.contains('phone') && normPhone(v).isNotEmpty) myPhones.add(normPhone(v));
      if (kl.contains('email') && normEmail(v).isNotEmpty) myEmails.add(normEmail(v));
      if ((kl.contains('uid') || kl == 'id') && v.isNotEmpty) myUids.add(v);
    }
    clientName = prefs.getString('clientName') ?? prefs.getString('fullName') ?? '';
    clientPhone = prefs.getString('clientPhone') ?? prefs.getString('phone') ?? '';
    clientEmail = prefs.getString('clientEmail') ?? prefs.getString('email') ?? '';
    clientPhoto = prefs.getString('clientPhoto') ?? prefs.getString('clientPhotoUrl') ?? prefs.getString('photoUrl') ?? '';
  }

  bool matchesBooking(Map v) {
    final bPhones = [normPhone(v['clientPhone']?.toString()), normPhone(v['phone']?.toString()), normPhone(v['nursePhone']?.toString())].where((e) => e.isNotEmpty).toList();
    final bEmails = [normEmail(v['clientEmail']?.toString()), normEmail(v['email']?.toString()), normEmail(v['nurseEmail']?.toString())].where((e) => e.isNotEmpty).toList();
    final bUids = [v['clientUid'], v['clientId'], v['uid'], v['nurseId'], v['nurseUid']].where((e) => e != null).map((e) => e.toString()).toList();
    if (myPhones.any((p) => bPhones.contains(p))) return true;
    if (myEmails.any((e) => bEmails.contains(e))) return true;
    if (myUids.any((u) => bUids.contains(u))) return true;
    return false;
  }

  bool isTerminal(Map v) {
    final st = (v['status'] ?? '').toString().toLowerCase();
    if (v['ceoPaid'] == true && st.contains('paid')) return true;
    if (st.contains('client_confirmed_finished')) return true;
    if (st.contains('cancelled')) return true;
    if (st.contains('rejected_cleared')) return true;
    return false;
  }

  bool isHistory(Map v) {
    final st = (v['status'] ?? '').toString().toLowerCase();
    return v['ceoPaid'] == true && st.contains('paid');
  }

  // Read one RTDB node safely - skip bad children, don't kill whole list
  void _addNodeToMap(Map<String, Map> map, DataSnapshot s) {
    if (!s.exists) return;
    final m = _asMap(s.value);
    if (m == null) return;
    m.forEach((k, val) {
      final v = _asMap(val);
      if (v == null) return; // skip String / number / List child, don't crash
      final bid = v['bookingId'] ?? k;
      if (!map.containsKey(bid)) map[bid] = {...v, 'id': k, 'bookingId': bid};
    });
  }

  Future<void> _loadAll() async {
    if (mounted) setState(() => isLoading = true);
    await _collectIdentities();
    final Map<String, Map> map = {};
    final db = FirebaseDatabase.instance;
    for (final p in ['bookings','allBookings','ceoBookings','bookingsByFull']) {
      try {
        final s = await db.ref(p).get();
        _addNodeToMap(map, s);
      } catch (_) {}
    }
    final userKeys = [...myUids, ...myEmails.map((e) => e.replaceAll(RegExp(r'[.@]'), '_'))];
    for (final uk in userKeys) {
      for (final base in ['clientBookings','myBookings','bookingsByClient']) {
        try {
          final s = await db.ref('$base/$uk').get();
          _addNodeToMap(map, s);
        } catch (_) {}
      }
    }
    for (final ph in myPhones) {
      try {
        final s = await db.ref('bookingsByPhone/$ph').get();
        _addNodeToMap(map, s);
      } catch (_) {}
    }
    var arr = map.values.toList();
    // FIX: use _asNum, never (as num) - String/double time no longer crashes sort
    int byTime(Map a, Map b) => _asNum(b['time'] ?? b['createdAt'] ?? 0).compareTo(_asNum(a['time'] ?? a['createdAt'] ?? 0));
    List<Map> filtered;
    if (showMode == 'recent') {
      arr.sort(byTime);
      filtered = arr.where((v) => !isTerminal(v) && !isHistory(v)).take(10).toList();
    } else {
      filtered = arr.where((v) {
        if (isTerminal(v)) return false;
        if (isHistory(v)) return false;
        if (myPhones.isEmpty && myEmails.isEmpty && myUids.isEmpty) return true;
        return matchesBooking(v);
      }).toList();
      if (filtered.isEmpty && arr.isNotEmpty) {
        arr.sort(byTime);
        filtered = arr.where((v) => !isTerminal(v) && !isHistory(v)).take(5).toList();
      }
    }
    filtered.sort(byTime);
    if (!mounted) return;
    setState(() { bookings = filtered; isLoading = false; });
  }

  Future<void> _loadHistory() async {
    await _collectIdentities();
    final keys = [...myUids, ...myPhones, ...myEmails];
    List<Map> arr = [];
    for (final k in keys) {
      try {
        final s = await FirebaseDatabase.instance.ref('clientBookingHistory/$k').get();
        if (s.exists) {
          final m = _asMap(s.value);
          if (m == null) continue;
          m.forEach((ck, val) {
            final v = _asMap(val);
            if (v == null) return;
            arr.add({...v, 'id': ck, 'bookingId': v['bookingId'] ?? ck});
          });
        }
      } catch (_) {}
    }
    arr.sort((a, b) => _asNum(b['clientConfirmedAt'] ?? 0).compareTo(_asNum(a['clientConfirmedAt'] ?? 0)));
    if (!mounted) return;
    setState(() => history = arr);
  }

  Future<void> _confirmDone(String id) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Confirm work done for $id?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Done'))]));
    if (confirm != true) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final booking = bookings.firstWhere((b) => b['bookingId'] == id, orElse: () => {});
    final key = myUids.isNotEmpty ? myUids.first : myPhones.isNotEmpty ? myPhones.first : myEmails.isNotEmpty ? myEmails.first : '';
    if (key.isNotEmpty) {
      await FirebaseDatabase.instance.ref('clientBookingHistory/$key/$id').set({...booking, 'status': 'client_confirmed_finished', 'clientConfirmed': true, 'clientConfirmedAt': now});
    }
    await FirebaseDatabase.instance.ref('bookings/$id').update({'status': 'client_confirmed_finished', 'lastChangedBy': 'client', 'lastChangedAt': now, 'clientConfirmed': true, 'clientConfirmedAt': now});
    Future.delayed(const Duration(milliseconds: 800), () async {
      await FirebaseDatabase.instance.ref('bookings/$id').remove().catchError((_) {});
      if (mounted) { _loadAll(); _loadHistory(); }
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Confirmed - Nurse will hear HIS song')));
  }

  Future<void> _cancelBooking(String id) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Cancel $id?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Cancel'))]));
    if (confirm != true) return;
    await FirebaseDatabase.instance.ref('bookings/$id').update({'status': 'cancelled_by_client', 'lastChangedBy': 'client', 'lastChangedAt': DateTime.now().millisecondsSinceEpoch, 'cancelledAt': DateTime.now().millisecondsSinceEpoch});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cancelled - Nurse will hear HIS song')));
    _loadAll();
  }

  Future<void> _openNav(Map b) async {
    final lat = b['patientLat'] ?? b['lat'] ?? b['clientLat'];
    final lng = b['patientLng'] ?? b['lng'] ?? b['clientLng'];
    if (lat == null) return;
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _showDetails(Map b) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('Booking ID ${b['bookingId']}'),
      content: SingleChildScrollView(child: Text('ID: ${b['bookingId']}\nStatus: ${b['status'] ?? 'pending'}\nClient: ${b['clientName'] ?? ''} - ${b['clientPhone'] ?? ''}\nNurse: ${b['nurseName'] ?? ''} - ${b['nursePhone'] ?? ''}\nAmount: ${b['currency'] ?? 'GHS'} ${b['amount'] ?? ''}\nService: ${b['serviceType'] ?? b['service'] ?? ''}\nLocation: ${b['location'] ?? b['patientLocation'] ?? ''}\nTime: ${_safeDate(b['time'] ?? b['createdAt'])}')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  Color _badgeColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('accepted')) return Colors.green;
    if (s.contains('rejected') || s.contains('cancelled')) return Colors.red;
    return Colors.amber;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('My Bookings', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () { _loadAll(); _loadHistory(); })]),
      body: SingleChildScrollView(
        child: Column(children: [
          Container(margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16)), child: Row(children: [
            CircleAvatar(radius: 24, backgroundImage: clientPhoto.isNotEmpty ? NetworkImage(clientPhoto) : null, child: clientPhoto.isEmpty ? Text(clientName.isNotEmpty ? clientName[0].toUpperCase() : 'C') : null),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(clientName, style: const TextStyle(fontWeight: FontWeight.bold)), Text('$clientPhone - $clientEmail', style: const TextStyle(color: Colors.white60, fontSize: 11))])),
            DropdownButton<String>(value: showMode, items: const [DropdownMenuItem(value: 'all', child: Text('All')), DropdownMenuItem(value: 'recent', child: Text('Recent 10'))], onChanged: (v) { setState(() => showMode = v ?? 'all'); _loadAll(); }),
          ])),
          if (isLoading) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()),
          if (!isLoading && bookings.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No active bookings — Book a nurse to see pending here.')),
          ...bookings.map((b) => _bookingCard(b)),
          const SizedBox(height: 16),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Align(alignment: Alignment.centerLeft, child: Text('📜 History — Confirmed / Paid', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)))),
          ...history.map((h) => ListTile(
            title: Text('Booking ID ${h['bookingId']}'),
            subtitle: Text('${h['status']} • ${_safeDate(h['clientConfirmedAt'])}'),
            trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
              for (final k in [...myUids, ...myPhones, ...myEmails]) {
                await FirebaseDatabase.instance.ref('clientBookingHistory/$k/${h['bookingId']}').remove().catchError((_) {});
              }
              _loadHistory();
            }),
          )),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  Widget _bookingCard(Map b) {
    final status = (b['status'] ?? 'pending').toString();
    final id = b['bookingId'] ?? '';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Booking ID $id', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: _badgeColor(status).withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: _badgeColor(status))), child: Text(status.toUpperCase(), style: TextStyle(color: _badgeColor(status), fontSize: 10, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 8),
        Text('👩‍⚕️ Nurse: ${b['nurseName'] ?? ''} - ${b['nursePhone'] ?? ''}'),
        Text('🏥 Patient: ${b['patientName'] ?? b['clientName'] ?? ''}'),
        Text('💰 Amount: ${b['currency'] ?? 'GHS'} ${b['amount'] ?? ''} • Pay Now: ${b['payNow'] ?? b['amountPaidNow'] ?? ''}'),
        Text('🕒 ${_safeDate(b['time'] ?? b['createdAt'])}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: ElevatedButton(onPressed: () => _confirmDone(id.toString()), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('✅ Confirm Done', style: TextStyle(fontSize: 11)))),
          const SizedBox(width: 6),
          Expanded(child: ElevatedButton(onPressed: () => _openNav(b), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), child: const Text('🗺️ Nav', style: TextStyle(fontSize: 11)))),
          const SizedBox(width: 6),
          Expanded(child: ElevatedButton(onPressed: () => _showDetails(b), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]), child: const Text('Details', style: TextStyle(fontSize: 11)))),
          const SizedBox(width: 6),
          Expanded(child: ElevatedButton(onPressed: () => _cancelBooking(id.toString()), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Cancel', style: TextStyle(fontSize: 11)))),
        ]),
      ]),
    );
  }
}
