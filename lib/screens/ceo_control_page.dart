import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'ceo_service.dart';

class CeoControlPage extends StatefulWidget {
  const CeoControlPage({super.key});
  @override State<CeoControlPage> createState() => _CeoControlPageState();
}

class _CeoControlPageState extends State<CeoControlPage> {
  String dest = 'nurses'; // nurses or index
  final _textCtrl = TextEditingController();
  final _videoUrlCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();
  String textColor = '#FFFFFF';
  String bgColor = '#191531';
  String displayType = 'marquee_slow';
  String speed = 'slow';
  bool sending = false;
  List<CeoAnnouncement> history = [];

  @override void initState() { super.initState(); _loadHistory(); }
  Future<void> _loadHistory() async {
    final msgs = await CeoService.getNursesMessages();
    if (mounted) setState(() => history = msgs);
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final XFile? f = await picker.pickVideo(source: ImageSource.gallery);
    if (f != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Video picked: ${f.name}. Paste video URL below or upload to Storage and paste link.')));
    }
  }

  Future<void> _send() async {
    if (_textCtrl.text.trim().isEmpty && _videoUrlCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type message or video URL first')));
      return;
    }
    setState(() => sending = true);
    final ok = await CeoService.send(dest: dest, text: _textCtrl.text.trim(), textColor: textColor, bgColor: bgColor, displayType: displayType, speed: speed, videoUrl: _videoUrlCtrl.text.trim(), imageUrl: _imageUrlCtrl.text.trim());
    setState(() => sending = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dest == 'nurses' ? 'Sent to Nurses Group Chat' : 'Sent to Home Page Banner - will show on Index now')));
      _textCtrl.clear(); _videoUrlCtrl.clear(); _imageUrlCtrl.clear();
      _loadHistory();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed - check internet')));
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CEO Control'), backgroundColor: const Color(0xFF1E0A3A)),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('SEND TO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: ChoiceChip(label: const Text('Nurses Group Chat'), selected: dest == 'nurses', onSelected: (_) => setState(() => dest = 'nurses'))),
          const SizedBox(width: 8),
          Expanded(child: ChoiceChip(label: const Text('Home Page Banner'), selected: dest == 'index', onSelected: (_) => setState(() => dest = 'index'))),
        ]),
        const SizedBox(height: 6),
        Text(dest == 'nurses' ? 'Messages go to Nurses Group Chat - Nurses see with photo + name' : 'Will display in Welcome banner on Home Page - Colour + speed editable', style: const TextStyle(color: Color(0xFFC4B5FD), fontSize: 12)),
        const SizedBox(height: 16),
        if (dest == 'index') ...[
          const Text('HOME SETTINGS', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(value: displayType, decoration: const InputDecoration(labelText: 'Display Type', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'marquee_slow', child: Text('Slow Move')), DropdownMenuItem(value: 'marquee_fast', child: Text('Fast Move')), DropdownMenuItem(value: 'static', child: Text('Static')), DropdownMenuItem(value: 'photo_full', child: Text('Full Photo/Video'))], onChanged: (v) => setState(() => displayType = v!))),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String>(value: speed, decoration: const InputDecoration(labelText: 'Speed', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'slow', child: Text('Slow')), DropdownMenuItem(value: 'medium', child: Text('Medium')), DropdownMenuItem(value: 'fast', child: Text('Fast'))], onChanged: (v) => setState(() => speed = v!))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: TextEditingController(text: textColor), decoration: const InputDecoration(labelText: 'Text Colour e.g #FFFFFF', border: OutlineInputBorder()), onChanged: (v) => textColor = v)),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: TextEditingController(text: bgColor), decoration: const InputDecoration(labelText: 'Background e.g #191531', border: OutlineInputBorder()), onChanged: (v) => bgColor = v)),
          ]),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12)), child: Text('PREVIEW: ${_textCtrl.text.isEmpty ? 'Type to preview...' : _textCtrl.text}', style: const TextStyle(color: Colors.white))),
          const SizedBox(height: 16),
        ],
        TextField(controller: _textCtrl, maxLines: 3, decoration: InputDecoration(labelText: dest == 'nurses' ? 'Message to nurses...' : 'Announcement for home page...', border: const OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _videoUrlCtrl, decoration: const InputDecoration(labelText: 'Video URL - paste your CEO video link here', border: OutlineInputBorder(), prefixIcon: Icon(Icons.videocam))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _pickVideo, icon: const Icon(Icons.video_library), label: const Text('Pick Video from Phone'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: () async { final p = ImagePicker(); final f = await p.pickImage(source: ImageSource.gallery); if (f != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo picked: ${f.name}'))); }, icon: const Icon(Icons.photo), label: const Text('Pick Photo'))),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _imageUrlCtrl, decoration: const InputDecoration(labelText: 'Photo URL (optional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.image))),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: dest == 'nurses' ? const Color(0xFFA855F7) : const Color(0xFFFACC15), padding: const EdgeInsets.all(16)), onPressed: sending ? null : _send, child: Text(sending ? 'Sending...' : dest == 'nurses' ? 'Send to Nurses Group Chat' : 'Send to Home Page Banner', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900)))),
        const SizedBox(height: 20),
        const Text('Recent Nurses Messages', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        ...history.reversed.map((m) => Card(color: const Color(0xFF1C1238), child: ListTile(title: Text(m.text, style: const TextStyle(color: Colors.white)), subtitle: Text(m.senderName, style: const TextStyle(color: Color(0xFFA78BFA))), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () async { await CeoService.delete(m.id, 'nurses'); _loadHistory(); })))),
      ])),
    );
  }
}
