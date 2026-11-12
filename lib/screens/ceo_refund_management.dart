import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';

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

  // Same as HTML loadRefunds() - merge refundRequests + allRefundRequests
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
    } catch (e) {
      _toast('Error: $e');
    }
    if (mounted) setState(() => isLoading = false);
  }

  // Same as HTML startRealtime() - onValue for both paths
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

  // Same as HTML renderRefunds() filter + search
  List<Map<String, dynamic>> get filtered {
    var list = List<Map<String, dynamic>>.from(allRefunds);
    if (filterStatus != 'all') list = list.where((r) => (r['status'] ?? 'pending').toString() == filterStatus).toList();
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

  // Same as HTML updateRefundStatus() - writes to 3 places
  Future<void> _updateStatus(Map<String, dynamic> r, String newStatus) async {
    final refundId = (r['refundId'] ?? '').toString();
    final bookingKey = (r['bookingKey'] ?? '').toString();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1238),
        title: Text('Set refund $refundId to ${newStatus.toUpperCase()}?', style: const TextStyle(color: Colors.white, fontSize: 14)),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes'))],
      ),
    );
    if (confirm != true) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.child('refundRequests/$refundId').update({'status': newStatus, 'updatedAt': now, 'updatedAtStr': DateTime.now().toString()});
      await _db.child('allRefundRequests/$refundId').update({'status': newStatus, 'updatedAt': now});
      if (bookingKey.isNotEmpty) {
        await _db.child('bookings/$bookingKey').update({'refundStatus': newStatus, 'refundUpdatedAt': now});
      }
      final idx = allRefunds.indexWhere((x) => (x['refundId'] ?? '').toString() == refundId);
      if (idx != -1) setState(() => allRefunds[idx]['status'] = newStatus);
      _toast('✅ Refund $refundId set to $newStatus');
    } catch (e) {
      _toast('❌ Error: $e');
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
    final total = allRefunds.fold<double>(0, (sum, r) => sum + (double.tryParse('${r['amount'] ?? 0}') ?? 0));
    final list = filtered;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0A1C),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CEO DASHBOARD — REFUND MANAGEMENT', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            Text('● LIVE — Client Photo Phone Email + Patient + Nurse', style: TextStyle(fontSize: 10, color: Color(0xFFFACC15))),
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
            // STATS - same as HTML
            Row(
              children: [
                _stat('$pending', 'PENDING', const Color(0xFFFACC15)),
                _stat('$approved', 'APPROVED', const Color(0xFF22C55E)),
                _stat('$paid', 'PAID', const Color(0xFF60A5FA)),
                _stat('$rejected', 'REJECTED', const Color(0xFFEF4444)),
                _stat('GHS ${total.toStringAsFixed(0)}', 'TOTAL GHS', Colors.white),
              ],
            ),
            const SizedBox(height: 12),
            // INFO + FILTER + SEARCH
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF59E0B).withOpacity(0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💰 Refund Requests from Clients — Reflects from refund-query.html — Real-time', style: TextStyle(fontSize: 13, color: Color(0xFFFACC15), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('When client submits refund in refund-query.html, it saves to Firebase refundRequests + allRefundRequests + bookings/{id}/refundRequested — This CEO page shows them LIVE with Client Photo + Name + Phone + Email + Patient + Nurse + Time for you to Approve / Pay via Paystack', style: TextStyle(fontSize: 10, color: Color(0xFFA78BFA))),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: filterStatus,
                          dropdownColor: const Color(0xFF1C1238),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(filled: true, fillColor: const Color(0xFF0E0A1C).withOpacity(0.6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.purple.withOpacity(0.2))), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                          items: const [DropdownMenuItem(value: 'all', child: Text('All Status')), DropdownMenuItem(value: 'pending', child: Text('Pending')), DropdownMenuItem(value: 'approved', child: Text('Approved')), DropdownMenuItem(value: 'paid', child: Text('Paid')), DropdownMenuItem(value: 'rejected', child: Text('Rejected'))],
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
                child: const Column(children: [Text('💰', style: TextStyle(fontSize: 44)), SizedBox(height: 8), Text('No refund requests yet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), SizedBox(height: 4), Text('When client requests refund in refund-query.html, it appears here with client photo + phone + email + patient + nurse + Paystack ref', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11))]),
              ),
            // LIST - same as HTML list.innerHTML map
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
                            TextSpan(text: 'Amount: GHS ${r['amount']} • Reason: ${r['reason']} • Details: ${r['details']}\n'),
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
