import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  void _go(String route) {
    try {
      Navigator.pushNamed(context, route);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Opening $route failed: $e')));
    }
  }

  StreamSubscription<DatabaseEvent>? _liveSub;
  Timer? _clockTimer;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _loadClient();
    _loadBookingsCount();
    _loadLiveNursesCount();
    _startClock();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh when coming back from Client Settings after changing photo/name
    // Settings page should pop with true, but this also covers it
  }

  @override
  void dispose() {
    _disposed = true;
    _clockTimer?.cancel();
    _liveSub?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v == null) return {};
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_disposed || !mounted) return;
      setState(() => ghanaNow = DateTime.now().toUtc().add(const Duration(hours: 0)));
    });
  }

  // ---------- FIXED: LOAD OWNER (CLIENT) PHOTO + NAME FROM EVERYWHERE ----------
  Future<void> _loadClient() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;

    String name = prefs.getString('clientName') ??
        prefs.getString('fullName') ??
        prefs.getString('clientUsername') ??
        user?.displayName ??
        'Client';
    String uname = prefs.getString('clientUsername') ?? prefs.getString('username') ?? '';
    String ph = prefs.getString('clientPhone') ?? prefs.getString('phone') ?? user?.phoneNumber ?? '';
    String phPhoto = prefs.getString('clientPhoto') ??
        prefs.getString('clientPhotoUrl') ??
        prefs.getString('photoUrl') ??
        prefs.getString('photoURL') ??
        prefs.getString('photo') ??
        prefs.getString('profilePic') ??
        prefs.getString('avatarUrl') ??
        user?.photoURL ??
        '';
    String uid = user?.uid ?? prefs.getString('lcg_client_uid') ?? prefs.getString('clientUid') ?? prefs.getString('clientId') ?? '';

    if (mounted && !_disposed) {
      setState(() {
        clientName = name;
        username = uname;
        phone = ph;
        photo = phPhoto;
        countryCode = prefs.getString('clientCountryCode') ?? '+233';
      });
    }

    // Try ALL possible Firebase paths - not only allowedClients/$username
    final List<String> paths = [];
    if (uname.isNotEmpty) {
      paths.add('allowedClients/$uname');
      paths.add('clients/$uname');
      paths.add('users/$uname');
    }
    if (uid.isNotEmpty) {
      paths.add('allowedClients/$uid');
      paths.add('clients/$uid');
      paths.add('users/$uid');
      paths.add('clientsById/$uid');
    }

    for (final path in paths) {
      try {
        final snap = await FirebaseDatabase.instance.ref(path).get();
        if (!mounted || _disposed) return;
        if (!snap.exists) continue;
        final d = _asMap(snap.value);
        if (d.isEmpty) continue;

        final freshName = (d['fullName'] ?? d['name'] ?? d['clientName'] ?? d['displayName'] ?? '').toString();
        final freshPhone = (d['phone'] ?? d['clientPhone'] ?? d['phoneNumber'] ?? '').toString();
        final freshUser = (d['username'] ?? d['clientUsername'] ?? '').toString();
        final freshPhoto = (d['photoUrl'] ?? d['photoURL'] ?? d['photo'] ?? d['avatarUrl'] ?? d['profilePic'] ?? d['profilePhoto'] ?? d['imageUrl'] ?? '').toString();

        bool changed = false;
        if (freshName.isNotEmpty && freshName != 'Client' && freshName != clientName) {
          clientName = freshName; changed = true;
        }
        if (freshPhone.isNotEmpty && freshPhone != phone) { phone = freshPhone; changed = true; }
        if (freshUser.isNotEmpty && freshUser != username) { username = freshUser; changed = true; }
        if (freshPhoto.isNotEmpty && freshPhoto != photo) { photo = freshPhoto; changed = true; }

        if (changed && mounted && !_disposed) setState(() {});
        // If we found a full record with photo, stop. Else keep searching.
        if (freshName.isNotEmpty && freshPhoto.isNotEmpty) break;
        if (freshName.isNotEmpty && d.containsKey('photoUrl') == false && paths.indexOf(path) < 1) {
          // keep looking for photo in other paths
        }
      } catch (_) {}
    }

    // Save back to prefs so next open is instant, even offline
    try {
      await prefs.setString('clientName', clientName);
      await prefs.setString('clientPhoto', photo);
      if (username.isNotEmpty) await prefs.setString('clientUsername', username);
      if (phone.isNotEmpty) await prefs.setString('clientPhone', phone);
    } catch (_) {}
  }

  // Helper: photo can be http URL OR base64 data:image/... OR local path
  ImageProvider? _photoProvider() {
    if (photo.isEmpty) return null;
    final p = photo.trim();
    if (p.startsWith('http://') || p.startsWith('https://')) {
      return NetworkImage(p);
    }
    if (p.startsWith('data:image')) {
      try {
        final base64Str = p.split(',').last;
        return MemoryImage(base64Decode(base64Str));
      } catch (_) { return null; }
    }
    // Raw base64 without prefix
    if (p.length > 100 && !p.contains(' ') && !p.contains('/mnt/')) {
      try { return MemoryImage(base64Decode(p)); } catch (_) { return null; }
    }
    return null;
  }

  Future<void> _loadBookingsCount() async {
    final prefs = await SharedPreferences.getInstance();
    final myPhone = (prefs.getString('clientPhone') ?? prefs.getString('phone') ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final myUsername = (prefs.getString('clientUsername') ?? prefs.getString('username') ?? '').toLowerCase();
    final myUid = prefs.getString('lcg_client_uid') ?? prefs.getString('clientUid') ?? '';
    try {
      final snap = await FirebaseDatabase.instance.ref('bookings').get();
      if (!mounted || _disposed) return;
      if (!snap.exists || snap.value == null) { if (mounted) setState(() => myBookingsCount = 0); return; }
      int count = 0;
      final List<Map<String, dynamic>> items = [];
      if (snap.value is Map) {
        (snap.value as Map).forEach((key, val) { if (val is Map) items.add(Map<String, dynamic>.from(val)); });
      } else if (snap.value is List) {
        for (final val in (snap.value as List)) { if (val is Map) items.add(Map<String, dynamic>.from(val)); }
      }
      for (final b in items) {
        final status = (b['status'] ?? '').toString().toLowerCase();
        // FIXED: was `return` - killed whole loop. Must be `continue`
        if (status.contains('client_confirmed') || status.contains('client_confirmed_finished')) continue;
        final bPhone = (b['clientPhone'] ?? b['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
        final phoneMatch = bPhone.isNotEmpty && myPhone.isNotEmpty && bPhone.length >= 9 && myPhone.length >= 9 && bPhone.substring(bPhone.length - 9) == myPhone.substring(myPhone.length - 9);
        final usernameMatch = b['clientUsername'] != null && myUsername.isNotEmpty && b['clientUsername'].toString().toLowerCase() == myUsername;
        final uidMatch = b['clientId'] != null && myUid.isNotEmpty && b['clientId'] == myUid;
        if (phoneMatch || usernameMatch || uidMatch) count++;
      }
      if (mounted && !_disposed) setState(() => myBookingsCount = count);
    } catch (_) {}
  }

  void _loadLiveNursesCount() {
    _liveSub?.cancel();
    _liveSub = FirebaseDatabase.instance.ref('onlineNurses').onValue.listen((e) {
      if (_disposed || !mounted) return;
      int count = 0;
      try {
        if (e.snapshot.exists && e.snapshot.value != null) {
          final v = e.snapshot.value;
          if (v is Map) { count = v.length; }
          else if (v is List) { count = v.where((x) => x != null).length; }
          else if (v is int) { count = v; }
        }
      } catch (_) { count = 0; }
      if (mounted && !_disposed) setState(() => liveNursesCount = count);
    }, onError: (_) {});
  }

  String get ghanaDate {
    final months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
    final weekdays = ['SUN','MON','TUE','WED','THU','FRI','SAT'];
    return '${weekdays[ghanaNow.weekday % 7]} • ${months[ghanaNow.month - 1]} ${ghanaNow.day}, ${ghanaNow.year}';
  }

  String get ghanaTime => DateFormat('hh:mm a').format(ghanaNow);

  @override
  Widget build(BuildContext context) {
    final img = _photoProvider();
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0A1C).withOpacity(0.96),
        title: const Text('LOVE CARE GLOBAL', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        actions: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: liveNursesCount > 0 ? Colors.green : Colors.red, borderRadius: BorderRadius.circular(20)), child: Text('🟢 $liveNursesCount ONLINE', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.emergency, color: Colors.red), onPressed: () => _go('/sos')),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 0), child: SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => _go('/sound-settings'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))), child: const Text('🔔 Sound Settings', style: TextStyle(fontWeight: FontWeight.bold))))),
          // Profile Card - OWNER PHOTO + NAME
          Container(
            margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.15))),
            child: Row(children: [
              // OWNER PHOTO: real photo if exists, else first letter
              CircleAvatar(
                radius: 32,
                backgroundImage: img,
                backgroundColor: const Color(0xFFA855F7),
                onBackgroundImageError: (_, __) {},
                child: img == null ? Text(clientName.isNotEmpty ? clientName[0].toUpperCase() : 'C', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)) : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // OWNER NAME: real name, not CLIENT
                Text(clientName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                if (username.isNotEmpty) Text('@$username', style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 12)),
                if (phone.isNotEmpty) Text(phone, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text('📅 $ghanaDate • $ghanaTime', style: const TextStyle(color: Colors.white60, fontSize: 10)),
              ])),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white70),
                onPressed: () async {
                  // After Settings, reload photo/name
                  await Navigator.pushNamed(context, '/client-settings');
                  if (mounted) _loadClient();
                },
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: GridView.count(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.1,
              children: [
                _gridCard('🩺', 'Book Nurse', '🟢 LIVE • No shake • Fast online', const Color(0xFFA855F7), () => _go('/book-nurse')),
                _gridCard('📅', 'My Bookings', '$myBookingsCount Bookings\n$ghanaDate', const Color(0xFF38BDF8), () => _go('/my-bookings'), isBookings: true),
                _gridCard('⚙️', 'Client Settings', 'Profile • Photo • Phone', const Color(0xFF1E1B3A), () => _go('/client-settings')),
                _gridCard('📝', 'Complaint', 'Report a problem', const Color(0xFF1E1B3A), () => _go('/client-complaint')),
                _gridCard('💰', 'Refund Query', 'Photo + Time Saved', const Color(0xFFFB923C), () => _go('/refund-query')),
                _gridCard('⭐', 'Rating', 'Rate your nurse', const Color(0xFFFACC15), () => _go('/rating')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _go('/sos'),
                icon: const Icon(Icons.emergency),
                label: const Text('🚨 Emergency SOS', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFFACC15), width: 2),
                  ),
                ),
              ),
            ),
          ),
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
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
