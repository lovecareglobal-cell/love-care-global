import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

/// HR Page - Nurse Withdrawals - CEO Control
/// Converted from hr-page-GHS-USD_3.html
/// - Reads: ceoWithdrawals (live) + fallback: nurseWithdrawals, hrWithdrawals,
///   withdrawalRequests, ceoHRPage/withdrawals (merges by id, so old withdrawals
///   saved to a different path still show up - same recall fix as Registration Center)
/// - Amounts: GHS is primary. If a record also has dollars / amountUSD / USD,
///   both GHS + USD are shown. Totals are in GHS.
/// - Approve / Reject: writes to ALL 5 paths (like the HTML did), + nurse notification
/// - NEVER BLANK: always shows Loading, then List / Empty / Error banner.
///   Firebase errors are shown on screen instead of a white page.

class HRPageScreen extends StatefulWidget {
  const HRPageScreen({super.key});
  @override
  State<HRPageScreen> createState() => _HRPageScreenState();
}

class _HRPageScreenState extends State<HRPageScreen> {
  // FIX: Do NOT use FirebaseDatabase.instance on Web - it fails with
  // "Cannot parse Firebase url" if FirebaseOptions has no databaseURL.
  // Use the explicit RTDB URL for project web-care-618e8.
  static const String _rtdbUrl = 'https://web-care-618e8-default-rtdb.firebaseio.com';
  DatabaseReference _db(String path) {
    return FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: _rtdbUrl).ref(path);
  }

  List<Map<String, dynamic>> _all = [];
  String _filter = 'all';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // ---------- Load ----------
  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 1. Live listener on the main path (like the HTML)
      _db('ceoWithdrawals').onValue.listen(
        (event) {
          if (!mounted) return;
          final val = event.snapshot.value;
          final list = <Map<String, dynamic>>[];
          if (val is Map) {
            val.forEach((k, v) {
              if (v is Map) list.add({'id': k.toString(), ...Map<String, dynamic>.from(v)});
            });
          }
          _mergeAndSet(list, fromLive: true);
        },
        onError: (e) {
          if (mounted) setState(() => _error = 'Live updates failed: $e');
        },
      );
      // 2. One-time fallback: other paths where old withdrawals may live
      await _loadFallback();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Could not load withdrawals: $e\nCheck FirebaseOptions databaseURL in main.dart / firebase_options.dart.';
      });
    }
  }

  Future<void> _loadFallback() async {
    final byId = <String, Map<String, dynamic>>{for (final w in _all) w['id'].toString(): w};
    for (final path in ['nurseWithdrawals', 'hrWithdrawals', 'withdrawalRequests', 'ceoHRPage/withdrawals']) {
      try {
        final snap = await _db(path).get();
        if (!snap.exists) continue;
        final val = snap.value;
        if (val is! Map) continue;
        val.forEach((k, v) {
          if (v is! Map) return;
          final id = k.toString();
          if (!byId.containsKey(id)) {
            byId[id] = {'id': id, ...Map<String, dynamic>.from(v)};
          }
        });
      } catch (_) {}
    }
    if (mounted) setState(() => _all = byId.values.toList());
  }

  void _mergeAndSet(List<Map<String, dynamic>> live, {required bool fromLive}) {
    // Live list wins for records it has; fallback records already in _all are kept
    // if the live list is empty (e.g. ceoWithdrawals was never written, old ones live elsewhere)
    if (live.isEmpty && _all.isNotEmpty) return;
    setState(() {
      _all = live;
      _loading = false;
    });
  }

  // ---------- Helpers ----------
  double _amt(Map w) {
    final v = w['amount'] ?? w['amountGHS'] ?? w['ghs'] ?? w['GHS'] ?? 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  double? _usd(Map w) {
    final v = w['amountUSD'] ?? w['dollars'] ?? w['USD'] ?? w['usd'];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  String _status(Map w) => ((w['status'] ?? 'pending') as String).toLowerCase();
  String _method(Map w) => ((w['method'] ?? '') as String).toLowerCase();

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_all);
    if (_filter == 'momo' || _filter == 'bank' || _filter == 'card') {
      list = list.where((w) => _method(w) == _filter).toList();
    } else if (_filter != 'all') {
      list = list.where((w) => _status(w) == _filter).toList();
    }
    list.sort((a, b) {
      final at = (a['createdAt'] is num ? (a['createdAt'] as num).toInt() : 0);
      final bt = (b['createdAt'] is num ? (b['createdAt'] as num).toInt() : 0);
      return bt.compareTo(at);
    });
    return list;
  }

  Map<String, dynamic> get _counts {
    int pending = 0, approved = 0, rejected = 0, momo = 0, bank = 0, card = 0;
    double total = 0, pendingAmt = 0, approvedAmt = 0, rejectedAmt = 0;
    for (final w in _all) {
      final s = _status(w);
      final amt = _amt(w);
      total += amt;
      if (s == 'pending') { pending++; pendingAmt += amt; }
      else if (s == 'approved' || s == 'completed') { approved++; approvedAmt += amt; }
      else if (s == 'rejected') { rejected++; rejectedAmt += amt; }
      if (_method(w) == 'momo') momo++;
      if (_method(w) == 'bank') bank++;
      if (_method(w) == 'card') card++;
    }
    return {
      'all': _all.length, 'pending': pending, 'approved': approved, 'rejected': rejected,
      'momo': momo, 'bank': bank, 'card': card,
      'total': total, 'pendingAmt': pendingAmt, 'approvedAmt': approvedAmt, 'rejectedAmt': rejectedAmt,
    };
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------- Approve / Reject ----------
  Future<String?> _askText(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Type here')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Confirm')),
        ],
      ),
    );
  }

  Future<void> _approve(Map w) async {
    final id = w['id'].toString();
    final note = await _askText('Approve this withdrawal? Enter note for nurse:', 'Approved - Sent via ${_method(w)}');
    if (note == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve?'),
        content: Text('Approve GHS ${_amt(w).toStringAsFixed(2)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Approve')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final upd = <String, Object?>{
        'status': 'approved', 'approved': true, 'approvedAt': now,
        'approvedAtStr': DateTime.now().toString(), 'ceoNote': note, 'approvedBy': 'CEO Asabere Peter',
      };
      // Write to ALL 5 paths, like the HTML did - so nurse + HR + CEO all see it
      for (final path in ['nurseWithdrawals/$id', 'ceoWithdrawals/$id', 'hrWithdrawals/$id', 'withdrawalRequests/$id', 'ceoHRPage/withdrawals/$id']) {
        await _db(path).update(upd);
      }
      final nurseId = (w['nurseId'] ?? w['nurseUid'] ?? '').toString();
      if (nurseId.isNotEmpty) {
        await _db('nurseNotifications/$nurseId/$id').set({
          'type': 'withdrawal_approved',
          'title': 'Withdrawal Approved - GHS ${_amt(w).toStringAsFixed(2)}',
          'message': 'Your withdrawal of GHS ${_amt(w).toStringAsFixed(2)} via ${_method(w)} approved. $note',
          'amount': _amt(w), 'method': _method(w), 'createdAt': now, 'read': false,
        });
      }
      _toast('Approved');
      await _loadAll();
    } catch (e) {
      _toast('Approve failed: $e');
    }
  }

  Future<void> _reject(Map w) async {
    final id = w['id'].toString();
    final reason = await _askText('Reject? Enter reason:', 'Insufficient details');
    if (reason == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject?'),
        content: const Text('Reject this withdrawal?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Reject')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final upd = <String, Object?>{
        'status': 'rejected', 'approved': false, 'rejectedAt': now,
        'rejectedAtStr': DateTime.now().toString(), 'ceoNote': reason, 'rejectedBy': 'CEO',
      };
      for (final path in ['nurseWithdrawals/$id', 'ceoWithdrawals/$id', 'hrWithdrawals/$id']) {
        await _db(path).update(upd);
      }
      _toast('Rejected');
      await _loadAll();
    } catch (e) {
      _toast('Reject failed: $e');
    }
  }

  void _viewDetails(Map w) {
    final m = _method(w);
    String details = '';
    if (m == 'momo') details = 'Network: ${w['momoNetwork'] ?? ''}\nNumber: ${w['momoNumber'] ?? ''}\nName: ${w['momoName'] ?? ''}';
    else if (m == 'bank') details = 'Bank: ${w['bankName'] ?? ''}\nAccount: ${w['bankAccount'] ?? ''}\nName: ${w['bankAccountName'] ?? ''}';
    else details = 'Type: ${w['cardType'] ?? ''}\nLast 4: ****${w['cardNumber'] ?? ''}\nName: ${w['cardName'] ?? ''}';
    final time = (w['createdAt'] is num) ? DateTime.fromMillisecondsSinceEpoch((w['createdAt'] as num).toInt()).toString() : '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Withdrawal Details'),
        content: SingleChildScrollView(child: Text('ID: ${w['withdrawalId'] ?? w['id']}\nNurse: ${w['nurseName'] ?? 'Unknown'}\nAmount: GHS ${_amt(w).toStringAsFixed(2)}\nMethod: $m\nStatus: ${_status(w)}\nTime: $time\n\nDetails:\n$details')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _copyDetails(Map w) {
    final m = _method(w);
    String methodLine = '';
    if (m == 'momo') methodLine = 'MoMo: ${w['momoNetwork'] ?? ''} ${w['momoNumber'] ?? ''} Name: ${w['momoName'] ?? ''}';
    else if (m == 'bank') methodLine = 'Bank: ${w['bankName'] ?? ''} Acc: ${w['bankAccount'] ?? ''} Name: ${w['bankAccountName'] ?? ''}';
    else methodLine = 'Card: ${w['cardType'] ?? ''} ****${w['cardNumber'] ?? ''} Name: ${w['cardName'] ?? ''}';
    final text = 'Withdrawal ID: ${w['withdrawalId'] ?? w['id']}\nNurse: ${w['nurseName'] ?? ''} (${w['nurseId'] ?? ''})\nAmount: GHS ${_amt(w).toStringAsFixed(2)}\nMethod: $m\n$methodLine';
    Clipboard.setData(ClipboardData(text: text));
    _toast('Copied');
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0C0A1E);
    const card = Color(0xFF1A1633);
    const gold = Color(0xFFFACC15);
    final c = _counts;
    final filtered = _filtered;

    Widget tab(String key, String label, int count) {
      final active = _filter == key;
      return GestureDetector(
        onTap: () => setState(() => _filter = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: active ? gold : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Text('$label ($count)', style: TextStyle(color: active ? Colors.black : const Color(0xFF9A95B8), fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      );
    }

    Widget stat(String label, String value, String sub) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.08))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Color(0xFF9A95B8), fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
          Text(sub, style: const TextStyle(color: Color(0xFF9A95B8), fontSize: 11)),
        ]),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0A1E),
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('HR Page - Nurse Withdrawals - CEO Control', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          Text('Nurses request withdrawal MoMo, Bank, Card - CEO receives details and amount - Approve/Reject', style: TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
        ]),
        actions: [
          Chip(label: Text('${c['all']} Requests'), backgroundColor: Colors.white.withOpacity(0.06)),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll, tooltip: 'Refresh'),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              tab('all', 'All', c['all']), const SizedBox(width: 8),
              tab('pending', 'Pending', c['pending']), const SizedBox(width: 8),
              tab('approved', 'Approved', c['approved']), const SizedBox(width: 8),
              tab('rejected', 'Rejected', c['rejected']), const SizedBox(width: 8),
              tab('momo', 'MoMo', c['momo']), const SizedBox(width: 8),
              tab('bank', 'Bank', c['bank']), const SizedBox(width: 8),
              tab('card', 'Card', c['card']),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 10, runSpacing: 10,
              children: [
                SizedBox(width: 160, child: stat('Pending', '${c['pending']}', 'GHS ${(c['pendingAmt'] as double).toStringAsFixed(2)}')),
                SizedBox(width: 160, child: stat('Approved', '${c['approved']}', 'GHS ${(c['approvedAmt'] as double).toStringAsFixed(2)}')),
                SizedBox(width: 160, child: stat('Rejected', '${c['rejected']}', 'GHS ${(c['rejectedAmt'] as double).toStringAsFixed(2)}')),
                SizedBox(width: 160, child: stat('Total Requested', 'GHS ${(c['total'] as double).toStringAsFixed(2)}', 'All time')),
                SizedBox(width: 160, child: stat('MoMo', '${c['momo']}', 'Requests')),
                SizedBox(width: 160, child: stat('Bank', '${c['bank']}', 'Requests')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Loading withdrawals...', style: TextStyle(color: Color(0xFF9A95B8)))]))
                : filtered.isEmpty
                    ? Center(child: Text('No $_filter withdrawals', style: const TextStyle(color: Color(0xFF9A95B8))))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _withdrawalCard(filtered[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _withdrawalCard(Map w) {
    final s = _status(w);
    final m = _method(w);
    final amt = _amt(w);
    final usd = _usd(w);
    final statusText = s == 'approved' ? 'APPROVED' : s == 'completed' ? 'COMPLETED' : s == 'rejected' ? 'REJECTED' : 'PENDING';
    final statusColor = s == 'pending' ? const Color(0xFFFDE68A) : s == 'approved' || s == 'completed' ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5);
    final timeStr = (w['createdAt'] is num) ? DateTime.fromMillisecondsSinceEpoch((w['createdAt'] as num).toInt()).toString() : '';

    Widget detailLine(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text('$label: $value', style: const TextStyle(fontSize: 12, color: Colors.white)),
      );
    }

    Widget methodDetails() {
      if (m == 'momo') {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          detailLine('Network', '${w['momoNetwork'] ?? 'MoMo'}'),
          detailLine('Number', '${w['momoNumber'] ?? ''}'),
          detailLine('Name', '${w['momoName'] ?? ''}'),
        ]);
      } else if (m == 'bank') {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          detailLine('Bank', '${w['bankName'] ?? ''}'),
          detailLine('Account', '${w['bankAccount'] ?? ''}'),
          detailLine('Name', '${w['bankAccountName'] ?? ''}'),
          detailLine('Branch', '${w['bankBranch'] ?? 'N/A'}'),
        ]);
      } else if (m == 'card') {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          detailLine('Type', '${w['cardType'] ?? ''}'),
          detailLine('Last 4', '****${w['cardNumber'] ?? ''}'),
          detailLine('Name', '${w['cardName'] ?? ''}'),
        ]);
      }
      return const Text('Method details not provided', style: TextStyle(fontSize: 12, color: Colors.white70));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text('GHS ${amt.toStringAsFixed(2)}${usd != null ? '  •  USD ${usd.toStringAsFixed(2)}' : ''} - ${m.toUpperCase()}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(999)), child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
        Text('Nurse: ${w['nurseName'] ?? 'Unknown'} (${w['nurseEmail'] ?? ''})', style: const TextStyle(fontSize: 12, color: Colors.white)),
        if (w['bookingId'] != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFFACC15).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Text('Booking ID: ${w['bookingId']} - Total: GHS ${(double.tryParse('${w['bookingTotal'] ?? amt}') ?? amt).toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: Color(0xFFFACC15))),
          ),
        Text('ID: ${w['nurseId'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
        Text('Requested: $timeStr', style: const TextStyle(fontSize: 11, color: Colors.white70)),
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFF0C0A1E).withOpacity(0.6), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('WITHDRAWAL DETAILS - CEO RECEIVES:', style: TextStyle(fontSize: 11, color: Color(0xFF9A95B8), fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            methodDetails(),
            if (w['notes'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Notes: ${w['notes']}', style: const TextStyle(fontSize: 12, color: Colors.white))),
          ]),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (s == 'pending') ...[
            ElevatedButton(onPressed: () => _approve(w), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: Text('Approve - Send GHS ${amt.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11))),
            ElevatedButton(onPressed: () => _reject(w), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Reject', style: TextStyle(fontSize: 11))),
          ],
          OutlinedButton(onPressed: () => _viewDetails(w), child: const Text('Full Details', style: TextStyle(fontSize: 11))),
          OutlinedButton(onPressed: () => _copyDetails(w), child: const Text('Copy Details', style: TextStyle(fontSize: 11, color: Color(0xFFFACC15)))),
        ]),
      ]),
    );
  }
}

// Alias: both names point to the same screen, so main.dart works either way.
typedef HRWithdrawalsPage = HRPageScreen;
