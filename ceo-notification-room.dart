import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// CEO Notification Room - Flutter version of ceo-notification-room.html
/// - Loads LIVE: ceoNotifications (limitToLast 100) + ceoNotificationRoom (limitToLast 100), dedupe by key (merge updates), sorted createdAt desc — same as HTML loadAll()
/// - Badge: "{filtered} Notifications - {unread} Unread" — same as HTML render()
/// - Filter: filterType(t) — filter by type OR title contains filter (case-insensitive). Filters: all / booking / withdrawal / completed / accepted / on_the_way / close — same as HTML
/// - Card: type badge BOOKING / WITHDRAWAL (type includes withdrawal) / COMPLETED (type includes completed OR title includes Completed) / ON THE WAY (title includes On The Way) / CLOSE (title includes Close) / ACCEPTED (title includes Accepted), NEW badge if !read, title, message, time - ID: bookingId ?? withdrawalId ?? id last 8, Nurse: nurseName, Amount: GHS amount
/// - Actions: Read (update read:true in source path ceoNotifications/{id} OR ceoNotificationRoom/{id}), Delete (remove from BOTH ceoNotifications/{id} + ceoNotificationRoom/{id}), Mark All Read (confirm, update all unread in their source), Delete All (confirm + type DELETE prompt, remove BOTH ceoNotifications + ceoNotificationRoom)
/// - Sound: RECEIVER-ONLY — MY_ROLE ceo, MY_PAGE ceo-notification-room. Ring only if NOT my own booking (isMyBooking: my phone/email/uid NOT in booking's nurse/client fields) AND shouldRing (status changed / new booking within 2 min). Uses lcg_custom_song / Sound Settings (NO alert buttons — only Sound Settings). Sender never hears his own song.
///   Implementation: bookings onChildChanged/onChildAdded -> check isMyBooking + shouldRing -> playCustomSound. Same as HTML receiver-only block.

class CEONotificationRoomScreen extends StatefulWidget {
  const CEONotificationRoomScreen({super.key});
  @override
  State<CEONotificationRoomScreen> createState() => _CEONotificationRoomScreenState();
}

class _CEONotificationRoomScreenState extends State<CEONotificationRoomScreen> {
  List<Map> all = [];
  String currentFilter = 'all';
  final AudioPlayer _player = AudioPlayer();
  List<String> myPhones = [], myEmails = [], myUids = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
    _getIds().then((_) => _startReceiverSound());
  }

  Future<void> _getIds() async {
    final prefs = await SharedPreferences.getInstance();
    myPhones = []; myEmails = []; myUids = [];
    for (final k in prefs.getKeys()) {
      final v = prefs.getString(k) ?? '';
      final kl = k.toLowerCase();
      if (kl.contains('phone')) { final p = v.replaceAll(RegExp(r'[^0-9]'), ''); final p9 = p.length >= 9 ? p.substring(p.length - 9) : p; if (p9.isNotEmpty) myPhones.add(p9); }
      if (kl.contains('email')) myEmails.add(v.toLowerCase().trim());
      if (kl.contains('uid') || k == 'id') myUids.add(v);
    }
  }

  bool _isMyBooking(Map b) {
    final bPhones = [(b['clientPhone'] ?? ''), (b['phone'] ?? ''), (b['nursePhone'] ?? '')].map((e) => e.toString().replaceAll(RegExp(r'[^0-9]'), '')).map((p) => p.length >= 9 ? p.substring(p.length - 9) : p).toList();
    final bEmails = [(b['clientEmail'] ?? ''), (b['email'] ?? ''), (b['nurseEmail'] ?? '')].map((e) => e.toString().toLowerCase().trim()).toList();
    final bUids = [b['clientUid'], b['clientId'], b['uid'], b['nurseId'], b['nurseUid']].map((e) => e?.toString() ?? '').toList();
    return myPhones.any((p) => bPhones.contains(p)) || myEmails.any((e) => bEmails.contains(e)) || myUids.any((u) => bUids.contains(u));
  }

  void _loadAll() {
    for (final path in ['ceoNotifications', 'ceoNotificationRoom']) {
      FirebaseDatabase.instance.ref(path).limitToLast(100).onValue.listen((e) {
        if (!e.snapshot.exists) { setState(() {}); return; }
        (e.snapshot.value as Map).forEach((k, v) {
          final val = Map<String, dynamic>.from(v as Map);
          final idx = all.indexWhere((n) => n['id'] == k);
          if (idx == -1) all.add({...val, 'id': k, 'source': path});
          else all[idx] = {...all[idx], ...val};
        });
        all.sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
        setState(() {});
      });
    }
  }

  void _startReceiverSound() {
    // Receiver-only: only ring if NOT my own booking
    FirebaseDatabase.instance.ref('bookings').onChildChanged.listen((e) {
      if (!e.snapshot.exists) return;
      final v = Map<String, dynamic>.from(e.snapshot.value as Map);
      if (_isMyBooking(v)) return; // sender never hears own song
      _playCustomSound();
    });
    FirebaseDatabase.instance.ref('bookings').onChildAdded.listen((e) {
      if (!e.snapshot.exists) return;
      final v = Map<String, dynamic>.from(e.snapshot.value as Map);
      final tt = (v['time'] ?? v['createdAt'] ?? 0) as num;
      if (DateTime.now().millisecondsSinceEpoch - tt > 120000) return;
      if (_isMyBooking(v)) return;
      _playCustomSound();
    });
  }

  Future<void> _playCustomSound() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString('lcg_custom_song');
    if (custom != null && custom.isNotEmpty) { try { await _player.play(UrlSource(custom)); return; } catch (_) {} }
    try { await _player.play(AssetSource('sounds/${prefs.getString('lcg_sound_choice') ?? 'bell'}.mp3')); } catch (_) {}
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _typeText(Map n) {
    final type = (n['type'] ?? '').toString().toLowerCase();
    final title = (n['title'] ?? '').toString();
    if (type.contains('withdrawal')) return 'WITHDRAWAL';
    if (type.contains('completed') || title.contains('Completed')) return 'COMPLETED';
    if (title.contains('On The Way')) return 'ON THE WAY';
    if (title.contains('Close')) return 'CLOSE';
    if (title.contains('Accepted')) return 'ACCEPTED';
    return 'BOOKING';
  }

  List<Map> get filtered {
    if (currentFilter == 'all') return List<Map>.from(all);
    return all.where((n) => (n['type'] ?? '').toString().toLowerCase().contains(currentFilter) || (n['title'] ?? '').toString().toLowerCase().contains(currentFilter)).toList();
  }

  Future<void> _markRead(Map n) async {
    final id = n['id'];
    try {
      if (n['source'] == 'ceoNotifications') await FirebaseDatabase.instance.ref('ceoNotifications/$id').update({'read': true});
      if (n['source'] == 'ceoNotificationRoom') await FirebaseDatabase.instance.ref('ceoNotificationRoom/$id').update({'read': true});
      setState(() => n['read'] = true);
      _toast('Marked read');
    } catch (e) { _toast(e.toString()); }
  }

  Future<void> _markAllRead() async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Mark all as read?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Mark All'))]));
    if (confirm != true) return;
    try {
      for (final n in all) {
        if (n['read'] != true) {
          if (n['source'] == 'ceoNotifications') await FirebaseDatabase.instance.ref('ceoNotifications/${n['id']}').update({'read': true}).catchError((_) {});
          if (n['source'] == 'ceoNotificationRoom') await FirebaseDatabase.instance.ref('ceoNotificationRoom/${n['id']}').update({'read': true}).catchError((_) {});
          n['read'] = true;
        }
      }
      setState(() {});
      _toast('All marked read');
    } catch (e) { _toast(e.toString()); }
  }

  Future<void> _deleteOne(Map n) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Delete this notification?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
    if (confirm != true) return;
    try {
      await FirebaseDatabase.instance.ref('ceoNotifications/${n['id']}').remove().catchError((_) {});
      await FirebaseDatabase.instance.ref('ceoNotificationRoom/${n['id']}').remove().catchError((_) {});
      setState(() => all.removeWhere((x) => x['id'] == n['id']));
      _toast('Deleted');
    } catch (e) { _toast(e.toString()); }
  }

  Future<void> _deleteAll() async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Delete ALL ${all.length} notifications?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete All'))]));
    if (confirm != true) return;
    final ctrl = TextEditingController();
    final c = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Type DELETE to confirm:'), content: TextField(controller: ctrl), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Confirm'))]));
    if (c != 'DELETE') return;
    try {
      await FirebaseDatabase.instance.ref('ceoNotifications').remove();
      await FirebaseDatabase.instance.ref('ceoNotificationRoom').remove();
      setState(() => all = []);
      _toast('All deleted');
    } catch (e) { _toast(e.toString()); }
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    final unread = list.where((n) => n['read'] != true).length;
    final filters = ['all', 'booking', 'withdrawal', 'completed', 'accepted', 'on_the_way', 'close'];
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(title: const Text('CEO Notification Room', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 8), child: Chip(label: Text('${list.length} Notifications - $unread Unread', style: const TextStyle(fontSize: 11))))), IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings'))]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(10), child: Row(children: [
          Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: filters.map((f) => ChoiceChip(label: Text(f == 'all' ? 'All' : f, style: const TextStyle(fontSize: 11)), selected: currentFilter == f, onSelected: (_) => setState(() => currentFilter = f))).toList())),
          TextButton(onPressed: _markAllRead, child: const Text('Mark All Read', style: TextStyle(fontSize: 11))),
          TextButton(onPressed: _deleteAll, child: const Text('Delete All', style: TextStyle(fontSize: 11, color: Colors.red))),
        ])),
        Expanded(child: list.isEmpty ? Center(child: Text('No $currentFilter notifications\nCEO will receive written notifications for all booking progress', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60))) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: list.length > 100 ? 100 : list.length, itemBuilder: (_, i) {
          final n = list[i];
          final isUnread = n['read'] != true;
          return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(16), border: Border(left: BorderSide(color: isUnread ? const Color(0xFFFACC15) : Colors.transparent, width: 4))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.purple.withOpacity(0.15), borderRadius: BorderRadius.circular(999)), child: Text(_typeText(n), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFC4B5FD)))), const SizedBox(width: 6), if (isUnread) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFFACC15), borderRadius: BorderRadius.circular(999)), child: const Text('NEW', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black)))]),
            const SizedBox(height: 6),
            Text(n['title'] ?? 'Notification', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(n['message'] ?? '', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Text('${n['createdAt'] != null ? DateTime.fromMillisecondsSinceEpoch((n['createdAt'] as num).toInt()) : ''} - ID: ${n['bookingId'] ?? n['withdrawalId'] ?? (n['id'] as String).length > 8 ? (n['id'] as String).substring((n['id'] as String).length - 8) : n['id']}${n['nurseName'] != null ? ' - Nurse: ${n['nurseName']}' : ''}${n['amount'] != null ? ' - Amount: GHS ${n['amount']}' : ''}', style: const TextStyle(fontSize: 10, color: Colors.white60)),
            const SizedBox(height: 10),
            Row(children: [OutlinedButton(onPressed: () => _markRead(n), child: const Text('Read', style: TextStyle(fontSize: 11))), const SizedBox(width: 6), OutlinedButton(onPressed: () => _deleteOne(n), child: const Text('Delete', style: TextStyle(fontSize: 11, color: Colors.red)))]),
          ]));
        })),
      ]),
    );
  }
}
