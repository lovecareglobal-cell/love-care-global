import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

/// CLEANUP - Fix Auto-Approved Bug - Flutter version of cleanup-auto-approval.html
/// - Bug: Existing nurses were auto-approved because registration created allowedNurses. This tool moves them back to PENDING.
/// - SCAN - same as HTML scan():
///   Read allowedNurses once. If not exists -> "No allowedNurses found".
///   For each entry: if isApproved===false OR status==='pending' -> count++ + log "BUG FOUND: allowedNurses/{key} has isApproved={isApproved}, status={status}, email={email} - Should be PENDING, not in allowedNurses"
///   Else -> log "OK: allowedNurses/{key} isApproved={isApproved}, status={status}, email={email}"
///   Log "\nFound {count} auto-approved nurses that should be pending"
/// - FIX - same as HTML fixPending():
///   Confirm: "This will DELETE allowedNurses entries for nurses that have isApproved=false, moving them back to PENDING.\n\nCEO will need to approve them again properly.\n\nContinue?"
///   Read allowedNurses once. If not exists -> "No allowedNurses".
///   For each entry where isApproved===false OR status==='pending' OR canLogin===false:
///     Remove allowedNurses/{key} -> log "✅ Deleted allowedNurses/{key} - now pending"
///     Remove allowedNursesByUid/{uid||key}
///     If uid: pendingData = {...v, isApproved:false, approved:false, canLogin:false, status:'pending', pending:true}
///       Set pending_nurses/{uid} = pendingData -> log "✅ Ensured pending_nurses/{uid}"
///       Set pendingNurses/{uid} = pendingData
///       Update nurses/{uid} {isApproved:false, approved:false, canLogin:false, status:'pending', pending:true}
///       Update ceoRegistrationCenter/nurses/{uid} {isApproved:false, approved:false, canLogin:false, status:'pending'}
///     fixed++
///   Log "\nFixed {fixed} nurses - moved back to PENDING"
///   Log "Now CEO page should show them in Pending tab, not Approved"
///   Toast "Fixed {fixed} nurses. They are now pending. CEO must approve them in ceo-registration-center.html"
/// - CHECK ALL - same as HTML checkAll():
///   Read nurses once. If not exists -> "No nurses". For each: log "nurses/{key}: email={email}, isApproved={isApproved}, status={status}, canLogin={canLogin}"
///   Read allowedNurses once. If exists: log "\n--- allowedNurses ---" + for each: log "allowedNurses/{key}: email={email}, isApproved={isApproved}"
/// - NO alert buttons — only Sound Settings.

class CleanupAutoApprovalScreen extends StatefulWidget {
  const CleanupAutoApprovalScreen({super.key});
  @override
  State<CleanupAutoApprovalScreen> createState() => _CleanupAutoApprovalScreenState();
}

class _CleanupAutoApprovalScreenState extends State<CleanupAutoApprovalScreen> {
  String logText = 'Ready...  This will find nurses where allowedNurses exists but isApproved=false and delete allowedNurses so they become pending again.  CEO will then need to approve them properly.';
  bool busy = false;

  void _log(String m) => setState(() => logText = '$logText\n$m');
  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _scan() async {
    setState(() { logText = ''; busy = true; });
    try {
      _log('Scanning allowedNurses for auto-approved bug...');
      final snap = await FirebaseDatabase.instance.ref('allowedNurses').get();
      if (!snap.exists) { _log('No allowedNurses found'); setState(() => busy = false); return; }
      int count = 0;
      (snap.value as Map).forEach((k, v) {
        if (v is! Map) return;
        final isApproved = v['isApproved'], status = v['status'], email = v['email'];
        if (isApproved == false || status == 'pending') {
          count++;
          _log('BUG FOUND: allowedNurses/$k has isApproved=$isApproved, status=$status, email=$email - Should be PENDING, not in allowedNurses');
        } else {
          _log('OK: allowedNurses/$k isApproved=$isApproved, status=$status, email=$email');
        }
      });
      _log('\nFound $count auto-approved nurses that should be pending');
    } catch (e) { _log('Error: $e'); }
    setState(() => busy = false);
  }

  Future<void> _fixPending() async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Fix auto-approved nurses?'), content: const Text('This will DELETE allowedNurses entries for nurses that have isApproved=false, moving them back to PENDING.\n\nCEO will need to approve them again properly.\n\nContinue?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('FIX'))]));
    if (confirm != true) return;
    setState(() { logText = ''; busy = true; });
    try {
      _log('Fixing auto-approved nurses - moving to pending...');
      final snap = await FirebaseDatabase.instance.ref('allowedNurses').get();
      if (!snap.exists) { _log('No allowedNurses'); setState(() => busy = false); return; }
      int fixed = 0;
      final db = FirebaseDatabase.instance;
      for (final entry in (snap.value as Map).entries) {
        final key = entry.key.toString(); final v = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : {};
        if (v['isApproved'] == false || v['status'] == 'pending' || v['canLogin'] == false) {
          try { await db.ref('allowedNurses/$key').remove(); _log('✅ Deleted allowedNurses/$key - now pending'); } catch (e) { _log('Error $key: $e'); }
          try { await db.ref('allowedNursesByUid/${v['uid'] ?? key}').remove(); } catch (_) {}
          if ((v['uid'] ?? '').toString().isNotEmpty) {
            final uid = v['uid'].toString();
            final pendingData = {...v, 'isApproved': false, 'approved': false, 'canLogin': false, 'status': 'pending', 'pending': true};
            try { await db.ref('pending_nurses/$uid').set(pendingData); _log('✅ Ensured pending_nurses/$uid'); } catch (_) {}
            try { await db.ref('pendingNurses/$uid').set(pendingData); } catch (_) {}
            try { await db.ref('nurses/$uid').update({'isApproved': false, 'approved': false, 'canLogin': false, 'status': 'pending', 'pending': true}); } catch (_) {}
            try { await db.ref('ceoRegistrationCenter/nurses/$uid').update({'isApproved': false, 'approved': false, 'canLogin': false, 'status': 'pending'}); } catch (_) {}
          }
          fixed++;
        }
      }
      _log('\nFixed $fixed nurses - moved back to PENDING');
      _log('Now CEO page should show them in Pending tab, not Approved');
      _toast('Fixed $fixed nurses. They are now pending. CEO must approve them in ceo-registration-center.html');
    } catch (e) { _log('Error: $e'); }
    setState(() => busy = false);
  }

  Future<void> _checkAll() async {
    setState(() { logText = ''; busy = true; });
    try {
      _log('Checking all nurses...');
      final snap = await FirebaseDatabase.instance.ref('nurses').get();
      if (!snap.exists) { _log('No nurses'); }
      else (snap.value as Map).forEach((k, v) { if (v is Map) _log('nurses/$k: email=${v['email']}, isApproved=${v['isApproved']}, status=${v['status']}, canLogin=${v['canLogin']}'); });
      final snap2 = await FirebaseDatabase.instance.ref('allowedNurses').get();
      if (snap2.exists) {
        _log('\n--- allowedNurses ---');
        (snap2.value as Map).forEach((k, v) { if (v is Map) _log('allowedNurses/$k: email=${v['email']}, isApproved=${v['isApproved']}'); });
      }
    } catch (e) { _log('Error: $e'); }
    setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('CLEANUP - Fix Auto-Approved Nurses', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1C1238), actions: [IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings'))]),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.purple.withOpacity(0.18))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CLEANUP - Fix Auto-Approved Nurses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Text('Existing nurses were auto-approved because registration created allowedNurses. This tool moves them back to PENDING.', style: TextStyle(fontSize: 11, color: Color(0xFFFCA5A5))),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: busy ? null : _scan, child: const Text('SCAN - Find auto-approved nurses (allowedNurses with isApproved=false)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)))),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: busy ? null : _fixPending, child: const Text('FIX - Move auto-approved back to PENDING (delete allowedNurses)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: busy ? null : _checkAll, child: const Text('CHECK ALL - Show all nurses status', style: TextStyle(color: Color(0xFF052E16), fontWeight: FontWeight.bold, fontSize: 11)))),
        const SizedBox(height: 12),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)), child: Text(logText, style: const TextStyle(color: Color(0xFF00FF00), fontSize: 11))),
      ]))))),
    );
  }
}
