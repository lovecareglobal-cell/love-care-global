import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClientDashboardScreen extends StatefulWidget {
  const ClientDashboardScreen({super.key});
  @override
  State<ClientDashboardScreen> createState() => _ClientDashboardScreenState();
}

class _ClientDashboardScreenState extends State<ClientDashboardScreen> {
  String clientName = 'Client';
  String clientPhone = '';
  int myBookingsCount = 0;
  int liveNursesCount = 0;
  DateTime ghanaNow = DateTime.now().toUtc();
  bool _disposed = false;

  StreamSubscription<DatabaseEvent>? _bookingsSub;
  StreamSubscription<DatabaseEvent>? _liveSub;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _loadClient();
    _listenBookingsCountLive();
    _loadLiveNursesCount();
    _startClock();
  }

  @override
  void dispose() {
    _disposed = true;
    _bookingsSub?.cancel();
    _liveSub?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadClient() async {
    final prefs = await SharedPreferences.getInstance();
    final auth = FirebaseAuth.instance.currentUser;
    if (!mounted) return;
    setState(() {
      clientName = prefs.getString('clientName') ?? prefs.getString('fullName') ?? auth?.displayName ?? 'Client';
      clientPhone = prefs.getString('clientPhone') ?? prefs.getString('phone') ?? auth?.phoneNumber ?? '';
    });
  }

  String normPhone(String? p) {
    if (p == null) return '';
    var d = p.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('233')) d = '0${d.substring(3)}';
    if (d.length > 10) d = d.substring(d.length - 10);
    return d;
  }

  void _listenBookingsCountLive() {
    _bookingsSub?.cancel();
    _bookingsSub = FirebaseDatabase.instance.ref('bookings').onValue.listen((e) {
      if (_disposed || !mounted) return;
      if (!e.snapshot.exists || e.snapshot.value == null) {
        setState(() => myBookingsCount = 0);
        return;
      }
      final val = e.snapshot.value;
      int count = 0;
      if (val is Map) {
        val.forEach((k, v) {
          if (v is Map) {
            final s = '${v['status'] ?? ''}'.toLowerCase();
            if (s.contains('complete') || s.contains('cancel') || s.contains('reject')) return;
            final p = normPhone('${v['clientPhone'] ?? v['phone'] ?? ''}');
            final u = '${v['clientId'] ?? v['userId'] ?? v['uid'] ?? ''}';
            final myP = normPhone(clientPhone);
            final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
            if ((myP.isEmpty && myUid.isEmpty) || p == myP || (u.isNotEmpty && u == myUid)) count++;
          }
        });
      }
      setState(() => myBookingsCount = count);
    }, onError: (_) {});
  }

  void _loadLiveNursesCount() {
    _liveSub?.cancel();
    _liveSub = FirebaseDatabase.instance.ref('onlineNurses').onValue.listen((e) {
      if (_disposed || !mounted) return;
      int count = 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (e.snapshot.exists && e.snapshot.value is Map) {
        (e.snapshot.value as Map).forEach((k, v) {
          if (v is Map) {
            final isOnline = v['isOnline'] == true || v['online'] == true;
            final lastSeen = int.tryParse('${v['lastSeen'] ?? v['timestamp'] ?? 0}') ?? 0;
            if (isOnline) {
              if (lastSeen == 0 || now - lastSeen < 2 * 60 * 1000) count++;
            } else if (lastSeen != 0 && now - lastSeen < 2 * 60 * 1000 && !v.containsKey('isOnline')) {
              count++;
            }
          } else if (v == true) count++;
        });
      }
      setState(() => liveNursesCount = count);
    });
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || !mounted) return;
      setState(() => ghanaNow = DateTime.now().toUtc());
    });
  }

  String get ghanaTime => DateFormat('EEE • MMM d, y • hh:mm:ss a').format(ghanaNow);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: const Color(0xFFD81B60),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hi, $clientName', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('$liveNursesCount ONLINE • $ghanaTime', style: const TextStyle(fontSize: 11)),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.notifications), onPressed: () {})],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFD81B60), borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  const CircleAvatar(radius: 28, backgroundColor: Colors.white, child: Text('C', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFD81B60)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(clientName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), Text(clientPhone, style: const TextStyle(color: Colors.white70))])),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)), child: Row(children: [const CircleAvatar(radius: 4, backgroundColor: Colors.green), const SizedBox(width: 5), Text('$liveNursesCount ONLINE', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))])),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _card('My Bookings', '$myBookingsCount Bookings', Icons.calendar_today, () => Navigator.pushNamed(context, '/my-bookings'))),
              const SizedBox(width: 12),
              Expanded(child: _card('Book Nurse', liveNursesCount > 0 ? 'LIVE • $liveNursesCount online' : 'No nurse online now', Icons.local_hospital, () => Navigator.pushNamed(context, '/book-nurse'))),
            ]),
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.access_time, color: Colors.grey), const SizedBox(width: 8), Text(ghanaTime, style: const TextStyle(fontWeight: FontWeight.bold))])),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, String sub, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: const Color(0xFFD81B60)), const SizedBox(height: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), Text(sub, style: const TextStyle(fontSize: 12, color: Colors.grey))]),
      ),
    );
  }
}
