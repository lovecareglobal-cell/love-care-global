import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';

/// CEO Complainant - Flutter version of ceo-complainant.html
/// - Loads: allComplaints + clientComplaints + nurseComplaints + ceoComplaints, dedupe by key (first wins), sorted createdAt desc, refresh every 20s — same as HTML loadComplaints()
/// - normalizeComplaint: id, complaintId (complaintId ?? id), bookingId, clientName (Client), clientPhone, nurseName (Nurse), nurseId, service (Nursing Care), amount, complaintType (other), complaintText, status (pending), from (from ?? type includes client ? client : nurse), type, createdAt (createdAt ?? time), evidenceCount (evidenceCount ?? evidenceFiles.length), evidenceFiles, hasAudio, hasVideo, audioUrl, videoUrl
/// - Stats: Total, Client (from client OR type includes client_complaint), Nurse (from nurse OR type includes nurse_complaint), Pending, Resolved — "{total} Complaints | {client} Client→Nurse | {nurse} Nurse→Client" — same as HTML updateStats()
/// - Render: search (clientName + nurseName + bookingId + complaintType + complaintText) + 3 columns/tabs: Client (👤 Client → Nurse), Nurse (👩‍⚕️ Nurse → Client), All — same as HTML renderComplaints/renderColumn()
///   Card: badge 👤 Client → Nurse / 👩‍⚕️ Nurse → Client, badge status pending/resolved, badge 📎 evidenceCount, 🎤 Audio, 🎥 Video, "{client} complains about {nurse}" / "{nurse} complains about {client}", 📋 bookingId (first 12) • complaintType • complaintText (first 80), time
/// - View Complaint (modal): avatar, "{client} → {nurse}" / "{nurse} → {client}", complaintId • time, Type, Text, Evidence: Audio (audio player link), Video (video link), Files (name/type, image thumb, 👁️ View) — same as HTML viewComplaint()
/// - CEO Feedback Actionment — same as HTML ceoFeedbackAction / ceoFeedbackActionFull():
///   Fields: Victim (nurse/client dropdown), Punishment Type, Extra (Trust % / Deduct Rating Points / Days — shown when type includes trust/fine/suspend), CEO Message (textarea), CEO Voice (Record/Stop — MediaRecorder audio/webm in HTML; Flutter: record via device recorder — here: voice note via "Record Voice" uses audioplayers/record plugin if added, stored as base64 in HTML; Flutter stores voiceUrl placeholder + hasVoice flag, same DB shape)
///   Validate: victim required, punishment required, if no message AND no voice -> confirm "Feedback Action without message?"
///   Confirm: "⚖️ CONFIRM REVIEWMENT\n\nVictim: {TYPE} — {name}\nFeedback Actionment: {TYPE}\nExtra: {extra}\n\nMessage: {first 100}...\n\nThis will APPLY IMMEDIATELY on system! Restrict Accessed cannot book, suspended cannot go online."
///   punishmentId = "REVIEW-{complaintId}-{now}"
///   Effects (same as HTML): warning -> trustDeduct 5 ; decrease_trust -> trustDeduct parse(extra) ?? 20 ; suspend* -> isTemporarySuspended true, days 1/3/7/30 or parse(extra) ?? 3, suspendUntil = now + days*24h, trustDeduct 10, canBook false ; block* -> isRestricted true, isTemporarySuspended true, suspendUntil = block_permanent ? 0 : now+30d, trustDeduct 30, canBook false ; ban_booking -> canBook false, trustDeduct 15 ; fine_deduct -> trustDeduct 10 ; (guidance / reduce_rating / resolve_no_punish -> no block, trustDeduct 0)
///   punishmentData: {punishmentId, complaintId, action, victimType, victimId, victimName, victimPhone, victimEmail, ceoMessage, hasVoice, voiceUrl, extraValue, createdAt, createdAtStr, complaintDetails, evidenceReviewed true, applied true, status active, isRead false, isListened false, ceoId CEO, immediateEffect true, suspendUntil, suspendUntilStr (or PERMANENT), trustDeduct, isRestricted, isTemporarySuspended, canBook}
///   Victim keys: [victimId, victimEmail, victimEmailKey (lower, .#$@[] -> _), victimPhoneKey (digits last 9), victimPhone] filter len>2, dedupe
///   For each key: set ceoPunishments/{key}/{punishmentId} + userPunishments + nursePunishments + clientPunishments + punishments/{key}/{punishmentId} + notifications/{key}/{punishmentId} {type punishment, title "⚖️ CEO Feedback Actionment: {TYPE}", message first 200, fullMessage, punishmentId, complaintId, victimType, action, hasVoice, createdAt, isRead false, immediateEffect true, suspendUntil, isRestricted}
///   Main: allPunishments/{punishmentId} + punishmentsByComplaint/{complaintId}/{punishmentId} + ceoActions/{punishmentId} + punishmentsByEmail/{emailKey}/{punishmentId} + punishmentsByPhone/{phoneKey}/{punishmentId}
///   Victim record — nurse: nurses/{victimId} {isRestricted, isTemporarySuspended, suspendUntil, suspendUntilStr, canBeBooked canBook, canGoOnline !(restricted||suspended), isOnline/online false if blocked/suspended, lastPunishment, lastPunishmentType, lastPunishmentAt, punishmentCount +1, hasActivePunishment true} + if blocked/suspended: remove onlineNurses + liveNurses, nursePresence/{id} {status offline, isOnline false, isRestricted, isTemporarySuspended, suspendUntil, lastPunishment}, nurseLocations/{id} {isOnline false, isRestricted, isTemporarySuspended} + trustScore transaction max(0, 100-trustDeduct) + rating transaction max(1, 5-trustDeduct/20)
///   Victim record — client: clients/{victimId} {isRestricted, isTemporarySuspended, suspendUntil, suspendUntilStr, canBook, canBookNurse canBook, lastPunishment, lastPunishmentType, lastPunishmentAt, punishmentCount +1, hasActivePunishment true} + fallback allowedClients/{emailKey} + clientsByEmail/{emailKey} same fields
///   + mark complaint resolved in allComplaints + clientComplaints + nurseComplaints + ceoComplaints {status resolved, resolvedAt, punishmentId} (HTML did not explicitly mark resolved — this keeps Pending/Resolved stats truthful; same complaintId)
/// - Live: allComplaints + clientComplaints + nurseComplaints + ceoComplaints onChildAdded within 60s -> toast "🚨 NEW Complaint LIVE" + reload — same as HTML attachLiveComplaints()
/// - NO alert buttons — only Sound Settings.

class CEOComplainantScreen extends StatefulWidget {
  const CEOComplainantScreen({super.key});
  @override
  State<CEOComplainantScreen> createState() => _CEOComplainantScreenState();
}

class _CEOComplainantScreenState extends State<CEOComplainantScreen> {
  List<Map> allComplaints = [];
  String search = '';
  String tab = 'all'; // all / client / nurse
  Timer? _timer;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadComplaints();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _loadComplaints());
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Map _normalize(String id, Map v) => {'id': id, 'complaintId': v['complaintId'] ?? id, 'bookingId': v['bookingId'] ?? '', 'clientName': v['clientName'] ?? 'Client', 'clientPhone': v['clientPhone'] ?? '', 'clientId': v['clientId'] ?? v['clientUid'] ?? '', 'clientEmail': v['clientEmail'] ?? '', 'nurseName': v['nurseName'] ?? 'Nurse', 'nurseId': v['nurseId'] ?? v['nurseUid'] ?? '', 'nurseEmail': v['nurseEmail'] ?? '', 'nursePhone': v['nursePhone'] ?? '', 'service': v['service'] ?? 'Nursing Care', 'amount': v['amount'] ?? 0, 'complaintType': v['complaintType'] ?? 'other', 'complaintText': v['complaintText'] ?? '', 'status': v['status'] ?? 'pending', 'from': v['from'] ?? ((v['type'] ?? '').toString().contains('client') ? 'client' : 'nurse'), 'type': v['type'] ?? '', 'createdAt': v['createdAt'] ?? v['time'] ?? DateTime.now().millisecondsSinceEpoch, 'evidenceCount': v['evidenceCount'] ?? ((v['evidenceFiles'] as List?)?.length ?? 0), 'evidenceFiles': v['evidenceFiles'] ?? [], 'hasAudio': v['hasAudio'] ?? false, 'hasVideo': v['hasVideo'] ?? false, 'audioUrl': v['audioUrl'] ?? '', 'videoUrl': v['videoUrl'] ?? '', 'raw': v};

  Future<void> _loadComplaints() async {
    Map<String, Map> map = {};
    for (final path in ['allComplaints', 'clientComplaints', 'nurseComplaints', 'ceoComplaints']) {
      try {
        final snap = await FirebaseDatabase.instance.ref(path).get();
        if (!snap.exists) continue;
        (snap.value as Map).forEach((k, val) { if (val is Map && !map.containsKey(k)) map[k] = Map<String, dynamic>.from(val); });
      } catch (_) {}
    }
    final list = map.entries.map((e) => _normalize(e.key.toString(), e.value)).toList();
    list.sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
    setState(() => allComplaints = list);
    _attachLive();
  }

  void _attachLive() {
    for (final path in ['allComplaints', 'clientComplaints', 'nurseComplaints', 'ceoComplaints']) {
      FirebaseDatabase.instance.ref(path).onChildAdded.listen((e) {
        if (!e.snapshot.exists) return;
        final v = Map<String, dynamic>.from(e.snapshot.value as Map);
        if (DateTime.now().millisecondsSinceEpoch - ((v['createdAt'] ?? v['time'] ?? 0) as num) < 60000) { _toast('🚨 NEW Complaint LIVE'); _loadComplaints(); }
      });
    }
  }

  bool _isClient(Map c) => c['from'] == 'client' || (c['type'] ?? '').toString().contains('client_complaint') || (c['type'] ?? '').toString().contains('client');
  List<Map> get filtered {
    var list = List<Map>.from(allComplaints);
    if (search.isNotEmpty) list = list.where((c) => '${c['clientName']} ${c['nurseName']} ${c['bookingId']} ${c['complaintType']} ${c['complaintText']}'.toLowerCase().contains(search)).toList();
    if (tab == 'client') list = list.where((c) => _isClient(c)).toList();
    if (tab == 'nurse') list = list.where((c) => !_isClient(c)).toList();
    return list;
  }

  String _formatTime(dynamic t) => t == null ? '' : DateTime.fromMillisecondsSinceEpoch((t as num).toInt()).toString();

  void _viewComplaint(Map c) {
    final isClient = _isClient(c);
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text(isClient ? '👤 ${c['clientName']} → 👩‍⚕️ ${c['nurseName']}' : '👩‍⚕️ ${c['nurseName']} → 👤 ${c['clientName']}'),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${c['complaintId']} • ${_formatTime(c['createdAt'])}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
        const SizedBox(height: 10),
        Text('📝 Type: ${c['complaintType']}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: Text(c['complaintText'], style: const TextStyle(fontSize: 13))),
        const SizedBox(height: 10),
        const Text('🎤 Audio + 🎥 Video + 📎 Files — Evidence', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        if (c['hasAudio'] == true && (c['audioUrl'] as String).isNotEmpty) TextButton(onPressed: () => launchUrl(Uri.parse(c['audioUrl']), mode: LaunchMode.externalApplication), child: const Text('🎤 Play Audio')),
        if (c['hasVideo'] == true && (c['videoUrl'] as String).isNotEmpty) TextButton(onPressed: () => launchUrl(Uri.parse(c['videoUrl']), mode: LaunchMode.externalApplication), child: const Text('🎥 Play Video')),
        if ((c['evidenceFiles'] as List).isNotEmpty) ...((c['evidenceFiles'] as List).map((f) {
          final fm = f is Map ? Map<String, dynamic>.from(f) : {};
          return ListTile(leading: Text((fm['type'] ?? '').toString().startsWith('image/') ? '🖼️' : (fm['type'] ?? '').toString().startsWith('video/') ? '🎥' : '📎'), title: Text(fm['name'] ?? 'Evidence', style: const TextStyle(fontSize: 12)), subtitle: Text(fm['type'] ?? 'File', style: const TextStyle(fontSize: 10)), trailing: (fm['url'] ?? '').toString().isNotEmpty ? TextButton(onPressed: () => launchUrl(Uri.parse(fm['url'])), child: const Text('👁️ View')) : null);
        }).toList()),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () { Navigator.pop(context); _openPunishment(c); }, child: const Text('⚖️ CEO Feedback Actionment'))],
    ));
  }

  void _openPunishment(Map c) {
    String victimType = _isClient(c) ? 'nurse' : 'client'; // default: punish the accused side
    String punishType = 'warning';
    final extraCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    bool hasVoice = false;
    showDialog(context: context, builder: (_) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      title: const Text('⚖️ CEO Feedback Actionment — Read & Listen'),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('WHO to punish — Nurse or Client', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        DropdownButton<String>(value: victimType, isExpanded: true, items: [DropdownMenuItem(value: 'nurse', child: Text('👩‍⚕️ Nurse — ${c['nurseName'] ?? c['nurseId']}')), DropdownMenuItem(value: 'client', child: Text('👤 Client — ${c['clientName'] ?? c['clientId']}'))], onChanged: (v) => setD(() => victimType = v ?? 'nurse')),
        const SizedBox(height: 10),
        const Text('REVIEWMENT TYPE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        DropdownButton<String>(value: punishType, isExpanded: true, items: const [
          DropdownMenuItem(value: 'guidance', child: Text('⚠️ Warning — Yellow card, no block')),
          DropdownMenuItem(value: 'decrease_trust', child: Text('📉 Adjust Trust Score -10% to -50%')),
          DropdownMenuItem(value: 'fine_deduct', child: Text('💰 Deduct Rating Points — Deduct from wallet')),
          DropdownMenuItem(value: 'suspend_1day', child: Text('⏸️ Temporary Restriction 1 Day — Cannot book/be booked')),
          DropdownMenuItem(value: 'suspend_3days', child: Text('⏸️ Temporary Restriction 3 Days')),
          DropdownMenuItem(value: 'suspend_7days', child: Text('⏸️ Temporary Restriction 7 Days')),
          DropdownMenuItem(value: 'suspend_30days', child: Text('⏸️ Temporary Restriction 30 Days')),
          DropdownMenuItem(value: 'block_temporary', child: Text('🚫 Restrict Access Temporary — Must appeal')),
          DropdownMenuItem(value: 'block_permanent', child: Text('🚫 Restrict Access Permanent — Banned forever')),
          DropdownMenuItem(value: 'ban_booking', child: Text('🚫 Ban Booking — Cannot book new jobs')),
          DropdownMenuItem(value: 'reduce_rating', child: Text('⭐ Reduce Rating — Lower stars')),
          DropdownMenuItem(value: 'resolve_no_punish', child: Text('✅ Resolve — No punishment, just advice')),
        ], onChanged: (v) => setD(() => punishType = v ?? 'warning')),
        if (punishType.contains('trust') || punishType.contains('fine') || punishType.contains('suspend')) Column(children: [const SizedBox(height: 8), const Text('Extra: Trust % to deduct / Deduct Rating Points amount / Days', style: TextStyle(fontSize: 10, color: Color(0xFFFACC15))), TextField(controller: extraCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'e.g., 20 for 20% or 50 for GHS 50'))]),
        const SizedBox(height: 10),
        const Text('📝 CEO MESSAGE — Write to Victim (They will READ this)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF60A5FA))),
        TextField(controller: msgCtrl, maxLines: 4, decoration: const InputDecoration(hintText: 'Write your judgment / advice / punishment reason...')),
        const SizedBox(height: 10),
        const Text('🎤 CEO VOICE — Speak to Victim (They will LISTEN)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA))),
        Row(children: [Expanded(child: OutlinedButton(onPressed: () { _toast('Voice recording: add record package (record: ^5.0) to record audio/webm — same as HTML MediaRecorder. For now, type your message and it will be delivered as text.'); setD(() => hasVoice = false); }, child: const Text('🎤 Record Voice'))), const SizedBox(width: 8), if (hasVoice) const Chip(label: Text('🎤 Voice recorded'))]),
        const SizedBox(height: 8),
        const Text('Victim will read this in their punishment inbox + notification', style: TextStyle(fontSize: 9, color: Colors.white60)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () { Navigator.pop(context); _applyPunishment(c, victimType, punishType, extraCtrl.text, msgCtrl.text, hasVoice); }, child: const Text('⚖️ APPLY IMMEDIATELY'))],
    )));
  }

  Future<void> _applyPunishment(Map c, String victimType, String punishType, String extraValue, String ceoMessage, bool hasVoice) async {
    if (victimType.isEmpty) { _toast('Select WHO to punish — Nurse or Client'); return; }
    if (punishType.isEmpty) { _toast('Select REVIEWMENT TYPE'); return; }
    if (ceoMessage.trim().isEmpty && !hasVoice) {
      final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('No message or voice'), content: const Text('Feedback Action without message?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue'))]));
      if (ok != true) return;
    }
    final victimId = victimType == 'nurse' ? (c['nurseId'] ?? c['nurseUid'] ?? c['nurseEmail'] ?? c['nursePhone'] ?? '').toString() : (c['clientId'] ?? c['clientUid'] ?? c['clientEmail'] ?? c['clientPhone'] ?? '').toString();
    final victimName = victimType == 'nurse' ? (c['nurseName'] ?? 'Nurse') : (c['clientName'] ?? 'Client');
    final victimPhone = victimType == 'nurse' ? (c['nursePhone'] ?? '').toString() : (c['clientPhone'] ?? '').toString();
    final victimEmail = victimType == 'nurse' ? (c['nurseEmail'] ?? '').toString() : (c['clientEmail'] ?? '').toString();
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('⚖️ CONFIRM REVIEWMENT'), content: Text('Victim: ${victimType.toUpperCase()} — $victimName\nFeedback Actionment: ${punishType.toUpperCase()}\nExtra: ${extraValue.isEmpty ? 'N/A' : extraValue}\n\nMessage: ${ceoMessage.length > 100 ? ceoMessage.substring(0, 100) : ceoMessage}...\n\nThis will APPLY IMMEDIATELY on system! Restrict Accessed cannot book, suspended cannot go online.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('APPLY'))]));
    if (confirm != true) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final punishmentId = 'REVIEW-${c['id']}-$now';
      int suspendUntil = 0, trustDeduct = 0; bool isRestricted = false, isTemp = false, canBook = true;
      if (punishType == 'warning') trustDeduct = 5;
      else if (punishType == 'decrease_trust') trustDeduct = int.tryParse(extraValue) ?? 20;
      else if (punishType.contains('suspend')) {
        isTemp = true;
        int days = 1;
        if (punishType == 'suspend_1day') days = 1;
        else if (punishType == 'suspend_3days') days = 3;
        else if (punishType == 'suspend_7days') days = 7;
        else if (punishType == 'suspend_30days') days = 30;
        else if (punishType == 'suspend') days = int.tryParse(extraValue) ?? 3;
        suspendUntil = now + days * 24 * 60 * 60 * 1000;
        trustDeduct = 10; canBook = false;
      } else if (punishType.contains('block')) {
        isRestricted = true; isTemp = true;
        suspendUntil = punishType == 'block_permanent' ? 0 : now + 30 * 24 * 60 * 60 * 1000;
        trustDeduct = 30; canBook = false;
      } else if (punishType == 'ban_booking') { canBook = false; trustDeduct = 15; }
      else if (punishType == 'fine_deduct') trustDeduct = 10;
      final suspendStr = suspendUntil != 0 ? DateTime.fromMillisecondsSinceEpoch(suspendUntil).toString() : (isRestricted && punishType == 'block_permanent' ? 'PERMANENT' : '');
      final punishmentData = {'punishmentId': punishmentId, 'complaintId': c['complaintId'] ?? c['id'], 'action': punishType, 'victimType': victimType, 'victimId': victimId, 'victimName': victimName, 'victimPhone': victimPhone, 'victimEmail': victimEmail, 'ceoMessage': ceoMessage, 'hasVoice': hasVoice, 'voiceUrl': '', 'extraValue': extraValue, 'createdAt': now, 'createdAtStr': DateTime.now().toString(), 'complaintDetails': c, 'evidenceReviewed': true, 'applied': true, 'status': 'active', 'isRead': false, 'isListened': false, 'ceoId': 'CEO', 'immediateEffect': true, 'suspendUntil': suspendUntil, 'suspendUntilStr': suspendStr, 'trustDeduct': trustDeduct, 'isRestricted': isRestricted, 'isTemporarySuspended': isTemp, 'canBook': canBook};
      final emailKey = victimEmail.isNotEmpty ? victimEmail.toLowerCase().replaceAll(RegExp(r'[.#\$@\[\]]'), '_') : '';
      final phoneKey = victimPhone.isNotEmpty ? victimPhone.replaceAll(RegExp(r'[^0-9]'), '').substring(victimPhone.replaceAll(RegExp(r'[^0-9]'), '').length >= 9 ? victimPhone.replaceAll(RegExp(r'[^0-9]'), '').length - 9 : 0) : '';
      final keys = [victimId, victimEmail, emailKey, phoneKey, victimPhone].where((k) => k.isNotEmpty && k.length > 2).toSet().toList();
      final db = FirebaseDatabase.instance;
      for (final key in keys) {
        await db.ref('ceoPunishments/$key/$punishmentId').set(punishmentData).catchError((_) {});
        await db.ref('userPunishments/$key/$punishmentId').set(punishmentData).catchError((_) {});
        await db.ref('nursePunishments/$key/$punishmentId').set(punishmentData).catchError((_) {});
        await db.ref('clientPunishments/$key/$punishmentId').set(punishmentData).catchError((_) {});
        await db.ref('punishments/$key/$punishmentId').set(punishmentData).catchError((_) {});
        await db.ref('notifications/$key/$punishmentId').set({'type': 'punishment', 'title': '⚖️ CEO Feedback Actionment: ${punishType.toUpperCase()}', 'message': ceoMessage.length > 200 ? ceoMessage.substring(0, 200) : ceoMessage, 'fullMessage': ceoMessage, 'punishmentId': punishmentId, 'complaintId': c['complaintId'] ?? c['id'], 'victimType': victimType, 'action': punishType, 'hasVoice': hasVoice, 'createdAt': now, 'isRead': false, 'immediateEffect': true, 'suspendUntil': suspendUntil, 'isRestricted': isRestricted}).catchError((_) {});
      }
      await db.ref('allPunishments/$punishmentId').set(punishmentData).catchError((_) {});
      await db.ref('punishmentsByComplaint/${c['complaintId'] ?? c['id']}/$punishmentId').set(punishmentData).catchError((_) {});
      await db.ref('ceoActions/$punishmentId').set(punishmentData).catchError((_) {});
      if (emailKey.isNotEmpty) await db.ref('punishmentsByEmail/$emailKey/$punishmentId').set(punishmentData).catchError((_) {});
      if (phoneKey.isNotEmpty) await db.ref('punishmentsByPhone/$phoneKey/$punishmentId').set(punishmentData).catchError((_) {});
      if (victimType == 'nurse') {
        final countSnap = await db.ref('nurses/$victimId/punishmentCount').get();
        final count = ((countSnap.value ?? 0) as num).toInt() + 1;
        await db.ref('nurses/$victimId').update({'isRestricted': isRestricted, 'isTemporarySuspended': isTemp, 'suspendUntil': suspendUntil, 'suspendUntilStr': suspendStr, 'canBeBooked': canBook, 'canGoOnline': !isRestricted && !isTemp, if (isRestricted || isTemp) 'isOnline': false, if (isRestricted || isTemp) 'online': false, 'lastPunishment': punishmentId, 'lastPunishmentType': punishType, 'lastPunishmentAt': now, 'punishmentCount': count, 'hasActivePunishment': true});
        if (isRestricted || isTemp) {
          await db.ref('onlineNurses/$victimId').remove().catchError((_) {});
          await db.ref('liveNurses/$victimId').remove().catchError((_) {});
          await db.ref('nursePresence/$victimId').set({'status': 'offline', 'isOnline': false, 'isRestricted': isRestricted, 'isTemporarySuspended': isTemp, 'suspendUntil': suspendUntil, 'lastPunishment': punishmentId}).catchError((_) {});
          await db.ref('nurseLocations/$victimId').update({'isOnline': false, 'isRestricted': isRestricted, 'isTemporarySuspended': isTemp}).catchError((_) {});
        }
        if (trustDeduct > 0) {
          await db.ref('nurses/$victimId/trustScore').runTransaction((Object? cur) { final v = (cur as num?) ?? 100; return Transaction.success(((v - trustDeduct).clamp(0, 100))); }).catchError((_) {});
          await db.ref('nurses/$victimId/rating').runTransaction((Object? cur) { final v = (cur as num?) ?? 5; return Transaction.success(((v - trustDeduct / 20).clamp(1, 5))); }).catchError((_) {});
        }
      } else {
        final countSnap = await db.ref('clients/$victimId/punishmentCount').get();
        final count = ((countSnap.value ?? 0) as num).toInt() + 1;
        try {
          await db.ref('clients/$victimId').update({'isRestricted': isRestricted, 'isTemporarySuspended': isTemp, 'suspendUntil': suspendUntil, 'suspendUntilStr': suspendStr, 'canBook': canBook, 'canBookNurse': canBook, 'lastPunishment': punishmentId, 'lastPunishmentType': punishType, 'lastPunishmentAt': now, 'punishmentCount': count, 'hasActivePunishment': true});
        } catch (_) {
          if (emailKey.isNotEmpty) { await db.ref('allowedClients/$emailKey').update({'isRestricted': isRestricted, 'isTemporarySuspended': isTemp, 'suspendUntil': suspendUntil, 'canBook': canBook}).catchError((_) {}); await db.ref('clientsByEmail/$emailKey').update({'isRestricted': isRestricted, 'isTemporarySuspended': isTemp, 'suspendUntil': suspendUntil, 'canBook': canBook}).catchError((_) {}); }
        }
      }
      // Mark complaint resolved in all complaint paths
      for (final p in ['allComplaints', 'clientComplaints', 'nurseComplaints', 'ceoComplaints']) {
        await db.ref('$p/${c['id']}').update({'status': 'resolved', 'resolvedAt': now, 'punishmentId': punishmentId}).catchError((_) {});
      }
      _toast('✅ Feedback Actionment APPLIED — $victimName $punishType');
      _loadComplaints();
    } catch (e) { _toast('Action failed: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    final total = allComplaints.length;
    final clientCount = allComplaints.where((c) => _isClient(c)).length;
    final nurseCount = total - clientCount;
    final pending = allComplaints.where((c) => c['status'] == 'pending').length;
    final resolved = allComplaints.where((c) => c['status'] == 'resolved').length;
    final list = filtered;
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(title: const Text('CEO Complainant', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 8), child: Text('$total Complaints | $clientCount Client→Nurse | $nurseCount Nurse→Client', style: const TextStyle(fontSize: 10, color: Colors.white60)))), IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings'))]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children: [
          _stat('Total', '$total'), _stat('Client', '$clientCount'), _stat('Nurse', '$nurseCount'), _stat('Pending', '$pending'), _stat('Resolved', '$resolved'),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
          Expanded(child: TextField(controller: _searchCtrl, decoration: const InputDecoration(hintText: 'Search client / nurse / booking / type / text', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), onChanged: (v) => setState(() => search = v.toLowerCase().trim()))),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _loadComplaints, child: const Text('🔄 Refresh')),
        ])),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _tabBtn('client', '👤 Client ($clientCount client)')),
          Expanded(child: _tabBtn('nurse', '👩‍⚕️ Nurse ($nurseCount nurse)')),
          Expanded(child: _tabBtn('all', '📦 All ($total total)')),
        ]),
        Expanded(child: list.isEmpty ? const Center(child: Text('No complaints', style: TextStyle(color: Colors.white60))) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: list.length, itemBuilder: (_, i) {
          final c = list[i]; final isClient = _isClient(c);
          return InkWell(onTap: () => _viewComplaint(c), child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(14)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(backgroundColor: isClient ? Colors.red : Colors.purple, child: Text((isClient ? c['clientName'] : c['nurseName']).toString().isNotEmpty ? (isClient ? c['clientName'] : c['nurseName']).toString()[0].toUpperCase() : 'C')),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, children: [Chip(label: Text(isClient ? '👤 Client → Nurse' : '👩‍⚕️ Nurse → Client', style: const TextStyle(fontSize: 10)), backgroundColor: isClient ? Colors.red.withOpacity(0.2) : Colors.purple.withOpacity(0.2)), Chip(label: Text(c['status'], style: const TextStyle(fontSize: 10))), if ((c['evidenceCount'] as int) > 0) Chip(label: Text('📎 ${c['evidenceCount']}', style: const TextStyle(fontSize: 10))), if (c['hasAudio'] == true) const Chip(label: Text('🎤 Audio', style: TextStyle(fontSize: 10))), if (c['hasVideo'] == true) const Chip(label: Text('🎥 Video', style: TextStyle(fontSize: 10)))]),
              const SizedBox(height: 6),
              Text(isClient ? '👤 ${c['clientName']} complains about 👩‍⚕️ ${c['nurseName']}' : '👩‍⚕️ ${c['nurseName']} complains about 👤 ${c['clientName']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text('📋 ${(c['bookingId'] as String).length > 12 ? (c['bookingId'] as String).substring(0, 12) : c['bookingId']} • ${c['complaintType']} • ${(c['complaintText'] as String).length > 80 ? (c['complaintText'] as String).substring(0, 80) + '...' : c['complaintText']}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
              Text(_formatTime(c['createdAt']), style: const TextStyle(fontSize: 10, color: Colors.white60)),
            ])),
          ])));
        })),
      ]),
    );
  }

  Widget _stat(String label, String value) => Container(width: 110, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]));
  Widget _tabBtn(String key, String label) => InkWell(onTap: () => setState(() => tab = key), child: Container(padding: const EdgeInsets.symmetric(vertical: 10), color: tab == key ? Colors.purple : Colors.transparent, child: Center(child: Text(label, style: TextStyle(fontSize: 11, fontWeight: tab == key ? FontWeight.bold : FontWeight.normal)))));
}
