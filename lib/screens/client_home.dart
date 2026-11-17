import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'book_nurse.dart';
import 'book_nurse_50.dart';
import 'live_nurse_map.dart';

// CLIENT HOME - CLIENT FIRST
// - Client sees: Her name, Book Nurse FULL / 50%, My Bookings, Track Nurse LIVE like Uber
// - After paying, booking appears here instantly
// - Tap TRACK LIVE -> UberLiveMap opens, nurse photo blinks + moves
// - Client can call nurse, see balance, see status

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});
  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  String clientName = '';
  String clientPhone = '';
  String clientEmail = '';
  String clientId = '';
  bool _isLoading = true;
  List<Map> myBookings = [];
  StreamSubscription? _bookSub;
  int _selectedTab = 0; // 0 = Home, 1 = My Bookings

  @override
  void initState() {
    super.initState();
    _loadClient();
  }

  @override
  void dispose() {
    _bookSub?.cancel();
    super.dispose();
  }

  Future<void> _loadClient() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();
      clientName = prefs.getString('clientName') ?? prefs.getString('fullName') ?? user?.displayName ?? 'Client';
      clientPhone = prefs.getString('clientPhone') ?? prefs.getString('phone') ?? '';
      clientEmail = prefs.getString('clientEmail') ?? prefs.getString('email') ?? user?.email ?? '';
      clientId = user?.uid ?? prefs.getString('clientId') ?? '';
      if (!mounted) return;
      setState(() => _isLoading = false);
      _listenMyBookings();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _listenMyBookings() {
    if (clientEmail.isEmpty) return;
    final emailKey = clientEmail.trim().toLowerCase().replaceAll(RegExp(r'[.#\$@\[\]]'), '_');
    // Listen to bookingsByClient - this is where book_nurse.dart saves
    _bookSub = FirebaseDatabase.instance.ref('bookingsByClient/$emailKey').onValue.listen((e) {
      if (!mounted) return;
      final v = e.snapshot.value;
      if (v is! Map) {
        setState(() => myBookings = []);
        return;
      }
      List<Map> list = [];
      v.forEach((k, val) {
        if (val is Map) {
          final m = Map.from(val);
          m['bookingId'] = k.toString();
          list.add(m);
        }
      });
      // Newest first
      list.sort((a, b) => (b['createdAt'] ?? b['time'] ?? 0).toString().compareTo((a['createdAt'] ?? a['time'] ?? 0).toString()));
      setState(() => myBookings = list);
    });
  }

  Future<void> _callNurse(String phone) async {
    // Use url_launcher in real app: launchUrl(Uri.parse('tel:$phone'))
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Calling nurse: $phone')));
  }

  void _openTrackLive(Map b) {
    final nurseId = (b['nurseId'] ?? '').toString();
    final nurseName = (b['nurseName'] ?? 'Nurse').toString();
    if (nurseId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nurse not assigned yet')));
      return;
    }
    // Fetch nurse photo fresh - so map shows correct photo
    FirebaseDatabase.instance.ref('nurses/$nurseId').get().then((snap) {
      String photo = '';
      if (snap.exists && snap.value is Map) {
        final m = Map.from(snap.value as Map);
        photo = (m['photoURL'] ?? m['photo'] ?? m['profilePic'] ?? '').toString();
      }
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => _TrackLiveScreen(
        booking: b,
        nurseId: nurseId,
        nurseName: nurseName,
        nursePhoto: photo,
        nursePhone: (b['nursePhone'] ?? '').toString(),
        patientLat: _asDouble(b['patientLat']),
        patientLng: _asDouble(b['patientLng']),
      )));
    });
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFF0E0A1C), body: Center(child: CircularProgressIndicator(color: Colors.purple)));
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(
        title: const Text('Love Care Global', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF1A1633),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadClient)],
      ),
      body: _selectedTab == 0 ? _buildHome() : _buildMyBookings(),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1A1633),
        selectedItemColor: const Color(0xFFA855F7),
        unselectedItemColor: Colors.white54,
        currentIndex: _selectedTab,
        onTap: (i) => setState(() => _selectedTab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'My Bookings'),
        ],
      ),
    );
  }

  Widget _buildHome() {
    int activeCount = myBookings.where((b) => (b['status'] ?? 'pending').toString() == 'pending' || (b['status'] ?? '').toString() == 'accepted').length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // GREETING
        Container(
          width: double.infinity, padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hello $clientName 👋', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(clientPhone.isNotEmpty ? clientPhone : clientEmail, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: const Color(0xFFA855F7).withOpacity(0.2), borderRadius: BorderRadius.circular(20)), child: Text('📋 $activeCount Active Booking(s) • ${myBookings.length} Total', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
          ]),
        ),
        const SizedBox(height: 16),

        const Text('What do you need today?', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        // BOOK NURSE FULL
        Container(
          width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFA855F7).withOpacity(0.12), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.4))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('👩‍⚕️ Book Nurse - FULL Payment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Pay 100% now via Paystack. Nurse comes immediately. Watch her moving LIVE on map.', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const BookNurseScreen())); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Book Nurse - Pay FULL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
          ]),
        ),
        const SizedBox(height: 12),

        // BOOK NURSE 50%
        Container(
          width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF00C853).withOpacity(0.12), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF00C853).withOpacity(0.4))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('💳 Book Nurse - 50% Payment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Not all clients have full money before nurse starts. Pay 50% now, give 50% cash to nurse later.', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const BookNurse50Screen())); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C853), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Book Nurse - Pay 50% + Cash', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
          ]),
        ),
        const SizedBox(height: 16),

        // LATEST BOOKING PREVIEW
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Latest Bookings', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          TextButton(onPressed: () => setState(() => _selectedTab = 1), child: const Text('View All →', style: TextStyle(color: Color(0xFFA855F7)))),
        ]),
        const SizedBox(height: 8),
        if (myBookings.isEmpty)
          Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14)), child: const Center(child: Text('No bookings yet.\nTap Book Nurse above to book your first nurse.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60))))
        else
          ...myBookings.take(2).map((b) => _bookingCard(b)),
      ]),
    );
  }

  Widget _buildMyBookings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('My Bookings (${myBookings.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Tap TRACK LIVE to watch your nurse moving like Uber.', style: TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 12),
        if (myBookings.isEmpty)
          Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14)), child: const Center(child: Text('No bookings yet.\nGo to Home > Book Nurse', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60))))
        else
          ...myBookings.map((b) => _bookingCard(b)),
      ]),
    );
  }

  Widget _bookingCard(Map b) {
    final status = (b['status'] ?? 'pending').toString();
    Color statusColor = status == 'accepted' ? Colors.green : status == 'rejected' ? Colors.red : status == 'completed' ? Colors.blue : Colors.orange;
    final paymentType = (b['paymentType'] ?? '').toString();
    final is50 = paymentType.contains('50');
    final total = _asDouble(b['amount']);
    final paid = _asDouble(b['payNow'] ?? b['amountPaidNow']);
    final balance = _asDouble(b['payLater'] ?? b['amountBalance']);
    final currency = (b['currency'] ?? 'GHS').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${b['bookingId'] ?? ''}', style: const TextStyle(color: Colors.white60, fontSize: 11))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(20)), child: Text(status.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          CircleAvatar(radius: 24, backgroundColor: Colors.purple, child: const Text('👩', style: TextStyle(fontSize: 20))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${b['nurseName'] ?? 'Nurse'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            Text('Patient: ${b['patientName'] ?? ''} • ${b['patientLocation'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text('${b['startTime'] ?? ''} - ${b['endTime'] ?? ''} • ${b['careMode'] ?? ''} • ${b['totalHours'] ?? ''} hrs', style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ])),
        ]),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(is50 ? '50% Payment' : 'FULL Payment', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)), Text('$currency ${total.toStringAsFixed(2)} Total', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Paid Now', style: TextStyle(color: Colors.greenAccent, fontSize: 12)), Text('$currency ${paid.toStringAsFixed(2)}', style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold))]),
          if (balance > 0) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Balance - Cash to Nurse', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)), Text('$currency ${balance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold))]),
        ])),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: ElevatedButton.icon(onPressed: () => _openTrackLive(b), icon: const Icon(Icons.map, size: 18), label: const Text('TRACK LIVE', style: TextStyle(fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: () => _callNurse((b['nursePhone'] ?? '').toString()), icon: const Icon(Icons.phone, size: 18), label: const Text('Call Nurse'), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
        ]),
      ]),
    );
  }
}

// ===== TRACK LIVE SCREEN - UBER MAP FULL SCREEN =====
class _TrackLiveScreen extends StatelessWidget {
  final Map booking;
  final String nurseId;
  final String nurseName;
  final String nursePhoto;
  final String nursePhone;
  final double patientLat;
  final double patientLng;
  const _TrackLiveScreen({required this.booking, required this.nurseId, required this.nurseName, required this.nursePhoto, required this.nursePhone, required this.patientLat, required this.patientLng});

  @override
  Widget build(BuildContext context) {
    final status = (booking['status'] ?? 'pending').toString();
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: Text('Tracking $nurseName', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14)), child: Row(children: [
            CircleAvatar(radius: 26, backgroundImage: nursePhoto.isNotEmpty ? NetworkImage(nursePhoto) : null, backgroundColor: Colors.purple, child: nursePhoto.isEmpty ? const Text('👩') : null),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nurseName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text('Patient: ${booking['patientName'] ?? ''} • Status: ${status.toUpperCase()}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text('Booking: ${booking['bookingId'] ?? ''}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
            ])),
          ])),
          const SizedBox(height: 12),
          // UBER LIVE MAP - photo moves
          if (patientLat != 0 && patientLng != 0)
            UberLiveMap(nurseId: nurseId, nurseName: nurseName, nursePhoto: nursePhoto, patientLat: patientLat, patientLng: patientLng)
          else
            Container(height: 200, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(14)), child: const Center(child: Text('Patient location not found.\nAsk nurse to share location.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)))),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(12)), child: const Text('Keep this page open. Nurse photo will move as she travels. If photo is not moving, nurse has not tapped GO ONLINE or Location is not = Always.', textAlign: TextAlign.center, style: TextStyle(color: Colors.amber, fontSize: 12))),
        ]),
      ),
    );
  }
}
