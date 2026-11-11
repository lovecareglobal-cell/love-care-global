import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

/// Nurse Complaint - Flutter version of nurse-complaint.html
/// - Params: bookingId, clientName, clientId, nurseName, nurseId, service, amount (route args, same as URL ?bookingId=... in HTML)
/// - Complaint Type: abuse / non_payment / unsafe / harassment / false_accusation / overwork / other
/// - Text min 20 chars, confirm dialog, ID NURSE-COMP-{bookingId}-{now}
/// - Evidence: Files (base64) + Audio (base64) + Video (base64) via file_picker — HTML used MediaRecorder, Flutter uses file_picker for audio/video files
/// - Saves to: nurseComplaints/{id} + allComplaints/{id} + ceoComplaints/{id} + complaintsByBooking/{bookingId}/{id}
///   Data: complaintId, bookingId, clientId, clientName, nurseId, nurseName, service, amount, complaintType, complaintText, status pending, createdAt, time, evidenceCount, evidenceFiles, hasAudio, hasVideo, type nurse_complaint, from nurse, to client, reflectsOnCEO true
/// - After: toast + dialog + navigate to /my-job-offers (HTML: my-job-offer.html after 1.5s)
/// - My Work Ethics Notices (Punishment System): searches userNotices / ceoNotices / nurseNotices / notices / noticesByEmail / noticesByPhone for ALL nurse IDs + allNotices where victimType==nurse && victimEmail/phone/id matches
///   + live listener userNotices/{uid} child_added within 60s + unread -> confirm dialog -> open notice
/// - Notice actions: Mark Read (userNotices/{uid}/{id} isRead), Appeal (noticeAppeals/{id} {noticeId, userId, reason, createdAt, status pending})

class NurseComplaintScreen extends StatefulWidget {
  final Map<String, dynamic>? params;
  const NurseComplaintScreen({super.key, this.params});
  @override
  State<NurseComplaintScreen> createState() => _NurseComplaintScreenState();
}

class _NurseComplaintScreenState extends State<NurseComplaintScreen> {
  String bookingId = 'LCG-DEMO', clientName = 'Client', clientId = 'client_demo', nurseName = 'Nurse', nurseId = 'nurse_demo', service = 'Nursing Care', amount = '0';
  String complaintType = '';
  final _textCtrl = TextEditingController();
  List<Map> evidenceFiles = [];
  String? audioBase64, videoBase64;
  List<Map> notices = [];
  bool showNotices = false;
  String checkedIds = '';

  final types = const [
    {'v': 'abuse', 'l': '😡 Abuse / Verbal Abuse'},
    {'v': 'non_payment', 'l': '💰 Non Payment'},
    {'v': 'unsafe', 'l': '⚠️ Unsafe Environment'},
    {'v': 'harassment', 'l': '🚫 Harassment'},
    {'v': 'false_accusation', 'l': '❌ False Accusation'},
    {'v': 'overwork', 'l': '😰 Overwork'},
    {'v': 'other', 'l': '📝 Other'},
  ];

  @override
  void initState() {
    super.initState();
    _loadParams();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) _applyParams(Map<String, dynamic>.from(args));
  }

  void _loadParams() {
    if (widget.params != null) _applyParams(widget.params!);
    _loadNotices();
    _listenNewNotices();
  }

  void _applyParams(Map p) {
    setState(() {
      bookingId = (p['bookingId'] ?? p['id'] ?? bookingId).toString();
      clientName = (p['clientName'] ?? clientName).toString();
      clientId = (p['clientId'] ?? p['clientUid'] ?? clientId).toString();
      nurseName = (p['nurseName'] ?? nurseName).toString();
      nurseId = (p['nurseId'] ?? p['nurseUid'] ?? nurseId).toString();
      service = (p['service'] ?? p['serviceType'] ?? service).toString();
      amount = (p['amount'] ?? amount).toString();
    });
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<List<String>> _allIds() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('nurseEmail') ?? prefs.getString('email') ?? '';
    final phone = prefs.getString('nursePhone') ?? prefs.getString('phone') ?? '';
    final phone9 = phone.replaceAll(RegExp(r'[^0-9]'), '').length >= 9 ? phone.replaceAll(RegExp(r'[^0-9]'), '').substring(phone.replaceAll(RegExp(r'[^0-9]'), '').length - 9) : '';
    final ids = [prefs.getString('lcg_nurse_uid'), prefs.getString('nurseUid'), prefs.getString('nurseId'), prefs.getString('uid'), email, email.isNotEmpty ? email.toLowerCase().replaceAll(RegExp(r'[.#\$@\[\]]'), '_') : '', phone, phone9, prefs.getString('email'), prefs.getString('phone')];
    return ids.whereType<String>().where((e) => e.isNotEmpty).toSet().toList();
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res == null) return;
    for (final f in res.files) {
      if (f.path == null) continue;
      final bytes = await File(f.path!).readAsBytes();
      setState(() => evidenceFiles.add({'id': 'FILE-${evidenceFiles.length}', 'name': f.name, 'type': 'file', 'size': bytes.length, 'url': 'data:application/octet-stream;base64,${base64Encode(bytes)}'}));
    }
  }

  Future<void> _pickAudio() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (res == null || res.files.single.path == null) return;
    final bytes = await File(res.files.single.path!).readAsBytes();
    setState(() => audioBase64 = 'data:audio/webm;base64,${base64Encode(bytes)}');
    _toast('🎤 Audio recorded');
  }

  Future<void> _pickVideo() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res == null || res.files.single.path == null) return;
    final bytes = await File(res.files.single.path!).readAsBytes();
    setState(() => videoBase64 = 'data:video/webm;base64,${base64Encode(bytes)}');
    _toast('🎥 Video recorded');
  }

  Future<void> _submitComplaint() async {
    final text = _textCtrl.text.trim();
    if (complaintType.isEmpty) { _toast('Select complaint type'); return; }
    if (text.length < 20) { _toast('Type complaint text — At least 20 chars'); return; }
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Submit Complaint?'), content: Text('Submit complaint about client $clientName?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit'))]));
    if (confirm != true) return;
    _toast('Submitting...');
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final complaintId = 'NURSE-COMP-$bookingId-$now';
      final evidenceUrls = <Map>[...evidenceFiles];
      if (audioBase64 != null) evidenceUrls.add({'id': 'AUDIO-1', 'name': 'audio_$complaintId.webm', 'type': 'audio/webm', 'url': audioBase64});
      if (videoBase64 != null) evidenceUrls.add({'id': 'VIDEO-1', 'name': 'video_$complaintId.webm', 'type': 'video/webm', 'url': videoBase64});
      final prefs = await SharedPreferences.getInstance();
      final realNurseId = nurseId == 'nurse_demo' ? (prefs.getString('lcg_nurse_uid') ?? prefs.getString('nurseUid') ?? nurseId) : nurseId;
      final realNurseName = nurseName == 'Nurse' ? (prefs.getString('nurseName') ?? prefs.getString('fullName') ?? nurseName) : nurseName;
      final data = {'complaintId': complaintId, 'bookingId': bookingId, 'clientId': clientId, 'clientName': clientName, 'nurseId': realNurseId, 'nurseName': realNurseName, 'service': service, 'amount': amount, 'complaintType': complaintType, 'complaintText': text, 'status': 'pending', 'createdAt': now, 'time': now, 'evidenceCount': evidenceUrls.length, 'evidenceFiles': evidenceUrls, 'hasAudio': audioBase64 != null, 'hasVideo': videoBase64 != null, 'type': 'nurse_complaint', 'from': 'nurse', 'to': 'client', 'reflectsOnCEO': true};
      final db = FirebaseDatabase.instance;
      await db.ref('nurseComplaints/$complaintId').set(data);
      await db.ref('allComplaints/$complaintId').set(data);
      await db.ref('ceoComplaints/$complaintId').set(data);
      await db.ref('complaintsByBooking/$bookingId/$complaintId').set(data);
      _toast('✅ Nurse complaint submitted');
      await showDialog(context: context, builder: (_) => AlertDialog(title: const Text('✅ NURSE COMPLAINT SUBMITTED!'), content: Text('ID: $complaintId\nClient: $clientName\n\nCEO sees it LIVE'), actions: [ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
      Future.delayed(const Duration(milliseconds: 1500), () { if (mounted) Navigator.pushNamed(context, '/my-job-offers'); });
    } catch (e) { _toast('Error: $e'); }
  }

  // ---- Notices / Punishment ----
  Future<void> _loadNotices() async {
    final ids = await _allIds();
    final prefs = await SharedPreferences.getInstance();
    setState(() => checkedIds = ids.join(', ').substring(0, ids.join(', ').length > 120 ? 120 : ids.join(', ').length));
    Map<String, Map> allNotices = {};
    for (final id in ids) {
      for (final path in ['userNotices/$id', 'ceoNotices/$id', 'nurseNotices/$id', 'notices/$id', 'noticesByEmail/$id', 'noticesByPhone/$id']) {
        try {
          final snap = await FirebaseDatabase.instance.ref(path).get();
          if (snap.exists) {
            (snap.value as Map).forEach((_, v) { final p = Map<String, dynamic>.from(v as Map); if (p['noticeId'] != null) allNotices[p['noticeId']] = p; });
          }
        } catch (_) {}
      }
    }
    try {
      final allSnap = await FirebaseDatabase.instance.ref('allNotices').get();
      if (allSnap.exists) {
        final nurseEmail = (prefs.getString('nurseEmail') ?? prefs.getString('email') ?? '').toLowerCase();
        final nursePhone = (prefs.getString('nursePhone') ?? prefs.getString('phone') ?? '').replaceAll(RegExp(r'[^0-9]'), '');
        final nursePhone9 = nursePhone.length >= 9 ? nursePhone.substring(nursePhone.length - 9) : '';
        (allSnap.value as Map).forEach((_, v) {
          final p = Map<String, dynamic>.from(v as Map);
          if (p['victimType'] != 'nurse') return;
          final pEmail = (p['victimEmail'] ?? '').toString().toLowerCase();
          final pPhone = (p['victimPhone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
          final pPhone9 = pPhone.length >= 9 ? pPhone.substring(pPhone.length - 9) : '';
          if ((nurseEmail.isNotEmpty && pEmail == nurseEmail) || (nursePhone9.isNotEmpty && pPhone9 == nursePhone9) || ids.contains(p['victimId'])) allNotices[p['noticeId']] = p;
        });
      }
    } catch (_) {}
    final list = allNotices.values.toList()..sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
    setState(() => notices = list);
  }

  void _listenNewNotices() async {
    final ids = await _allIds();
    for (final uid in ids) {
      FirebaseDatabase.instance.ref('userNotices/$uid').onChildAdded.listen((e) {
        if (!e.snapshot.exists) return;
        final v = Map<String, dynamic>.from(e.snapshot.value as Map);
        if (v['createdAt'] != null && DateTime.now().millisecondsSinceEpoch - (v['createdAt'] as num) < 60000 && v['isRead'] != true) {
          Future.delayed(const Duration(seconds: 1), () async {
            final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('🚨 NEW PUNISHMENT!'), content: Text('${(v['action'] ?? '').toString().toUpperCase()} — CEO sent you professional feedback! Read now?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Read'))]));
            if (ok == true) _openNotice(v);
            _loadNotices();
          });
        }
      });
    }
  }

  void _openNotice(Map n) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('${n['action'] ?? 'Notice'} — ${n['noticeId'] ?? ''}'),
      content: SingleChildScrollView(child: Text('${n['message'] ?? n['reason'] ?? ''}\n\nAction: ${n['action'] ?? ''}\nCreated: ${n['createdAt'] != null ? DateTime.fromMillisecondsSinceEpoch((n['createdAt'] as num).toInt()) : ''}')),
      actions: [
        TextButton(onPressed: () => _markNoticeRead(n), child: const Text('Mark Read')),
        TextButton(onPressed: () => _appealNotice(n), child: const Text('Appeal to CEO')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ));
  }

  Future<void> _markNoticeRead(Map n) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('lcg_nurse_uid') ?? prefs.getString('nurseUid') ?? '';
    await FirebaseDatabase.instance.ref('userNotices/$uid/${n['noticeId']}').update({'isRead': true, 'readAt': DateTime.now().millisecondsSinceEpoch});
    _toast('✅ Marked read');
    Navigator.pop(context);
    _loadNotices();
  }

  Future<void> _appealNotice(Map n) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Appeal to CEO'), content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Explain why should be removed')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Send'))]));
    if (reason == null || reason.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('lcg_nurse_uid') ?? prefs.getString('nurseUid') ?? '';
    await FirebaseDatabase.instance.ref('noticeAppeals/${n['noticeId']}').set({'noticeId': n['noticeId'], 'userId': uid, 'reason': reason, 'createdAt': DateTime.now().millisecondsSinceEpoch, 'status': 'pending'});
    _toast('✅ Appeal sent');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final unread = notices.where((n) => n['isRead'] != true).length;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('Nurse Complaint', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [Stack(children: [IconButton(icon: const Icon(Icons.notifications), onPressed: () { setState(() => showNotices = !showNotices); if (showNotices) _loadNotices(); }), if (unread > 0) Positioned(right: 6, top: 6, child: CircleAvatar(radius: 9, backgroundColor: Colors.red, child: Text('$unread', style: const TextStyle(fontSize: 9, color: Colors.white))))])]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📝 Nurse Complaint — About Client', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Booking: $bookingId', style: const TextStyle(color: Colors.white60, fontSize: 11)),
            Text('Client: $clientName', style: const TextStyle(fontSize: 13)),
            Text('Nurse: $nurseName • Service: $service • Amount: GHS $amount', style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ])),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📝 Complaint Type + Text', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(value: complaintType.isEmpty ? null : complaintType, decoration: const InputDecoration(labelText: 'Complaint Type', border: OutlineInputBorder()), items: types.map((t) => DropdownMenuItem(value: t['v']!, child: Text(t['l']!))).toList(), onChanged: (v) => setState(() => complaintType = v ?? '')),
            const SizedBox(height: 10),
            TextField(controller: _textCtrl, maxLines: 5, decoration: const InputDecoration(labelText: 'Complaint Text — Detailed (min 20 chars)', hintText: 'Describe what client did...', border: OutlineInputBorder())),
          ])),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🎤 Audio + 🎥 Video + 📎 Files — Evidence', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [Expanded(child: ElevatedButton(onPressed: _pickFiles, child: const Text('📎 Pick Files'))), const SizedBox(width: 6), Expanded(child: ElevatedButton(onPressed: _pickAudio, child: const Text('🎤 Pick Audio'))), const SizedBox(width: 6), Expanded(child: ElevatedButton(onPressed: _pickVideo, child: const Text('🎥 Pick Video')))]),
            if (evidenceFiles.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Files: ${evidenceFiles.map((f) => f['name']).join(', ')}', style: const TextStyle(color: Colors.white60, fontSize: 11))),
            if (audioBase64 != null) const Padding(padding: EdgeInsets.only(top: 4), child: Text('🎤 Audio ready', style: TextStyle(color: Colors.green, fontSize: 11))),
            if (videoBase64 != null) const Padding(padding: EdgeInsets.only(top: 4), child: Text('🎥 Video ready', style: TextStyle(color: Colors.green, fontSize: 11))),
          ])),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _submitComplaint, style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text('Submit Complaint to CEO', style: TextStyle(fontWeight: FontWeight.bold)))),
          const SizedBox(height: 12),
          // My Notices
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('⚖️ My Work Ethics Notices', style: TextStyle(fontWeight: FontWeight.bold)), TextButton(onPressed: () { setState(() => showNotices = !showNotices); if (showNotices) _loadNotices(); }, child: Text(showNotices ? 'Hide' : 'Show'))]),
            Text('Checked IDs: $checkedIds', style: const TextStyle(color: Colors.white60, fontSize: 9)),
            if (showNotices) ...[
              const SizedBox(height: 8),
              if (notices.isEmpty) const Text('✅ No notices — Excellent work! Keep it up 🌟', style: TextStyle(color: Colors.white60)),
              ...notices.map((n) => ListTile(
                leading: CircleAvatar(backgroundColor: n['isRead'] == true ? Colors.grey : Colors.red, child: Text((n['action'] ?? 'N').toString().isNotEmpty ? (n['action'] as String)[0].toUpperCase() : 'N', style: const TextStyle(color: Colors.white))),
                title: Text('${n['action'] ?? 'Notice'} — ${n['noticeId'] ?? ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: Text((n['message'] ?? n['reason'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                trailing: Text(n['isRead'] == true ? 'Read' : 'NEW', style: TextStyle(color: n['isRead'] == true ? Colors.grey : Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                onTap: () => _openNotice(n),
              )),
            ],
          ])),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
