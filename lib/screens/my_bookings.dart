import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    _bookingsSub?.cancel();
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
    return s.contains('complete') || s.contains('cancel') || s.contains('reject') || s.contains('done');
  }

  bool isHistory(Map v) => v['isHistory'] == true;
  num _asNum(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final list = filter == 'All' ? bookings : bookings.where((b) => '${b['status']}'.toLowerCase() == filter.toLowerCase()).toList();
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
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFD81B60)))
                : (filter == 'History' ? history : list).isEmpty
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
                          itemCount: (filter == 'History' ? history : list).length,
                          itemBuilder: (_, i) {
                            final b = (filter == 'History' ? history : list)[i];
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: ListTile(
                                leading: const CircleAvatar(backgroundColor: Color(0xFFD81B60), child: Icon(Icons.person, color: Colors.white)),
                                title: Text('${b['service'] ?? b['type'] ?? 'Nurse Booking'}'),
                                subtitle: Text('Status: ${b['status'] ?? 'Pending'}\n${b['nurseName'] ?? 'Waiting for nurse...'}'),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
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
