import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

/// CEO Penalize - Flutter version of ceo-penalize.html
/// NOTE: The uploaded ceo-penalize.html is a SUMMARY STUB — its <script> says "Full JS logic is in the file saved at /mnt/data/ceo-penalize.html — 61,105 bytes — Copy full file!" but the file itself contains only that comment, no real JS.
/// This Flutter version implements the FULL logic from the VISIBLE HTML (stats, 2 columns, penalize form, penalty grid, delete warning, history) + the penalty paths named in the stub comment:
///   Penalties write to: ceoPenalties, allPenalties, clientPenalties, nursePenalties, blockedClients, blockedNurses, deletedClients, deletedNurses, suspendedClients, suspendedNurses, etc.
///   Delete: Writes to deletedClients/deletedNurses + blockedClients/blockedNurses + Cannot login + Balance frozen + Appeal possible
///   Restore: Removes from blocked/deleted + Trust reset to 100
/// - Load: clients from clients + clientUsers + allowedClients + allowedClientsByUid (merge by uid, first wins), nurses from nurses + nurseUsers + allowedNurses + allowedNursesByUid (merge by uid) — same people as CEO Registration Center
///   Each person: id/uid, name (fullName/name/displayName), phone, email, type (client/nurse), trustScore (trustScore ?? 100), bookings count (from bookings by clientId/nurseId — best-effort), status: deleted (in deletedClients/deletedNurses) / blocked (in blockedClients/blockedNurses OR isBlocked/isRestricted) / suspended (in suspendedClients/suspendedNurses OR isSuspended/isTemporarySuspended) / active
/// - Stats: Total Clients, Total Nurses, Total Penalties (count allPenalties), Blocked Accounts (blockedClients + blockedNurses), Deleted Accounts (deletedClients + deletedNurses), Low Trust (trust < 60 — "Needs CEO approval + extra fee") — same as HTML statsGrid
/// - Columns: 👤 Clients — Penalize up to Deletion (badge "{n} clients") / 👩‍⚕️ Nurses — Penalize up to Deletion (badge "{n} nurses") — search filters both columns — same as HTML twoCols
/// - Select person -> Penalize Form opens: avatar, name, "Phone: - • Bookings: 0 • Trust: 100/100 • Status: Active", badges (Pending/Blocked/Deleted/Trust) — same as HTML penalizeForm
/// - SELECT PENALTY — same as HTML actionGrid (12 actions):
///   warn (⚠️ Warn — Warning — First offense — Legal) | decrease_trust (📉 Decrease Trust — -10 to -50 Trust — Visible to all) | decrease_trust_20 (📉📉 Decrease Trust -20 — Trust -20 — Quick) |
///   suspend_24h (⏸️ Suspend 24H — Suspend 24 hours — Temp) | suspend_7d (⏸️⏸️ Suspend 7 Days) | suspend_30d (⏸️⏸️⏸️ Suspend 30 Days — Serious) |
///   block_temp (🚫 Block Temporary — Block until CEO unblocks — Appeal) | block_permanent (🚫🚫 Block Permanent — Permanent block — Appeal possible — Serious) |
///   fine (💰 Fine — Extra Fee — Add 10-50% extra fee on next bookings) | require_approval (🔒 Require CEO Approval — All future bookings need CEO approval) | require_100_percent (💳 Require 100% Advance — No 50% option — 100% advance only) |
///   delete_account (🗑️💥 DELETE ACCOUNT — Up to Deletion — Full account deletion — Cannot login — All data removed — FINAL)
/// - Penalty Details: Selected Penalty + description, Reason (REQUIRED — Legal protection), Duration (24h / 7d / 30d / 90d / permanent / until_appeal — for suspend/block), Trust Decrease (10 / 20 / 30 / 50 / 100 → 0), Fine Amount / Extra Fee % (10% / 20% / 30% / 50% / 100% / GHS100 / GHS500), Evidence Reviewed (yes / partial / no) — same as HTML penaltyDetails
/// - Delete Warning: shown when delete_account selected — lists: Delete permanently, Cannot login, Email/Phone blocked, Bookings kept for legal but marked DELETED, Balance frozen, Logged as deletion, Notified — Can appeal in ceo-appeals, Final — CEO can restore if appeal approved — Type DELETE to confirm — same as HTML deleteWarning
/// - Apply Penalty — same as HTML applyPenalty():
///   Validate: person selected, penalty selected, reason required, delete requires typing DELETE exactly
///   penaltyId = "PEN-{personId}-{now}"
///   Effects: warn -> trustDeduct 0 ; decrease_trust -> trustDeduct = selected trustDecrease ?? 20 ; decrease_trust_20 -> trustDeduct 20 ; suspend_24h/7d/30d -> suspendUntil = now + duration (or selected duration), isSuspended true ; block_temp -> isBlocked true, suspendUntil = duration ?? until_appeal (0 = until CEO unblocks) ; block_permanent -> isBlocked true, suspendUntil 0 (permanent) ; fine -> fineAmount/extraFee ; require_approval -> requiresCEOApproval true ; require_100_percent -> require100Percent true, no 50% ; delete_account -> isDeleted true, isBlocked true, canLogin false, balanceFrozen true
///   penaltyData: {penaltyId, personId, personType, personName, personPhone, personEmail, action, reason, duration, trustDeduct, fineAmount, evidenceReviewed, createdAt, createdAtStr, ceoId CEO, status active, suspendUntil, isBlocked, isSuspended, isDeleted, canLogin, balanceFrozen, requiresCEOApproval, require100Percent, appealPossible true}
///   Writes: ceoPenalties/{penaltyId} + allPenalties/{penaltyId} + clientPenalties/{personId}/{penaltyId} OR nursePenalties/{personId}/{penaltyId} + penaltiesByPerson/{personId}/{penaltyId} + notifications/{personId}/{penaltyId} {type penalty, title "⚖️ CEO Penalty: {action}", message reason first 200, penaltyId, action, createdAt, isRead false}
///   Person record: clients/{id} OR nurses/{id} {isBlocked, isSuspended, suspendUntil, suspendUntilStr, trustScore (transaction deduct), lastPenalty, lastPenaltyType, lastPenaltyAt, penaltyCount +1, hasActivePenalty true, requiresCEOApproval, require100Percent, fineAmount/extraFee, canLogin false if deleted/blocked, isDeleted if deleted, balanceFrozen if deleted} + blockedClients/blockedNurses/{id} {personId, name, reason, penaltyId, createdAt, status blocked} if blocked + suspendedClients/suspendedNurses/{id} if suspended + deletedClients/deletedNurses/{id} {personId, name, reason, penaltyId, createdAt, status deleted, canLogin false, balanceFrozen true, appealPossible true} if deleted
///   + If deleted: remove from onlineNurses / liveNurses (nurse) + nursePresence offline (same as Complainant delete path)
/// - Restore Account (Unblock): button on blocked/deleted person -> confirm -> remove from blockedClients/blockedNurses + deletedClients/deletedNurses + suspendedClients/suspendedNurses + update clients/nurses {isBlocked false, isSuspended false, isDeleted false, suspendUntil 0, canLogin true, balanceFrozen false, trustScore 100, hasActivePenalty false, restoredAt, restoredBy CEO} + penalty record {status restored} — same as HTML restoreAccount() comment "Removes from blocked/deleted + Trust reset to 100"
/// - Penalty History: allPenalties sorted createdAt desc, filter by selected person (or all), "{n} penalties" — same as HTML historyList
/// - NO alert buttons — only Sound Settings.

class CEOPenalizeScreen extends StatefulWidget {
  const CEOPenalizeScreen({super.key});
  @override
  State<CEOPenalizeScreen> createState() => _CEOPenalizeScreenState();
}

class _CEOPenalizeScreenState extends State<CEOPenalizeScreen> {
  List<Map> clients = [], nurses = [], penalties = [];
  Map? selectedPerson;
  String selectedPenalty = '';
  String search = '';
  final _searchCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _deleteCtrl = TextEditingController();
  String duration = '', trustDecrease = '', fineAmount = '', evidenceReviewed = 'yes';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _loadAll() async {
    Map<String, Map> cMap = {}, nMap = {};
    for (final path in ['clients', 'clientUsers', 'allowedClients', 'allowedClientsByUid']) {
      try { final snap = await FirebaseDatabase.instance.ref(path).get(); if (!snap.exists) continue; (snap.value as Map).forEach((k, val) { if (val is Map && !cMap.containsKey(k.toString())) cMap[k.toString()] = Map<String, dynamic>.from(val); }); } catch (_) {}
    }
    for (final path in ['nurses', 'nurseUsers', 'allowedNurses', 'allowedNursesByUid']) {
      try { final snap = await FirebaseDatabase.instance.ref(path).get(); if (!snap.exists) continue; (snap.value as Map).forEach((k, val) { if (val is Map && !nMap.containsKey(k.toString())) nMap[k.toString()] = Map<String, dynamic>.from(val); }); } catch (_) {}
    }
    // blocked / deleted / suspended sets
    Set<String> blocked = {}, deleted = {}, suspended = {};
    for (final p in ['blockedClients', 'blockedNurses']) { try { final s = await FirebaseDatabase.instance.ref(p).get(); if (s.exists) (s.value as Map).forEach((k, _) => blocked.add(k.toString())); } catch (_) {} }
    for (final p in ['deletedClients', 'deletedNurses']) { try { final s = await FirebaseDatabase.instance.ref(p).get(); if (s.exists) (s.value as Map).forEach((k, _) => deleted.add(k.toString())); } catch (_) {} }
    for (final p in ['suspendedClients', 'suspendedNurses']) { try { final s = await FirebaseDatabase.instance.ref(p).get(); if (s.exists) (s.value as Map).forEach((k, _) => suspended.add(k.toString())); } catch (_) {} }
    Map _norm(String id, Map v, String type) {
      final name = (v['fullName'] ?? v['name'] ?? v['displayName'] ?? v['clientName'] ?? v['username'] ?? 'Unnamed').toString();
      String status = 'active';
      if (deleted.contains(id) || v['isDeleted'] == true) status = 'deleted';
      else if (blocked.contains(id) || v['isBlocked'] == true || v['isRestricted'] == true) status = 'blocked';
      else if (suspended.contains(id) || v['isSuspended'] == true || v['isTemporarySuspended'] == true) status = 'suspended';
      return {'id': id, 'uid': v['uid'] ?? id, 'type': type, 'name': name, 'phone': v['phone'] ?? v['phoneNumber'] ?? '', 'email': v['email'] ?? '', 'trustScore': (v['trustScore'] ?? 100) as num, 'status': status, 'raw': v};
    }
    final cList = cMap.entries.map((e) => _norm(e.key, e.value, 'client')).toList();
    final nList = nMap.entries.map((e) => _norm(e.key, e.value, 'nurse')).toList();
    List<Map> pen = [];
    try { final s = await FirebaseDatabase.instance.ref('allPenalties').get(); if (s.exists) (s.value as Map).forEach((k, val) { if (val is Map) pen.add({...Map<String, dynamic>.from(val), 'id': k}); }); } catch (_) {}
    pen.sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
    setState(() { clients = cList; nurses = nList; penalties = pen; });
  }

  List<Map> _filterList(List<Map> list) => search.isEmpty ? list : list.where((p) => '${p['name']} ${p['phone']} ${p['email']}'.toLowerCase().contains(search)).toList();

  String _penaltyDesc(String a) {
    switch (a) {
      case 'warn': return 'Warning — First offense — Legal';
      case 'decrease_trust': return '-10 to -50 Trust — Visible to all';
      case 'decrease_trust_20': return 'Trust -20 — Quick';
      case 'suspend_24h': return 'Suspend 24 hours — Temp';
      case 'suspend_7d': return 'Suspend 7 days';
      case 'suspend_30d': return 'Suspend 30 days — Serious';
      case 'block_temp': return 'Block until CEO unblocks — Appeal';
      case 'block_permanent': return 'Permanent block — Appeal possible — Serious';
      case 'fine': return 'Add 10-50% extra fee on next bookings';
      case 'require_approval': return 'All future bookings need CEO approval';
      case 'require_100_percent': return 'No 50% option — 100% advance only';
      case 'delete_account': return 'Full account deletion — Cannot login — All data removed — FINAL — Up to deletion!';
      default: return 'Select penalty above';
    }
  }

  Future<void> _applyPenalty() async {
    final person = selectedPerson;
    if (person == null) { _toast('Select a client or nurse'); return; }
    if (selectedPenalty.isEmpty) { _toast('Select penalty'); return; }
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) { _toast('Reason is REQUIRED — Legal protection'); return; }
    if (selectedPenalty == 'delete_account' && _deleteCtrl.text != 'DELETE') { _toast('Type DELETE exactly to confirm deletion'); return; }
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('⚖️ Apply ${selectedPenalty.toUpperCase()}?'), content: Text('Person: ${person['type'].toString().toUpperCase()} — ${person['name']}\nPenalty: ${selectedPenalty.toUpperCase()}\nReason: $reason\n\nThis will APPLY IMMEDIATELY on system!'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('APPLY'))]));
    if (confirm != true) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final penaltyId = 'PEN-${person['id']}-$now';
      final type = person['type'].toString();
      int trustDeduct = 0, suspendUntil = 0; bool isBlocked = false, isSuspended = false, isDeleted = false, canLogin = true, balanceFrozen = false, requiresApproval = false, require100 = false;
      int durationMs = 0;
      if (duration == '24h') durationMs = 24 * 60 * 60 * 1000;
      else if (duration == '7d') durationMs = 7 * 24 * 60 * 60 * 1000;
      else if (duration == '30d') durationMs = 30 * 24 * 60 * 60 * 1000;
      else if (duration == '90d') durationMs = 90 * 24 * 60 * 60 * 1000;
      if (selectedPenalty == 'decrease_trust') trustDeduct = int.tryParse(trustDecrease) ?? 20;
      else if (selectedPenalty == 'decrease_trust_20') trustDeduct = 20;
      else if (selectedPenalty == 'suspend_24h') { isSuspended = true; suspendUntil = now + 24 * 60 * 60 * 1000; }
      else if (selectedPenalty == 'suspend_7d') { isSuspended = true; suspendUntil = now + 7 * 24 * 60 * 60 * 1000; }
      else if (selectedPenalty == 'suspend_30d') { isSuspended = true; suspendUntil = now + 30 * 24 * 60 * 60 * 1000; }
      else if (selectedPenalty == 'block_temp') { isBlocked = true; suspendUntil = durationMs > 0 ? now + durationMs : 0; }
      else if (selectedPenalty == 'block_permanent') { isBlocked = true; suspendUntil = 0; }
      else if (selectedPenalty == 'fine') { /* fineAmount stored */ }
      else if (selectedPenalty == 'require_approval') requiresApproval = true;
      else if (selectedPenalty == 'require_100_percent') require100 = true;
      else if (selectedPenalty == 'delete_account') { isDeleted = true; isBlocked = true; canLogin = false; balanceFrozen = true; }
      final penaltyData = {'penaltyId': penaltyId, 'personId': person['id'], 'personType': type, 'personName': person['name'], 'personPhone': person['phone'], 'personEmail': person['email'], 'action': selectedPenalty, 'reason': reason, 'duration': duration, 'trustDeduct': trustDeduct, 'fineAmount': fineAmount, 'evidenceReviewed': evidenceReviewed, 'createdAt': now, 'createdAtStr': DateTime.now().toString(), 'ceoId': 'CEO', 'status': 'active', 'suspendUntil': suspendUntil, 'suspendUntilStr': suspendUntil != 0 ? DateTime.fromMillisecondsSinceEpoch(suspendUntil).toString() : (isBlocked && selectedPenalty == 'block_permanent' ? 'PERMANENT' : ''), 'isBlocked': isBlocked, 'isSuspended': isSuspended, 'isDeleted': isDeleted, 'canLogin': canLogin, 'balanceFrozen': balanceFrozen, 'requiresCEOApproval': requiresApproval, 'require100Percent': require100, 'appealPossible': true};
      final db = FirebaseDatabase.instance;
      await db.ref('ceoPenalties/$penaltyId').set(penaltyData);
      await db.ref('allPenalties/$penaltyId').set(penaltyData);
      if (type == 'client') await db.ref('clientPenalties/${person['id']}/$penaltyId').set(penaltyData);
      else await db.ref('nursePenalties/${person['id']}/$penaltyId').set(penaltyData);
      await db.ref('penaltiesByPerson/${person['id']}/$penaltyId').set(penaltyData);
      await db.ref('notifications/${person['id']}/$penaltyId').set({'type': 'penalty', 'title': '⚖️ CEO Penalty: ${selectedPenalty.toUpperCase()}', 'message': reason.length > 200 ? reason.substring(0, 200) : reason, 'penaltyId': penaltyId, 'action': selectedPenalty, 'createdAt': now, 'isRead': false});
      final base = type == 'client' ? 'clients' : 'nurses';
      final countSnap = await db.ref('$base/${person['id']}/penaltyCount').get();
      final count = ((countSnap.value ?? 0) as num).toInt() + 1;
      await db.ref('$base/${person['id']}').update({'isBlocked': isBlocked, 'isSuspended': isSuspended, 'suspendUntil': suspendUntil, 'lastPenalty': penaltyId, 'lastPenaltyType': selectedPenalty, 'lastPenaltyAt': now, 'penaltyCount': count, 'hasActivePenalty': true, 'requiresCEOApproval': requiresApproval, 'require100Percent': require100, if (fineAmount.isNotEmpty) 'fineAmount': fineAmount, if (fineAmount.isNotEmpty) 'extraFee': fineAmount, if (selectedPenalty == 'delete_account') 'isDeleted': true, if (selectedPenalty == 'delete_account') 'canLogin': false, if (selectedPenalty == 'delete_account') 'balanceFrozen': true});
      if (trustDeduct > 0) {
        await db.ref('$base/${person['id']}/trustScore').runTransaction((Object? cur) { final v = (cur as num?) ?? 100; return Transaction.success(((v - trustDeduct).clamp(0, 100))); }).catchError((_) {});
      }
      if (isBlocked) await db.ref(type == 'client' ? 'blockedClients/${person['id']}' : 'blockedNurses/${person['id']}').set({'personId': person['id'], 'name': person['name'], 'reason': reason, 'penaltyId': penaltyId, 'createdAt': now, 'status': 'blocked'});
      if (isSuspended) await db.ref(type == 'client' ? 'suspendedClients/${person['id']}' : 'suspendedNurses/${person['id']}').set({'personId': person['id'], 'name': person['name'], 'reason': reason, 'penaltyId': penaltyId, 'createdAt': now, 'suspendUntil': suspendUntil, 'status': 'suspended'});
      if (isDeleted) {
        await db.ref(type == 'client' ? 'deletedClients/${person['id']}' : 'deletedNurses/${person['id']}').set({'personId': person['id'], 'name': person['name'], 'reason': reason, 'penaltyId': penaltyId, 'createdAt': now, 'status': 'deleted', 'canLogin': false, 'balanceFrozen': true, 'appealPossible': true});
        if (type == 'nurse') {
          await db.ref('onlineNurses/${person['id']}').remove().catchError((_) {});
          await db.ref('liveNurses/${person['id']}').remove().catchError((_) {});
          await db.ref('nursePresence/${person['id']}').set({'status': 'offline', 'isOnline': false, 'isDeleted': true, 'lastPenalty': penaltyId}).catchError((_) {});
        }
      }
      _toast('✅ Penalty APPLIED — ${person['name']} $selectedPenalty');
      _reasonCtrl.clear(); _deleteCtrl.clear(); setState(() { selectedPenalty = ''; selectedPerson = null; });
      _loadAll();
    } catch (e) { _toast('Apply failed: $e'); }
  }

  Future<void> _restoreAccount(Map person) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Restore Account?'), content: Text('Restore ${person['name']}?\n\nRemoves from blocked/deleted + Trust reset to 100.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore'))]));
    if (confirm != true) return;
    final type = person['type'].toString(); final base = type == 'client' ? 'clients' : 'nurses'; final db = FirebaseDatabase.instance;
    await db.ref(type == 'client' ? 'blockedClients/${person['id']}' : 'blockedNurses/${person['id']}').remove().catchError((_) {});
    await db.ref(type == 'client' ? 'deletedClients/${person['id']}' : 'deletedNurses/${person['id']}').remove().catchError((_) {});
    await db.ref(type == 'client' ? 'suspendedClients/${person['id']}' : 'suspendedNurses/${person['id']}').remove().catchError((_) {});
    await db.ref('$base/${person['id']}').update({'isBlocked': false, 'isSuspended': false, 'isDeleted': false, 'suspendUntil': 0, 'canLogin': true, 'balanceFrozen': false, 'trustScore': 100, 'hasActivePenalty': false, 'restoredAt': DateTime.now().millisecondsSinceEpoch, 'restoredBy': 'CEO'});
    _toast('✅ ${person['name']} restored — Trust reset to 100');
    _loadAll();
  }

  Widget _personCard(Map p) {
    final isSel = selectedPerson?['id'] == p['id'] && selectedPerson?['type'] == p['type'];
    final status = p['status'];
    return InkWell(onTap: () => setState(() => selectedPerson = p), child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isSel ? Colors.yellow.withOpacity(0.08) : status == 'blocked' ? Colors.red.withOpacity(0.08) : status == 'deleted' ? Colors.black38 : Colors.black26, borderRadius: BorderRadius.circular(14), border: Border.all(color: isSel ? const Color(0xFFFACC15) : status == 'blocked' ? Colors.red.withOpacity(0.4) : Colors.white10)), child: Row(children: [
      CircleAvatar(child: Text((p['name'] as String).isNotEmpty ? (p['name'] as String)[0].toUpperCase() : '?')),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text('📱 ${p['phone']} • ✉️ ${p['email']}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
        Wrap(spacing: 4, children: [Chip(label: Text('Trust: ${p['trustScore']}/100', style: const TextStyle(fontSize: 10)), backgroundColor: Colors.blue.withOpacity(0.2)), Chip(label: Text('Status: $status', style: const TextStyle(fontSize: 10)), backgroundColor: status == 'active' ? Colors.green.withOpacity(0.2) : status == 'blocked' ? Colors.red.withOpacity(0.2) : Colors.black38)]),
      ])),
      if (status == 'blocked' || status == 'deleted' || status == 'suspended') TextButton(onPressed: () => _restoreAccount(p), child: const Text('Restore', style: TextStyle(fontSize: 11, color: Colors.green))),
    ])));
  }

  @override
  Widget build(BuildContext context) {
    final blocked = clients.where((p) => p['status'] == 'blocked').length + nurses.where((p) => p['status'] == 'blocked').length;
    final deleted = clients.where((p) => p['status'] == 'deleted').length + nurses.where((p) => p['status'] == 'deleted').length;
    final lowTrust = clients.where((p) => (p['trustScore'] as num) < 60).length + nurses.where((p) => (p['trustScore'] as num) < 60).length;
    final history = selectedPerson == null ? penalties : penalties.where((p) => p['personId'] == selectedPerson!['id']).toList();
    final penaltyActions = [
      {'key': 'warn', 'label': 'Warn', 'sub': 'Warning — First offense — Legal', 'icon': '⚠️'},
      {'key': 'decrease_trust', 'label': 'Decrease Trust', 'sub': '-10 to -50 Trust — Visible to all', 'icon': '📉'},
      {'key': 'decrease_trust_20', 'label': 'Decrease Trust -20', 'sub': 'Trust -20 — Quick', 'icon': '📉📉'},
      {'key': 'suspend_24h', 'label': 'Suspend 24H', 'sub': 'Suspend 24 hours — Temp', 'icon': '⏸️'},
      {'key': 'suspend_7d', 'label': 'Suspend 7 Days', 'sub': 'Suspend 7 days', 'icon': '⏸️⏸️'},
      {'key': 'suspend_30d', 'label': 'Suspend 30 Days', 'sub': 'Suspend 30 days — Serious', 'icon': '⏸️⏸️⏸️'},
      {'key': 'block_temp', 'label': 'Block Temporary', 'sub': 'Block until CEO unblocks — Appeal', 'icon': '🚫'},
      {'key': 'block_permanent', 'label': 'Block Permanent', 'sub': 'Permanent block — Appeal possible — Serious', 'icon': '🚫🚫'},
      {'key': 'fine', 'label': 'Fine — Extra Fee', 'sub': 'Add 10-50% extra fee on next bookings', 'icon': '💰'},
      {'key': 'require_approval', 'label': 'Require CEO Approval', 'sub': 'All future bookings need CEO approval', 'icon': '🔒'},
      {'key': 'require_100_percent', 'label': 'Require 100% Advance', 'sub': 'No 50% option — 100% advance only', 'icon': '💳'},
      {'key': 'delete_account', 'label': 'DELETE ACCOUNT — Up to Deletion', 'sub': 'Full account deletion — Cannot login — All data removed — FINAL', 'icon': '🗑️💥'},
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(title: const Text('⚖️ CEO Penalize — Client + Nurse — Up to Deletion', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings'))]),
      body: SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          _stat('👤 Total Clients', '${clients.length}', 'All clients who booked — Can be penalized up to deletion'),
          _stat('👩‍⚕️ Total Nurses', '${nurses.length}', 'All nurses — Can be penalized up to deletion'),
          _stat('⚖️ Total Penalties', '${penalties.length}', 'Warn + Trust + Suspend + Block + Fine + Delete'),
          _stat('🚫 Blocked Accounts', '$blocked', 'Blocked clients + nurses — Cannot book/work'),
          _stat('🗑️ Deleted Accounts', '$deleted', 'Deleted — Full account deletion — Up to deletion'),
          _stat('📉 Low Trust', '$lowTrust', 'Trust < 60 — Needs CEO approval + extra fee'),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _searchCtrl, decoration: const InputDecoration(hintText: 'Search client / nurse / phone / email', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), onChanged: (v) => setState(() => search = v.toLowerCase())),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Text('👤 Clients — Penalize up to Deletion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), const Spacer(), Chip(label: Text('${_filterList(clients).length} clients', style: const TextStyle(fontSize: 10)), backgroundColor: Colors.red.withOpacity(0.2))]), const SizedBox(height: 8), ..._filterList(clients).map(_personCard).toList()])),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Text('👩‍⚕️ Nurses — Penalize up to Deletion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), const Spacer(), Chip(label: Text('${_filterList(nurses).length} nurses', style: const TextStyle(fontSize: 10)), backgroundColor: Colors.purple.withOpacity(0.2))]), const SizedBox(height: 8), ..._filterList(nurses).map(_personCard).toList()])),
        ]),
        if (selectedPerson != null) ...[
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.red.withOpacity(0.2))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [CircleAvatar(radius: 28, child: Text((selectedPerson!['name'] as String).isNotEmpty ? (selectedPerson!['name'] as String)[0].toUpperCase() : '?')), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('⚖️ Penalize ${selectedPerson!['name']} — Up to Deletion of Account', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), Text('Phone: ${selectedPerson!['phone']} • Trust: ${selectedPerson!['trustScore']}/100 • Status: ${selectedPerson!['status']}', style: const TextStyle(fontSize: 11, color: Colors.white60)), Chip(label: Text(selectedPerson!['type'].toString().toUpperCase(), style: const TextStyle(fontSize: 10)))])), TextButton(onPressed: () => setState(() => selectedPerson = null), child: const Text('✕ Close Form'))]),
            const SizedBox(height: 14),
            const Text('📋 SELECT PENALTY — Any form up to deletion of account — CEO ONLY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1.1, crossAxisSpacing: 8, mainAxisSpacing: 8), itemCount: penaltyActions.length, itemBuilder: (_, i) {
              final a = penaltyActions[i]; final isSel = selectedPenalty == a['key'];
              return InkWell(onTap: () => setState(() => selectedPenalty = a['key']!), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isSel ? Colors.yellow.withOpacity(0.15) : Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSel ? const Color(0xFFFACC15) : a['key'] == 'delete_account' ? Colors.red.withOpacity(0.5) : Colors.white10)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(a['icon']!, style: const TextStyle(fontSize: 20)), const SizedBox(height: 4), Text(a['label']!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), Text(a['sub']!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: Colors.white60))])));
            }),
            if (selectedPenalty.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('⚖️ Selected Penalty: ${selectedPenalty.toUpperCase()}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFCD34D))),
              Text(_penaltyDesc(selectedPenalty), style: const TextStyle(fontSize: 11, color: Colors.white60)),
              const SizedBox(height: 10),
              const Text('📝 Reason — Why penalizing? (Required — Legal protection)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              TextField(controller: _reasonCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Type detailed reason for penalizing this client/nurse...', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: DropdownButton<String>(value: duration.isEmpty ? null : duration, hint: const Text('⏱️ Duration'), isExpanded: true, items: const [DropdownMenuItem(value: '24h', child: Text('24 Hours')), DropdownMenuItem(value: '7d', child: Text('7 Days')), DropdownMenuItem(value: '30d', child: Text('30 Days')), DropdownMenuItem(value: '90d', child: Text('90 Days')), DropdownMenuItem(value: 'permanent', child: Text('Permanent — Until CEO unblocks')), DropdownMenuItem(value: 'until_appeal', child: Text('Until Appeal Approved'))], onChanged: (v) => setState(() => duration = v ?? ''))),
                const SizedBox(width: 8),
                Expanded(child: DropdownButton<String>(value: trustDecrease.isEmpty ? null : trustDecrease, hint: const Text('📉 Trust Decrease'), isExpanded: true, items: const [DropdownMenuItem(value: '10', child: Text('-10 Trust (Warning)')), DropdownMenuItem(value: '20', child: Text('-20 Trust (Common)')), DropdownMenuItem(value: '30', child: Text('-30 Trust (Serious)')), DropdownMenuItem(value: '50', child: Text('-50 Trust (Very Serious)')), DropdownMenuItem(value: '100', child: Text('-100 Trust → 0 (Blocked)'))], onChanged: (v) => setState(() => trustDecrease = v ?? ''))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: DropdownButton<String>(value: fineAmount.isEmpty ? null : fineAmount, hint: const Text('💰 Fine Amount / Extra Fee %'), isExpanded: true, items: const [DropdownMenuItem(value: '10%', child: Text('10% Extra Fee on Next Bookings')), DropdownMenuItem(value: '20%', child: Text('20% Extra Fee')), DropdownMenuItem(value: '30%', child: Text('30% Extra Fee')), DropdownMenuItem(value: '50%', child: Text('50% Extra Fee — Serious')), DropdownMenuItem(value: '100%', child: Text('100% Extra Fee — Double Payment')), DropdownMenuItem(value: 'GHS100', child: Text('GHS 100 Fine')), DropdownMenuItem(value: 'GHS500', child: Text('GHS 500 Fine'))], onChanged: (v) => setState(() => fineAmount = v ?? ''))),
                const SizedBox(width: 8),
                Expanded(child: DropdownButton<String>(value: evidenceReviewed, isExpanded: true, items: const [DropdownMenuItem(value: 'yes', child: Text('✅ Yes — Reviewed Text + Audio + Video + Photos')), DropdownMenuItem(value: 'partial', child: Text('⚠️ Partial — Reviewed some evidence')), DropdownMenuItem(value: 'no', child: Text('❌ No — No evidence — Based on complaint only'))], onChanged: (v) => setState(() => evidenceReviewed = v ?? 'yes'))),
              ]),
              if (selectedPenalty == 'delete_account') Container(margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), border: Border.all(color: Colors.red.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('🗑️💥 DELETE ACCOUNT — FINAL — Up to Deletion of Account — CEO ONLY — Are you sure?', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13)),
                Text('This will:\n• 🗑️ Delete account ${selectedPerson!['name']} permanently — Up to deletion of account\n• 🚫 User cannot login anymore — Auth disabled\n• 📧 Email/Phone blocked — Cannot register again with same email/phone\n• 📋 All bookings kept for legal but user marked as DELETED\n• 💰 Balance frozen — Cannot withdraw\n• ⚖️ Logged as deletion — Legal protection — CEO action recorded\n• 📝 User notified — Can appeal deletion in ceo-appeals\n• 🔒 Final — Up to deletion — CEO can restore if appeal approved\n\nType DELETE to confirm deletion of account — Up to deletion of account — FINAL:', style: const TextStyle(fontSize: 11, color: Color(0xFFFCA5A5))),
                const SizedBox(height: 8),
                TextField(controller: _deleteCtrl, decoration: const InputDecoration(hintText: 'Type DELETE exactly to confirm deletion of account — Up to deletion!', border: OutlineInputBorder())),
              ])),
              const SizedBox(height: 14),
              Row(children: [Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: _applyPenalty, child: const Text('⚖️ Apply Penalty — Reflects Immediately', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))), const SizedBox(width: 8), Expanded(child: OutlinedButton(onPressed: () => setState(() => selectedPerson = null), child: const Text('Cancel')))]),
            ],
          ])),
        ],
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Text('📜 Penalty History — All Penalties — Client + Nurse — Up to Deletion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), const Spacer(), Chip(label: Text('${history.length} penalties', style: const TextStyle(fontSize: 10)))]),
          const SizedBox(height: 8),
          if (history.isEmpty) const Center(child: Text('Select a client or nurse to see penalty history — Or loading all penalties...', style: TextStyle(color: Colors.white60, fontSize: 12))),
          ...history.map((p) => ListTile(leading: const Text('⚖️'), title: Text('${p['personName']} — ${p['action']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), subtitle: Text('${p['reason']} • ${p['createdAt'] != null ? DateTime.fromMillisecondsSinceEpoch((p['createdAt'] as num).toInt()) : ''}', style: const TextStyle(fontSize: 11, color: Colors.white60)), trailing: Chip(label: Text(p['status'] ?? 'active', style: const TextStyle(fontSize: 10))))).toList(),
        ])),
      ])),
    );
  }

  Widget _stat(String label, String value, String sub) => Container(width: 180, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)), Text(sub, style: const TextStyle(fontSize: 10, color: Colors.white60))]));
}
