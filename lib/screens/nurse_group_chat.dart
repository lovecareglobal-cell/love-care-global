import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

class NurseGroupChatScreen extends StatefulWidget {
  const NurseGroupChatScreen({super.key});
  @override
  State<NurseGroupChatScreen> createState() => _NurseGroupChatScreenState();
}

// Alias - so main.dart + old files still work
class NurseGroupChatPage extends NurseGroupChatScreen {
  const NurseGroupChatPage({super.key});
}

class _NurseGroupChatScreenState extends State<NurseGroupChatScreen> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();

  String currentUserId = '';
  String currentUserName = 'Nurse';
  String currentUserPhoto = '';
  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> onlineNurses = [];
  List<Map<String, dynamic>> allNurses = [];
  List<Map<String, dynamic>> blockedList = [];
  String searchQ = '';
  String typingText = '';
  bool showSidebar = false;
  bool showEmoji = false;
  bool isSending = false;

  // Pending media - same as HTML pendingImages / Videos / Files
  List<String> pendingImages = [];
  List<String> pendingVideos = [];
  List<Map<String, dynamic>> pendingFiles = [];

  final List<String> emojis = ['😀','😂','❤️','🙏','👍','👏','🔥','💜','🩺','👩‍⚕️','😊','😢','🎉','💪','🌹','✅','⚠️','💬'];

  @override
  void initState() {
    super.initState();
    _initUser();
  }

  @override
  void dispose() {
    _msgController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initUser() async {
    final prefs = await SharedPreferences.getInstance();
    currentUserId = prefs.getString('lcg_nurse_uid') ?? prefs.getString('nurseUid') ?? prefs.getString('uid') ?? prefs.getString('nurseId') ?? 'nurse_${DateTime.now().millisecondsSinceEpoch}';
    currentUserName = prefs.getString('nurseName') ?? prefs.getString('fullName') ?? prefs.getString('displayName') ?? prefs.getString('name') ?? 'Nurse';
    currentUserPhoto = prefs.getString('nursePhoto') ?? prefs.getString('photo') ?? '';
    // Try load real photo from nurses/<uid>
    try {
      final snap = await _db.child('nurses/$currentUserId').get();
      if (snap.exists && snap.value is Map) {
        final v = Map<String, dynamic>.from(snap.value as Map);
        final p = (v['photoURL'] ?? v['photo'] ?? v['profilePhoto'] ?? v['avatar'] ?? v['image'] ?? '').toString();
        if (p.isNotEmpty) {
          currentUserPhoto = p;
          await prefs.setString('nursePhoto', p);
        }
        final n = (v['fullName'] ?? v['name'] ?? v['displayName'] ?? '').toString();
        if (n.isNotEmpty) currentUserName = n;
      }
    } catch (_) {}
    if (mounted) setState(() {});
    _loadOnline();
    _loadMessages();
    _checkBlocked();
    _listenTyping();
    // Mark online + onDisconnect remove
    try {
      await _db.child('onlineNurses/$currentUserId').set({'name': currentUserName, 'photo': currentUserPhoto, 'onlineAt': DateTime.now().millisecondsSinceEpoch, 'inChat': true});
      _db.child('onlineNurses/$currentUserId').onDisconnect().remove();
    } catch (_) {}
  }

  void _loadOnline() {
    // Approved nurses list
    _db.child('nurses').onValue.listen((e) {
      if (e.snapshot.value == null || e.snapshot.value is! Map) return;
      final data = Map<String, dynamic>.from(e.snapshot.value as Map);
      final list = <Map<String, dynamic>>[];
      for (final entry in data.entries) {
        if (entry.value is! Map) continue;
        final v = Map<String, dynamic>.from(entry.value as Map);
        list.add({...v, 'id': entry.key.toString(), 'name': (v['fullName'] ?? v['name'] ?? 'Nurse').toString(), 'photo': (v['photoURL'] ?? v['photo'] ?? '').toString(), 'specialty': (v['specialty'] ?? v['specialization'] ?? '').toString()});
      }
      allNurses = list;
      if (mounted) setState(() {});
    });
    _db.child('onlineNurses').onValue.listen((e) {
      if (e.snapshot.value == null || e.snapshot.value is! Map) return;
      final data = Map<String, dynamic>.from(e.snapshot.value as Map);
      final list = <Map<String, dynamic>>[];
      for (final entry in data.entries) {
        if (entry.value is! Map) continue;
        final v = Map<String, dynamic>.from(entry.value as Map);
        list.add({...v, 'id': entry.key.toString(), 'name': (v['name'] ?? 'Nurse').toString(), 'photo': (v['photo'] ?? '').toString()});
      }
      onlineNurses = list;
      if (mounted) setState(() {});
    });
  }

  void _loadMessages() {
    // Primary: nurseCommunityChat/messages - last 150
    _db.child('nurseCommunityChat/messages').orderByChild('createdAt').limitToLast(150).onValue.listen((e) {
      _mergeMessages(e.snapshot.value, 'nurseCommunityChat');
    });
    // CEO messages from nurses_group_chat - only CEO
    _db.child('nurses_group_chat/messages').orderByChild('createdAt').limitToLast(150).onValue.listen((e) {
      if (e.snapshot.value == null || e.snapshot.value is! Map) return;
      final data = Map<String, dynamic>.from(e.snapshot.value as Map);
      for (final entry in data.entries) {
        if (entry.value is! Map) continue;
        final v = Map<String, dynamic>.from(entry.value as Map);
        final sid = (v['senderId'] ?? '').toString();
        final isCEO = sid.contains('CEO') || (v['senderName'] ?? '').toString().contains('CEO') || v['isCEO'] == true;
        if (!isCEO) continue;
        _addOrUpdate({...v, 'id': entry.key.toString(), 'key': entry.key.toString()});
      }
      _sortMessages();
    });
  }

  void _mergeMessages(Object? value, String src) {
    if (value == null || value is! Map) return;
    final data = Map<String, dynamic>.from(value as Map);
    for (final entry in data.entries) {
      if (entry.value is! Map) continue;
      final v = Map<String, dynamic>.from(entry.value as Map);
      _addOrUpdate({...v, 'id': entry.key.toString(), 'key': entry.key.toString()});
    }
    _sortMessages();
  }

  void _addOrUpdate(Map<String, dynamic> m) {
    final key = (m['key'] ?? m['id'] ?? m['messageId'] ?? '').toString();
    final idx = messages.indexWhere((x) => (x['key'] ?? x['id'] ?? x['messageId'] ?? '').toString() == key);
    if (idx == -1) {
      messages.add(m);
    } else {
      messages[idx] = {...messages[idx], ...m};
    }
  }

  void _sortMessages() {
    messages.sort((a, b) {
      final ta = int.tryParse('${a['createdAt'] ?? a['time'] ?? 0}') ?? 0;
      final tb = int.tryParse('${b['createdAt'] ?? b['time'] ?? 0}') ?? 0;
      return ta.compareTo(tb);
    });
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _checkBlocked() {
    _db.child('nurses_group_chat/blocked_users').onValue.listen((e) {
      blockedList = [];
      if (e.snapshot.value != null && e.snapshot.value is Map) {
        final data = Map<String, dynamic>.from(e.snapshot.value as Map);
        for (final entry in data.entries) {
          if (entry.value is! Map) continue;
          final v = Map<String, dynamic>.from(entry.value as Map);
          if ((v['userId'] ?? '').toString() == currentUserId) blockedList.add(v);
        }
      }
      if (mounted) setState(() {});
    });
  }

  void _listenTyping() {
    _db.child('nurseCommunityChat/typing').onValue.listen((e) {
      if (e.snapshot.value == null || e.snapshot.value is! Map) {
        typingText = '';
      } else {
        final data = Map<String, dynamic>.from(e.snapshot.value as Map);
        final names = <String>[];
        for (final entry in data.entries) {
          if (entry.value is! Map) continue;
          final v = Map<String, dynamic>.from(entry.value as Map);
          final nm = (v['name'] ?? '').toString();
          final tm = int.tryParse('${v['time'] ?? 0}') ?? 0;
          if (nm != currentUserName && DateTime.now().millisecondsSinceEpoch - tm < 5000) names.add(nm);
        }
        typingText = names.isEmpty ? '' : '${names.join(', ')} is typing...';
      }
      if (mounted) setState(() {});
    });
  }

  void _handleTyping() {
    _db.child('nurseCommunityChat/typing/$currentUserId').set({'name': currentUserName, 'time': DateTime.now().millisecondsSinceEpoch});
    Future.delayed(const Duration(seconds: 3), () => _db.child('nurseCommunityChat/typing/$currentUserId').remove());
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _mediaUrl(dynamic item) {
    if (item is String) return item;
    if (item is Map) {
      final v = Map<String, dynamic>.from(item);
      return (v['data'] ?? v['url'] ?? v['src'] ?? '').toString();
    }
    return '$item';
  }

  String _timeStr(dynamic t) {
    final v = int.tryParse('$t') ?? 0;
    if (v == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(v);
    return '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  // ===== SEND - Same 5 paths as HTML =====
  Future<void> _send() async {
    if (blockedList.isNotEmpty) { _toast('🚫 You are blocked — Contact CEO'); return; }
    final text = _msgController.text.trim();
    if (text.isEmpty && pendingImages.isEmpty && pendingVideos.isEmpty && pendingFiles.isEmpty) return;
    setState(() => isSending = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final messageId = 'MSG-$now-${DateTime.now().microsecondsSinceEpoch.toString().substring(8)}';
    final msgData = <String, dynamic>{
      'messageId': messageId,
      'senderId': currentUserId,
      'senderName': currentUserName,
      'senderPhoto': currentUserPhoto.isNotEmpty ? currentUserPhoto : 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(currentUserName)}&background=a78bfa&color=fff',
      'text': text,
      'createdAt': now,
      'createdAtStr': DateTime.now().toString(),
      'type': 'nurse_community',
    };
    if (pendingImages.isNotEmpty) msgData['images'] = pendingImages;
    if (pendingVideos.isNotEmpty) msgData['videos'] = pendingVideos;
    if (pendingFiles.isNotEmpty) msgData['files'] = pendingFiles;
    try {
      await _db.child('nurseCommunityChat/messages/$messageId').set(msgData);
      await _db.child('nurses_group_chat/messages/$messageId').set(msgData);
      await _db.child('nurseGroupChat/$messageId').set(msgData);
      await _db.child('communityChats/nurses/$messageId').set(msgData);
      await _db.child('ceoChats/nurseBoard/$messageId').set(msgData);
      _msgController.clear();
      pendingImages = [];
      pendingVideos = [];
      pendingFiles = [];
      _toast('✅ Message sent with photo + name');
    } catch (e) {
      _toast('Error: $e');
    }
    setState(() => isSending = false);
  }

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage();
    for (final x in picked) {
      final bytes = await x.readAsBytes();
      if (bytes.length > 20 * 1024 * 1024) continue;
      pendingImages.add('data:image/jpeg;base64,${base64Encode(bytes)}');
    }
    setState(() {});
    _toast('🖼️ ${pendingImages.length} image(s) ready');
  }

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    pendingVideos.add('data:video/mp4;base64,${base64Encode(bytes)}');
    setState(() {});
    _toast('🎥 Video ready');
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (res == null) return;
    for (final f in res.files) {
      if (f.bytes == null) continue;
      pendingFiles.add({'name': f.name, 'data': 'data:application/octet-stream;base64,${base64Encode(f.bytes!)}'});
    }
    setState(() {});
    _toast('📄 ${pendingFiles.length} file(s) ready');
  }

  Future<void> _editMessage(Map<String, dynamic> m) async {
    final key = (m['key'] ?? m['id'] ?? m['messageId'] ?? '').toString();
    final ctrl = TextEditingController(text: (m['text'] ?? '').toString());
    final newText = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('✏️ Edit your message'),
        content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Edit message...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (newText == null) return;
    if (newText.isEmpty) { _deleteMessage(m); return; }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.child('nurseCommunityChat/messages/$key').update({'text': newText, 'edited': true, 'editedAt': now});
    await _db.child('nurses_group_chat/messages/$key').update({'text': newText, 'edited': true});
    _toast('✅ Edited');
  }

  Future<void> _deleteMessage(Map<String, dynamic> m) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('🗑️ Delete?'), content: const Text('Delete this message for everyone?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
    if (confirm != true) return;
    final key = (m['key'] ?? m['id'] ?? m['messageId'] ?? '').toString();
    await _db.child('nurseCommunityChat/messages/$key').remove();
    await _db.child('nurses_group_chat/messages/$key').remove();
    await _db.child('nurseGroupChat/$key').remove();
    setState(() => messages.removeWhere((x) => (x['key'] ?? x['id'] ?? '').toString() == key));
    _toast('🗑️ Deleted');
  }

  @override
  Widget build(BuildContext context) {
    final isBlocked = blockedList.isNotEmpty;
    final filteredOnline = onlineNurses.where((n) => (n['name'] ?? '').toString().toLowerCase().contains(searchQ.toLowerCase())).toList();
    final displayOnline = filteredOnline.isEmpty && searchQ.isEmpty ? onlineNurses : filteredOnline;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0A1E),
        title: const Text('👩‍⚕️ Nurses Community Chat 💬', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton.icon(onPressed: () => setState(() => showSidebar = !showSidebar), icon: const Icon(Icons.people, color: Colors.white, size: 16), label: Text('Online (${onlineNurses.length})', style: const TextStyle(color: Colors.white, fontSize: 11))),
          // NO CEO BUTTON HERE - REMOVED ON PURPOSE
        ],
      ),
      body: Row(
        children: [
          // Sidebar - Online Nurses - Desktop / toggle on mobile
          if (showSidebar)
            Container(
              width: 250,
              color: const Color(0xFF1A1633),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [const Expanded(child: Text('👥 Nurses', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))), IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 18), onPressed: () => setState(() => showSidebar = false))]),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(onChanged: (v) => setState(() => searchQ = v), style: const TextStyle(color: Colors.white, fontSize: 12), decoration: InputDecoration(hintText: '🔍 Search...', hintStyle: const TextStyle(color: Colors.white54, fontSize: 11), filled: true, fillColor: Colors.white.withOpacity(0.06), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: displayOnline.isEmpty
                        ? const Center(child: Text('No nurses online', style: TextStyle(color: Colors.white54, fontSize: 12)))
                        : ListView.builder(
                            itemCount: displayOnline.length,
                            itemBuilder: (context, i) {
                              final n = displayOnline[i];
                              final photo = (n['photo'] ?? '').toString();
                              return ListTile(
                                leading: CircleAvatar(backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null, child: photo.isEmpty ? Text((n['name'] ?? 'N').toString().substring(0, 1)) : null),
                                title: Text((n['name'] ?? 'Nurse').toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                subtitle: Text((n['specialty'] ?? '').toString(), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                trailing: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF34D399), shape: BoxShape.circle)),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          // Chat Area
          Expanded(
            child: Column(
              children: [
                if (isBlocked)
                  Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), border: Border.all(color: Colors.red.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)),
                    child: Text('🚫 YOU ARE BLOCKED\nReason: ${blockedList[0]['reason'] ?? 'Misbehaving'} • By: ${blockedList[0]['blockedBy'] ?? 'CEO'}', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                Expanded(
                  child: messages.isEmpty
                      ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text('💬', style: TextStyle(fontSize: 40)), SizedBox(height: 12), Text('Welcome to Nurses Community Chat!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), SizedBox(height: 6), Text('Photo + Name appears for everyone who chats', style: TextStyle(color: Colors.white54, fontSize: 12))]))
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(14),
                          itemCount: messages.length,
                          itemBuilder: (context, i) {
                            final msg = messages[i];
                            final senderId = (msg['senderId'] ?? '').toString();
                            final senderName = (msg['senderName'] ?? msg['name'] ?? 'Nurse').toString();
                            final senderPhoto = (msg['senderPhoto'] ?? msg['photo'] ?? '').toString();
                            final isMe = senderId == currentUserId;
                            final isCEO = senderId.contains('CEO') || senderName.contains('CEO') || msg['isCEO'] == true;
                            final isEdited = msg['edited'] == true;
                            final text = (msg['text'] ?? '').toString();
                            final images = msg['images'] is List ? (msg['images'] as List) : <dynamic>[];
                            final videos = msg['videos'] is List ? (msg['videos'] as List) : <dynamic>[];
                            final files = msg['files'] is List ? (msg['files'] as List) : <dynamic>[];
                            final voice = (msg['voice'] ?? '').toString();
                            final videoMsg = (msg['videoMessage'] ?? '').toString();

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: isCEO ? const Color(0xFF2A1A00) : const Color(0xFF1A1633), borderRadius: BorderRadius.circular(16), border: Border.all(color: isCEO ? const Color(0xFFFACC15).withOpacity(0.4) : Colors.white10)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(radius: 18, backgroundImage: senderPhoto.isNotEmpty ? NetworkImage(senderPhoto) : null, child: senderPhoto.isEmpty ? Text(senderName.isNotEmpty ? senderName.substring(0, 1) : 'N') : null),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(child: Text(senderName, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                                                const SizedBox(width: 6),
                                                if (isCEO) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFFACC15).withOpacity(0.2), borderRadius: BorderRadius.circular(999)), child: const Text('👑 CEO', style: TextStyle(color: Color(0xFFFACC15), fontSize: 9, fontWeight: FontWeight.bold)))
                                                else if (isMe) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(999)), child: const Text('You', style: TextStyle(color: Colors.white70, fontSize: 9)))
                                                else Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.purple.withOpacity(0.2), borderRadius: BorderRadius.circular(999)), child: const Text('👩‍⚕️ Nurse', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 9))),
                                              ],
                                            ),
                                            Text('${_timeStr(msg['createdAt'] ?? msg['time'])}${isEdited ? ' • edited' : ''}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14))),
                                  // Images - FIXED spread: ... + .map().toList() - NO extra [ ]
                                  if (images.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: images.map<Widget>((img) {
                                          final url = _mediaUrl(img);
                                          return ClipRRect(borderRadius: BorderRadius.circular(10), child: url.startsWith('data:') || url.startsWith('http') ? Image.network(url, width: 140, height: 140, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 140, height: 60, color: Colors.white10, child: const Center(child: Text('🖼️ Image', style: TextStyle(color: Colors.white54, fontSize: 11))))) : Container(width: 140, height: 60, color: Colors.white10, child: Center(child: Text('🖼️ $url', style: TextStyle(color: Colors.white54, fontSize: 11)))));
                                        }).toList(),
                                      ),
                                    ),
                                  // Videos
                                  if (videos.isNotEmpty)
                                    ...videos.map<Widget>((v) => Padding(padding: const EdgeInsets.only(top: 6), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)), child: Text('🎥 Video: ${_mediaUrl(v)}', style: const TextStyle(color: Colors.white70, fontSize: 12))))).toList(),
                                  // Voice
                                  if (voice.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)), child: const Text('🎤 Voice message', style: TextStyle(color: Colors.white70, fontSize: 12)))),
                                  // Video Message
                                  if (videoMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)), child: const Text('🎥 Video message', style: TextStyle(color: Colors.white70, fontSize: 12)))),
                                  // Files
                                  if (files.isNotEmpty)
                                    ...files.map<Widget>((f) {
                                      String fname = '';
                                      if (f is Map) fname = (Map<String, dynamic>.from(f)['name'] ?? '').toString();
                                      return Padding(padding: const EdgeInsets.only(top: 6), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)), child: Row(children: [Expanded(child: Text('📄 $fname', style: const TextStyle(color: Colors.white, fontSize: 12))), const Text('⬇️ Download', style: TextStyle(color: Colors.white70, fontSize: 10))])) );
                                    }).toList(),
                                  // Actions - Edit/Delete only for ME, CEO badge only for CEO
                                  if (isMe)
                                    Row(children: [TextButton(onPressed: () => _editMessage(msg), child: const Text('✏️ Edit', style: TextStyle(fontSize: 11))), TextButton(onPressed: () => _deleteMessage(msg), child: const Text('🗑️ Delete', style: TextStyle(color: Colors.redAccent, fontSize: 11)))])
                                  else if (isCEO)
                                    const Padding(padding: EdgeInsets.only(top: 6), child: Text('👑 CEO — From CEO Control Chat', style: TextStyle(fontSize: 9, color: Color(0xFFFACC15)))),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                if (typingText.isNotEmpty) Container(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text(typingText, style: const TextStyle(color: Colors.white54, fontSize: 11))),
                // Pending preview
                if (pendingImages.isNotEmpty || pendingVideos.isNotEmpty || pendingFiles.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    color: Colors.white.withOpacity(0.05),
                    child: Text('📎 Ready: ${pendingImages.length} image(s) • ${pendingVideos.length} video(s) • ${pendingFiles.length} file(s) — Tap Send to send all', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ),
                // Emoji panel
                if (showEmoji)
                  Container(
                    height: 120,
                    padding: const EdgeInsets.all(10),
                    color: const Color(0xFF1A1633),
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, crossAxisSpacing: 6, mainAxisSpacing: 6),
                      itemCount: emojis.length,
                      itemBuilder: (context, idx) => InkWell(onTap: () { _msgController.text += emojis[idx]; setState(() => showEmoji = false); }, child: Center(child: Text(emojis[idx], style: const TextStyle(fontSize: 22)))),
                    ),
                  ),
                // Input area
                Container(
                  padding: const EdgeInsets.all(10),
                  color: const Color(0xFF1A1633),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(icon: const Icon(Icons.emoji_emotions, color: Colors.white70), onPressed: () => setState(() => showEmoji = !showEmoji)),
                          IconButton(icon: const Icon(Icons.image, color: Colors.white70), onPressed: _pickImages, tooltip: 'Images'),
                          IconButton(icon: const Icon(Icons.videocam, color: Colors.white70), onPressed: _pickVideo, tooltip: 'Video'),
                          IconButton(icon: const Icon(Icons.attach_file, color: Colors.white70), onPressed: _pickFiles, tooltip: 'Files'),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _msgController,
                              enabled: !isBlocked,
                              onChanged: (_) => _handleTyping(),
                              style: const TextStyle(color: Colors.white),
                              maxLines: 3,
                              minLines: 1,
                              decoration: InputDecoration(hintText: isBlocked ? '🚫 Blocked — Contact CEO' : 'Type message to all nurses... 💬', hintStyle: const TextStyle(color: Colors.white54, fontSize: 13), filled: true, fillColor: Colors.white.withOpacity(0.06), border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            backgroundColor: const Color(0xFF7C3AED),
                            child: IconButton(icon: isSending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send, color: Colors.white, size: 18), onPressed: isSending ? null : _send),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
