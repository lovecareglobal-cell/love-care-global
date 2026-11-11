import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';

/// HR Page - GHS / USD - Flutter version of hr-page-GHS-USD.html
/// NOTE: Despite the filename "GHS-USD", the HTML shows ONLY GHS amounts (no USD conversion, no exchange rate).
/// This Flutter version keeps the same GHS display as HTML, with USD shown as GHS amount (same as HTML — no conversion).
/// - Loads LIVE from ceoWithdrawals (onValue), sorted createdAt desc
/// - Counts: all, pending, approved (approved+completed), rejected, momo, bank, card
///   Stats: Pending (count + amount), Approved (count + amount), Rejected (count + amount), Total Requested (GHS total), MoMo count, Bank count, totalBadge "{all} Requests"
/// - Filters: all / pending / approved / rejected / momo / bank / card — same as HTML filterStatus()
/// - Card: GHS {amount} - {METHOD} + status badge PENDING/APPROVED/COMPLETED/REJECTED, Nurse (name + email), Booking ID (yellow) + Booking Total, Nurse ID, Requested time, method details (MoMo: network/number/name, Bank: bank/account/name/branch, Card: type/****last4/name), CEO Note / HR Note
/// - Approve: prompt note (default "Approved - Sent via {method}") -> confirm "Approve GHS {amount}?" -> update status approved, approved true, approvedAt, approvedAtStr, ceoNote note, approvedBy "CEO Asabere Peter" in nurseWithdrawals + ceoWithdrawals + hrWithdrawals + withdrawalRequests + ceoHRPage/withdrawals + nurseNotifications/{nurseId}/{id} {type withdrawal_approved, title "Withdrawal Approved - GHS {amount}", message "Your withdrawal of GHS {amount} via {method} approved. {note}", read false}
/// - Reject: prompt reason (default "Insufficient details") -> confirm "Reject?" -> update status rejected, approved false, rejectedAt, rejectedAtStr, ceoNote reason, rejectedBy "CEO" in nurseWithdrawals + ceoWithdrawals + hrWithdrawals
/// - Details: dialog with ID / Nurse / Amount / Method / Status / Time / method details — same as HTML viewDetails alert
/// - Copy Details: clipboard "Withdrawal ID: ... Nurse: ... (...) Amount: GHS ... Method: ... MoMo/Bank/Card details" -> toast Copied — same as HTML copyDetails
/// - NO alert buttons — only Sound Settings.

class HRPageScreen extends StatefulWidget {
  const HRPageScreen({super.key});
  @override
  State<HRPageScreen> createState() => _HRPageScreenState();
}

class _HRPageScreenState extends State<HRPageScreen> {
  List<Map> all = [];
  String currentFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _loadAll() {
    FirebaseDatabase.instance.ref('ceoWithdrawals').onValue.listen((e) {
      if (!e.snapshot.exists) { setState(() => all = []); return; }
      final list = <Map>[];
      (e.snapshot.value as Map).forEach((k, v) { list.add({...Map<String, dynamic>.from(v as Map), 'id': k}); });
      setState(() => all = list);
    });
  }

  Map<String, dynamic> get counts {
    int pending = 0, approved = 0, rejected = 0, momo = 0, bank = 0, card = 0;
    double total = 0, pendingAmt = 0, approvedAmt = 0, rejectedAmt = 0;
    for (final w in all) {
      final s = (w['status'] ?? 'pending').toString().toLowerCase();
      final amt = double.tryParse((w['amount'] ?? 0).toString()) ?? 0;
      total += amt;
      if (s == 'pending') { pending++; pendingAmt += amt; }
      else if (s == 'approved' || s == 'completed') { approved++; approvedAmt += amt; }
      else if (s == 'rejected') { rejected++; rejectedAmt += amt; }
      if (w['method'] == 'momo') momo++;
      if (w['method'] == 'bank') bank++;
      if (w['method'] == 'card') card++;
    }
    return {'all': all.length, 'pending': pending, 'approved': approved, 'rejected': rejected, 'momo': momo, 'bank': bank, 'card': card, 'total': total, 'pendingAmt': pendingAmt, 'approvedAmt': approvedAmt, 'rejectedAmt': rejectedAmt};
  }

  List<Map> get filtered {
    var f = List<Map>.from(all);
    if (currentFilter != 'all') {
      if (['momo', 'bank', 'card'].contains(currentFilter)) f = f.where((w) => w['method'] == currentFilter).toList();
      else f = f.where((w) => (w['status'] ?? 'pending').toString().toLowerCase() == currentFilter).toList();
    }
    f.sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
    return f;
  }

  String _statusText(Map w) {
    final s = (w['status'] ?? '').toString().toLowerCase();
    if (s == 'approved') return 'APPROVED';
    if (s == 'completed') return 'COMPLETED';
    if (s == 'rejected') return 'REJECTED';
    return 'PENDING';
  }

  String _methodDetails(Map w) {
    if (w['method'] == 'momo') return 'Network: ${w['momoNetwork'] ?? 'MoMo'}\nNumber: ${w['momoNumber'] ?? ''}\nName: ${w['momoName'] ?? ''}';
    if (w['method'] == 'bank') return 'Bank: ${w['bankName'] ?? ''}\nAccount: ${w['bankAccount'] ?? ''}\nName: ${w['bankAccountName'] ?? ''}\nBranch: ${w['bankBranch'] ?? 'N/A'}';
    if (w['method'] == 'card') return 'Type: ${w['cardType'] ?? ''}\nLast 4: ****${w['cardNumber'] ?? ''}\nName: ${w['cardName'] ?? ''}';
    return '';
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<String?> _prompt(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(context: context, builder: (_) => AlertDialog(title: Text(title), content: TextField(controller: ctrl), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('OK'))]));
  }

  Future<void> _approve(Map w) async {
    final note = await _prompt('Approve this withdrawal? Enter note for nurse:', 'Approved - Sent via ${w['method'] ?? ''}');
    if (note == null) return;
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Approve?'), content: Text('Approve GHS ${w['amount'] ?? 0}?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve'))]));
    if (confirm != true) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final upd = {'status': 'approved', 'approved': true, 'approvedAt': now, 'approvedAtStr': DateTime.now().toString(), 'ceoNote': note, 'approvedBy': 'CEO Asabere Peter'};
      final db = FirebaseDatabase.instance;
      final id = w['id'];
      await db.ref('nurseWithdrawals/$id').update(upd);
      await db.ref('ceoWithdrawals/$id').update(upd);
      await db.ref('hrWithdrawals/$id').update(upd);
      await db.ref('withdrawalRequests/$id').update(upd);
      await db.ref('ceoHRPage/withdrawals/$id').update(upd);
      if (w['nurseId'] != null) await db.ref('nurseNotifications/${w['nurseId']}/$id').set({'type': 'withdrawal_approved', 'title': 'Withdrawal Approved - GHS ${w['amount']}', 'message': 'Your withdrawal of GHS ${w['amount']} via ${w['method']} approved. $note', 'amount': w['amount'], 'method': w['method'], 'createdAt': now, 'read': false});
      _toast('Approved');
    } catch (e) { _toast(e.toString()); }
  }

  Future<void> _reject(Map w) async {
    final reason = await _prompt('Reject? Enter reason:', 'Insufficient details');
    if (reason == null) return;
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Reject?'), content: const Text('Reject?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject'))]));
    if (confirm != true) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final upd = {'status': 'rejected', 'approved': false, 'rejectedAt': now, 'rejectedAtStr': DateTime.now().toString(), 'ceoNote': reason, 'rejectedBy': 'CEO'};
      final db = FirebaseDatabase.instance;
      final id = w['id'];
      await db.ref('nurseWithdrawals/$id').update(upd);
      await db.ref('ceoWithdrawals/$id').update(upd);
      await db.ref('hrWithdrawals/$id').update(upd);
      _toast('Rejected');
    } catch (e) { _toast(e.toString()); }
  }

  void _viewDetails(Map w) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('Withdrawal Details: ${w['withdrawalId'] ?? w['id']}'),
      content: SingleChildScrollView(child: Text('ID: ${w['withdrawalId'] ?? w['id']}\nNurse: ${w['nurseName']}\nAmount: GHS ${w['amount']}\nMethod: ${w['method']}\nStatus: ${w['status']}\nTime: ${w['createdAt'] != null ? DateTime.fromMillisecondsSinceEpoch((w['createdAt'] as num).toInt()) : ''}\n\nDetails: ${_methodDetails(w)}')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  void _copyDetails(Map w) {
    final text = 'Withdrawal ID: ${w['withdrawalId'] ?? w['id']} Nurse: ${w['nurseName']} (${w['nurseId']}) Amount: GHS ${w['amount']} Method: ${w['method']} ${w['method'] == 'momo' ? 'MoMo: ${w['momoNetwork']} ${w['momoNumber']} Name: ${w['momoName']}' : w['method'] == 'bank' ? 'Bank: ${w['bankName']} Acc: ${w['bankAccount']} Name: ${w['bankAccountName']}' : 'Card: ${w['cardType']} ****${w['cardNumber']} Name: ${w['cardName']}'}';
    Clipboard.setData(ClipboardData(text: text));
    _toast('Copied');
  }

  @override
  Widget build(BuildContext context) {
    final c = counts;
    final list = filtered;
    final filters = ['all', 'pending', 'approved', 'rejected', 'momo', 'bank', 'card'];
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(title: const Text('HR Page - Nurse Withdrawals', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 8), child: Chip(label: Text("${c['all']} Requests", style: const TextStyle(fontSize: 11))))), IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings'))]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _stat('Pending', '${c['pending']}', 'GHS ${(c['pendingAmt'] as double).toStringAsFixed(2)}'),
            _stat('Approved', '${c['approved']}', 'GHS ${(c['approvedAmt'] as double).toStringAsFixed(2)}'),
            _stat('Rejected', '${c['rejected']}', 'GHS ${(c['rejectedAmt'] as double).toStringAsFixed(2)}'),
            _stat('Total Requested', '${c['all']}', 'GHS ${(c['total'] as double).toStringAsFixed(2)}'),
            _stat('MoMo', '${c['momo']}', ''),
            _stat('Bank', '${c['bank']}', ''),
            _stat('Card', '${c['card']}', ''),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: filters.map((f) {
            final label = f == 'all' ? 'All (${c['all']})' : f == 'pending' ? 'Pending (${c['pending']})' : f == 'approved' ? 'Approved (${c['approved']})' : f == 'rejected' ? 'Rejected (${c['rejected']})' : f == 'momo' ? 'MoMo (${c['momo']})' : f == 'bank' ? 'Bank (${c['bank']})' : 'Card (${c['card']})';
            return ChoiceChip(label: Text(label, style: const TextStyle(fontSize: 11)), selected: currentFilter == f, onSelected: (_) => setState(() => currentFilter = f));
          }).toList()),
          const SizedBox(height: 12),
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No withdrawals', style: TextStyle(color: Colors.white60))),
          ...list.map((w) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text('GHS ${(double.tryParse((w['amount'] ?? 0).toString()) ?? 0).toStringAsFixed(2)} - ${(w['method'] ?? '').toString().toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(999)), child: Text(_statusText(w), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))]),
            const SizedBox(height: 8),
            Text('Nurse: ${w['nurseName'] ?? 'Unknown'} (${w['nurseEmail'] ?? ''})', style: const TextStyle(fontSize: 12)),
            if (w['bookingId'] != null) Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFFFACC15).withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Text('Booking ID: ${w['bookingId']} - Total: GHS ${(double.tryParse((w['bookingTotal'] ?? w['amount'] ?? 0).toString()) ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Color(0xFFFACC15)))),
            Text('ID: ${w['nurseId'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
            Text('Requested: ${w['createdAt'] != null ? DateTime.fromMillisecondsSinceEpoch((w['createdAt'] as num).toInt()) : ''}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
            const SizedBox(height: 6),
            Text(_methodDetails(w), style: const TextStyle(fontSize: 12)),
            if (w['ceoNote'] != null && (w['ceoNote'] as String).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('CEO Note: ${w['ceoNote']}', style: const TextStyle(fontSize: 11, color: Color(0xFF86EFAC)))),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              if ((w['status'] ?? 'pending').toString().toLowerCase() == 'pending') ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green), onPressed: () => _approve(w), child: const Text('Approve', style: TextStyle(fontSize: 11))),
              if ((w['status'] ?? 'pending').toString().toLowerCase() == 'pending') ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => _reject(w), child: const Text('Reject', style: TextStyle(fontSize: 11))),
              OutlinedButton(onPressed: () => _viewDetails(w), child: const Text('Details', style: TextStyle(fontSize: 11))),
              OutlinedButton(onPressed: () => _copyDetails(w), child: const Text('Copy', style: TextStyle(fontSize: 11))),
            ]),
          ]))),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value, String sub) => Container(width: 150, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: Colors.white60, fontSize: 11))]));
}
