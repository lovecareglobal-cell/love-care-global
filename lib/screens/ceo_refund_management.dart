import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';

/// CEO Refund Management - CLIENT REFUNDS ONLY, CEO SIDE
/// - Loads: refundRequests + allRefundRequests + AUTO-SYNC from bookings
/// - NEW 20/80 RULE: Client pays ONLY 20% CEO fee in app to book.
///   Nurse cash 80% is paid CASH by client to nurse AFTER work. CEO never pays nurse.
/// - REFUND RULES (locked):
///   Nurse rejects = AUTO refund FULL 20% to client. CEO MUST refund. Cannot Reject this refund.
///   Client cancels BEFORE start = NO refund. CEO keeps 20%. Reject any refund request for this.
///   Client cancels AFTER start = NO refund. CEO keeps 20% + client pays nurse cash for days worked.
///   Client cancels = nurse gets GH 0 from CEO, nurse -> Available.
/// - Refund Amount = CEO fee ONLY (20% of total). NEVER total, NEVER 50%, NEVER nurse cash.
///   Old bookings with only amount/total -> CEO = total * 0.20, Nurse = total * 0.80.
/// - Mark as PAID clears: refundRequests + allRefundRequests + bookings/{id} refundPaid:true, refundStatus:refund_paid.
/// - 50% DELETED. No 50% anywhere.

class CEORefundManagementScreen extends StatefulWidget {
  const CEORefundManagementScreen({super.key});
  @override
  State<CEORefundManagementScreen> createState() => _CEORefundManagementScreenState();
}

// Aliases - so main.dart + old files still work
class CEORefundManagementPage extends CEORefundManagementScreen {
  const CEORefundManagementPage({super.key});
}
class CeoRefundManagementScreen extends CEORefundManagementScreen {
  const CeoRefundManagementScreen({super.key});
}

class _CEORefundManagementScreenState extends State<CEORefundManagementScreen> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  List<Map<String, dynamic>> allRefunds = [];
  String filterStatus = 'all';
  String searchQ = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRefunds();
    _startRealtime();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---- NEW 20/80 MONEY HELPERS ----
  double _num(dynamic v) => double.tryParse('$v') ?? 0;
  double _totalOf(Map r) {
    double t = _num(r['totalAmount'] ?? r['total'] ?? r['totalGHS'] ?? 0);
    if (t > 0) return t;
    final ceo = _num(r['ceoFee'] ?? r['ceoFeeGHS'] ?? 0);
    final nurse = _num(r['nurseCash'] ?? r['nurseCashAmount'] ?? 0);
    if (ceo > 0) return ceo * 5;
    if (nurse > 0) return nurse / 0.80;
    // Old refund requests only saved amount = total paid (before 20/80 fix) OR refund amount itself.
    // If booking says nurse rejected, amount may already be 20%. We handle that in _refundAmountOf.
    return _num(r['amount'] ?? 0);
  }
  double _ceoFeeOf(Map r) {
    double c = _num(r['ceoFee'] ?? r['ceoFeeGHS'] ?? r['amountPaidNow'] ?? 0);
    if (c > 0) return c;
    return _totalOf(r) * 0.20;
  }
  double _nurseCashOf(Map r) {
    double n = _num(r['nurseCash'] ?? r['nurseCashAmount'] ?? r['amountYouWillCollectCash'] ?? 0);
    if (n > 0) return n;
    return _totalOf(r) * 0.80;
  }
  // Refund amount = CEO fee ONLY. If this is an auto nurse-reject, amount saved in booking is ceoFee.
  // If manual request saved amount = total (old bug), we convert to 20%.
  double _refundAmountOf(Map r) {
    if (r['refundAmount'] != null && _num(r['refundAmount']) > 0) return _num(r['refundAmount']);
    if (r['isAutoRefund'] == true) {
      // Auto: booking ceoFee is correct. If ceoFee missing, use ceoFeeOf.
      return _ceoFeeOf(r);
    }
    // Manual: if amount looks like total (bigger than ceoFee and ceoFee known), use ceoFee.
    final amt = _num(r['amount'] ?? 0);
    final ceo = _ceoFeeOf(r);
    if (ceo > 0 && amt > ceo + 1) return ceo;
    if (amt > 0 && ceo <= 0) return amt * 0.20;
    if (amt > 0) return amt;
    return ceo;
  }
  String _refundRule(Map r) {
    final s = '${r['bookingStatus'] ?? r['status'] ?? ''}'.toLowerCase();
    final reason = '${r['reason'] ?? r['refundReason'] ?? r['cancelTermsApplied'] ?? ''}'.toLowerCase();
    if (r['isAutoRefund'] == true || s.contains('rejected_by_nurse') || reason.contains('nurse_rejects') || r['refundCeoFee'] == true) return 'nurse_rejects';
    if (reason.contains('after_start') || s.contains('cancelled_by_client') && reason.contains('after')) return 'client_cancels_after_start';
    if (s.contains('cancelled_by_client') || reason.contains('before_start') || reason.contains('client_cancels_before')) return 'client_cancels_before_start';
    if (s.contains('cancel')) return 'client_cancels_before_start';
    return 'manual';
  }
  String _refundRuleLabel(Map r) {
    switch (_refundRule(r)) {
      case 'nurse_rejects':
        return 'AUTO REFUND DUE - Nurse Rejected - Must refund FULL 20%';
      case 'client_cancels_before_start':
        return 'NO REFUND - Client Cancelled Before Start - CEO keeps 20%';
      case 'client_cancels_after_start':
        return 'NO REFUND - Client Cancelled After Start - CEO keeps 20% + Client pays nurse cash for days worked';
      default:
        return 'Manual Request - Check rule: Nurse rejects = refund 20%. Client cancels = CEO keeps 20%.';
    }
  }
  bool _mustRefund(Map r) => _refundRule(r) == 'nurse_rejects';
  bool _mustNotRefund(Map r) => _refundRule(r) == 'client_cancels_before_start' || _refundRule(r) == 'client_cancels_after_start';

  // Same as HTML loadRefunds() - merge refundRequests + allRefundRequests + AUTO from bookings
  Future<void> _loadRefunds() async {
    try {
      final snap1 = await _db.child('refundRequests').get();
      final snap2 = await _db.child('allRefundRequests').get();
      final merged = <String, Map<String, dynamic>>{};
      if (snap1.exists && snap1.value is Map) {
        final data = Map<String, dynamic>.from(snap1.value as Map);
        for (final e in data.entries) {
          if (e.value is Map) merged[e.key.toString()] = {...Map<String, dynamic>.from(e.value as Map), 'refundId': (Map<String, dynamic>.from(e.value as Map)['refundId'] ?? e.key).toString()};
        }
      }
      if (snap2.exists && snap2.value is Map) {
        final data = Map<String, dynamic>.from(snap2.value as Map);
        for (final e in data.entries) {
          if (e.value is Map) {
            final v = Map<String, dynamic>.from(e.value as Map);
            merged.putIfAbsent(e.key.toString(), () => {...v, 'refundId': (v['refundId'] ?? e.key).toString()});
          }
        }
      }
      allRefunds = merged.values.toList();
      allRefunds.sort((a, b) => (int.tryParse('${b['createdAt'] ?? 0}') ?? 0).compareTo(int.tryParse('${a['createdAt'] ?? 0}') ?? 0));
      await _syncAutoRefundsFromBookings();
    } catch (e) {
      _toast('Error: $e');
    }
    if (mounted) setState(() => isLoading = false);
  }

  // AUTO: Nurse rejects -> create refund request for FULL 20% if not already there.
  // Client cancels -> do NOT auto-create refund (CEO keeps 20%). We only show rule if manual request exists.
  Future<void> _syncAutoRefundsFromBookings() async {
    try {
      final snap = await _db.child('bookings').get();
      if (!snap.exists || snap.value is! Map) return;
      final data = Map<String, dynamic>.from(snap.value as Map);
      for (final e in data.entries) {
        if (e.value is! Map) continue;
        final b = Map<String, dynamic>.from(e.value as Map);
        final status = '${b['status'] ?? ''}'.toLowerCase();
        final isNurseReject = status == 'rejected_by_nurse' || b['refundCeoFee'] == true;
        final refundPaid = b['refundPaid'] == true || b['refundStatus'] == 'refund_paid' || b['refundStatus'] == 'paid';
        if (!isNurseReject || refundPaid) continue;
        final bookingKey = e.key.toString();
        final bookingId = (b['bookingId'] ?? bookingKey).toString();
        // Already have a refund for this booking?
        final exists = allRefunds.any((r) => (r['bookingId'] ?? '').toString() == bookingId || (r['bookingKey'] ?? '').toString() == bookingKey);
        if (exists) {
          // Enrich existing with correct 20% numbers if missing
          final idx = allRefunds.indexWhere((r) => (r['bookingId'] ?? '').toString() == bookingId || (r['bookingKey'] ?? '').toString() == bookingKey);
          if (idx != -1 && allRefunds[idx]['isAutoRefund'] != true) {
            allRefunds[idx]['isAutoRefund'] = true;
            allRefunds[idx]['refundCeoFee'] = true;
            allRefunds[idx]['ceoFee'] = _ceoFeeOf({...b, ...allRefunds[idx]});
            allRefunds[idx]['totalAmount'] = _totalOf({...b, ...allRefunds[idx]});
            allRefunds[idx]['nurseCash'] = _nurseCashOf({...b, ...allRefunds[idx]});
          }
          continue;
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        final refundId = 'auto_$bookingKey';
        final auto = <String, dynamic>{
          'refundId': refundId,
          'bookingId': bookingId,
          'bookingKey': bookingKey,
          'bookingStatus': b['status'],
          'status': 'pending',
          'isAutoRefund': true,
          'autoRefund': true,
          'refundCeoFee': true,
          'refundStatus': 'refund_due_full_20',
          'cancelTermsApplied': 'nurse_rejects_refund_full_20',
          'clientName': b['clientName'] ?? '',
          'clientPhone': b['clientPhone'] ?? '',
          'clientEmail': b['clientEmail'] ?? '',
          'clientPhoto': b['clientPhoto'] ?? b['clientPhotoUrl'] ?? '',
          'clientPhotoUrl': b['clientPhotoUrl'] ?? b['clientPhoto'] ?? '',
          'nurseName': b['nurseName'] ?? '',
          'nursePhone': b['nursePhone'] ?? '',
          'nurseId': b['nurseId'] ?? '',
          'patientName': b['patientName'] ?? '',
          'patientPhone': b['patientPhone'] ?? '',
          'patientLocation': b['patientLocation'] ?? b['location'] ?? '',
          'amount': _ceoFeeOf(b),
          'refundAmount': _ceoFeeOf(b),
          'ceoFee': _ceoFeeOf(b),
          'totalAmount': _totalOf(b),
          'nurseCash': _nurseCashOf(b),
          'reason': 'Nurse rejected - Auto refund FULL 20%',
          'details': 'Nurse ${b['nurseName'] ?? ''} rejected booking $bookingId. Client gets FULL 20% refund. CEO keeps GH 0 for this booking.',
          'destination': b['clientPhone'] ?? '',
          'method': 'Paystack / MoMo - refund to client',
          'paystackRef': b['paystackRef'] ?? b['transactionId'] ?? '',
          'bookingTime': b['time'] ?? b['createdAt'] ?? now,
          'createdAt': b['rejectedAt'] ?? now,
        };
        allRefunds.add(auto);
        // Save so it persists and shows on other devices / after refresh
        try {
          await _db.child('refundRequests/$refundId').set(auto);
          await _db.child('allRefundRequests/$refundId').set(auto);
        } catch (_) {}
      }
      _sortAll();
    } catch (_) {}
  }

  // Same as HTML startRealtime() - onValue for both paths + bookings auto-sync
  void _startRealtime() {
    _db.child('refundRequests').onValue.listen((e) {
      if (e.snapshot.value == null || e.snapshot.value is! Map) return;
      final data = Map<String, dynamic>.from(e.snapshot.value as Map);
      for (final entry in data.entries) {
        if (entry.value is! Map) continue;
        final v = Map<String, dynamic>.from(entry.value as Map);
        _addOrUpdate({...v, 'refundId': (v['refundId'] ?? entry.key).toString()});
      }
      _sortAll();
    });
    _db.child('allRefundRequests').onValue.listen((e) {
      if (e.snapshot.value == null || e.snapshot.value is! Map) return;
      final data = Map<String, dynamic>.from(e.snapshot.value as Map);
      for (final entry in data.entries) {
        if (entry.value is! Map) continue;
        final v = Map<String, dynamic>.from(entry.value as Map);
        final rid = (v['refundId'] ?? entry.key).toString();
        final exists = allRefunds.any((r) => (r['refundId'] ?? '').toString() == rid);
        if (!exists) allRefunds.add({...v, 'refundId': rid});
      }
      _sortAll();
    });
    // Realtime auto-sync: when nurse rejects, refund appears here LIVE
    _db.child('bookings').onChildChanged.listen((e) {
      if (e.snapshot.value == null || e.snapshot.value is! Map) return;
      final b = Map<String, dynamic>.from(e.snapshot.value as Map);
      final status = '${b['status'] ?? ''}'.toLowerCase();
      if (status == 'rejected_by_nurse' || b['refundCeoFee'] == true) {
        _syncAutoRefundsFromBookings();
      }
    });
  }

  void _addOrUpdate(Map<String, dynamic> r) {
    final rid = (r['refundId'] ?? '').toString();
    final idx = allRefunds.indexWhere((x) => (x['refundId'] ?? '').toString() == rid);
    if (idx == -1) {
      allRefunds.add(r);
    } else {
      allRefunds[idx] = {...allRefunds[idx], ...r};
    }
  }

  void _sortAll() {
    allRefunds.sort((a, b) => (int.tryParse('${b['createdAt'] ?? 0}') ?? 0).compareTo(int.tryParse('${a['createdAt'] ?? 0}') ?? 0));
    if (mounted) setState(() {});
  }

  // Same as HTML renderRefunds() filter + search + NEW 20/80 filters
  List<Map<String, dynamic>> get filtered {
    var list = List<Map<String, dynamic>>.from(allRefunds);
    if (filterStatus == 'auto_due') {
      list = list.where((r) => _mustRefund(r) && (r['status'] ?? 'pending') != 'paid' && (r['status'] ?? 'pending') != 'rejected').toList();
    } else if (filterStatus == 'no_refund') {
      list = list.where((r) => _mustNotRefund(r)).toList();
    } else if (filterStatus != 'all') {
      list = list.where((r) => (r['status'] ?? 'pending').toString() == filterStatus).toList();
    }
    if (searchQ.trim().isNotEmpty) {
      final q = searchQ.toLowerCase();
      list = list.where((r) => '${r['clientName']} ${r['clientPhone']} ${r['clientEmail']} ${r['bookingId']} ${r['nurseName']} ${r['patientName']}'.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  String _timeAgo(dynamic t) {
    final v = int.tryParse('$t') ?? 0;
    if (v == 0) return '';
    final d = DateTime.now().millisecondsSinceEpoch - v;
    final m = (d / 60000).floor();
    if (m < 1) return 'Just now';
    if (m < 60) return '$m m ago';
    final h = (m / 60).floor();
    if (h < 24) return '$h h ago';
    return '${(h / 24).floor()}d ago';
  }

  String _dateStr(dynamic t) {
    final v = int.tryParse('$t') ?? 0;
    if (v == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(v);
    return '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _cleanPhone(String p) => p.replaceAll(RegExp(r'[^0-9+]'), '');

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _toast('Cannot open: $url');
    }
  }

  // Same as HTML updateRefundStatus() - writes to 3 places + bookings refundPaid when PAID
  Future<void> _updateStatus(Map<String, dynamic> r, String newStatus) async {
    final refundId = (r['refundId'] ?? '').toString();
    final bookingKey = (r['bookingKey'] ?? '').toString();
    final refundAmount = _refundAmountOf(r);

    // BLOCK: Cannot Reject an Auto Nurse-Reject refund - CEO MUST refund 20%
    if (newStatus == 'rejected' && _mustRefund(r)) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1C1238),
          title: const Text('Cannot Reject This Refund', style: TextStyle(color: Colors.white, fontSize: 14)),
          content: Text(
            'Nurse rejected booking ${r['bookingId']}.\n\nRule: Nurse rejects = FULL 20% refund to client.\nRefund Due: GHS ${refundAmount.toStringAsFixed(2)}\n\nYou MUST Approve then Mark as PAID after you refund via Paystack / MoMo.\nCEO keeps GH 0 for this booking.',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK, I Will Refund'))],
        ),
      );
      return;
    }

    // WARN: Client cancelled - CEO keeps 20%, do NOT approve refund
    if ((newStatus == 'approved' || newStatus == 'paid') && _mustNotRefund(r)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1C1238),
          title: const Text('Warning - Client Cancelled, CEO Keeps 20%', style: TextStyle(color: Colors.white, fontSize: 14)),
          content: Text(
            'Booking ${r['bookingId']} was cancelled by CLIENT.\n\nRule: Client cancels = NO refund. CEO keeps 20% (GHS ${refundAmount.toStringAsFixed(2)}).\n\nAre you SURE you still want to $newStatus this? This should normally be Rejected.',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel - Keep 20%')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Refund Anyway'))],
        ),
      );
      if (ok != true) return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1238),
        title: Text('Set refund $refundId to ${newStatus.toUpperCase()}?\nRefund: GHS ${refundAmount.toStringAsFixed(2)} (20% ONLY)', style: const TextStyle(color: Colors.white, fontSize: 14)),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes'))],
      ),
    );
    if (confirm != true) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final isPaid = newStatus == 'paid';
      await _db.child('refundRequests/$refundId').update({'status': newStatus, 'updatedAt': now, 'updatedAtStr': DateTime.now().toString(), 'refundAmount': refundAmount, if (isPaid) 'refundPaid': true, if (isPaid) 'refundPaidAt': now});
      await _db.child('allRefundRequests/$refundId').update({'status': newStatus, 'updatedAt': now, 'refundAmount': refundAmount, if (isPaid) 'refundPaid': true, if (isPaid) 'refundPaidAt': now});
      if (bookingKey.isNotEmpty) {
        await _db.child('bookings/$bookingKey').update({'refundStatus': isPaid ? 'refund_paid' : newStatus, 'refundUpdatedAt': now, 'refundAmount': refundAmount, if (isPaid) 'refundPaid': true, if (isPaid) 'refundPaidAt': now});
      }
      final idx = allRefunds.indexWhere((x) => (x['refundId'] ?? '').toString() == refundId);
      if (idx != -1) setState(() {
        allRefunds[idx]['status'] = newStatus;
        allRefunds[idx]['refundAmount'] = refundAmount;
        if (isPaid) allRefunds[idx]['refundPaid'] = true;
      });
      _toast('Refund $refundId set to $newStatus - GHS ${refundAmount.toStringAsFixed(2)} (20% only)');
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Color _cardBorder(String s) {
    if (s == 'pending') return const Color(0xFFFACC15);
    if (s == 'approved') return const Color(0xFF22C55E);
    if (s == 'paid') return const Color(0xFF2563EB);
    return const Color(0xFFEF4444);
  }

  Color _statusColor(String s) {
    if (s == 'pending') return const Color(0xFFFACC15);
    if (s == 'approved') return const Color(0xFF22C55E);
    if (s == 'paid') return const Color(0xFF60A5FA);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final pending = allRefunds.where((r) => (r['status'] ?? 'pending') == 'pending').length;
    final approved = allRefunds.where((r) => r['status'] == 'approved').length;
    final paid = allRefunds.where((r) => r['status'] == 'paid').length;
    final rejected = allRefunds.where((r) => r['status'] == 'rejected').length;
    // TOTAL = sum of 20% refunds ONLY, never total booking value
    final total = allRefunds.fold<double>(0, (sum, r) => sum + _refundAmountOf(r));
    final autoDue = allRefunds.where((r) => _mustRefund(r) && (r['status'] ?? 'pending') != 'paid' && (r['status'] ?? 'pending') != 'rejected').fold<double>(0, (s, r) => s + _refundAmountOf(r));
    final list = filtered;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0A1C),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CEO DASHBOARD — REFUND MANAGEMENT', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            Text('● LIVE — 20% ONLY — Nurse Rejects = Refund, Client Cancels = CEO Keeps', style: TextStyle(fontSize: 10, color: Color(0xFFFACC15))),
          ],
        ),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton.icon(onPressed: _loadRefunds, icon: const Icon(Icons.refresh, color: Colors.white, size: 16), label: const Text('Refresh', style: TextStyle(color: Colors.white, fontSize: 11))),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: TextButton(onPressed: () => Navigator.pushNamed(context, '/ceo-dashboard'), style: TextButton.styleFrom(backgroundColor: const Color(0xFF22C55E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))), child: const Text('CEO Home', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            // STATS - same as HTML + AUTO DUE
            Row(
              children: [
                _stat('$pending', 'PENDING', const Color(0xFFFACC15)),
                _stat('$approved', 'APPROVED', const Color(0xFF22C55E)),
                _stat('$paid', 'PAID', const Color(0xFF60A5FA)),
                _stat('$rejected', 'REJECTED', const Color(0xFFEF4444)),
                _stat('GHS ${total.toStringAsFixed(0)}', 'TOTAL REFUND\n20% ONLY', Colors.white),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4))),
              child: Text(
                'AUTO REFUND DUE: GHS ${autoDue.toStringAsFixed(2)} - Nurse rejected bookings. You MUST refund these 20% to clients. Client cancelled = NO refund, CEO keeps 20%.',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            // INFO + FILTER + SEARCH
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF59E0B).withOpacity(0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Refund Requests — 20% ONLY — Auto + Manual — Real-time', style: TextStyle(fontSize: 13, color: Color(0xFFFACC15), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('Nurse rejects = AUTO refund FULL 20% appears here, CEO cannot Reject it. Client cancels before start = NO refund, CEO keeps 20%. Client cancels after start = NO refund, CEO keeps 20% + client pays nurse cash for days worked. Refund amount is CEO fee ONLY, never total, never nurse cash.', style: TextStyle(fontSize: 10, color: Color(0xFFA78BFA))),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: filterStatus,
                          dropdownColor: const Color(0xFF1C1238),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(filled: true, fillColor: const Color(0xFF0E0A1C).withOpacity(0.6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.purple.withOpacity(0.2))), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                          items: const [DropdownMenuItem(value: 'all', child: Text('All Status')), DropdownMenuItem(value: 'pending', child: Text('Pending')), DropdownMenuItem(value: 'approved', child: Text('Approved')), DropdownMenuItem(value: 'paid', child: Text('Paid')), DropdownMenuItem(value: 'rejected', child: Text('Rejected')), DropdownMenuItem(value: 'auto_due', child: Text('Auto Refund Due - Nurse Rejected')), DropdownMenuItem(value: 'no_refund', child: Text('No Refund - CEO Keeps 20%'))],
                          onChanged: (v) => setState(() => filterStatus = v ?? 'all'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          onChanged: (v) => setState(() => searchQ = v),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(hintText: 'Search: client name, phone, booking ID, nurse...', hintStyle: const TextStyle(color: Colors.white54, fontSize: 11), filled: true, fillColor: const Color(0xFF0E0A1C).withOpacity(0.6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.purple.withOpacity(0.2))), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('${list.length} refund requests shown — ${allRefunds.length} total — Filter: $filterStatus — Search: ${searchQ.isEmpty ? 'none' : searchQ} — Each shows Client Photo Name Phone Email + Patient + Nurse + Paystack Ref + Time', style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (isLoading) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFFFACC15))),
            if (!isLoading && list.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)),
                child: const Column(children: [Text('💰', style: TextStyle(fontSize: 44)), SizedBox(height: 8), Text('No refund requests yet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), SizedBox(height: 4), Text('Nurse rejects = AUTO refund appears here. Client cancels = NO refund, CEO keeps 20%.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11))]),
              ),
            // LIST - same as HTML list.innerHTML map + 20/80 breakdown
            ...list.map((r) {
              final status = (r['status'] ?? 'pending').toString();
              final clientName = (r['clientName'] ?? '').toString();
              final nurseName = (r['nurseName'] ?? '').toString();
              final clientPhoto = (r['clientPhotoUrl'] ?? r['clientPhoto'] ?? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(clientName.isEmpty ? 'Client' : clientName)}&background=facc15&color=000').toString();
              final nursePhoto = (r['nursePhotoUrl'] ?? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(nurseName.isEmpty ? 'Nurse' : nurseName)}&background=22c55e&color=fff').toString();
              final clientPhone = (r['clientPhone'] ?? '').toString();
              final nursePhone = (r['nursePhone'] ?? '').toString();
              final clientPhoneClean = _cleanPhone(clientPhone);
              final nursePhoneClean = _cleanPhone(nursePhone);
              final waText = Uri.encodeComponent('Hello $clientName your refund ${r['refundId']} for booking ${r['bookingId']} is $status — CEO LOVE CARE GLOBAL');
              final refundAmt = _refundAmountOf(r);
              final totalAmt = _totalOf(r);
              final nurseCash = _nurseCashOf(r);
              final isAuto = r['isAutoRefund'] == true;
              final ruleLabel = _refundRuleLabel(r);
              final mustRefund = _mustRefund(r);
              final mustNot = _mustNotRefund(r);

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20), border: Border.all(color: _cardBorder(status), width: 2)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: Client avatar + name + status
                    Row(
                      children: [
                        CircleAvatar(radius: 24, backgroundImage: NetworkImage(clientPhoto), backgroundColor: const Color(0xFF1E1A3A)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(clientName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('${r['bookingId'] ?? ''} • ${_timeAgo(r['createdAt'])}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: _statusColor(status).withOpacity(0.15), borderRadius: BorderRadius.circular(999)), child: Text(status.toUpperCase(), style: TextStyle(color: _statusColor(status), fontSize: 10, fontWeight: FontWeight.bold))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // RULE BADGE - 20/80
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: mustRefund ? Colors.red.withOpacity(0.15) : mustNot ? Colors.orange.withOpacity(0.15) : Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: mustRefund ? Colors.red.withOpacity(0.4) : mustNot ? Colors.orange.withOpacity(0.4) : Colors.white24)),
                      child: Text(
                        (isAuto ? '🤖 AUTO - ' : '') + ruleLabel,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: mustRefund ? Colors.redAccent : mustNot ? Colors.orangeAccent : Colors.white),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // MONEY BREAKDOWN - 20/80
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFF0E0A1C).withOpacity(0.6), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total Booking: GHS ${totalAmt.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                          Text('CEO Kept (20%): GHS ${_ceoFeeOf(r).toStringAsFixed(2)} - This is what you refund', style: const TextStyle(fontSize: 11, color: Color(0xFFFACC15), fontWeight: FontWeight.bold)),
                          Text('Nurse Cash (80%): GHS ${nurseCash.toStringAsFixed(2)} - Client pays nurse CASH, NOT CEO', style: const TextStyle(fontSize: 11, color: Color(0xFF86EFAC))),
                          Text('REFUND DUE: GHS ${refundAmt.toStringAsFixed(2)} (20% ONLY)', style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // CLIENT + NURSE - 2 columns
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: const Color(0xFF0E0A1C).withOpacity(0.6), borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('👤 CLIENT — Photo Name Phone Email Saved', style: TextStyle(fontSize: 11, color: Color(0xFFFACC15), fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Row(children: [CircleAvatar(radius: 24, backgroundImage: NetworkImage(clientPhoto)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(clientName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), Text('📞 $clientPhone', style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11)), Text('📧 ${r['clientEmail'] ?? ''}', style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11))]))]),
                                const SizedBox(height: 6),
                                Text('LatLng: ${r['clientLat'] ?? ''}, ${r['clientLng'] ?? ''} • PhotoURL: ${(r['clientPhotoUrl'] ?? '').toString().isNotEmpty ? 'YES' : 'NO'}', style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: const Color(0xFF0E0A1C).withOpacity(0.6), borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('👩‍⚕️ NURSE — Who Rejected / No-Show', style: TextStyle(fontSize: 11, color: Color(0xFF22C55E), fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Row(children: [CircleAvatar(radius: 22, backgroundImage: NetworkImage(nursePhoto)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(nurseName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), Text('📞 $nursePhone', style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11)), Text('ID: ${r['nurseId'] ?? ''}', style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11))]))]),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // PATIENT + BOOKING + REFUND
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFF0E0A1C).withOpacity(0.6), borderRadius: BorderRadius.circular(12)),
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(fontSize: 11, color: Color(0xFFC4B5FD), height: 1.6),
                          children: [
                            const TextSpan(text: '🏥 PATIENT: ', style: TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold)),
                            TextSpan(text: '${r['patientName'] ?? ''} • 📞 ${r['patientPhone'] ?? ''} • 📍 ${r['patientLocation'] ?? ''}${(r['patientLat'] ?? '').toString().isNotEmpty ? ' • LatLng: ${r['patientLat']}, ${r['patientLng']}' : ''}\n'),
                            const TextSpan(text: '📅 BOOKING: ', style: TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold)),
                            TextSpan(text: '${r['bookingId']} • Status: ${r['bookingStatus'] ?? ''} • PayRef: ${r['paystackRef'] ?? ''} • Time: ${_dateStr(r['bookingTime'] ?? r['createdAt'])}\n'),
                            const TextSpan(text: '💰 REFUND: ', style: TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold)),
                            TextSpan(text: 'Amount: GHS ${refundAmt.toStringAsFixed(2)} (20% ONLY, Total was GHS ${totalAmt.toStringAsFixed(2)}) • Reason: ${r['reason']} • Details: ${r['details']}\n'),
                            const TextSpan(text: '📲 DESTINATION: ', style: TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold)),
                            TextSpan(text: '${r['destination'] ?? ''} • Method: ${r['method'] ?? ''}\n'),
                            TextSpan(text: 'BookingKey: ${r['bookingKey'] ?? ''} • RefundID: ${r['refundId']}', style: const TextStyle(color: Color(0xFFA78BFA))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ACTION BUTTONS - 4 in a row, wrap on mobile
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _btn('✅ Approve Refund', const Color(0xFF22C55E), Colors.white, () => _updateStatus(r, 'approved')),
                        _btn('💳 Mark as PAID — Paystack Done', const Color(0xFF2563EB), Colors.white, () => _updateStatus(r, 'paid')),
                        _btn('❌ Reject Refund', const Color(0xFFEF4444), Colors.white, () => _updateStatus(r, 'rejected')),
                        _btn('⏳ Set Pending', const Color(0xFFFB923C), Colors.white, () => _updateStatus(r, 'pending')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _btn('📞 Call Client — ${clientPhone.length >= 9 ? clientPhone.substring(clientPhone.length - 9) : clientPhone}', Colors.white.withOpacity(0.08), const Color(0xFFD8B4FE), () => _launch('tel:$clientPhoneClean')),
                        _btn('💬 WhatsApp Client', const Color(0xFF25D366), Colors.white, () => _launch('https://wa.me/${clientPhoneClean.replaceAll('+', '')}?text=$waText')),
                        _btn('💳 Open Paystack Dashboard', const Color(0xFF2563EB), Colors.white, () => _launch('https://dashboard.paystack.com/')),
                        _btn('📞 Call Nurse', Colors.white.withOpacity(0.08), const Color(0xFFD8B4FE), () => _launch('tel:$nursePhoneClean')),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF0E0A1C).withOpacity(0.6), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.purple.withOpacity(0.15))),
        child: Column(children: [Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)), const SizedBox(height: 2), Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFA78BFA)))]),
      ),
    );
  }

  Widget _btn(String label, Color bg, Color fg, VoidCallback onTap) {
    return SizedBox(
      width: 160,
      child: ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: fg, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
    );
  }
}
