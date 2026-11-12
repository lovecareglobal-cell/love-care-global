import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';

// Alias for main.dart - main.dart calls CEOBookingProgressScreen
// This file's real class is CeoBookingsProgressPage
class CEOBookingProgressScreen extends CeoBookingsProgressPage {
  const CEOBookingProgressScreen({super.key});
}

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

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  void _loadAll() {
    for (final path in ['bookings', 'ceoBookings', 'allBookings']) {
      _db.child(path).onValue.listen((event) {
        if (event.snapshot.value == null) return;
        if (event.snapshot.value is! Map) return;
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        for (final entry in data.entries) {
          final id = entry.key.toString();
          if (id == 'LCG-20251016-ABC123') continue;
          if (entry.value is! Map) continue;
          final v = Map<String, dynamic>.from(entry.value as Map);
          final idx = allBookings.indexWhere((b) => b['id'] == id);
          final merged = {...v, 'id': id, 'bookingId': v['bookingId'] ?? id};
          if (idx == -1) {
            allBookings.add(merged);
          } else {
            allBookings[idx] = {...allBookings[idx], ...merged};
          }
        }
        if (mounted) setState(() {});
      });
    }
  }

  void _listenForSounds() {
    Future.delayed(const Duration(seconds: 2), () {
      _db.child('bookings').onChildChanged.listen((e) {
        final v = e.snapshot.value;
        if (v == null || v is! Map) return;
        final st = (Map<String, dynamic>.from(v as Map)['status'] ?? '').toString().toLowerCase();
        final k = '${e.snapshot.key}_$st';
        if (_seenKeys.contains(k)) return;
        _seenKeys.add(k);
        _playSound();
      });
      _db.child('bookings').onChildAdded.listen((e) {
        final v = e.snapshot.value;
        if (v == null || v is! Map) return;
        final m = Map<String, dynamic>.from(v as Map);
        final tt = m['time'] ?? m['createdAt'] ?? 0;
        final ttInt = tt is int ? tt : int.tryParse('$tt') ?? 0;
        if (DateTime.now().millisecondsSinceEpoch - ttInt > 120000) return;
        _playSound();
      });
    });
  }

  Future<void> _playSound() async {
    try {
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

  int _toInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  int get todayCount => allBookings.where((b) {
    final t = _toInt(b['time'] ?? b['createdAt'] ?? DateTime.now().millisecondsSinceEpoch);
    return DateTime.fromMillisecondsSinceEpoch(t).toString().substring(0, 10) == DateTime.now().toString().substring(0, 10);
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
    list.sort((a, b) => _toInt(b['time'] ?? 0).compareTo(_toInt(a['time'] ?? 0)));
    return list.take(100).toList();
  }

  void _viewDetails(Map b) {
    String fmt(dynamic t) {
      if (t == null) return 'Not yet';
      final v = _toInt(t);
      if (v == 0) return 'Not yet';
      return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(v));
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Booking: ${b['bookingId'] ?? b['id']}'),
        content: Text('Status: ${b['status']}\nNurse: ${b['nurseName']}\nClient: ${b['clientName']}\nAmount: ${b['currency'] ?? 'GHS'} ${b['amount']}\nTime: ${b['time'] != null ? fmt(b['time']) : ''}\nCompleted: ${b['clientConfirmedAt'] != null ? fmt(b['clientConfirmedAt']) : 'Not yet'}'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _trackNurse(String? nurseId, String bookingId) {
    if (nurseId == null || nurseId.isEmpty) { _toast('No nurse ID'); return; }
    Navigator.pushNamed(context, '/ceo-live-tracking-map', arguments: {'nurseId': nurseId, 'bookingId': bookingId});
    _toast('Tracking Nurse $nurseId...');
  }

  @override
  Widget build(BuildContext context) {
    final c = counts;
    final list = filtered;
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(
        title: const Text('Bookings Progress'),
        backgroundColor: const Color(0xFF1A1633),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: InkWell(
              onTap: () => Navigator.pushNamed(context, '/sound-settings'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFA855F7)])),
                child: const Text('Sound Settings', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(child: _stat('Total', '${c['all']}', 'GHS ${revenue.toStringAsFixed(0)}')),
                const SizedBox(width: 10),
                Expanded(child: _stat('Today', '$todayCount', 'Active Nurses: $activeNurses')),
                const SizedBox(width: 10),
                Expanded(child: _stat('Pending', '${c['pending']}', 'GHS ${pendingAmt.toStringAsFixed(0)}')),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                for (final f in ['all', 'pending', 'accepted', 'on_the_way', 'close', 'completed', 'client_confirmed', 'rejected'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('$f (${c[f] ?? 0})'),
                      selected: currentFilter == f,
                      onSelected: (_) => setState(() => currentFilter = f),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('No bookings yet', style: TextStyle(color: Colors.white)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final b = list[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text('${b['bookingId'] ?? b['id']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                Text('${b['status'] ?? ''}', style: const TextStyle(color: Color(0xFFFACC15), fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('Client: ${b['clientName'] ?? ''} | Nurse: ${b['nurseName'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            Text('Amount: ${b['currency'] ?? 'GHS'} ${b['amount'] ?? 0}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                TextButton(onPressed: () => _viewDetails(b), child: const Text('Details')),
                                TextButton(onPressed: () => _trackNurse(b['nurseId']?.toString(), '${b['bookingId'] ?? b['id']}'), child: const Text('Track Nurse')),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String title, String value, String sub) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}
