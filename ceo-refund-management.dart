import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';

/// CEO Refund Management - Flutter version of ceo-refund-management.html
/// - Loads: refundRequests + allRefundRequests merged by key (allRefundRequests overwrites same key — Object.assign(merged, snap1) then Object.assign(merged, snap2)), sorted createdAt desc — same as HTML loadRefunds()
///   Uses anonymous auth in HTML (ensureAuth: signInAnonymously) — Flutter: FirebaseAuth.instance.signInAnonymously() if not signed in (add firebase_auth to pubspec)
/// - Realtime: onValue refundRequests + onValue allRefundRequests (merge new refundIds only) + refresh every 20s — same as HTML startRealtime() + setInterval(loadRefunds, 20000)
/// - Filter: filterStatus (all / pending / approved / paid / rejected) + search (clientName + clientPhone + clientEmail + bookingId + nurseName + patientName) — same as HTML renderRefunds()
/// - Stats: Pending, Approved, Paid, Rejected (counts by status), TOTAL GHS (sum parseFloat(amount)) — "GHS {total}" — same as HTML renderRefunds() stats
///   countInfo: "{filtered} refund requests shown — {total} total — Filter: {filter} — Search: {search||none} — Each shows Client Photo Name Phone Email + Patient + Nurse + Paystack Ref + Time"
/// - Card: cardClass pendingCard (yellow border) / approvedCard (green) / paidCard (blue) / rejectedCard (red) — same as HTML
///   Header: "{refundId} — {bookingId}", "{STATUS} — {reason}", "{timeAgo} • {createdAtStr} • GHS {amount} • {currency||GHS} • Method: {method} • Destination: {destination}", badge STATUS
///   timeAgo: <1m "Just now", <60m "{m}m ago", <24h "{h}h ago", else "{d}d ago" — same as HTML
///   CLIENT — Photo Name Phone Email: clientPhotoUrl || clientPhoto || ui-avatars (name, facc15, 000), clientName, 📞 clientPhone, 📧 clientEmail, "LatLng: {clientLat}, {clientLng} • PhotoURL: YES — {first 30}... / NO"
///   NURSE — Who Rejected / No-Show: nursePhotoUrl || ui-avatars (name, 22c55e, fff), nurseName, 📞 nursePhone, ID: nurseId
///   PATIENT: {patientName} • 📞 {patientPhone} • 📍 {patientLocation} • LatLng: {patientLat}, {patientLng}
///   BOOKING: {bookingId} • Status: {bookingStatus} • PayRef: {paystackRef} • Time: bookingTime||createdAt (en-GH)
///   REFUND: Amount: GHS {amount} • Reason: {reason} • Details: {details}
///   DESTINATION: {destination} • Method: {method}
///   BookingKey: {bookingKey} • RefundID: {refundId}
/// - Actions — same as HTML updateRefundStatus(refundId, bookingKey, newStatus):
///   Confirm "Set refund {refundId} to {STATUS}?"
///   Update refundRequests/{refundId} {status, updatedAt, updatedAtStr} + allRefundRequests/{refundId} {status, updatedAt} + if bookingKey: bookings/{bookingKey} {refundStatus, refundUpdatedAt}
///   Update local + render, toast "✅ Refund {refundId} set to {status}"
///   Buttons: ✅ Approve Refund (approved) | 💳 Mark as PAID — Paystack Done (paid) | ❌ Reject Refund (rejected) | ⏳ Set Pending (pending)
/// - Contact buttons — same as HTML:
///   📞 Call Client — {phone last 9} (tel: clientPhoneClean) | 💬 WhatsApp Client (https://wa.me/{phone without +}?text=Hello {clientName} your refund {refundId} for booking {bookingId} is {status} — CEO LOVE CARE GLOBAL) |
///   💳 Open Paystack Dashboard (https://dashboard.paystack.com/) | 📞 Call Nurse (tel: nursePhoneClean)
///   Phone clean: (clientPhone||'').replace(/[^0-9+]/g,'') — same as HTML
/// - Empty: "💰 No refund requests yet — When client requests refund in refund-query.html, it appears here with client photo + phone + email + patient + nurse + Paystack ref"
/// - NO alert buttons — only Sound Settings + CEO Home.

class CEORefundManagementScreen extends StatefulWidget {
  const CEORefundManagementScreen({super.key});
  @override
  State<CEORefundManagementScreen> createState() => _CEORefundManagementScreenState();
}

class _CEORefundManagementScreenState extends State<CEORefundManagementScreen> {
  List<Map> allRefunds = [];
  String filterStatus = 'all';
  String search = '';
  Timer? _timer;
  final _searchCtrl = TextEditingController();
  StreamSubscription? _sub1, _sub2;

  @override
  void initState() {
    super.initState();
    _loadRefunds();
    _startRealtime();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _loadRefunds());
  }

  @override
  void dispose() { _timer?.cancel(); _sub1?.cancel(); _sub2?.cancel(); super.dispose(); }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _loadRefunds() async {
    try {
      Map<String, Map> merged = {};
      final snap1 = await FirebaseDatabase.instance.ref('refundRequests').get();
      if (snap1.exists) (snap1.value as Map).forEach((k, v) { if (v is Map) merged[k.toString()] = Map<String, dynamic>.from(v); });
      final snap2 = await FirebaseDatabase.instance.ref('allRefundRequests').get();
      if (snap2.exists) (snap2.value as Map).forEach((k, v) { if (v is Map) merged[k.toString()] = Map<String, dynamic>.from(v); });
      final list = merged.values.toList();
      list.sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
      setState(() => allRefunds = list);
    } catch (e) { _toast('Error: $e'); }
  }

  void _startRealtime() {
    _sub1 = FirebaseDatabase.instance.ref('refundRequests').onValue.listen((e) {
      if (!e.snapshot.exists) return;
      final list = (e.snapshot.value as Map).values.map((v) => Map<String, dynamic>.from(v as Map)).toList();
      list.sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
      setState(() => allRefunds = list);
    });
    _sub2 = FirebaseDatabase.instance.ref('allRefundRequests').onValue.listen((e) {
      if (!e.snapshot.exists) return;
      final currentIds = allRefunds.map((r) => r['refundId']).toSet();
      final list = List<Map>.from(allRefunds);
      for (final v in (e.snapshot.value as Map).values) {
        final m = Map<String, dynamic>.from(v as Map);
        if (!currentIds.contains(m['refundId'])) list.add(m);
      }
      list.sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
      setState(() => allRefunds = list);
    });
  }

  List<Map> get filtered {
    var list = List<Map>.from(allRefunds);
    if (filterStatus != 'all') list = list.where((r) => (r['status'] ?? 'pending') == filterStatus).toList();
    if (search.isNotEmpty) list = list.where((r) => '${r['clientName']} ${r['clientPhone']} ${r['clientEmail']} ${r['bookingId']} ${r['nurseName']} ${r['patientName']}'.toLowerCase().contains(search)).toList();
    return list;
  }

  String _timeAgo(dynamic createdAt) {
    final d = DateTime.now().millisecondsSinceEpoch - ((createdAt ?? DateTime.now().millisecondsSinceEpoch) as num).toInt();
    final m = (d / 60000).floor();
    if (m < 1) return 'Just now';
    if (m < 60) return '${m}m ago';
    final h = (m / 60).floor();
    if (h < 24) return '${h}h ago';
    return '${(h / 24).floor()}d ago';
  }

  String _cleanPhone(String? p) => (p ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
  String _avatarUrl(String? photo, String name, String bg, String fg) => (photo ?? '').isNotEmpty ? photo! : 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=$bg&color=$fg';

  Future<void> _updateRefundStatus(Map r, String newStatus) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Set refund ${r['refundId']} to ${newStatus.toUpperCase()}?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm'))]));
    if (confirm != true) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await FirebaseDatabase.instance.ref('refundRequests/${r['refundId']}').update({'status': newStatus, 'updatedAt': now, 'updatedAtStr': DateTime.now().toString()});
      await FirebaseDatabase.instance.ref('allRefundRequests/${r['refundId']}').update({'status': newStatus, 'updatedAt': now});
      if ((r['bookingKey'] ?? '').toString().isNotEmpty) await FirebaseDatabase.instance.ref('bookings/${r['bookingKey']}').update({'refundStatus': newStatus, 'refundUpdatedAt': now});
      setState(() { final idx = allRefunds.indexWhere((x) => x['refundId'] == r['refundId']); if (idx > -1) allRefunds[idx]['status'] = newStatus; });
      _toast('✅ Refund ${r['refundId']} set to $newStatus');
    } catch (e) { _toast('❌ Error: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    final pending = allRefunds.where((r) => r['status'] == 'pending').length;
    final approved = allRefunds.where((r) => r['status'] == 'approved').length;
    final paid = allRefunds.where((r) => r['status'] == 'paid').length;
    final rejected = allRefunds.where((r) => r['status'] == 'rejected').length;
    final total = allRefunds.fold<double>(0, (s, r) => s + (double.tryParse(r['amount'].toString()) ?? 0));
    final list = filtered;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('CEO DASHBOARD — REFUND MANAGEMENT', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1C1238), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRefunds), IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings')), TextButton(onPressed: () => Navigator.pushNamed(context, '/ceo-dashboard'), child: const Text('CEO Home', style: TextStyle(color: Colors.white, fontSize: 11)))], bottom: const PreferredSize(preferredSize: Size.fromHeight(18), child: Padding(padding: EdgeInsets.only(bottom: 6), child: Text('● LIVE — Client Photo Phone Email + Patient + Nurse', style: TextStyle(fontSize: 10, color: Color(0xFFFACC15))))))),
      body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(children: [
        Row(children: [_stat('$pending', 'PENDING', const Color(0xFFFACC15)), _stat('$approved', 'APPROVED', const Color(0xFF22C55E)), _stat('$paid', 'PAID', const Color(0xFF60A5FA)), _stat('$rejected', 'REJECTED', const Color(0xFFEF4444)), _stat('GHS ${total.toStringAsFixed(0)}', 'TOTAL GHS', Colors.white)]),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.08), border: Border.all(color: Colors.orange.withOpacity(0.2)), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('💰 Refund Requests from Clients — Reflects from refund-query.html — Real-time', style: TextStyle(fontSize: 13, color: Color(0xFFFACC15), fontWeight: FontWeight.bold)),
          const Text('When client submits refund in refund-query.html, it saves to Firebase refundRequests + allRefundRequests + bookings/{id}/refundRequested — This CEO page shows them LIVE with Client Photo + Name + Phone + Email + Patient + Nurse + Time for you to Approve / Pay via Paystack', style: TextStyle(fontSize: 10, color: Color(0xFFA78BFA))),
          const SizedBox(height: 10),
          Row(children: [
            SizedBox(width: 180, child: DropdownButton<String>(value: filterStatus, isExpanded: true, items: const [DropdownMenuItem(value: 'all', child: Text('All Status')), DropdownMenuItem(value: 'pending', child: Text('Pending')), DropdownMenuItem(value: 'approved', child: Text('Approved')), DropdownMenuItem(value: 'paid', child: Text('Paid')), DropdownMenuItem(value: 'rejected', child: Text('Rejected'))], onChanged: (v) => setState(() => filterStatus = v ?? 'all'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _searchCtrl, decoration: const InputDecoration(hintText: 'Search: client name, phone, booking ID, nurse...', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), onChanged: (v) => setState(() => search = v.toLowerCase()))),
          ]),
          const SizedBox(height: 8),
          Text('${list.length} refund requests shown — ${allRefunds.length} total — Filter: $filterStatus — Search: ${search.isEmpty ? 'none' : search} — Each shows Client Photo Name Phone Email + Patient + Nurse + Paystack Ref + Time', style: const TextStyle(fontSize: 10, color: Colors.white60)),
        ])),
        const SizedBox(height: 12),
        if (list.isEmpty) Container(padding: const EdgeInsets.all(30), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: const Column(children: [Text('💰', style: TextStyle(fontSize: 44)), Text('No refund requests yet', style: TextStyle(fontWeight: FontWeight.bold)), Text('When client requests refund in refund-query.html, it appears here with client photo + phone + email + patient + nurse + Paystack ref', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11))])),
        ...list.map((r) {
          final status = (r['status'] ?? 'pending').toString();
          final statusColor = status == 'pending' ? const Color(0xFFFACC15) : status == 'approved' ? const Color(0xFF22C55E) : status == 'paid' ? const Color(0xFF60A5FA) : const Color(0xFFEF4444);
          final clientPhoto = _avatarUrl((r['clientPhotoUrl'] ?? r['clientPhoto'])?.toString(), (r['clientName'] ?? 'Client').toString(), 'facc15', '000');
          final nursePhoto = _avatarUrl(r['nursePhotoUrl']?.toString(), (r['nurseName'] ?? 'Nurse').toString(), '22c55e', 'fff');
          final clientPhoneClean = _cleanPhone(r['clientPhone']?.toString());
          final nursePhoneClean = _cleanPhone(r['nursePhone']?.toString());
          return Container(margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20), border: Border.all(color: statusColor, width: 2)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 24, backgroundImage: NetworkImage(clientPhoto)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['refundId']} — ${r['bookingId']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Text('${status.toUpperCase()} — ${r['reason'] ?? ''}', style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold)),
                Text('${_timeAgo(r['createdAt'])} • ${r['createdAtStr'] ?? ''} • GHS ${r['amount'] ?? 0} • ${r['currency'] ?? 'GHS'} • Method: ${r['method'] ?? ''} • Destination: ${r['destination'] ?? ''}', style: const TextStyle(fontSize: 10, color: Color(0xFFA78BFA))),
              ])),
              Chip(label: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, color: status == 'pending' ? const Color(0xFF1E0A3A) : Colors.white)), backgroundColor: statusColor),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('👤 CLIENT — Photo Name Phone Email Saved', style: TextStyle(fontSize: 11, color: Color(0xFFFACC15), fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(children: [CircleAvatar(backgroundImage: NetworkImage(clientPhoto)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r['clientName'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), Text('📞 ${r['clientPhone'] ?? ''}', style: const TextStyle(fontSize: 11, color: Color(0xFF86EFAC))), Text('📧 ${r['clientEmail'] ?? ''}', style: const TextStyle(fontSize: 11, color: Color(0xFFA78BFA)))]))]),
                Text('LatLng: ${r['clientLat'] ?? ''}, ${r['clientLng'] ?? ''} • PhotoURL: ${(r['clientPhotoUrl'] ?? '').toString().isNotEmpty ? 'YES — ${(r['clientPhotoUrl'] as String).substring(0, (r['clientPhotoUrl'] as String).length > 30 ? 30 : (r['clientPhotoUrl'] as String).length)}...' : 'NO'}', style: const TextStyle(fontSize: 10, color: Colors.white60)),
              ]))),
              const SizedBox(width: 10),
              Expanded(child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('👩‍⚕️ NURSE — Who Rejected / No-Show', style: TextStyle(fontSize: 11, color: Color(0xFF22C55E), fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(children: [CircleAvatar(backgroundImage: NetworkImage(nursePhoto)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r['nurseName'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), Text('📞 ${r['nursePhone'] ?? ''}', style: const TextStyle(fontSize: 11, color: Color(0xFF86EFAC))), Text('ID: ${r['nurseId'] ?? ''}', style: const TextStyle(fontSize: 11, color: Color(0xFFA78BFA)))]))]),
              ]))),
            ]),
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)), child: Text('🏥 PATIENT: ${r['patientName'] ?? ''} • 📞 ${r['patientPhone'] ?? ''} • 📍 ${r['patientLocation'] ?? ''}${r['patientLat'] != null ? ' • LatLng: ${r['patientLat']}, ${r['patientLng']}' : ''}\n📅 BOOKING: ${r['bookingId']} • Status: ${r['bookingStatus'] ?? ''} • PayRef: ${r['paystackRef'] ?? ''} • Time: ${r['bookingTime'] != null ? DateTime.fromMillisecondsSinceEpoch((r['bookingTime'] as num).toInt()) : (r['createdAt'] != null ? DateTime.fromMillisecondsSinceEpoch((r['createdAt'] as num).toInt()) : '')}\n💰 REFUND: Amount: GHS ${r['amount']} • Reason: ${r['reason']} • Details: ${r['details']}\n📲 DESTINATION: ${r['destination'] ?? ''} • Method: ${r['method'] ?? ''}\nBookingKey: ${r['bookingKey'] ?? ''} • RefundID: ${r['refundId']}', style: const TextStyle(fontSize: 11, color: Color(0xFFC4B5FD)))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)), onPressed: () => _updateRefundStatus(r, 'approved'), child: const Text('✅ Approve Refund', style: TextStyle(fontSize: 11)))),
              const SizedBox(width: 6),
              Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)), onPressed: () => _updateRefundStatus(r, 'paid'), child: const Text('💳 Mark as PAID — Paystack Done', style: TextStyle(fontSize: 11)))),
              const SizedBox(width: 6),
              Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)), onPressed: () => _updateRefundStatus(r, 'rejected'), child: const Text('❌ Reject Refund', style: TextStyle(fontSize: 11)))),
              const SizedBox(width: 6),
              Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFB923C)), onPressed: () => _updateRefundStatus(r, 'pending'), child: const Text('⏳ Set Pending', style: TextStyle(fontSize: 11)))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => launchUrl(Uri.parse('tel:$clientPhoneClean')), child: Text('📞 Call Client — ${(r['clientPhone'] ?? '').toString().length >= 9 ? (r['clientPhone'] as String).substring((r['clientPhone'] as String).length - 9) : r['clientPhone'] ?? ''}', style: const TextStyle(fontSize: 10)))),
              const SizedBox(width: 6),
              Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)), onPressed: () => launchUrl(Uri.parse('https://wa.me/${clientPhoneClean.replaceAll('+', '')}?text=${Uri.encodeComponent('Hello ${r['clientName'] ?? ''} your refund ${r['refundId']} for booking ${r['bookingId']} is $status — CEO LOVE CARE GLOBAL')}'), mode: LaunchMode.externalApplication), child: const Text('💬 WhatsApp Client', style: TextStyle(fontSize: 10)))),
              const SizedBox(width: 6),
              Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)), onPressed: () => launchUrl(Uri.parse('https://dashboard.paystack.com/'), mode: LaunchMode.externalApplication), child: const Text('💳 Open Paystack Dashboard', style: TextStyle(fontSize: 10)))),
              const SizedBox(width: 6),
              Expanded(child: OutlinedButton(onPressed: () => launchUrl(Uri.parse('tel:$nursePhoneClean')), child: const Text('📞 Call Nurse', style: TextStyle(fontSize: 10)))),
            ]),
          ]));
        }).toList(),
      ])),
    );
  }

  Widget _stat(String value, String label, Color color) => Expanded(child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.purple.withOpacity(0.15))), child: Column(children: [Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)), Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFA78BFA)))])));
}
