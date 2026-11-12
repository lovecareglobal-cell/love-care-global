import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key});
  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

// Aliases - so main.dart + old files still work
class ChatRoomPage extends ChatRoomScreen {
  const ChatRoomPage({super.key});
}
class CEOControlChatListScreen extends ChatRoomScreen {
  const CEOControlChatListScreen({super.key});
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  List<Map<String, dynamic>> allChats = [];
  String searchQ = '';
  bool isLoading = true;

  // Same as HTML
  final List<String> clientPaths = ['clients', 'clientUsers', 'users', 'clientRegistrations', 'googleClients', 'clientGoogleLogins', 'authUsers', 'clientsGoogle', 'usersGoogle', 'clientAuthUsers', 'googleAuthClients', 'clientsByGoogle', 'googleSignInClients', 'clientGoogleUsers', 'allClients', 'ceoClientUpdates', 'client_registrations', 'pendingClientRegistrations', 'ceoBookingReceiverClients', 'googleUsers', 'googleLogins'];
  final List<String> nursePaths = ['nurses', 'nurseUsers', 'allNurses', 'nurse_registrations', 'pendingNurseRegistrations'];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // Same as HTML getTimestamp()
  int _getTimestamp(Map<String, dynamic> v) {
    final candidates = [v['updatedAt'], v['lastUpdate'], v['lastLogin'], v['lastLoginAt'], v['lastSignInTime'], v['createdAt'], v['timestamp'], v['registeredAt'], v['time'], v['date'], v['created'], v['metadata'] is Map ? (v['metadata'] as Map)['lastSignInTime'] : null, v['metadata'] is Map ? (v['metadata'] as Map)['creationTime'] : null];
    int max = 0;
    for (final c in candidates) {
      if (c == null) continue;
      int ms = 0;
      if (c is int) ms = c;
      if (c is double) ms = c.toInt();
      if (c is String) {
        final d = DateTime.tryParse(c);
        if (d != null) ms = d.millisecondsSinceEpoch;
        else { final n = int.tryParse(c); if (n != null) ms = n; }
      }
      if (c is Map) {
        if (c['seconds'] != null) ms = (int.tryParse('${c['seconds']}') ?? 0) * 1000;
        if (c['_seconds'] != null) ms = (int.tryParse('${c['_seconds']}') ?? 0) * 1000;
      }
      if (ms > max) max = ms;
    }
    return max;
  }

  // Same as HTML formatActionTime()
  String _formatTime(int ts) {
    if (ts == 0) return 'time unknown';
    final date = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final diffMins = now.difference(date).inMinutes;
    final diffHours = now.difference(date).inHours;
    final diffDays = now.difference(date).inDays;
    final timeStr = '${date.hour % 12 == 0 ? 12 : date.hour % 12}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
    final dateStr = '${_month(date.month)} ${date.day}, ${date.year}';
    final shortDate = '${_month(date.month)} ${date.day}';
    if (diffMins < 1) return 'Just now  $timeStr';
    if (diffMins < 60) return '${diffMins}m ago  $timeStr today';
    if (diffHours < 24) return '${diffHours}h ago  $timeStr today';
    if (diffDays == 1) return 'Yesterday  $timeStr';
    if (diffDays < 7) return '${diffDays}d ago  $shortDate $timeStr';
    return '$dateStr  $timeStr';
  }

  String _month(int m) => ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];

  String _extractName(Map<String, dynamic> v) {
    final n = ((v['name'] ?? v['fullName'] ?? v['displayName'] ?? v['clientName'] ?? v['userName'] ?? '') as String).trim();
    if (n.isNotEmpty) return n;
    final email = (v['email'] ?? '').toString();
    if (email.contains('@')) return email.split('@')[0];
    return 'Unknown';
  }

  Future<void> _loadAll() async {
    setState(() => isLoading = true);
    _toast('Loading CEO chats — Deduplicating + Time...');
    final Map<String, Map<String, dynamic>> clientMapByEmail = {};
    final Map<String, Map<String, dynamic>> nurseMap = {};

    // Clients - 21 paths
    for (final p in clientPaths) {
      try {
        final snap = await _db.child(p).get();
        if (!snap.exists || snap.value is! Map) continue;
        final data = Map<String, dynamic>.from(snap.value as Map);
        for (final entry in data.entries) {
          if (entry.value is! Map) continue;
          final v = Map<String, dynamic>.from(entry.value as Map);
          // Skip nurses inside client paths - same as HTML
          if (v['services'] != null || v['qualification'] != null || v['role'] == 'nurse') continue;
          final email = ((v['email'] ?? v['clientEmail'] ?? v['userEmail'] ?? '') as String).toLowerCase().trim();
          if (email.isEmpty || !email.contains('@')) continue;
          if (email.contains('anonymous') || email.contains('test@') || email.contains('no email')) continue;
          final newTs = _getTimestamp(v);
          final existing = clientMapByEmail[email];
          final oldTs = existing != null ? _getTimestamp(existing) : 0;
          if (existing == null || newTs >= oldTs) {
            if (existing != null) {
              final merged = {...existing, ...v, '_id': entry.key.toString(), '_path': p, '_ts': newTs > oldTs ? newTs : oldTs};
              final oldPhone = (existing['phone'] ?? existing['phoneNumber'] ?? '').toString();
              final newPhone = (v['phone'] ?? v['phoneNumber'] ?? '').toString();
              if ((oldPhone.isEmpty || oldPhone == 'no phone') && newPhone.isNotEmpty && newPhone != 'no phone') merged['phone'] = newPhone;
              clientMapByEmail[email] = merged;
            } else {
              clientMapByEmail[email] = {...v, '_id': entry.key.toString(), '_path': p, '_ts': newTs};
            }
          }
        }
      } catch (_) {}
    }

    // Nurses - 5 paths
    for (final p in nursePaths) {
      try {
        final snap = await _db.child(p).get();
        if (!snap.exists || snap.value is! Map) continue;
        final data = Map<String, dynamic>.from(snap.value as Map);
        for (final entry in data.entries) {
          if (entry.value is! Map) continue;
          final v = Map<String, dynamic>.from(entry.value as Map);
          final email = ((v['email'] ?? v['nurseEmail'] ?? '') as String).toLowerCase().trim();
          if (email.isEmpty || !email.contains('@')) continue;
          nurseMap[email] = {...v, '_id': entry.key.toString(), '_path': p};
        }
      } catch (_) {}
    }

    // Firestore clients - same as HTML
    try {
      final fs = await FirebaseFirestore.instance.collection('clients').get();
      for (final doc in fs.docs) {
        final v = doc.data();
        final email = ((v['email'] ?? '') as String).toLowerCase().trim();
        if (email.isEmpty || !email.contains('@')) continue;
        final ts = _getTimestamp(v);
        if (!clientMapByEmail.containsKey(email) || ts > _getTimestamp(clientMapByEmail[email]!)) {
          clientMapByEmail[email] = {...v, '_id': doc.id, '_path': 'firestore/clients', '_ts': ts};
        }
      }
    } catch (_) {}

    final chats = <Map<String, dynamic>>[];
    for (final v in clientMapByEmail.values) {
      final name = _extractName(v);
      if (name.isEmpty || name.toLowerCase().contains('anonymous')) continue;
      final email = (v['email'] ?? v['clientEmail'] ?? '').toString();
      if (email.isEmpty) continue;
      final isGoogle = v['provider'] == 'google' || v['isGoogle'] == true || v['googleLogin'] == true || email.toLowerCase().contains('gmail.com') || (v['photoURL'] ?? '').toString().contains('google');
      final phone = (v['phone'] ?? v['phoneNumber'] ?? v['phone_number'] ?? 'no phone').toString();
      final photo = (v['photo'] ?? v['photoURL'] ?? v['profilePhoto'] ?? '').toString();
      final ts = (v['_ts'] ?? _getTimestamp(v) ?? DateTime.now().millisecondsSinceEpoch) as int;
      final lastAction = (v['lastAction'] ?? v['action'] ?? (isGoogle ? 'Google Login' : 'Registered')).toString();
      chats.add({'id': (v['_id'] ?? email).toString(), 'type': 'client', 'name': name, 'email': email, 'phone': phone, 'photo': photo, 'isGoogle': isGoogle, 'raw': v, 'updatedAt': ts, 'timeDisplay': _formatTime(ts), 'lastAction': lastAction, 'source': (v['_path'] ?? 'clients').toString()});
    }
    for (final v in nurseMap.values) {
      final name = _extractName(v);
      final email = (v['email'] ?? '').toString();
      final phone = (v['phone'] ?? v['phoneNumber'] ?? 'no phone').toString();
      final ts = _getTimestamp(v);
      chats.add({'id': (v['_id'] ?? email).toString(), 'type': 'nurse', 'name': name, 'email': email, 'phone': phone, 'photo': (v['photo'] ?? '').toString(), 'isGoogle': false, 'raw': v, 'updatedAt': ts, 'timeDisplay': _formatTime(ts), 'lastAction': 'Nurse', 'source': 'nurses'});
    }
    chats.sort((a, b) => (b['updatedAt'] as int).compareTo(a['updatedAt'] as int));
    setState(() { allChats = chats; isLoading = false; });
    _toast('✅ Loaded ${chats.length} chats — DEDUPED + TIME');
  }

  Future<void> _clearDuplicates() async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(backgroundColor: const Color(0xFF1C1238), title: const Text('Clean duplicate no-email entries?', style: TextStyle(color: Colors.white, fontSize: 14)), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clean'))]));
    if (confirm != true) return;
    _toast('Cleaning...');
    int deleted = 0;
    for (final p in ['clients', 'clientUsers', 'clientRegistrations', 'googleClients']) {
      try {
        final snap = await _db.child(p).get();
        if (!snap.exists || snap.value is! Map) continue;
        final data = Map<String, dynamic>.from(snap.value as Map);
        for (final entry in data.entries) {
          if (entry.value is! Map) continue;
          final v = Map<String, dynamic>.from(entry.value as Map);
          final email = ((v['email'] ?? v['clientEmail'] ?? '') as String).toLowerCase().trim();
          if (email.isEmpty || !email.contains('@') || email.contains('no email') || email.contains('anonymous')) {
            await _db.child('$p/${entry.key}').remove();
            deleted++;
          }
        }
      } catch (_) {}
    }
    _toast('✅ Cleaned $deleted invalid entries');
    Future.delayed(const Duration(seconds: 1), _loadAll);
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
    else _toast('Cannot open: $url');
  }

  void _openUser(Map<String, dynamic> item) {
    final phone = (item['phone'] ?? '').toString();
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final raw = item['raw'] is Map ? Map<String, dynamic>.from(item['raw'] as Map) : <String, dynamic>{};
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1238),
        title: Text((item['name'] ?? '').toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Type: ${item['type']} • Source: ${item['source']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text('Email: ${item['email']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text('Phone: $phone', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text('Updated: ${item['timeDisplay']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text('Last Action: ${item['lastAction']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              if (raw['location'] != null) Text('Location: ${raw['location']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              if (raw['specialty'] != null) Text('Specialty: ${raw['specialty']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          if (clean.isNotEmpty && clean != 'no phone') TextButton(onPressed: () => _launch('tel:$clean'), child: const Text('📞 Call')),
          if (clean.isNotEmpty && clean != 'no phone') TextButton(onPressed: () => _launch('https://wa.me/${clean.replaceAll('+', '')}?text=${Uri.encodeComponent('Hello ${item['name']} — Love Care Global')}'), child: const Text('💬 WhatsApp')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = searchQ.toLowerCase().trim();
    final filtered = q.isEmpty ? allChats : allChats.where((c) => (c['name'] as String).toLowerCase().contains(q) || (c['email'] as String).toLowerCase().contains(q) || (c['phone'] as String).toLowerCase().contains(q)).toList();
    final clientCount = allChats.where((c) => c['type'] == 'client').length;
    final googleCount = allChats.where((c) => c['isGoogle'] == true).length;
    final nurseCount = allChats.where((c) => c['type'] == 'nurse').length;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0A1C),
        title: const Text('CEO Control Chat', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton(onPressed: _loadAll, child: const Text('🔄 Refresh', style: TextStyle(color: Color(0xFFD8B4FE), fontSize: 11))),
          TextButton(onPressed: _clearDuplicates, child: const Text('🧹 Clean Dupes', style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 11))),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _badge('$clientCount clients ($googleCount Google) + $nurseCount nurses — Sorted by time', const Color(0xFFA855F7)),
                _badge('All: ${allChats.length}', const Color(0xFFA855F7)),
                _badge('Clients: $clientCount', const Color(0xFFD8B4FE)),
                _badge('Google: $googleCount', const Color(0xFF86EFAC)),
                _badge('Nurses: $nurseCount', const Color(0xFF93C5FD)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(onChanged: (v) => setState(() => searchQ = v), style: const TextStyle(color: Colors.white, fontSize: 13), decoration: InputDecoration(hintText: 'Search by name, email, phone...', hintStyle: const TextStyle(color: Colors.white54, fontSize: 12), filled: true, fillColor: const Color(0xFF1C1238), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.purple.withOpacity(0.15))), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFACC15)))
                : filtered.isEmpty
                    ? const Center(child: Text('No clients found', style: TextStyle(color: Color(0xFF9A95B8))))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final item = filtered[i];
                          final name = (item['name'] ?? 'Unknown').toString();
                          final photo = (item['photo'] ?? '').toString();
                          final isNurse = item['type'] == 'nurse';
                          return InkWell(
                            onTap: () => _openUser(item),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(color: const Color(0xFF1C1238).withOpacity(0.6), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.purple.withOpacity(0.1))),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(radius: 24, backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null, backgroundColor: const Color(0xFF3B0F6E), child: photo.isEmpty ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)) : null),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                                        Text((item['email'] ?? '').toString(), style: const TextStyle(fontSize: 12, color: Color(0xFFA78BFA))),
                                        Text((item['phone'] ?? '').toString(), style: const TextStyle(fontSize: 11, color: Color(0xFF9A95B8))),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            _badge(isNurse ? 'Nurse' : 'Client', isNurse ? const Color(0xFF93C5FD) : const Color(0xFFD8B4FE)),
                                            if (item['isGoogle'] == true) _badge('G Google Login  $name', const Color(0xFF86EFAC)),
                                            _badge('🕐 ${item['timeDisplay']}', const Color(0xFFFACC15)),
                                            _badge('🎯 ${item['lastAction']}', const Color(0xFFFACC15)),
                                            _badge('${item['source']}', const Color(0xFF6B7280)),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text('Updated: ${item['timeDisplay']}  ID: ${(item['id'] ?? '').toString().length > 12 ? (item['id'] as String).substring(0, 12) : item['id']}...', style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
                                      ],
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

  Widget _badge(String text, Color color) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(0.2))), child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)));
  }
}
