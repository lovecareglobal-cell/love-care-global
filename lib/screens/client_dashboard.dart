import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

/// Client Dashboard - Flutter version of client-dashboard.html
/// - Profile: Avatar, Name, @username, Phone
/// - REAL DATE: Africa/Accra timezone, updates daily
/// - Grid: Book Nurse, My Bookings (count + real date), Settings, Complaint, Refund, Rating, SOS
/// - Sound Settings button
/// - Live Online Nurses count from onlineNurses
/// - My Bookings count: filter by phone last 9 digits / username / uid, exclude client_confirmed

class ClientDashboardScreen extends StatefulWidget {
  const ClientDashboardScreen({super.key});
  @override
  State<ClientDashboardScreen> createState() => _ClientDashboardScreenState();
}

class _ClientDashboardScreenState extends State<ClientDashboardScreen> {
  String clientName = 'Client';
  String username = '';
  String phone = '';
  String photo = '';
  String countryCode = '+233';
  int myBookingsCount = 0;
  int liveNursesCount = 0;
  DateTime ghanaNow = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadClient();
    _loadBookingsCount();
    _loadLiveNursesCount();
    _startClock();
  }

  void _startClock() {
    // Real date - update every minute, Ghana time = UTC+0
    Future.delayed(const Duration(minutes: 1), () {
      if (mounted) { setState(() => ghanaNow = DateTime.now().toUtc().add(const Duration(hours: 0))); _startClock(); }
    });
  }

  Future<void> _loadClient() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      clientName = prefs.getString('clientName') ?? prefs.getString('fullName') ?? prefs.getString('clientUsername') ?? 'Client';
      username = prefs.getString('clientUsername') ?? prefs.getString('username') ?? '';
      phone = prefs.getString('clientPhone') ?? prefs.getString('phone') ?? '';
      photo = prefs.getString('clientPhoto') ?? prefs.getString('clientPhotoUrl') ?? prefs.getString('photoUrl') ?? '';
      countryCode = prefs.getString('clientCountryCode') ?? '+233';
    });
    // Also fetch fresh from RTDB by username
    if (username.isNotEmpty) {
      final snap = await FirebaseDatabase.instance.ref('allowedClients/$username').get();
      if (snap.exists) {
        final d = Map<String, dynamic>.from(snap.value as Map);
        setState(() {
          clientName = d['fullName'] ?? d['name'] ?? clientName;
          phone = d['phone'] ?? phone;
          photo = d['photoUrl'] ?? d['photo'] ?? d['avatarUrl'] ?? photo;
        });
      }
    }
  }

  Future<void> _loadBookingsCount() async {
    final prefs = await SharedPreferences.getInstance();
    final myPhone = (prefs.getString('clientPhone') ?? prefs.getString('phone') ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final myUsername = (prefs.getString('clientUsername') ?? prefs.getString('username') ?? '').toLowerCase();
    final myUid = prefs.getString('lcg_client_uid') ?? prefs.getString('clientUid') ?? '';
    try {
      final snap = await FirebaseDatabase.instance.ref('bookings').get();
      if (!snap.exists) { setState(() => myBookingsCount = 0); return; }
      int count = 0;
      final map = snap.value as Map;
      map.forEach((key, val) {
        final b = Map<String, dynamic>.from(val as Map);
        final status = (b['status'] ?? '').toString().toLowerCase();
        if (status.contains('client_confirmed') || status.contains('client_confirmed_finished')) return;
        final bPhone = (b['clientPhone'] ?? b['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
        final phoneMatch = bPhone.isNotEmpty && myPhone.isNotEmpty && bPhone.length >= 9 && myPhone.length >= 9 && bPhone.substring(bPhone.length - 9) == myPhone.substring(myPhone.length - 9);
        final usernameMatch = b['clientUsername'] != null && myUsername.isNotEmpty && b['clientUsername'].toString().toLowerCase() == myUsername;
        final uidMatch = b['clientId'] != null && myUid.isNotEmpty && b['clientId'] == myUid;
        if (phoneMatch || usernameMatch || uidMatch) count++;
      });
      setState(() => myBookingsCount = count);
    } catch (_) {}
  }

  void _loadLiveNursesCount() {
    FirebaseDatabase.instance.ref('onlineNurses').onValue.listen((e) {
      final count = e.snapshot.exists ? (e.snapshot.value as Map).length : 0;
      setState(() => liveNursesCount = count);
    });
  }

  String get ghanaDate {
    // Africa/Accra = UTC+0, same as HTML toLocaleString with timeZone Africa/Accra
    final months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
    final weekdays = ['SUN','MON','TUE','WED','THU','FRI','SAT'];
    return '${weekdays[ghanaNow.weekday % 7]} • ${months[ghanaNow.month - 1]} ${ghanaNow.day}, ${ghanaNow.year}';
  }

  String get ghanaTime => DateFormat('hh:mm a').format(ghanaNow);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0A1C).withOpacity(0.96),
        title: const Text('LOVE CARE GLOBAL', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        actions: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: liveNursesCount > 0 ? Colors.green : Colors.red, borderRadius: BorderRadius.circular(20)), child: Text('🟢 $liveNursesCount ONLINE', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.emergency, color: Colors.red), onPressed: () => Navigator.pushNamed(context, '/sos')),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(children: [
          // Sound Settings - same as HTML top button
          Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 0), child: SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))), child: const Text('🔔 Sound Settings', style: TextStyle(fontWeight: FontWeight.bold))))),
          // Profile Card
          Container(
            margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.15))),
            child: Row(children: [
              CircleAvatar(radius: 32, backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null, child: photo.isEmpty ? Text(clientName.isNotEmpty ? clientName[0].toUpperCase() : 'C', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)) : null),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(clientName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                if (username.isNotEmpty) Text('@$username', style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 12)),
                if (phone.isNotEmpty) Text(phone, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text('📅 $ghanaDate • $ghanaTime', style: const TextStyle(color: Colors.white60, fontSize: 10)),
              ])),
              IconButton(icon: const Icon(Icons.settings, color: Colors.white70), onPressed: () {}),
            ]),
          ),
          // Grid - same as HTML gcard
          Padding(
            padding: const EdgeInsets.all(12),
            child: GridView.count(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.1,
              children: [
                _gridCard('🩺', 'Book Nurse', '🟢 LIVE • No shake • Fast online', const Color(0xFFA855F7), () => Navigator.pushNamed(context, '/book-nurse')),
                _gridCard('📅', 'My Bookings', '$myBookingsCount Bookings\n$ghanaDate', const Color(0xFF38BDF8), () => Navigator.pushNamed(context, '/my-bookings'), isBookings: true),
                _gridCard('⚙️', 'Client Settings', '', const Color(0xFF1E1B3A), () {}),
                _gridCard('📝', 'Complaint', '', const Color(0xFF1E1B3A), () {}),
                _gridCard('💰', 'Refund Query', 'Photo + Time Saved', const Color(0xFFFB923C), () {}),
                _gridCard('⭐', 'Rating', '', const Color(0xFFFACC15), () {}),
              ],
            ),
          ),
          // SOS Big
          Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 20), child: SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.emergency), label: const Text('🚨 Emergency SOS', style: TextStyle(fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFFACC15), width: 2))))),
          const Text('CEO: Asabere Peter • +233544121814', style: TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _gridCard(String emoji, String title, String subtitle, Color color, VoidCallback onTap, {bool isBookings = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]), borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
          if (subtitle.isNotEmpty) ...[const SizedBox(height: 4), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 11))],
          if (isBookings) ...[const SizedBox(height: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), child: Text('$myBookingsCount', style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 16)))],
        ]),
      ),
    );
  }
}
