import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class ClientHomePage extends StatefulWidget {
  const ClientHomePage({super.key});

  @override
  State<ClientHomePage> createState() => _ClientHomePageState();
}

class _ClientHomePageState extends State<ClientHomePage> {
  bool _isLoading = true;
  String clientName = '';
  String clientPhone = '';
  String clientEmail = '';
  String clientId = '';
  String clientPhoto = ''; // NEW: client own photo

  List<Map<String, dynamic>> myBookings = [];
  int activeCount = 0;

  @override
  void initState() {
    super.initState();
    _loadClient();
  }

  // ---------- LOAD CLIENT + PHOTO ----------
  Future<void> _loadClient() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();
      clientName = prefs.getString('clientName') ??
          prefs.getString('fullName') ??
          user?.displayName ??
          'Client';
      clientPhone =
          prefs.getString('clientPhone') ?? prefs.getString('phone') ?? '';
      clientEmail =
          prefs.getString('clientEmail') ??
              prefs.getString('email') ??
              user?.email ??
              '';
      clientId = user?.uid ?? prefs.getString('clientId') ?? '';

      // 1. Try prefs / Auth photo first
      clientPhoto = prefs.getString('clientPhoto') ??
          prefs.getString('photoURL') ??
          prefs.getString('photo') ??
          prefs.getString('profilePic') ??
          user?.photoURL ??
          '';

      // 2. Try Firebase Realtime Database - clients / users
      if (clientId.isNotEmpty) {
        for (final path in [
          'clients/$clientId',
          'users/$clientId',
          'clientsById/$clientId'
        ]) {
          try {
            final snap = await FirebaseDatabase.instance.ref(path).get();
            if (snap.exists && snap.value is Map) {
              final m = Map.from(snap.value as Map);
              final p = (m['photoURL'] ??
                      m['photo'] ??
                      m['profilePic'] ??
                      m['profilePhoto'] ??
                      '')
                  .toString();
              final n = (m['fullName'] ?? m['name'] ?? m['clientName'] ?? '')
                  .toString();
              if (p.isNotEmpty) clientPhoto = p;
              if (n.isNotEmpty && clientName == 'Client') clientName = n;
              if (p.isNotEmpty) break;
            }
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
      _listenMyBookings();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------- LISTEN MY BOOKINGS ----------
  void _listenMyBookings() {
    if (clientId.isEmpty) return;
    FirebaseDatabase.instance
        .ref('bookings')
        .orderByChild('clientId')
        .equalTo(clientId)
        .onValue
        .listen((event) {
      final data = event.snapshot.value;
      List<Map<String, dynamic>> list = [];
      if (data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            final m = Map<String, dynamic>.from(value);
            m['id'] = key.toString();
            list.add(m);
          }
        });
      }
      // Newest first
      list.sort((a, b) {
        final at = (a['createdAt'] ?? 0).toString();
        final bt = (b['createdAt'] ?? 0).toString();
        return bt.compareTo(at);
      });
      if (!mounted) return;
      setState(() {
        myBookings = list;
        activeCount = list
            .where((b) =>
                (b['status'] ?? '').toString().toLowerCase() != 'completed' &&
                (b['status'] ?? '').toString().toLowerCase() != 'cancelled')
            .length;
      });
    });
  }

  String _formatDate(dynamic v) {
    try {
      if (v == null) return '';
      if (v is int) {
        return DateFormat('dd MMM yyyy, hh:mm a')
            .format(DateTime.fromMillisecondsSinceEpoch(v));
      }
      return v.toString();
    } catch (_) {
      return v.toString();
    }
  }

  Color _statusColor(String s) {
    final l = s.toLowerCase();
    if (l.contains('accept') || l.contains('confirm')) return Colors.green;
    if (l.contains('pend')) return Colors.orange;
    if (l.contains('complete')) return Colors.blue;
    if (l.contains('cancel') || l.contains('reject')) return Colors.red;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFFA855F7))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFA855F7),
        elevation: 0,
        title: Row(
          children: [
            // APP BAR PHOTO
            CircleAvatar(
              radius: 18,
              backgroundImage:
                  clientPhoto.isNotEmpty ? NetworkImage(clientPhoto) : null,
              backgroundColor: Colors.white,
              child: clientPhoto.isEmpty
                  ? Text(
                      clientName.isNotEmpty
                          ? clientName[0].toUpperCase()
                          : 'C',
                      style: const TextStyle(
                          color: Color(0xFFA855F7),
                          fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(clientName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                  Text(clientPhone.isNotEmpty ? clientPhone : clientEmail,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.pushNamed(context, '/client_settings');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------- GREETING ----------
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFA855F7), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    // CLIENT PHOTO - real photo, or first letter if no photo
                    CircleAvatar(
                      radius: 30,
                      backgroundImage: clientPhoto.isNotEmpty
                          ? NetworkImage(clientPhoto)
                          : null,
                      backgroundColor: Colors.white,
                      child: clientPhoto.isEmpty
                          ? Text(
                              clientName.isNotEmpty
                                  ? clientName[0].toUpperCase()
                                  : 'C',
                              style: const TextStyle(
                                  color: Color(0xFFA855F7),
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Hello $clientName 👋',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                                clientPhone.isNotEmpty
                                    ? clientPhone
                                    : clientEmail,
                                style: const TextStyle(
                                    color: Colors.white60, fontSize: 12)),
                          ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(
                          '📋 $activeCount Active Booking(s) • ${myBookings.length} Total',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold))),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ---------- QUICK ACTIONS ----------
            const Text('What do you need today?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _actionCard(
                        icon: Icons.search,
                        label: 'Book Nurse',
                        color: const Color(0xFFA855F7),
                        onTap: () =>
                            Navigator.pushNamed(context, '/book_nurse'))),
                const SizedBox(width: 12),
                Expanded(
                    child: _actionCard(
                        icon: Icons.list_alt,
                        label: 'My Bookings',
                        color: Colors.blue,
                        onTap: () {
                          // scroll to bookings - already on page
                        })),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _actionCard(
                        icon: Icons.chat,
                        label: 'Messages',
                        color: Colors.green,
                        onTap: () =>
                            Navigator.pushNamed(context, '/messages'))),
                const SizedBox(width: 12),
                Expanded(
                    child: _actionCard(
                        icon: Icons.person,
                        label: 'My Profile',
                        color: Colors.orange,
                        onTap: () => Navigator.pushNamed(
                            context, '/client_settings'))),
              ],
            ),

            const SizedBox(height: 22),

            // ---------- MY BOOKINGS ----------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('My Bookings',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('${myBookings.length} bookings',
                    style: const TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 12),

            if (myBookings.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16)),
                child: const Column(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 40, color: Colors.grey),
                    SizedBox(height: 10),
                    Text('No bookings yet',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('Book your first nurse to get started',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              )
            else
              ...myBookings.map((b) => _bookingCard(b)),
          ],
        ),
      ),
    );
  }

  Widget _actionCard(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            CircleAvatar(
                backgroundColor: color.withOpacity(0.1),
                child: Icon(icon, color: color)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _bookingCard(Map<String, dynamic> b) {
    final nurseName = (b['nurseName'] ?? b['nurseFullName'] ?? 'Nurse').toString();
    final nursePhoto = (b['nursePhoto'] ??
            b['nursePhotoURL'] ??
            b['photoURL'] ??
            b['photo'] ??
            b['profilePic'] ??
            '')
        .toString();
    final status = (b['status'] ?? 'Pending').toString();
    final service = (b['service'] ?? b['serviceType'] ?? 'Home Care').toString();
    final date = _formatDate(b['date'] ?? b['createdAt']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // NURSE PHOTO + NAME - real photo if saved, else first letter
          CircleAvatar(
            radius: 24,
            backgroundImage:
                nursePhoto.isNotEmpty ? NetworkImage(nursePhoto) : null,
            backgroundColor: Colors.purple,
            child: nursePhoto.isEmpty
                ? Text(
                    nurseName.isNotEmpty ? nurseName[0].toUpperCase() : 'N',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Text(nurseName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                            overflow: TextOverflow.ellipsis)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: _statusColor(status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(status,
                          style: TextStyle(
                              color: _statusColor(status),
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(service,
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 2),
                Text(date,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                if ((b['location'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('📍 ${b['location']}',
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
