import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// My Bookings - CLIENT side
/// - Shows ONLY client's own bookings (phone + email + UID + name)
/// - NEW 20/80 RULE: Client pays ONLY 20% CEO fee in app to book.
///   Nurse cash 80% is paid CASH by client to nurse AFTER work. CEO never sends money to nurse.
/// - 50% DELETED. No 50% button, no 50% logic anywhere.
/// - Cancel Terms (locked):
///   Nurse rejects = full 20% refund to client.
///   Client cancels BEFORE start = CEO keeps 20%, nurse -> Available.
///   Client cancels AFTER start (accepted/on_the_way/close) = CEO keeps 20% + client pays nurse cash for days worked, nurse -> Available.
/// - Confirm Cash Paid: client confirms nurse cash paid, job -> cash_confirmed, nurse -> Available.

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});
  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List<Map> bookings = [];
  List<Map> history = [];
  bool isLoading = true;
  String filter = 'All';

  final Set<String> myPhones = {};
  final Set<String> myEmails = {};
  final Set<String> myUids = {};
  String? myName;

  StreamSubscription<DatabaseEvent>? _bookingsSub;
  StreamSubscription<DatabaseEvent>? _historySub;

  @override
  void initState() {
    super.initState();
    _collectIdentities().then((_) {
      _listenLive();
      _loadHistory();
    });
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && isLoading) setState(() => isLoading = false);
    });
  }

  @override
  void dispose() {
    _bookingsSub?.cancel();
    _historySub?.cancel();
    super.dispose();
  }

  String normPhone(String? p) {
    if (p == null) return '';
    var d = p.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('233')) d = '0${d.substring(3)}';
    if (d.length > 10) d = d.substring(d.length - 10);
    return d;
  }

  String normEmail(String? e) => (e ?? '').trim().toLowerCase();

  Future<void> _collectIdentities() async {
    myPhones.clear();
    myEmails.clear();
    myUids.clear();
    final prefs = await SharedPreferences.getInstance();
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser != null) {
      myUids.add(authUser.uid);
      if (authUser.phoneNumber != null) myPhones.add(normPhone(authUser.phoneNumber));
      if (authUser.email != null) myEmails.add(normEmail(authUser.email));
    }
    for (final k in prefs.getKeys()) {
      final lk = k.toLowerCase();
      final v = prefs.get(k);
      if (v is! String || v.isEmpty) continue;
      if (lk.contains('phone')) myPhones.add(normPhone(v));
      if (lk.contains('email')) myEmails.add(normEmail(v));
      if (lk.contains('uid') || lk.contains('user_id')) myUids.add(v);
      if (lk.contains('name') || lk.contains('username')) myName = v;
    }
    myName ??= prefs.getString('clientName') ?? prefs.getString('fullName') ?? prefs.getString('name');
  }

  void _listenLive() {
    setState(() => isLoading = true);
    _bookingsSub = FirebaseDatabase.instance.ref('bookings').onValue.listen((event) {
      final map = <String, Map>{};
      _addNodeToMap(map, event.snapshot);
      _applyFilter(map);
    }, onError: (_) {
      if (mounted) setState(() => isLoading = false);
    });
  }

  void _addNodeToMap(Map<String, Map> map, DataSnapshot snap) {
    if (!snap.exists || snap.value == null) return;
    final val = snap.value;
    if (val is Map) {
      val.forEach((k, v) {
        if (v is Map) {
          final m = Map<String, dynamic>.from(v);
          m['key'] = k.toString();
          map[k.toString()] = m;
        }
      });
    }
  }

  void _applyFilter(Map<String, Map> map) {
    var arr = map.values.toList();
    List<Map> filtered = arr.where((v) {
      if (isTerminal(v) || isHistory(v)) return false;
      if (myPhones.isEmpty && myEmails.isEmpty && myUids.isEmpty) return true;
      return matchesBooking(v);
    }).toList();
    filtered.sort((a, b) => _asNum(b['time'] ?? b['createdAt'] ?? 0).compareTo(_asNum(a['time'] ?? a['createdAt'] ?? 0)));
    if (!mounted) return;
    setState(() {
      bookings = filtered;
      isLoading = false;
    });
  }

  void _loadHistory() {
    _historySub = FirebaseDatabase.instance.ref('bookings').onValue.listen((event) {
      final map = <String, Map>{};
      _addNodeToMap(map, event.snapshot);
      var arr = map.values.where((v) => isTerminal(v) || isHistory(v)).toList();
      arr = arr.where((v) {
        if (myPhones.isEmpty && myEmails.isEmpty && myUids.isEmpty) return true;
        return matchesBooking(v);
      }).toList();
      if (mounted) setState(() => history = arr);
    });
  }

  bool matchesBooking(Map v) {
    final p = normPhone('${v['clientPhone'] ?? v['phone'] ?? v['phoneNumber'] ?? ''}');
    final e = normEmail('${v['clientEmail'] ?? v['email'] ?? ''}');
    final u = '${v['clientId'] ?? v['userId'] ?? v['uid'] ?? ''}';
    final n = '${v['clientName'] ?? v['name'] ?? v['fullName'] ?? ''}'.toLowerCase();
    if (p.isNotEmpty && myPhones.contains(p)) return true;
    if (e.isNotEmpty && myEmails.contains(e)) return true;
    if (u.isNotEmpty && myUids.contains(u)) return true;
    if (myName != null && myName!.isNotEmpty && n.contains(myName!.toLowerCase())) return true;
    return false;
  }

  bool isTerminal(Map v) {
    final s = '${v['status'] ?? ''}'.toLowerCase();
    return s.contains('complete') || s.contains('cancel') || s.contains('reject') || s.contains('done') || s.contains('cash_received') || s.contains('cash_confirmed');
  }

  bool isHistory(Map v) => v['isHistory'] == true;
  num _asNum(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
  double _asDouble(dynamic v) => _asNum(v).toDouble();

  // ---- NEW 20/80 MONEY HELPERS (CLIENT SEES FULL, NURSE SEES ONLY HER CASH) ----
  double _total(Map b) {
    double t = _asDouble(b['totalAmount'] ?? b['total'] ?? b['amount']);
    if (t > 0) return t;
    final ceo = _asDouble(b['ceoFee']);
    final nurse = _asDouble(b['nurseCash'] ?? b['nurseCashAmount']);
    if (ceo > 0 || nurse > 0) return ceo + nurse;
    return 0;
  }
  double _ceoFee(Map b) {
    double c = _asDouble(b['ceoFee'] ?? b['amountPaidNow'] ?? b['payNow']);
    if (c > 0) return c;
    return _total(b) * 0.20;
  }
  double _nurseCash(Map b) {
    double n = _asDouble(b['nurseCash'] ?? b['nurseCashAmount'] ?? b['amountYouWillCollectCash'] ?? b['payLater']);
    if (n > 0) return n;
    return _total(b) * 0.80;
  }
  String _money(Map b, double v) => '${b['currency'] ?? 'GHS'} ${v.toStringAsFixed(2)}';

  bool _isAfterStart(Map b) {
    final s = '${b['status'] ?? ''}'.toLowerCase();
    return s == 'accepted' || s == 'on_the_way' || s == 'close' || s == 'completed' || s == 'on_the_way_to_client' || s.contains('started') || s.contains('in_progress');
  }

  Future<void> _unlockNurse(Map b) async {
    final nid = '${b['nurseId'] ?? ''}';
    if (nid.isEmpty) return;
    try {
      await FirebaseDatabase.instance.ref('nurses/$nid').update({'isAvailable': true, 'isBooked': false, 'isBusy': false, 'status': 'available', 'currentBookingId': null, 'currentBookingStatus': null});
    } catch (_) {}
    try {
      await FirebaseDatabase.instance.ref('onlineNurses/$nid').update({'isAvailable': true, 'isBooked': false, 'currentBookingId': null});
    } catch (_) {}
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _cancelBooking(Map b) async {
    final id = (b['key'] ?? b['bookingId'] ?? b['id'] ?? '').toString();
    if (id.isEmpty) return;
    final afterStart = _isAfterStart(b);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Booking?'),
        content: Text(
          afterStart
              ? 'You cancel AFTER work started.\n\nCEO keeps 20%: ${_money(b, _ceoFee(b))}\nYou must pay nurse CASH for days worked: ${_money(b, _nurseCash(b))} (full job cash, adjust for days worked with nurse).\nNurse becomes Available again.'
              : 'You cancel BEFORE work starts.\n\nCEO keeps 20% as cancellation fee: ${_money(b, _ceoFee(b))}\nNurse gets GH₵0.\nNurse becomes Available again.\n\nTerms: Nurse rejects = full 20% refund. You cancel before start = CEO keeps 20%. You cancel after start = CEO keeps 20% + you pay nurse cash for days worked.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No, Keep Booking')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Cancel')),
        ],
      ),
    );
    if (confirm != true) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await FirebaseDatabase.instance.ref('bookings/$id').update({
      'status': 'cancelled_by_client',
      'lastChangedBy': 'client',
      'lastChangedAt': now,
      'cancelledAt': now,
      'cancelledByClient': true,
      'cancelTermsApplied': afterStart ? 'client_cancels_after_start_ceo_keeps_20_plus_nurse_cash_days_worked' : 'client_cancels_before_start_ceo_keeps_20',
      'ceoKeepsFee': true,
      'refundCeoFee': false,
      'nurseCashDueOnCancel': _nurseCash(b),
    });
    await _unlockNurse(b);
    _toast(afterStart ? 'Cancelled - CEO keeps 20% + Pay nurse cash for days worked' : 'Cancelled - CEO keeps 20% as fee');
    _listenLive();
  }

  Future<void> _confirmCashPaid(Map b) async {
    final id = (b['key'] ?? b['bookingId'] ?? b['id'] ?? '').toString();
    if (id.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Cash Paid to Nurse?'),
        content: Text('Confirm you paid nurse CASH: ${_money(b, _nurseCash(b))}\nCEO does NOT pay nurse. After this, job is closed and nurse becomes Available again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not Yet')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Cash Paid')),
        ],
      ),
    );
    if (confirm != true) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await FirebaseDatabase.instance.ref('bookings/$id').update({
      'status': 'cash_confirmed_by_client',
      'lastChangedBy': 'client',
      'lastChangedAt': now,
      'cashPaidToNurse': true,
      'nurseCashPaid': true,
      'cashConfirmedByClient': true,
      'cashConfirmedAt': now,
    });
    await _unlockNurse(b);
    _toast('Cash confirmed - Nurse is Available again');
    _listenLive();
  }

  void _showDetails(Map b) {
    final s = '${b['status'] ?? 'Pending'}';
    final isRejected = s.toLowerCase().contains('reject');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${b['service'] ?? b['type'] ?? 'Nurse Booking'}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Booking: ${b['bookingId'] ?? b['key'] ?? ''}'),
              Text('Status: $s'),
              Text('Nurse: ${b['nurseName'] ?? 'Waiting for nurse...'} - ${b['nursePhone'] ?? ''}'),
              Text('Client: ${b['clientName'] ?? ''} - ${b['clientPhone'] ?? ''}'),
              Text('Patient: ${b['patientName'] ?? ''} - ${b['patientLocation'] ?? b['location'] ?? ''}'),
              Text('Time: ${b['startTime'] ?? ''} - ${b['endTime'] ?? ''} • ${b['careMode'] ?? ''}'),
              const SizedBox(height: 10),
              Text('Total: ${_money(b, _total(b))}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Paid to Book (CEO 20%): ${_money(b, _ceoFee(b))}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              Text('Pay Nurse CASH After Work (80%): ${_money(b, _nurseCash(b))}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                isRejected
                    ? 'Nurse rejected - Full 20% refund due to you: ${_money(b, _ceoFee(b))}. Book another nurse.'
                    : 'Terms: Nurse rejects = full 20% refund. You cancel before start = CEO keeps 20%. You cancel after start = CEO keeps 20% + you pay nurse cash for days worked.',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          if (!isTerminal(b))
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _cancelBooking(b);
              },
              child: const Text('Cancel Booking', style: TextStyle(color: Colors.red)),
            ),
          if (!isTerminal(b))
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _confirmCashPaid(b);
              },
              child: Text('Confirm Cash Paid - ${_money(b, _nurseCash(b))}'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = filter == 'All' ? bookings : bookings.where((b) => '${b['status']}'.toLowerCase() == filter.toLowerCase()).toList();
    final showing = filter == 'History' ? history : list;
    return Scaffold(
      appBar: AppBar(title: const Text('My Bookings'), backgroundColor: const Color(0xFFD81B60)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: ['All', 'Pending', 'Accepted', 'History'].map((f) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: filter == f,
                      onSelected: (_) => setState(() => filter = f),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.pink.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
            child: const Text(
              '20% CEO fee paid in app to book. 80% paid CASH to nurse after work. CEO never pays nurse. Cancel before start = CEO keeps 20%. Nurse rejects = full 20% refund.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFD81B60)))
                : showing.isEmpty
                    ? RefreshIndicator(
                        onRefresh: () async => _listenLive(),
                        child: ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('No bookings yet.\nTap Book Nurse to start.', textAlign: TextAlign.center)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async => _listenLive(),
                        child: ListView.builder(
                          itemCount: showing.length,
                          itemBuilder: (_, i) {
                            final b = showing[i];
                            final s = '${b['status'] ?? 'Pending'}';
                            final isRejected = s.toLowerCase().contains('reject');
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: InkWell(
                                onTap: () => _showDetails(b),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const CircleAvatar(backgroundColor: Color(0xFFD81B60), child: Icon(Icons.person, color: Colors.white)),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('${b['service'] ?? b['type'] ?? 'Nurse Booking'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                                Text('Status: $s\n${b['nurseName'] ?? 'Waiting for nurse...'}', style: const TextStyle(fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.arrow_forward_ios, size: 14),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text('Total: ${_money(b, _total(b))}  •  Paid 20%: ${_money(b, _ceoFee(b))}', style: const TextStyle(fontSize: 12)),
                                      Text('Pay Nurse CASH After Work: ${_money(b, _nurseCash(b))}', style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
                                      if (isRejected) Text('Nurse rejected - Full 20% refund due: ${_money(b, _ceoFee(b))}', style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      if (!isTerminal(b))
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton(
                                                onPressed: () => _cancelBooking(b),
                                                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () => _confirmCashPaid(b),
                                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)),
                                                child: Text('Cash Paid ${_money(b, _nurseCash(b))}', style: const TextStyle(fontSize: 11)),
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
