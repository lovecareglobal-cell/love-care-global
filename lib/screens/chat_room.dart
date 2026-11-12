import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

/// CEO Control Chat - Chat Room List - Flutter version of chat-room.html
/// Lists Clients + Nurses from many RTDB paths, deduped by email, sorted by last action time
/// CEO can search by name, email, phone. Shows counts: All / Clients / Google / Nurses

class CEOChatRoomScreen extends StatefulWidget {
  const CEOChatRoomScreen({super.key});
  @override
  State<CEOChatRoomScreen> createState() => _CEOChatRoomScreenState();
}

class _CEOChatRoomScreenState extends State<CEOChatRoomScreen> {
  List<Map> allChats = [];
  String search = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  int getTimestamp(Map v) {
    final candidates = [v['updatedAt'], v['createdAt'], v['time'], v['lastActionAt'], v['lastLogin'], v['timestamp']];
    for (final c in candidates) {
      if (c is int) return c;
      if (c is String) { final n = int.tryParse(c); if (n != null) return n; }
    }
    return 0;
  }

  String extractName(Map v) {
    return (v['fullName'] ?? v['name'] ?? v['clientName'] ?? v['displayName'] ?? v['username'] ?? '').toString();
  }

  String formatActionTime(int ts) {
    if (ts == 0) return 'No time';
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _loadAll() async {
    setState(() => isLoading = true);
    final db = FirebaseDatabase.instance;
    final clientPaths = ['clients','clientUsers','users','clientRegistrations','googleClients','clientGoogleLogins','authUsers','clientsGoogle','usersGoogle','clientAuthUsers','googleAuthClients','clientsByGoogle','googleSignInClients','clientGoogleUsers','allClients','ceoClientUpdates','client_registrations','pendingClientRegistrations','ceoBookingReceiverClients','googleUsers','googleLogins'];
    final nursePaths = ['nurses','nurseUsers','allNurses','nurse_registrations','pendingNurseRegistrations'];
    Map<String, Map> clientMapByEmail = {};
    Map<String, Map> nurseMap = {};
    for (final p in clientPaths) {
      try {
        final snap = await db.ref(p).get();
        if (!snap.exists) continue;
        final m = snap.value as Map;
        m.forEach((id, val) {
          if (val is! Map) return;
          final v = Map<String, dynamic>.from(val);
          if (v['services'] != null || v['qualification'] != null || v['role'] == 'nurse') return;
          final email = (v['email'] ?? v['clientEmail'] ?? v['userEmail'] ?? '').toString().toLowerCase().trim();
          if (email.isEmpty || !email.contains('@')) return;
          if (email.contains('anonymous') || email.contains('test@') || email.contains('no email')) return;
          final newTs = getTimestamp(v);
          final existing = clientMapByEmail[email];
          final oldTs = existing != null ? getTimestamp(existing) : 0;
          if (existing == null || newTs >= oldTs) {
            if (existing != null) {
              final merged = {...existing, ...v, '_id': id, '_path': p, '_ts': newTs > oldTs ? newTs : oldTs};
              final oldPhone = existing['phone'] ?? existing['phoneNumber'] ?? '';
              final newPhone = v['phone'] ?? v['phoneNumber'] ?? '';
              if ((oldPhone == '' || oldPhone == 'no phone') && newPhone != '' && newPhone != 'no phone') merged['phone'] = newPhone;
              clientMapByEmail[email] = merged;
            } else {
              clientMapByEmail[email] = {...v, '_id': id, '_path': p, '_ts': newTs};
            }
          }
        });
      } catch (_) {}
    }
    for (final p in nursePaths) {
      try {
        final snap = await db.ref(p).get();
        if (!snap.exists) continue;
        final m = snap.value as Map;
        m.forEach((id, val) {
          if (val is! Map) return;
          final v = Map<String, dynamic>.from(val);
          final email = (v['email'] ?? v['nurseEmail'] ?? '').toString().toLowerCase().trim();
          if (email.isEmpty || !email.contains('@')) return;
          nurseMap[email] = v;
        });
      } catch (_) {}
    }
    List<Map> chats = [];
    clientMapByEmail.forEach((email, v) {
      final name = extractName(v);
      if (name.isEmpty || name.toLowerCase().contains('anonymous')) return;
      final isGoogle = v['provider'] == 'google' || v['isGoogle'] == true || v['googleLogin'] == true || email.contains('gmail.com') || (v['photoURL']?.toString().contains('google') ?? false);
      final phone = v['phone'] ?? v['phoneNumber'] ?? v['phone_number'] ?? 'no phone';
      final photo = v['photo'] ?? v['photoURL'] ?? v['profilePhoto'] ?? '';
      final ts = v['_ts'] ?? getTimestamp(v);
      chats.add({'id': v['_id'] ?? email, 'type': 'client', 'name': name, 'email': email, 'phone': phone, 'photo': photo, 'isGoogle': isGoogle, 'updatedAt': ts, 'timeDisplay': formatActionTime(ts), 'lastAction': v['lastAction'] ?? v['action'] ?? (isGoogle ? 'Google Login' : 'Registered'), 'source': v['_path'] ?? 'clients'});
    });
    nurseMap.forEach((email, v) {
      final name = extractName(v);
      final phone = v['phone'] ?? v['phoneNumber'] ?? 'no phone';
      final ts = getTimestamp(v);
      chats.add({'id': email, 'type': 'nurse', 'name': name, 'email': email, 'phone': phone, 'photo': v['photo'] ?? '', 'isGoogle': false, 'updatedAt': ts, 'timeDisplay': formatActionTime(ts), 'lastAction': 'Nurse', 'source': 'nurses'});
    });
    chats.sort((a, b) => (b['updatedAt'] as int).compareTo(a['updatedAt'] as int));
    setState(() { allChats = chats; isLoading = false; });
  }

  Future<void> _clearDuplicates() async {
    // In Flutter, duplicates are already deduped by email in-memory (same as HTML clearDuplicates)
    await _loadAll();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Duplicates cleaned (by email)')));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = allChats.where((c) {
      if (search.isEmpty) return true;
      final q = search.toLowerCase();
      return c['name'].toString().toLowerCase().contains(q) || c['email'].toString().toLowerCase().contains(q) || c['phone'].toString().toLowerCase().contains(q);
    }).toList();
    final allCount = allChats.length;
    final clientCount = allChats.where((c) => c['type'] == 'client').length;
    final googleCount = allChats.where((c) => c['isGoogle'] == true).length;
    final nurseCount = allChats.where((c) => c['type'] == 'nurse').length;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('CEO Control Chat'), backgroundColor: const Color(0xFF1A1633), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll), TextButton(onPressed: _clearDuplicates, child: const Text('Clean Dupes', style: TextStyle(color: Colors.red))) ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children: [
          _badge('All: $allCount'), _badge('Clients: $clientCount', color: Colors.purple), _badge('Google: $googleCount', color: Colors.green), _badge('Nurses: $nurseCount', color: Colors.blue),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: TextField(onChanged: (v) => setState(() => search = v), decoration: const InputDecoration(hintText: 'Search by name, email, phone...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()))),
        Expanded(child: isLoading ? const Center(child: CircularProgressIndicator()) : filtered.isEmpty ? const Center(child: Text('No chats found')) : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) => _chatCard(filtered[i]))),
      ]),
    );
  }

  Widget _badge(String t, {Color color = Colors.purple}) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: color.withOpacity(0.12), border: Border.all(color: color.withOpacity(0.2)), borderRadius: BorderRadius.circular(20)), child: Text(t, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)));

  Widget _chatCard(Map c) {
    final isNurse = c['type'] == 'nurse';
    final photo = c['photo']?.toString() ?? '';
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/ceo-chat-detail', arguments: c),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.1))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: 24, backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null, child: photo.isEmpty ? Text(c['name'].toString().isNotEmpty ? c['name'][0].toUpperCase() : '?', style: const TextStyle(fontWeight: FontWeight.bold)) : null),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text(c['email'], style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 12)),
            Text(c['phone'], style: const TextStyle(color: Colors.white60, fontSize: 11)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              _badge(c['timeDisplay'], color: Colors.amber),
              if (c['isGoogle'] == true) _badge('Google', color: Colors.green),
              _badge(isNurse ? 'Nurse' : 'Client', color: isNurse ? Colors.blue : Colors.purple),
              _badge(c['lastAction'].toString(), color: Colors.white60),
            ]),
          ])),
        ]),
      ),
    );
  }
}
