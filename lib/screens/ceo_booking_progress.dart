import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class CEOBookingsProgressScreen extends StatefulWidget {
  const CEOBookingsProgressScreen({super.key});
  @override
  State<CEOBookingsProgressScreen> createState() => _CEOBookingsProgressScreenState();
}

// Aliases - so main.dart + old files still work
class CEOBookingsProgressPage extends CEOBookingsProgressScreen {
  const CEOBookingsProgressPage({super.key});
}
class CeoBookingsProgressScreen extends CEOBookingsProgressScreen {
  const CeoBookingsProgressScreen({super.key});
}
class CEOBookingProgressScreen extends CEOBookingsProgressScreen {
  const CEOBookingProgressScreen({super.key});
}

class _CEOBookingsProgressScreenState extends State<CEOBookingsProgressScreen> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  List<Map<String, dynamic>> allBookings = [];
  String currentFilter = 'all';
  bool isLoading = true;

  final List<Map<String, String>> filters = [
    {'key': 'all', 'label': 'All'},
    {'key': 'pending', 'label': 'Pending'},
    {'key': 'accepted', 'label': 'Accepted'},
    {'key': 'on_the_way', 'label': 'On The Way'},
    {'key': 'close', 'label': 'Close'},
    {'key': 'completed', 'label': 'Completed'},
    {'key': 'client_confirmed', 'label': 'Client Confirmed'},
    {'key': 'rejected', 'label': 'Rejected'},
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _loadAll() {
    // Same as HTML: ['bookings','ceoBookings','allBookings']
    for (final path in ['bookings', 'ceoBookings', 'allBookings']) {
      _db.child(path).onValue.listen((e) {
        if (e.snapshot.value == null || e.snapshot.value is! Map) return;
        final data = Map<String, dynamic>.from(e.snapshot.value as Map);
        for (final entry in data.entries) {
          if (entry.value is! Map) continue;
          final v = Map<String, dynamic>.from(entry.value as Map);
          final id = entry.key.toString();
          if (id == 'LCG-20251016-ABC123') continue; // skip test - same as HTML
          _addOrUpdate({...v, 'id': id, 'bookingId': (v['bookingId'] ?? id).toString()});
        }
        if (mounted) setState(() => isLoading = false);
      });
    }
  }

  void _addOrUpdate(Map<String, dynamic> b) {
    final id = (b['id'] ?? b['bookingId'] ?? '').toString();
    final idx = allBookings.indexWhere((x) => (x['id'] ?? x['bookingId'] ?? '').toString() == id);
    if (idx == -1) {
      allBookings.add(b);
    } else {
      allBookings[idx] = {...allBookings[idx], ...b};
    }
  }

  String _statusOf(Map<String, dynamic> b) => (b['status'] ?? '').toString().toLowerCase();

  // Same filter logic as HTML render()
  List<Map<String, dynamic>> get filtered {
    List<Map<String, dynamic>> list = List.from(allBookings);
    if (currentFilter == 'all') {
      // all
    } else if (currentFilter == 'pending') {
      list = list.where((b) => _statusOf(b) == 'pending' || _statusOf(b).contains('pending')).toList();
    } else if (currentFilter == 'accepted') {
      list = list.where((b) => _statusOf(b) == 'accepted').toList();
    } else if (currentFilter == 'on_the_way') {
      list = list.where((b) => _statusOf(b).contains('on_the_way') || _statusOf(b).contains('on the way') || _statusOf(b).contains('ontheway')).toList();
    } else if (currentFilter == 'close') {
      list = list.where((b) => _statusOf(b).contains('close')).toList();
    } else if (currentFilter == 'completed') {
      list = list.where((b) => _statusOf(b).contains('completed') || _statusOf(b) == 'finished').toList();
    } else if (currentFilter == 'client_confirmed') {
      list = list.where((b) => _statusOf(b).contains('client_confirmed')).toList();
    } else if (currentFilter == 'rejected') {
      list = list.where((b) => _statusOf(b).contains('rejected') || _statusOf(b).contains('cancelled')).toList();
    }
    list.sort((a, b) {
      final ta = int.tryParse('${a['time'] ?? a['createdAt'] ?? 0}') ?? 0;
      final tb = int.tryParse('${b['time'] ?? b['createdAt'] ?? 0}') ?? 0;
      return tb.compareTo(ta);
    });
    return list.take(100).toList();
  }

  int _count(String key) {
    if (key == 'all') return allBookings.length;
    if (key == 'pending') return allBookings.where((b) => _statusOf(b).contains('pending')).length;
    if (key == 'accepted') return allBookings.where((b) => _statusOf(b) == 'accepted').length;
    if (key == 'on_the_way') return allBookings.where((b) => _statusOf(b).contains('on_the_way')).length;
    if (key == 'close') return allBookings.where((b) => _statusOf(b).contains('close')).length;
    if (key == 'completed') return allBookings.where((b) => _statusOf(b).contains('completed') || _statusOf(b) == 'finished').length;
    if (key == 'client_confirmed') return allBookings.where((b) => _statusOf(b).contains('client_confirmed')).length;
    if (key == 'rejected') return allBookings.where((b) => _statusOf(b).contains('rejected') || _statusOf(b).contains('cancelled')).length;
    return 0;
  }

  double _amountFor(List<Map<String, dynamic>> list) {
    double total = 0;
    for (final b in list) {
      total += double.tryParse('${b['amount'] ?? 0}') ?? 0;
    }
    return total;
  }

  String _timeStr(dynamic t) {
    final v = int.tryParse('$t') ?? 0;
    if (v == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(v);
    return '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  (String, Color, Color, Color) _badgeFor(String s) {
    // returns (label, bg, fg, border)
    if (s == 'accepted') return ('ACCEPTED', const Color(0xFF22C55E).withOpacity(0.15), const Color(0xFF86EFAC), const Color(0xFF22C55E));
    if (s.contains('on_the_way')) return ('ON THE WAY', const Color(0xFF22C55E).withOpacity(0.15), const Color(0xFF86EFAC), const Color(0xFF22C55E));
    if (s.contains('close')) return ('CLOSE', const Color(0xFF22C55E).withOpacity(0.15), const Color(0xFF86EFAC), const Color(0xFF22C55E));
    if (s.contains('completed') || s == 'finished') return ('COMPLETED', const Color(0xFF22C55E).withOpacity(0.15), const Color(0xFF86EFAC), const Color(0xFF22C55E));
    if (s.contains('client_confirmed')) return ('CLIENT CONFIRMED - WORK COMPLETED', const Color(0xFF22C55E), Colors.white, const Color(0xFF22C55E));
    if (s.contains('rejected')) return ('REJECTED', const Color(0xFFEF4444).withOpacity(0.15), const Color(0xFFFCA5A5), const Color(0xFFEF4444));
    if (s.contains('cancelled')) return ('CANCELLED', const Color(0xFFEF4444).withOpacity(0.15), const Color(0xFFFCA5A5), const Color(0xFFEF4444));
    return ('PENDING', const Color(0xFFF59E0B).withOpacity(0.15), const Color(0xFFFDE68A), const Color(0xFFF59E0B));
  }

  Color _borderFor(String s) {
    if (s.contains('client_confirmed')) return const Color(0xFF22C55E);
    if (s == 'accepted') return const Color(0xFF22C55E);
    if (s.contains('rejected') || s.contains('cancelled')) return const Color(0xFFEF4444);
    return const Color(0xFFF59E0B);
  }

  void _viewDetails(Map<String, dynamic> b) {
    // Same as HTML alert() -> Flutter Dialog
    final time = _timeStr(b['time'] ?? b['createdAt']);
    final completed = b['clientConfirmedAt'] != null ? _timeStr(b['clientConfirmedAt']) : 'Not yet';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1633),
        title: const Text('Booking Details', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ID: ${b['bookingId'] ?? b['id']}', style: const TextStyle(color: Colors.white)),
              Text('Status: ${b['status']}', style: const TextStyle(color: Colors.white)),
              Text('Nurse: ${b['nurseName'] ?? 'Unknown'}', style: const TextStyle(color: Colors.white)),
              Text('Client: ${b['clientName'] ?? 'Client'}', style: const TextStyle(color: Colors.white)),
              Text('Amount: ${b['currency'] ?? 'GHS'} ${b['amount'] ?? 0}', style: const TextStyle(color: Colors.white)),
              Text('Time: $time', style: const TextStyle(color: Colors.white)),
              Text('Completed: $completed', style: const TextStyle(color: Colors.white)),
              if ((b['patientLocation'] ?? '').toString().isNotEmpty) Text('Location: ${b['patientLocation']}', style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _trackNurse(Map<String, dynamic> b) {
    final nurseId = (b['nurseId'] ?? '').toString();
    final bookingId = (b['bookingId'] ?? b['id'] ?? '').toString();
    if (nurseId.isEmpty) { _toast('No nurse ID'); return; }
    // Same as HTML window.open('ceo-live-tracking-map.html?nurseId=&bookingId=') -> Flutter route
    Navigator.pushNamed(context, '/ceo-live-tracking', arguments: {'nurseId': nurseId, 'bookingId': bookingId});
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    final pendingList = allBookings.where((b) => _statusOf(b).contains('pending')).toList();
    final acceptedList = allBookings.where((b) => _statusOf(b) == 'accepted').toList();
    final completedList = allBookings.where((b) => _statusOf(b).contains('completed') || _statusOf(b).contains('client_confirmed') || _statusOf(b) == 'finished').toList();
    final today = DateTime.now();
    final todayList = allBookings.where((b) {
      final t = int.tryParse('${b['time'] ?? b['createdAt'] ?? 0}') ?? 0;
      if (t == 0) return false;
      final d = DateTime.fromMillisecondsSinceEpoch(t);
      return d.year == today.year && d.month == today.month && d.day == today.day;
    }).toList();
    final activeNurseIds = <String>{};
    for (final b in allBookings) {
      final s = _statusOf(b);
      if (s == 'accepted' || s.contains('on_the_way') || s.contains('close')) {
        final nid = (b['nurseId'] ?? '').toString();
        if (nid.isNotEmpty) activeNurseIds.add(nid);
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0A1E),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CEO Bookings Progress - All Live Bookings', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            Text('Real-time: Pending, Accepted, On the way, Close, Completed, Rejected', style: TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
          ],
        ),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          Chip(label: Text('${allBookings.length} Total', style: const TextStyle(fontSize: 11)), backgroundColor: Colors.white.withOpacity(0.06)),
          TextButton(onPressed: () => Navigator.pushNamed(context, '/ceo-dashboard'), child: const Text('CEO Dashboard', style: TextStyle(color: Colors.white, fontSize: 11))),
          TextButton(onPressed: () => Navigator.pushNamed(context, '/ceo-notification-room'), child: const Text('Notification Room', style: TextStyle(color: Color(0xFFC4B5FD), fontSize: 11))),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() => isLoading = true)),
        ],
      ),
      body: Column(
        children: [
          // Tabs - same as HTML .tabs
          Container(
            height: 56,
            color: const Color(0xFF1A1633).withOpacity(0.5),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: filters.length,
              itemBuilder: (context, i) {
                final f = filters[i];
                final isActive = currentFilter == f['key'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${f['label']} (${_count(f['key']!)} )', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isActive ? Colors.black : const Color(0xFF9A95B8))),
                    selected: isActive,
                    selectedColor: const Color(0xFFFACC15),
                    backgroundColor: Colors.white.withOpacity(0.05),
                    onSelected: (_) => setState(() => currentFilter = f['key']!),
                  ),
                );
              },
            ),
          ),
          // Stats - same as HTML .stats
          Container(
            padding: const EdgeInsets.all(14),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.6,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: [
                _stat('Pending', '${pendingList.length}', 'GHS ${_amountFor(pendingList).toStringAsFixed(0)}'),
                _stat('Accepted', '${acceptedList.length}', 'GHS ${_amountFor(acceptedList).toStringAsFixed(0)}'),
                _stat('Completed', '${completedList.length}', 'GHS ${_amountFor(completedList).toStringAsFixed(0)}'),
                _stat('Total Revenue', 'GHS ${_amountFor(allBookings).toStringAsFixed(0)}', 'All bookings'),
                _stat('Active Nurses', '${activeNurseIds.length}', 'On jobs'),
                _stat('Today', '${todayList.length}', 'Bookings today'),
              ],
            ),
          ),
          // List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFACC15)))
                : list.isEmpty
                    ? Center(child: Text('No $currentFilter bookings', style: const TextStyle(color: Color(0xFF9A95B8))))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final b = list[i];
                          final s = _statusOf(b);
                          final badge = _badgeFor(s);
                          final timeStr = b['time'] != null ? _timeStr(b['time']) : (b['createdAt'] != null ? _timeStr(b['createdAt']) : '');
                          final completedAt = b['clientConfirmedAt'] != null ? _timeStr(b['clientConfirmedAt']) : (b['completedAt'] != null ? _timeStr(b['completedAt']) : '');
                          final bookingId = (b['bookingId'] ?? b['id'] ?? 'Unknown').toString();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.08))),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(width: 4, decoration: BoxDecoration(color: _borderFor(s), borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), bottomLeft: Radius.circular(14)))),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(child: Text('Booking: $bookingId', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white10)), child: Text('ID: ${bookingId.length > 8 ? bookingId.substring(bookingId.length - 8) : bookingId}', style: const TextStyle(fontSize: 10, color: Colors.white70))),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: badge.$2, borderRadius: BorderRadius.circular(999)), child: Text(badge.$1, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: badge.$3))),
                                          const SizedBox(height: 8),
                                          Text('Nurse: ${b['nurseName'] ?? 'Unknown'}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                          Text('Client: ${b['clientName'] ?? 'Client'}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                          Text('Location: ${b['patientLocation'] ?? 'N/A'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                          Text('Amount: ${b['currency'] ?? 'GHS'} ${b['amount'] ?? 0}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                          Text('Booked: $timeStr', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                          if (completedAt.isNotEmpty) Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Text('Work Completed: $completedAt', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 8,
                                            children: [
                                              ElevatedButton(onPressed: () => _viewDetails(b), style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.08), foregroundColor: Colors.white), child: const Text('View Details', style: TextStyle(fontSize: 12))),
                                              ElevatedButton(onPressed: () => _trackNurse(b), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), foregroundColor: Colors.black), child: const Text('Track Nurse', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, String sub) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF9A95B8), fontSize: 10)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          Text(sub, style: const TextStyle(color: Color(0xFF9A95B8), fontSize: 10)),
        ],
      ),
    );
  }
}
