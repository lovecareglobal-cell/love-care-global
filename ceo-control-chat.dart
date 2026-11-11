import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// CEO Control Chat - CLEAN FIXED SOUND WITH NOTIFICATIONS - Flutter version
/// - Destination pills: 💬 Nurses Group Chat / 🏠 Home Page Banner (same as HTML setDest)
/// - Nurses: sends to nurses_group_chat/messages + nurseCommunityChat/messages
/// - Home: sends to ceoHomePageAnnouncements + ceoHomePageCurrent + homePageBanner/current with textColor, bgColor, displayType, speed, active
/// - Chat loads: nurses_group_chat/messages limit 40 + ceoHomePageAnnouncements limit 20
/// - Attachments: Images / Videos / Docs as base64 (same as HTML hImgs/hVids/hDocs)
/// - Emoji panel, Edit/Delete, OneSignal push: all_nurses / all_clients / single / all

class CEOControlChatScreen extends StatefulWidget {
  const CEOControlChatScreen({super.key});
  @override
  State<CEOControlChatScreen> createState() => _CEOControlChatScreenState();
}

class _CEOControlChatScreenState extends State<CEOControlChatScreen> {
  String dest = 'nurses'; // nurses or index
  final _inputCtrl = TextEditingController();
  List<Map> messages = [];
  List<Map> imgs = [], vids = [], docs = [];
  String textColor = '#FFFFFF';
  String bgColor = '#7C3AED';
  String displayType = 'marquee';
  String speed = 'normal';
  bool showEmoji = false;
  bool showSettings = false;
  // OneSignal
  String notifTitle = '', notifMsg = '', notifUrl = 'nurses-dashboard.html', notifUid = '';
  String notifTarget = 'all_nurses';
  String oneSignalAppId = '', oneSignalApiKey = '';
  String notifStatus = '';

  final emojis = ['😊','😂','❤️','👍','👏','🙏','💪','😍','🥰','😘','😅','🤣','😎','🤩','😭','🥺','😮','😱','🤔','👌','✌️','🤝','💯','🔥','⭐','🌟','💖','💜','👩‍⚕️','👑','📢','🎉'];

  @override
  void initState() {
    super.initState();
    _loadMsgs();
    _loadOneSignalKeys();
  }

  Future<void> _loadOneSignalKeys() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      oneSignalAppId = prefs.getString('onesignal_app_id') ?? '';
      oneSignalApiKey = prefs.getString('onesignal_api_key') ?? '';
    });
  }

  Future<void> _saveOneSignalKeys() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('onesignal_app_id', oneSignalAppId);
    await prefs.setString('onesignal_api_key', oneSignalApiKey);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ OneSignal keys saved')));
  }

  void _loadMsgs() {
    FirebaseDatabase.instance.ref('nurses_group_chat/messages').limitToLast(40).onChildAdded.listen((e) {
      if (!e.snapshot.exists) return;
      final m = Map<String, dynamic>.from(e.snapshot.value as Map);
      setState(() { if (!messages.any((x) => x['key'] == e.snapshot.key)) messages.add({...m, 'key': e.snapshot.key, 'type': 'nurses'}); });
    });
    FirebaseDatabase.instance.ref('ceoHomePageAnnouncements').limitToLast(20).onChildAdded.listen((e) {
      if (!e.snapshot.exists) return;
      final m = Map<String, dynamic>.from(e.snapshot.value as Map);
      setState(() { if (!messages.any((x) => x['key'] == e.snapshot.key)) messages.add({...m, 'key': e.snapshot.key, 'type': 'home'}); });
    });
  }

  void _setDest(String d) {
    setState(() { dest = d; showSettings = d == 'index'; });
  }

  Future<void> _pickFiles(String kind) async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, type: kind == 'image' ? FileType.image : kind == 'video' ? FileType.video : FileType.any);
    if (res == null) return;
    for (final f in res.files) {
      if (f.path == null) continue;
      final bytes = await File(f.path!).readAsBytes();
      final b64 = 'data:${kind == 'image' ? 'image/jpeg' : kind == 'video' ? 'video/mp4' : 'application/octet-stream'};base64,${base64Encode(bytes)}';
      setState(() {
        if (kind == 'image') imgs.add({'name': f.name, 'data': b64});
        else if (kind == 'video') vids.add({'name': f.name, 'data': b64});
        else docs.add({'name': f.name, 'data': b64});
      });
    }
  }

  Future<void> _send() async {
    final txt = _inputCtrl.text.trim();
    if (txt.isEmpty && imgs.isEmpty && vids.isEmpty && docs.isEmpty) return;
    final id = 'MSG-${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecondsSinceEpoch.toString().substring(8, 12)}';
    final now = DateTime.now().millisecondsSinceEpoch;
    final base = {'messageId': id, 'senderId': 'CEO', 'senderName': 'CEO', 'senderPhoto': '', 'text': txt, 'createdAt': now, 'isCEO': true};
    if (imgs.isNotEmpty) base['images'] = imgs;
    if (vids.isNotEmpty) base['videos'] = vids;
    if (docs.isNotEmpty) base['files'] = docs;
    final db = FirebaseDatabase.instance;
    if (dest == 'nurses') {
      await db.ref('nurses_group_chat/messages/$id').set({...base, 'destination': 'nurses'});
      await db.ref('nurseCommunityChat/messages/$id').set({...base, 'destination': 'nurses'});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sent to nurse-group-chat.html')));
    } else {
      final home = {...base, 'announcementId': id, 'textColor': textColor, 'bgColor': bgColor, 'displayType': displayType, 'speed': speed, 'active': true, 'destination': 'index', 'isHomePage': true};
      await db.ref('ceoHomePageAnnouncements/$id').set(home);
      await db.ref('ceoHomePageCurrent').set(home);
      await db.ref('homePageBanner/current').set(home);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sent to Home Page banner')));
    }
    setState(() { _inputCtrl.clear(); imgs = []; vids = []; docs = []; });
  }

  Future<void> _delMsg(String key, String type) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Delete?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes'))]));
    if (confirm != true) return;
    final db = FirebaseDatabase.instance;
    await db.ref('nurses_group_chat/messages/$key').remove().catchError((_) {});
    await db.ref('nurseCommunityChat/messages/$key').remove().catchError((_) {});
    await db.ref('ceoHomePageAnnouncements/$key').remove().catchError((_) {});
    await db.ref('ceoHomePageCurrent').remove().catchError((_) {});
    setState(() => messages.removeWhere((m) => m['key'] == key));
  }

  Future<void> _editMsg(Map m) async {
    final ctrl = TextEditingController(text: m['text'] ?? '');
    final newText = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Edit Message'), content: TextField(controller: ctrl, maxLines: 3), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Save'))]));
    if (newText == null) return;
    final db = FirebaseDatabase.instance;
    await db.ref('nurses_group_chat/messages/${m['key']}').update({'text': newText}).catchError((_) {});
    await db.ref('ceoHomePageAnnouncements/${m['key']}').update({'text': newText}).catchError((_) {});
    setState(() => m['text'] = newText);
  }

  Future<void> _sendPushNotification() async {
    if (oneSignalAppId.isEmpty || oneSignalApiKey.isEmpty) {
      setState(() => notifStatus = '❌ Paste OneSignal App ID + REST API Key first');
      return;
    }
    setState(() => notifStatus = '⏳ Sending to $notifTarget...');
    Map<String, dynamic> body = {
      'app_id': oneSignalAppId,
      'headings': {'en': notifTitle.isEmpty ? 'Love Care Global' : notifTitle},
      'contents': {'en': notifMsg.isEmpty ? 'New notification' : notifMsg},
      'data': {'url': notifUrl, 'target': notifTarget},
      'url': notifUrl,
      'chrome_web_icon': 'icon-transparent-512.png',
      'android_accent_color': 'A855F7',
    };
    if (notifTarget == 'all_nurses') body['filters'] = [{'field': 'tag', 'key': 'role', 'relation': '=', 'value': 'nurse'}];
    else if (notifTarget == 'all_clients') body['filters'] = [{'field': 'tag', 'key': 'role', 'relation': '=', 'value': 'client'}];
    else if (notifTarget == 'single') {
      if (notifUid.isEmpty) { setState(() => notifStatus = '❌ Enter Nurse UID for One Nurse'); return; }
      body['include_external_user_ids'] = [notifUid];
      body['channel_for_external_user_ids'] = 'push';
    } else body['included_segments'] = ['All'];
    try {
      final res = await http.post(Uri.parse('https://onesignal.com/api/v1/notifications'), headers: {'Content-Type': 'application/json', 'Authorization': 'Basic $oneSignalApiKey'}, body: jsonEncode(body));
      final data = jsonDecode(res.body);
      if (data['id'] != null) {
        setState(() => notifStatus = '✅ Sent! ID: ${data['id']} | Recipients: ${data['recipients'] ?? 'queued'} - Nurses will get it even if app is closed');
        await FirebaseDatabase.instance.ref('ceoNotifications/${DateTime.now().millisecondsSinceEpoch}').set({'title': notifTitle, 'message': notifMsg, 'target': notifTarget, 'url': notifUrl, 'sentAt': DateTime.now().millisecondsSinceEpoch, 'onesignalId': data['id'], 'recipients': data['recipients']});
      } else setState(() => notifStatus = '❌ Failed: ${res.body}');
    } catch (e) { setState(() => notifStatus = '❌ Error: $e'); }
  }

  Color _parseColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C1E),
      appBar: AppBar(title: const Row(children: [Text('CEO Control', style: TextStyle(fontWeight: FontWeight.bold)), SizedBox(width: 8), Text('Clean', style: TextStyle(color: Colors.white60, fontSize: 12))]), backgroundColor: const Color(0xFF141028), actions: [IconButton(icon: const Icon(Icons.notifications), onPressed: () {})]),
      body: Column(children: [
        Container(padding: const EdgeInsets.all(12), color: const Color(0xFF191531), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('SEND TO', style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('💬 Nurses Group Chat'), selected: dest == 'nurses', onSelected: (_) => _setDest('nurses'), selectedColor: const Color(0xFFA78BFA).withOpacity(0.2)),
            ChoiceChip(label: const Text('🏠 Home Page Banner'), selected: dest == 'index', onSelected: (_) => _setDest('index'), selectedColor: const Color(0xFFFACC15).withOpacity(0.2)),
          ]),
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: dest == 'nurses' ? const Color(0xFFA78BFA).withOpacity(0.08) : const Color(0xFFFACC15).withOpacity(0.08), borderRadius: BorderRadius.circular(10)), child: Text(dest == 'nurses' ? 'Messages go to nurse-group-chat.html — Nurses see with photo + name' : 'Will display in Welcome banner on index.html — Colour + speed editable', style: TextStyle(color: dest == 'nurses' ? const Color(0xFFC4B5FD) : const Color(0xFFFACC15), fontSize: 11))),
          if (showSettings) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(decoration: const InputDecoration(labelText: 'Text Color (e.g. #FFFFFF)', border: OutlineInputBorder()), onChanged: (v) => setState(() => textColor = v.isEmpty ? '#FFFFFF' : v), controller: TextEditingController(text: textColor))),
              const SizedBox(width: 8),
              Expanded(child: TextField(decoration: const InputDecoration(labelText: 'Bg Color (e.g. #7C3AED)', border: OutlineInputBorder()), onChanged: (v) => setState(() => bgColor = v.isEmpty ? '#7C3AED' : v), controller: TextEditingController(text: bgColor))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(value: displayType, decoration: const InputDecoration(labelText: 'Display Type', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'marquee', child: Text('Marquee')), DropdownMenuItem(value: 'marquee_fast', child: Text('Marquee Fast')), DropdownMenuItem(value: 'photo_full', child: Text('Photo Full')), DropdownMenuItem(value: 'static', child: Text('Static'))], onChanged: (v) => setState(() => displayType = v ?? 'marquee'))),
              const SizedBox(width: 8),
              Expanded(child: DropdownButtonFormField<String>(value: speed, decoration: const InputDecoration(labelText: 'Speed', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'slow', child: Text('Slow')), DropdownMenuItem(value: 'normal', child: Text('Normal')), DropdownMenuItem(value: 'fast', child: Text('Fast'))], onChanged: (v) => setState(() => speed = v ?? 'normal'))),
            ]),
            const SizedBox(height: 8),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _parseColor(bgColor), borderRadius: BorderRadius.circular(12)), child: Text('📢 ${_inputCtrl.text.isEmpty ? 'Preview...' : _inputCtrl.text} — CEO', style: TextStyle(color: _parseColor(textColor)))),
          ],
        ])),
        Expanded(child: messages.isEmpty ? const Center(child: Text('Clean CEO — No messages yet', style: TextStyle(color: Colors.white60))) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: messages.length, itemBuilder: (_, i) {
          final m = messages[i];
          final isHome = m['type'] == 'home';
          final time = m['createdAt'] != null ? TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch((m['createdAt'] as num).toInt())).format(context) : '';
          return Align(alignment: Alignment.centerRight, child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78), decoration: BoxDecoration(color: isHome ? const Color(0xFFFACC15) : const Color(0xFFA78BFA), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Text('👑 CEO ${isHome ? '🏠 HOME' : '💬 NURSES'} ${m['senderName'] ?? 'CEO'} $time', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isHome ? Colors.black : Colors.white))]),
            const SizedBox(height: 4),
            Text(m['text'] ?? '', style: TextStyle(color: isHome ? Colors.black : Colors.white)),
            if (m['displayType'] != null) Text('${m['displayType']} • ${m['speed'] ?? ''}', style: const TextStyle(fontSize: 10, color: Colors.white60)),
            Row(children: [TextButton(onPressed: () => _editMsg(m), child: const Text('Edit', style: TextStyle(fontSize: 11))), TextButton(onPressed: () => _delMsg(m['key'], m['type']), child: const Text('Delete', style: TextStyle(color: Colors.red, fontSize: 11)))]),
          ])));
        })),
        // OneSignal
        ExpansionTile(title: const Text('🔔 Push Notification — OneSignal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), children: [
          Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            TextField(decoration: const InputDecoration(labelText: 'OneSignal App ID', border: OutlineInputBorder()), onChanged: (v) => oneSignalAppId = v, controller: TextEditingController(text: oneSignalAppId)),
            const SizedBox(height: 8),
            TextField(decoration: const InputDecoration(labelText: 'OneSignal REST API Key', border: OutlineInputBorder()), onChanged: (v) => oneSignalApiKey = v, controller: TextEditingController(text: oneSignalApiKey)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _saveOneSignalKeys, child: const Text('Save Keys')),
            const SizedBox(height: 8),
            TextField(decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()), onChanged: (v) => notifTitle = v),
            const SizedBox(height: 8),
            TextField(decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder()), onChanged: (v) => notifMsg = v),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(value: notifTarget, decoration: const InputDecoration(labelText: 'Target', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'all_nurses', child: Text('All Nurses')), DropdownMenuItem(value: 'all_clients', child: Text('All Clients')), DropdownMenuItem(value: 'single', child: Text('One Nurse (UID)')), DropdownMenuItem(value: 'all', child: Text('All'))], onChanged: (v) => setState(() => notifTarget = v ?? 'all_nurses')),
            if (notifTarget == 'single') ...[const SizedBox(height: 8), TextField(decoration: const InputDecoration(labelText: 'Nurse UID', border: OutlineInputBorder()), onChanged: (v) => notifUid = v)],
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _sendPushNotification, child: const Text('Send Push'))),
            if (notifStatus.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(notifStatus, style: const TextStyle(fontSize: 11))),
          ])),
        ]),
        // Input
        Container(padding: const EdgeInsets.all(10), color: const Color(0xFF191531), child: Column(children: [
          if (imgs.isNotEmpty || vids.isNotEmpty || docs.isNotEmpty) Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: Text('Files: ${imgs.length} images, ${vids.length} videos, ${docs.length} docs', style: const TextStyle(fontSize: 11))),
          if (showEmoji) Container(height: 120, padding: const EdgeInsets.all(8), child: GridView.builder(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8), itemCount: emojis.length, itemBuilder: (_, i) => GestureDetector(onTap: () { _inputCtrl.text += emojis[i]; }, child: Center(child: Text(emojis[i], style: const TextStyle(fontSize: 20)))))),
          Row(children: [
            IconButton(icon: const Icon(Icons.emoji_emotions), onPressed: () => setState(() => showEmoji = !showEmoji)),
            IconButton(icon: const Icon(Icons.image), onPressed: () => _pickFiles('image')),
            IconButton(icon: const Icon(Icons.videocam), onPressed: () => _pickFiles('video')),
            IconButton(icon: const Icon(Icons.attach_file), onPressed: () => _pickFiles('doc')),
            Expanded(child: TextField(controller: _inputCtrl, maxLines: 3, minLines: 1, decoration: InputDecoration(hintText: dest == 'nurses' ? 'Message to nurses...' : 'Announcement for home page...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(20))), onChanged: (_) => setState(() {}))),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _send, style: ElevatedButton.styleFrom(backgroundColor: dest == 'nurses' ? const Color(0xFFA78BFA) : const Color(0xFFFACC15)), child: Text(dest == 'nurses' ? 'Send' : 'Send Home', style: const TextStyle(color: Colors.black))),
          ]),
          Text(dest == 'nurses' ? 'Sending to nurse-group-chat.html' : 'Sending to Home Page (index.html) Welcome banner', style: const TextStyle(color: Colors.white60, fontSize: 10)),
        ])),
      ],
    );
  }
}
