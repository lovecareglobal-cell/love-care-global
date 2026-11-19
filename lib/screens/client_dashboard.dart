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

  // LIVE BOOKINGS COUNT
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

  // LIVE ONLINE NURSES
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

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    try { await FirebaseAuth.instance.signOut(); } catch (_) {}
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    const pink = Color(0xFFE91E63);
    const darkPink = Color(0xFF880E4F);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: pink,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hi, $clientName', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            Text('$liveNursesCount ONLINE • $ghanaTime', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.notifications, color: Colors.white, size: 28), onPressed: () => Navigator.pushNamed(context, '/client-settings')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // TOP PROFILE CARD - SAME AS YOUR SCREENSHOT
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: pink, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white,
                    child: Text(clientName.isNotEmpty ? clientName[0].toUpperCase() : 'C', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: pink)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(clientName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(clientPhone, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                      ],
                    ),
                  ),
                  // FIXED ONLINE PILL - TEXT MUST SHOW, NO BE EMPTY AGAIN
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('$liveNursesCount ONLINE', style: const TextStyle(color: darkPink, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ===== YOUR DASHBOARD - ONLY BUTTONS =====
            // Row 1
            Row(children: [
              Expanded(child: _button('Book Nurse', Icons.local_hospital, liveNursesCount > 0 ? '$liveNursesCount nurse online' : 'No nurse online now', pink, () => Navigator.pushNamed(context, '/book-nurse'))),
              const SizedBox(width: 12),
              Expanded(child: _button('My Bookings', Icons.calendar_today, '$myBookingsCount Bookings', pink, () => Navigator.pushNamed(context, '/my-bookings'))),
            ]),
            const SizedBox(height: 12),
            // Row 2
            Row(children: [
              Expanded(child: _button('My Job Offer', Icons.work, 'View offers', pink, () => Navigator.pushNamed(context, '/my-job-offer'))),
              const SizedBox(width: 12),
              Expanded(child: _button('Book Nurse 50%', Icons.discount, '50% booking', pink, () => Navigator.pushNamed(context, '/book-nurse-50'))),
            ]),
            const SizedBox(height: 12),
            // Row 3
            Row(children: [
              Expanded(child: _button('SOS Emergency', Icons.sos, 'Emergency help', Colors.red, () => Navigator.pushNamed(context, '/sos'))),
              const SizedBox(width: 12),
              Expanded(child: _button('Complaint', Icons.report_problem, 'Report issue', pink, () => Navigator.pushNamed(context, '/client-complaint'))),
            ]),
            const SizedBox(height: 12),
            // Row 4
            Row(children: [
              Expanded(child: _button('Rate Nurse', Icons.star, 'Rate your nurse', pink, () => Navigator.pushNamed(context, '/rating'))),
              const SizedBox(width: 12),
              Expanded(child: _button('Refund Query', Icons.money_off, 'Refund help', pink, () => Navigator.pushNamed(context, '/refund-query'))),
            ]),
            const SizedBox(height: 12),
            // Row 5
            Row(children: [
              Expanded(child: _button('Increase Payment', Icons.add_card, 'Top up booking', pink, () => Navigator.pushNamed(context, '/increase-payment'))),
              const SizedBox(width: 12),
              Expanded(child: _button('Settings', Icons.settings, 'Profile & alerts', pink, () => Navigator.pushNamed(context, '/client-settings'))),
            ]),
            const SizedBox(height: 12),
            // Row 6 - Full width logout
            SizedBox(
              width: double.infinity,
              child: _button('Logout', Icons.logout, 'Sign out safely', darkPink, _logout),
            ),
            const SizedBox(height: 16),

            // TIME BAR - FIXED, TIME MUST SHOW
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [const Icon(Icons.access_time, color: Colors.grey, size: 22), const SizedBox(width: 10), Expanded(child: Text(ghanaTime, style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold)))]),
            ),
            const SizedBox(height: 20),
            const Text('© 2026 Love Care Global - Accra, Ghana', style: TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ONE BUTTON STYLE FOR ALL - TITLE ALWAYS VISIBLE, NO HIDDEN TEXT AGAIN
  Widget _button(String title, IconData icon, String subtitle, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
