
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';

class CeoBookingsProgressPage extends StatefulWidget {
  const CeoBookingsProgressPage({super.key});
  @override
  State<CeoBookingsProgressPage> createState() => _CeoBookingsProgressPageState();
}

class _CeoBookingsProgressPageState extends State<CeoBookingsProgressPage> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final AudioPlayer _audio = AudioPlayer();

  List<Map<String, dynamic>> allBookings = [];
  String currentFilter = 'all';
  final Set<String> _seenKeys = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
    _listenForSounds();
  }

  void _loadAll() {
    for (final path in ['bookings', 'ceoBookings', 'allBookings']) {
      _db.child(path).onValue.listen((event) {
        if (event.snapshot.value == null) return;
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        for (final entry in data.entries) {
          final id = entry.key;
          if (id == 'LCG-20251016-ABC123') continue;
          final v = Map<String, dynamic>.from(entry.value as Map);
          final idx = allBookings.indexWhere((b) => b['id'] == id);
          final merged = {...v, 'id': id, 'bookingId': v['bookingId'] ?? id};
          if (idx == -1) {
            allBookings.add(merged);
          } else {
            allBookings[idx] = {...allBookings[idx], ...merged};
          }
        }
        setState(() {});
      });
    }
  }

  void _listenForSounds() {
    Future.delayed(const Duration(seconds: 2), () {
      _db.child('bookings').onChildChanged.listen((e) {
        final v = e.snapshot.value;
        if (v == null) return;
        final st = (Map<String, dynamic>.from(v as Map)['status'] ?? '').toString().toLowerCase();
        final k = '${e.snapshot.key}_$st';
        if (_seenKeys.contains(k)) return;
        _seenKeys.add(k);
        _playSound();
      });
      _db.child('bookings').onChildAdded.listen((e) {
        final v = Map<String, dynamic>.from(e.snapshot.value as Map);
        final tt = (v['time'] ?? v['createdAt'] ?? 0) as int;
        if (DateTime.now().millisecondsSinceEpoch - tt > 120000) return;
        _playSound();
      });
    });
  }

  Future<void> _playSound() async {
    try {
      // Same as your HTML: bell 3 times + vibrate logic is native in app
      await _audio.play(AssetSource('sounds/bell.mp3'));
    } catch (_) {}
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ===== COUNTS + STATS - Same logic as your HTML =====
  Map<String, int> get counts {
    final c = {'all': allBookings.length, 'pending': 0, 'accepted': 0, 'on_the_way': 0, 'close': 0, 'completed': 0, 'client_confirmed': 0, 'rejected': 0};
    for (final b in allBookings) {
      final s = (b['status'] ?? 'pending').toString().toLowerCase();
      if (s.contains('pending')) c['pending'] = c['pending']! + 1;
      else if (s == 'accepted') c['accepted'] = c['accepted']! + 1;
      else if (s.contains('on_the_way')) c['on_the_way'] = c['on_the_way']! + 1;
      else if (s.contains('close')) c['close'] = c['close']! + 1;
      else if (s.contains('completed') || s == 'finished') c['completed'] = c['completed']! + 1;
      else if (s.contains('client_confirmed')) c['client_confirmed'] = c['client_confirmed']! + 1;
      else if (s.contains('rejected')) c['rejected'] = c['rejected']! + 1;
    }
    return c;
  }

  double get revenue => allBookings.fold(0, (p, b) => p + (double.tryParse('${b['amount'] ?? 0}') ?? 0));
  double get pendingAmt => allBookings.where((b) => (b['status'] ?? '').toString().toLowerCase().contains('pending')).fold(0, (p, b) => p + (double.tryParse('${b['amount'] ?? 0}') ?? 0));
  double get acceptedAmt => allBookings.where((b) { final s = (b['status'] ?? '').toString().toLowerCase(); return s == 'accepted' || s.contains('on_the_way') || s.contains('close'); }).fold(0, (p, b) => p + (double.tryParse('${b['amount'] ?? 0}') ?? 0));
  double get completedAmt => allBookings.where((b) { final s = (b['status'] ?? '').toString().toLowerCase(); return s.contains('completed') || s.contains('client_confirmed'); }).fold(0, (p, b) => p + (double.tryParse('${b['amount'] ?? 0}') ?? 0));
  int get todayCount => allBookings.where((b) {
    final t = b['time'] ?? b['createdAt'] ?? DateTime.now().millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(t is int ? t : 0).toString().substring(0, 10) == DateTime.now().toString().substring(0, 10);
  }).length;
  int get activeNurses => allBookings.where((b) { final s = (b['status'] ?? '').toString().toLowerCase(); return s == 'accepted' || s.contains('on_the_way') || s.contains('close'); }).map((b) => b['nurseId']).toSet().length;

  List<Map<String, dynamic>> get filtered {
    var list = List<Map<String, dynamic>>.from(allBookings);
    if (currentFilter != 'all') {
      if (currentFilter == 'completed') {
        list = list.where((b) { final s = (b['status'] ?? '').toString().toLowerCase(); return s.contains('completed') || s.contains('finished') || s.contains('client_confirmed'); }).toList();
      } else if (currentFilter == 'client_confirmed') {
        list = list.where((b) => (b['status'] ?? '').toString().toLowerCase().contains('client_confirmed')).toList();
      } else {
        list = list.where((b) => (b['status'] ?? '').toString().toLowerCase().contains(currentFilter)).toList();
      }
    }
    list.sort((a, b) => ((b['time'] ?? 0) as int).compareTo((a['time'] ?? 0) as int));
    return list.take(100).toList();
  }

  void _viewDetails(Map b) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Booking: ${b['bookingId'] ?? b['id']}'),
        content: Text('Status: ${b['status']}\nNurse: ${b['nurseName']}\nClient: ${b['clientName']}\nAmount: ${b['currency'] ?? 'GHS'} ${b['amount']}\nTime: ${b['time'] != null ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(b['time'])) : ''}\nCompleted: ${b['clientConfirmedAt'] != null ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(b['clientConfirmedAt'])) : 'Not yet'}'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _trackNurse(String? nurseId, String bookingId) {
    if (nurseId == null || nurseId.isEmpty) { _toast('No nurse ID'); return; }
    // In Flutter we push the tracking page instead of window.open
    Navigator.pushNamed(context, '/ceo-live-tracking', arguments: {'nurseId': nurseId, 'bookingId': bookingId});
    _toast('Tracking Nurse $nurseId...');
  }

  @override
  Widget build(BuildContext context) {
    final c = counts;
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      body: Column(
        children: [
          // SOUND SETTINGS BUTTON - Same as your HTML top link
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: InkWell(
              onTap: () => Navigator.pushNamed(context, '/sound-settings'),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFA855F7)])),
                child: const Text('🔔 Sound Settings', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
