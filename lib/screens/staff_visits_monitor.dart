import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// STAFF VISITS MONITOR - separate page, separate link.
/// CEO ONLY. Shows who visited CEO Dashboard, and exactly when.
///
/// Link:  .../#/staff-visits
///        .../#/staff-visits-monitor
///
/// What it shows:
///   - Every staff visit: Name, Username, Phone, Exact Time (day/month/year + hour:minute:second)
///   - Total visits today, total visits all time
///   - Search by name or username (e.g. type "kwaku" to see only Kwaku)
///   - Live updates: when a staff logs in, their visit appears here without refresh
///   - Clear All button: deletes the visit log (does NOT delete the staff - they can still login)
///
/// Where visits come from:
///   Staff Login writes every login to staffVisits + ceoNotifications + ceoLoginHistory.
///   This page reads staffVisits (live).

class StaffVisitsMonitorPage extends StatefulWidget {
  const StaffVisitsMonitorPage({super.key});
  @override
  State<StaffVisitsMonitorPage> createState() => _StaffVisitsMonitorPageState();
}

class _StaffVisitsMonitorPageState extends State<StaffVisitsMonitorPage> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _visits = [];
  bool _loading = true;
  String _search = '';

  static FirebaseDatabase? _cachedDb;
  FirebaseDatabase get _db {
    _cachedDb ??= FirebaseDatabase.instance;
    return _cachedDb!;
  }

  @override
  void initState() {
    super.initState();
    // Separate link per staff: .../#/staff-visits?username=kwaku.osei
    // Opens the monitor already filtered to only that one staff.
    try {
      final q = Uri.base.queryParameters;
      if ((q['username'] ?? '').isNotEmpty) {
        _search = q['username']!;
        _searchCtrl.text = q['username']!;
      }
      if ((q['name'] ?? '').isNotEmpty) {
        _search = q['name']!;
        _searchCtrl.text = q['name']!;
      }
    } catch (_) {}
    _startListening();
  }

  Future<void> _ensureAuth() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (_) {}
  }

  Future<void> _startListening() async {
    await _ensureAuth();
    // Live: new visit appears here the second a staff logs in
    _db.ref('staffVisits').orderByChild('timestamp').limitToLast(100).onValue.listen((e) {
      final list = <Map<String, dynamic>>[];
      if (e.snapshot.exists && e.snapshot.value is Map) {
        (e.snapshot.value as Map).forEach((k, v) {
          if (v is Map) list.add({'id': k.toString(), ...Map<String, dynamic>.from(v)});
        });
      }
      list.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
      if (mounted) setState(() { _visits = list; _loading = false; });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.trim().isEmpty) return _visits;
    final q = _search.trim().toLowerCase();
    return _visits.where((v) {
      final name = (v['name'] ?? '').toString().toLowerCase();
      final user = (v['username'] ?? '').toString().toLowerCase();
      final phone = (v['phone'] ?? '').toString();
      return name.contains(q) || user.contains(q) || phone.contains(q);
    }).toList();
  }

  int get _todayCount {
    final now = DateTime.now();
    return _visits.where((v) {
      final ts = (v['timestamp'] ?? 0) as num;
      final d = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).length;
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear visit log?'),
        content: const Text('This deletes ALL visit records from this monitor.\n\nIt does NOT delete the staff - they can still login. You will just lose the history of who visited.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Clear All')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _ensureAuth();
      await _db.ref('staffVisits').remove();
      await _db.ref('ceoNotifications').remove();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visit log cleared')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Clear failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0A1E),
        title: const Text('Staff Visits Monitor', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [TextButton(onPressed: _clearAll, child: const Text('Clear All', style: TextStyle(color: Colors.red)))],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Counters
            Row(
              children: [
                Expanded(child: _stat('Today', '$_todayCount')),
                const SizedBox(width: 12),
                Expanded(child: _stat('All Time', '${_visits.length}')),
              ],
            ),
            const SizedBox(height: 16),
            // Search
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search by name or username - e.g. kwaku',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: const Color(0xFF1A1633),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text('Who visited CEO Dashboard', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Newest first. Updates live - no refresh needed.', style: TextStyle(fontSize: 11, color: Color(0xFF9A95B8))),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFFACC15)))
                  : _filtered.isEmpty
                      ? const Center(child: Text('No visits yet\n\nWhen a staff logs in, they appear here.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6B6788), fontSize: 12)))
                      : ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final v = _filtered[i];
                            final name = (v['name'] ?? '').toString();
                            final user = (v['username'] ?? '').toString();
                            final phone = (v['phone'] ?? '').toString();
                            final time = (v['loginTime'] ?? '').toString();
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.08))),
                              child: Row(
                                children: [
                                  CircleAvatar(backgroundColor: const Color(0xFFFACC15), child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('$name ($user)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 2),
                                        Text('Visited CEO Dashboard', style: const TextStyle(fontSize: 11, color: Color(0xFF9A95B8))),
                                        const SizedBox(height: 2),
                                        Text(time, style: const TextStyle(fontSize: 12, color: Color(0xFFFACC15), fontWeight: FontWeight.bold)),
                                        if (phone.isNotEmpty) Text(phone, style: const TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.visibility, size: 18, color: Color(0xFFFACC15)),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFFACC15))),
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9A95B8))),
        ],
      ),
    );
  }
}

// Aliases
typedef StaffVisitsPage = StaffVisitsMonitorPage;
typedef StaffVisitsMonitorScreen = StaffVisitsMonitorPage;
typedef CEONotificationsPage = StaffVisitsMonitorPage;
