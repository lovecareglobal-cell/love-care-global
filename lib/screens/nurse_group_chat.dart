import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

/// Nurses Group Chat - Flutter version of nurse-group-chat.html
/// - NO CEO Board button (removed as requested)
/// - CEO messages show as 👑 CEO badge, but nurses cannot open CEO Control
/// - Video with sound: volume 1.0, muted=false, playsinline
/// - Uses same Firebase paths as PWA: nurseCommunityChat/messages + nurses_group_chat/messages

class NurseGroupChatScreen extends StatefulWidget {
  const NurseGroupChatScreen({super.key});
  @override
  State<NurseGroupChatScreen> createState() => _NurseGroupChatScreenState();
}

class _NurseGroupChatScreenState extends State<NurseGroupChatScreen> {
  final _msgCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map> messages = [];
  List<Map> onlineNurses = [];
  List<Map> filteredNurses = [];
  bool showSidebar = false;
  final picker = ImagePicker();
  bool isSending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadOnlineNurses();
  }

  void _loadMessages() {
    // Same as PWA: nurseCommunityChat/messages + nurses_group_chat/messages for CEO
    FirebaseDatabase.instance.ref('nurseCommunityChat/messages').limitToLast(150).onChildAdded.listen((e) {
      final v = e.snapshot.value as Map?;
      if (v == null) return;
      setState(() {
        messages.add({...v, 'key': e.snapshot.key});
        messages.sort((a, b) => (a['createdAt'] ?? 0).compareTo(b['createdAt'] ?? 0));
      });
      _scrollToBottom();
    });
    FirebaseDatabase.instance.ref('nurses_group_chat/messages').limitToLast(150).onChildAdded.listen((e) {
      final v = e.snapshot.value as Map?;
      if (v == null) return;
      final isCEO = v['senderId']?.toString().contains('CEO') ?? false;
      if (isCEO && !messages.any((m) => m['key'] == e.snapshot.key)) {
        setState(() {
          messages.add({...v, 'key': e.snapshot.key});
          messages.sort((a, b) => (a['createdAt'] ?? 0).compareTo(b['createdAt'] ?? 0));
        });
        _scrollToBottom();
      }
    });
  }

  void _loadOnlineNurses() {
    FirebaseDatabase.instance.ref('nurses').onValue.listen((e) {
      final data = e.snapshot.value as Map?;
      if (data == null) return;
      final list = data.entries.map((en) => {...(en.value as Map), 'uid': en.key}).toList();
      setState(() { onlineNurses = List<Map>.from(list); filteredNurses = List<Map>.from(list); });
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  Future<String> _uploadFile(File file, String folder) async {
    final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final ref = FirebaseStorage.instance.ref().child(path);
    final task = ref.putFile(file);
    await task;
    return await ref.getDownloadURL();
  }

  Future<void> _sendMessage({File? image, File? video}) async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty && image == null && video == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login first'))); return; }
    setState(() => isSending = true);
    try {
      final nurseSnap = await FirebaseDatabase.instance.ref('nurses/${user.uid}').get();
      final nurse = nurseSnap.value as Map? ?? {};
      final id = 'MSG-${DateTime.now().millisecondsSinceEpoch}';
      Map data = {
        'messageId': id,
        'senderId': user.uid,
        'senderName': nurse['name'] ?? user.displayName ?? 'Nurse',
        'senderPhoto': nurse['photoURL'] ?? nurse['photo'] ?? '',
        'text': text,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isCEO': false,
        'destination': 'nurses',
      };
      if (image != null) {
        final url = await _uploadFile(image, 'nurseCommunityChat/images');
        data['images'] = [{'name': image.path.split('/').last, 'url': url, 'data': url}];
      }
      if (video != null) {
        // Video with sound - upload to Storage, not base64 (fixes PWA audio bug)
        final url = await _uploadFile(video, 'nurseCommunityChat/videos');
        data['videos'] = [{'name': video.path.split('/').last, 'url': url, 'data': url}];
        data['videoURL'] = url; data['video'] = url;
      }
      await FirebaseDatabase.instance.ref('nurseCommunityChat/messages/$id').set(data);
      await FirebaseDatabase.instance.ref('nurses_group_chat/messages/$id').set(data);
      _msgCtrl.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send failed: $e')));
    } finally {
      setState(() => isSending = false);
    }
  }

  Future<void> _pickImage() async {
    final XFile? f = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (f != null) await _sendMessage(image: File(f.path));
  }

  Future<void> _pickVideo() async {
    final XFile? f = await picker.pickVideo(source: ImageSource.gallery);
    if (f != null) {
      final file = File(f.path);
      if (file.lengthSync() > 50 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video must be <50MB')));
        return;
      }
      await _sendMessage(video: file);
    }
  }

  Widget _buildMessage(Map msg) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isMe = msg['senderId'] == uid;
    final senderName = msg['senderName']?.toString() ?? 'Nurse';
    final isCEO = (msg['senderId']?.toString().contains('CEO') ?? false) || msg['isCEO'] == true || senderName.contains('CEO') || senderName.contains('Asabere');
    final photo = msg['senderPhoto']?.toString() ?? '';
    final time = msg['createdAt'] != null ? DateTime.fromMillisecondsSinceEpoch(msg['createdAt'] as int).toLocal().toString().substring(11, 16) : '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isCEO ? const Color(0xFFFACC15) : isMe ? const Color(0xFFA78BFA) : const Color(0xFF191531),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(radius: 14, backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null, child: photo.isEmpty ? const Text('👩') : null),
              const SizedBox(width: 6),
              Expanded(child: Text('$senderName ${isCEO ? '👑 CEO' : ''}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isCEO ? Colors.black : Colors.white))),
              Text(time, style: TextStyle(fontSize: 9, color: isCEO ? Colors.black54 : Colors.white60)),
            ]),
            if (msg['text']?.toString().isNotEmpty ?? false) ...[
              const SizedBox(height: 6),
              Text(msg['text'].toString(), style: TextStyle(color: isCEO ? Colors.black : Colors.white, fontSize: 13)),
            ],
            // Images
            if (msg['images'] is List) ...[(msg['images'] as List).map((img) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(img['url'] ?? img['data'] ?? '', height: 180, width: double.infinity, fit: BoxFit.cover)),
            ))],
            // Videos - WITH SOUND
            if (msg['videos'] is List) ...[(msg['videos'] as List).map((v) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _VideoWithSound(url: v['url'] ?? v['data'] ?? v['videoURL'] ?? ''),
            ))],
            if (msg['videoURL'] != null && msg['videos'] == null) _VideoWithSound(url: msg['videoURL'].toString()),
            if (msg['videoMessage'] != null) _VideoWithSound(url: msg['videoMessage'].toString()),
            if (msg['voice'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [const Icon(Icons.mic, size: 16, color: Colors.white), const SizedBox(width: 6), const Text('🎤 Voice', style: TextStyle(fontSize: 11, color: Colors.white))])),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('👩‍⚕️ Nurses Community Chat', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF191531),
        // NO CEO Board button - removed as requested
        actions: [
          IconButton(icon: const Icon(Icons.people), onPressed: () => setState(() => showSidebar = !showSidebar), tooltip: 'Online Nurses'),
          IconButton(icon: const Icon(Icons.home), onPressed: () => Navigator.pushNamed(context, '/dashboard')),
        ],
      ),
      body: Column(
        children: [
          if (showSidebar) Container(
            height: 140,
            color: const Color(0xFF1A1633),
            child: Column(children: [
              Padding(padding: const EdgeInsets.all(8), child: TextField(controller: _searchCtrl, onChanged: (q) {
                setState(() => filteredNurses = onlineNurses.where((n) => (n['name']?.toString().toLowerCase() ?? '').contains(q.toLowerCase())).toList());
              }, decoration: const InputDecoration(hintText: '🔍 Search nurses...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true))),
              Expanded(child: ListView.builder(itemCount: filteredNurses.length, itemBuilder: (_, i) {
                final n = filteredNurses[i];
                return ListTile(leading: CircleAvatar(backgroundImage: (n['photoURL'] ?? n['photo']) != null ? NetworkImage(n['photoURL'] ?? n['photo']) : null, child: (n['photoURL'] ?? n['photo']) == null ? const Text('👩') : null), title: Text(n['name']?.toString() ?? 'Nurse', style: const TextStyle(fontSize: 12)), subtitle: Text(n['specialty']?.toString() ?? 'Nurse', style: const TextStyle(fontSize: 10)), trailing: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)));
              })),
            ]),
          ),
          Expanded(
            child: messages.isEmpty
              ? const Center(child: Text('💬 Welcome! All nurses talk together here.\nCEO messages appear as 👑 CEO', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)))
              : ListView.builder(controller: _scrollCtrl, itemCount: messages.length, itemBuilder: (_, i) => _buildMessage(messages[i])),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            color: const Color(0xFF191531),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.image), onPressed: _pickImage, tooltip: 'Photo'),
              IconButton(icon: const Icon(Icons.videocam), onPressed: _pickVideo, tooltip: 'Video with sound'),
              Expanded(child: TextField(controller: _msgCtrl, decoration: InputDecoration(hintText: 'Type message...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)))),
              const SizedBox(width: 6),
              CircleAvatar(backgroundColor: const Color(0xFFA855F7), child: IconButton(icon: Icon(isSending ? Icons.hourglass_empty : Icons.send, color: Colors.white), onPressed: isSending ? null : () => _sendMessage())),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Video player with SOUND ON - fixes PWA muted bug
class _VideoWithSound extends StatefulWidget {
  final String url;
  const _VideoWithSound({required this.url});
  @override
  State<_VideoWithSound> createState() => _VideoWithSoundState();
}
class _VideoWithSoundState extends State<_VideoWithSound> {
  VideoPlayerController? _ctrl;
  ChewieController? _chewie;
  @override
  void initState() {
    super.initState();
    if (widget.url.isNotEmpty && widget.url.startsWith('http')) {
      _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _ctrl!.initialize().then((_) {
        if (!mounted) return;
        _ctrl!.setVolume(1.0);
        setState(() {
          _chewie = ChewieController(videoPlayerController: _ctrl!, autoPlay: false, looping: false, showControls: true, allowFullScreen: true, allowMuting: true, placeholder: Container(color: Colors.black, child: const Center(child: Text('🔊 Tap Play - Sound ON', style: TextStyle(color: Colors.white, fontSize: 11)))));
        });
      });
    }
  }
  @override
  void dispose() { _ctrl?.dispose(); _chewie?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (_chewie == null) return Container(height: 120, color: Colors.black, child: const Center(child: CircularProgressIndicator()));
    return Column(children: [
      AspectRatio(aspectRatio: 16/9, child: Chewie(controller: _chewie!)),
      Container(width: double.infinity, padding: const EdgeInsets.all(6), color: Colors.black54, child: const Text('🔊 Sound ON - Tap 🔊 if no sound', style: TextStyle(color: Color(0xFF86EFAC), fontSize: 10, fontWeight: FontWeight.bold))),
    ]);
  }
}
