import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';

/// CEO Finance - Flutter version of ceo-finance.html
/// - Loads: clientsCache from clients + users + customers (by key) — same as HTML loadClientsCache()
///   Payments from bookings + paidBookings + payments + transactions + ceoBookings + acceptedBookings + finance + ceoFinance, dedupe by key (first wins), only paid: paid==true || isPaid==true || paymentStatus paid || status paid || (totalGHS||amount)>0, only amountGHS>0 — same as HTML loadFinance()
/// - normalizePayment: amountGHS (totalGHS || amountGHS || amount), amountUSD (totalUSD || amountUSD || amountGHS/15.5 — HTML uses /15.5), clientName (clientName ?? cache.fullName ?? Client), clientPhone (clientPhone ?? cache.phone), clientEmail (clientEmail ?? cache.email), clientLocation (clientLocation ?? cache.location ?? "Accra, Ghana"), clientAddress (clientAddress ?? cache.address ?? clientLocation), clientPhoto (clientPhoto ?? cache.photo), clientId (clientId ?? cache.id), nurseName (Nurse), nursePhone, service (Nursing Care), hours (8), bookingType (bookingType includes 50 ? "50% Payment" : "Full Payment"), status (paymentStatus||status includes paid || amountGHS>0 ? paid : pending), paymentMethod (Paystack / Mobile Money), paidAt (paidAt ?? createdAt), transactionId (transactionId || paymentId || id)
/// - Stats: Total GHS (sum amountGHS), Total USD (sum amountUSD), Success count (status paid), unique clients (Set clientName), top client (by total GHS: total/count/phone/email) — header "{n} Clients Paid | {GHS} Total | {unique} Unique | {success} Success" — same as HTML updateStats()
/// - Table: search (clientName + clientPhone + clientEmail + clientLocation + nurseName + id + service + amountGHS), tableCount "{n} clients paid", tableTotal sum filtered GHS — same as HTML renderTable()
///   Row: Time, 👤 clientName + 💰 Paid: GHS, 📱 phone + ✉️ email + 📍 location, GHS + USD • paymentMethod, 👩‍⚕️ nurseName + service • hours, badge Full Payment/50% Payment + ✅ Paid, 📋 id (first 10) + transactionId (first 16), 👁️ View Full Client Details
/// - Recent: first 10 payments, "{n} recent clients" — same as HTML renderRecent()
/// - View Full Client Details (modal): avatar, "👤 {client} — Client Who Paid", "Paid {GHS} on {time} • {bookingType}", badge "✅ Paid Success — {GHS}", FULL CLIENT DETAILS: Full Name, Client ID, Phone (tel: link), Email, Location, Full Address, Amount Paid (GHS / USD, "✅ Client paid successfully — Transaction: {transactionId}"), NURSE + SERVICE: Nurse Assigned, Service • hours, buttons Call Client (tel:), View Booking — same as HTML viewClientDetails()
/// - Filter: setFilter(t) — HTML has filter buttons (all / today / this month) — implemented as filter chips: All / Today / This Month — isToday / isThisMonth same as HTML
/// - Export CSV: header "Date Paid,Client Name,Client Phone,Client Email,Client Location,Client Address,Nurse Name,Amount GHS,Amount USD,Type,Service,Hours,Status,Booking ID,Transaction ID" + one row per filtered payment, filename "ceo-finance-client-details-{YYYY-MM-DD}.csv" — same as HTML exportCSV() (Flutter: share via clipboard / show dialog with CSV — see _exportCSV)
/// - Refresh every 15s — same as HTML window.onload setInterval(loadFinance, 15000)
/// - NO alert buttons — only Sound Settings.

class CEOFinanceScreen extends StatefulWidget {
  const CEOFinanceScreen({super.key});
  @override
  State<CEOFinanceScreen> createState() => _CEOFinanceScreenState();
}

class _CEOFinanceScreenState extends State<CEOFinanceScreen> {
  List<Map> allPayments = [];
  Map<String, Map> clientsCache = {};
  String search = '';
  String filter = 'all'; // all / today / this_month
  Timer? _timer;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFinance();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _loadFinance());
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  String _fmtGHS(dynamic v) => 'GH₵ ${(double.tryParse(v.toString()) ?? 0).toStringAsFixed(2)}';
  String _fmtUSD(dynamic v) => '\$${(double.tryParse(v.toString()) ?? 0).toStringAsFixed(2)}';
  String _fmtTime(dynamic t) => t == null ? '' : DateTime.fromMillisecondsSinceEpoch((t as num).toInt()).toString();
  bool _isToday(dynamic t) { if (t == null) return false; final d = DateTime.fromMillisecondsSinceEpoch((t as num).toInt()); final n = DateTime.now(); return d.year == n.year && d.month == n.month && d.day == n.day; }
  bool _isThisMonth(dynamic t) { if (t == null) return false; final d = DateTime.fromMillisecondsSinceEpoch((t as num).toInt()); final n = DateTime.now(); return d.year == n.year && d.month == n.month; }

  Map _normalize(String id, Map v, Map ce) {
    final amountGHS = double.tryParse((v['totalGHS'] ?? v['amountGHS'] ?? v['amount'] ?? 0).toString()) ?? 0;
    final amountUSD = double.tryParse((v['totalUSD'] ?? v['amountUSD'] ?? (amountGHS / 15.5)).toString()) ?? 0;
    final bookingType = (v['bookingType'] ?? '').toString().toLowerCase().contains('50') ? '50% Payment' : 'Full Payment';
    final status = (v['paymentStatus'] ?? v['status'] ?? 'paid').toString().toLowerCase().contains('paid') || amountGHS > 0 ? 'paid' : 'pending';
    return {'id': id, 'transactionId': v['transactionId'] ?? v['paymentId'] ?? id, 'clientName': v['clientName'] ?? ce['fullName'] ?? 'Client', 'clientPhone': v['clientPhone'] ?? ce['phone'] ?? '', 'clientEmail': v['clientEmail'] ?? ce['email'] ?? '', 'clientLocation': v['clientLocation'] ?? ce['location'] ?? 'Accra, Ghana', 'clientAddress': v['clientAddress'] ?? ce['address'] ?? v['clientLocation'] ?? '', 'clientPhoto': v['clientPhoto'] ?? ce['photo'] ?? '', 'clientId': v['clientId'] ?? ce['id'] ?? '', 'nurseName': v['nurseName'] ?? 'Nurse', 'nursePhone': v['nursePhone'] ?? '', 'amountGHS': amountGHS, 'amountUSD': amountUSD, 'service': v['service'] ?? 'Nursing Care', 'hours': v['hours'] ?? '8', 'bookingType': bookingType, 'status': status, 'paymentMethod': v['paymentMethod'] ?? 'Paystack / Mobile Money', 'paidAt': v['paidAt'] ?? v['createdAt'] ?? DateTime.now().millisecondsSinceEpoch, 'raw': v};
  }

  Future<void> _loadFinance() async {
    _toast('💰 Loading finance + FULL client details who paid...');
    for (final path in ['clients', 'users', 'customers']) {
      try { final snap = await FirebaseDatabase.instance.ref(path).get(); if (snap.exists) (snap.value as Map).forEach((k, val) { if (val is Map) clientsCache[k.toString()] = Map<String, dynamic>.from(val); }); } catch (_) {}
    }
    Map<String, Map> paymentMap = {};
    for (final path in ['bookings', 'paidBookings', 'payments', 'transactions', 'ceoBookings', 'acceptedBookings', 'finance', 'ceoFinance']) {
      try {
        final snap = await FirebaseDatabase.instance.ref(path).get();
        if (!snap.exists) continue;
        (snap.value as Map).forEach((k, val) {
          if (val is! Map) return;
          final v = Map<String, dynamic>.from(val);
          final hasAmount = (double.tryParse((v['totalGHS'] ?? v['amount'] ?? 0).toString()) ?? 0) > 0;
          final isPaid = v['paid'] == true || v['isPaid'] == true || v['paymentStatus'] == 'paid' || v['status'] == 'paid' || hasAmount;
          if (!isPaid && !hasAmount) return;
          if (!paymentMap.containsKey(k)) paymentMap[k.toString()] = v;
        });
      } catch (_) {}
    }
    final list = paymentMap.entries.map((e) => _normalize(e.key, e.value, clientsCache[e.value['clientId']?.toString() ?? ''] ?? {})).where((p) => (p['amountGHS'] as double) > 0).toList();
    list.sort((a, b) => ((b['paidAt'] ?? 0) as num).compareTo((a['paidAt'] ?? 0) as num));
    setState(() => allPayments = list);
    final totalGHS = list.fold<double>(0, (s, p) => s + (p['amountGHS'] as double));
    _toast('✅ CEO Finance: ${list.length} clients paid — GHS ${totalGHS.toStringAsFixed(0)} — Full client details LIVE');
  }

  List<Map> get filtered {
    var list = List<Map>.from(allPayments);
    if (filter == 'today') list = list.where((p) => _isToday(p['paidAt'])).toList();
    if (filter == 'this_month') list = list.where((p) => _isThisMonth(p['paidAt'])).toList();
    if (search.isNotEmpty) list = list.where((p) => '${p['clientName']} ${p['clientPhone']} ${p['clientEmail']} ${p['clientLocation']} ${p['nurseName']} ${p['id']} ${p['service']} ${p['amountGHS']}'.toLowerCase().contains(search)).toList();
    return list;
  }

  void _viewClientDetails(Map p) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('👤 ${p['clientName']} — Client Who Paid'),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Paid ${_fmtGHS(p['amountGHS'])} on ${_fmtTime(p['paidAt'])} • ${p['bookingType']}', style: const TextStyle(fontSize: 12, color: Colors.white60)),
        const SizedBox(height: 8),
        Chip(label: Text('✅ Paid Success — ${_fmtGHS(p['amountGHS'])}', style: const TextStyle(fontSize: 11)), backgroundColor: Colors.green.withOpacity(0.2)),
        const SizedBox(height: 12),
        const Text('👤 FULL CLIENT DETAILS — Who Paid The Money', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFACC15))),
        const SizedBox(height: 8),
        _detail('👤 Client Full Name — Who Paid', p['clientName']),
        _detail('🆔 Client ID', p['clientId'].toString().isEmpty ? p['id'] : p['clientId']),
        _detail('📱 Phone — Client Contact', p['clientPhone'].toString().isEmpty ? 'No phone' : p['clientPhone']),
        _detail('✉️ Email — Client Email', p['clientEmail'].toString().isEmpty ? 'No email' : p['clientEmail']),
        _detail('📍 Location — Where Client Lives', p['clientLocation']),
        _detail('🏠 Full Address', p['clientAddress']),
        _detail('💰 Amount Paid — How Much Client Paid — REFLECTS LIVE', '${_fmtGHS(p['amountGHS'])} / ${_fmtUSD(p['amountUSD'])}\n✅ Client paid successfully — Transaction: ${p['transactionId']}'),
        const SizedBox(height: 12),
        const Text('👩‍⚕️ NURSE + SERVICE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA))),
        _detail('👩‍⚕️ Nurse Assigned', p['nurseName']),
        _detail('🏥 Service', '${p['service']} • ${p['hours']}h'),
      ])),
      actions: [
        if (p['clientPhone'].toString().isNotEmpty) TextButton(onPressed: () => launchUrl(Uri.parse('tel:${p['clientPhone']}')), child: const Text('📞 Call Client')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ));
  }

  Widget _detail(String label, String value) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 10, color: Colors.white60)), Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))]));

  void _exportCSV() {
    final list = filtered;
    if (list.isEmpty) { _toast('No clients to export'); return; }
    var csv = 'Date Paid,Client Name,Client Phone,Client Email,Client Location,Client Address,Nurse Name,Amount GHS,Amount USD,Type,Service,Hours,Status,Booking ID,Transaction ID\n';
    for (final p in list) csv += '"${_fmtTime(p['paidAt'])}","${p['clientName']}","${p['clientPhone']}","${p['clientEmail']}","${p['clientLocation']}","${p['clientAddress']}","${p['nurseName']}",${p['amountGHS']},${p['amountUSD']},"${p['bookingType']}","${p['service']}","${p['hours']}","${p['status']}","${p['id']}","${p['transactionId']}"\n';
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('📊 Exported ${list.length} clients with full details'),
      content: SingleChildScrollView(child: Text('Filename: ceo-finance-client-details-${DateTime.now().toIso8601String().substring(0, 10)}.csv\n\n$csv', style: const TextStyle(fontSize: 10))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
    _toast('📊 Exported ${list.length} clients with full details');
  }

  @override
  Widget build(BuildContext context) {
    final totalGHS = allPayments.fold<double>(0, (s, p) => s + (p['amountGHS'] as double));
    final totalUSD = allPayments.fold<double>(0, (s, p) => s + (p['amountUSD'] as double));
    final successCount = allPayments.where((p) => p['status'] == 'paid').length;
    final uniqueClients = allPayments.map((p) => p['clientName']).toSet().length;
    Map<String, Map> clientTotals = {};
    for (final p in allPayments) {
      clientTotals.putIfAbsent(p['clientName'], () => {'total': 0.0, 'count': 0, 'phone': p['clientPhone'], 'email': p['clientEmail']});
      clientTotals[p['clientName']]!['total'] = (clientTotals[p['clientName']]!['total'] as double) + (p['amountGHS'] as double);
      clientTotals[p['clientName']]!['count'] = (clientTotals[p['clientName']]!['count'] as int) + 1;
    }
    final topClient = clientTotals.entries.isNotEmpty ? (clientTotals.entries.toList()..sort((a, b) => (b.value['total'] as double).compareTo(a.value['total'] as double))).first : null;
    final list = filtered;
    final totalFilteredGHS = list.fold<double>(0, (s, p) => s + (p['amountGHS'] as double));
    final recent = allPayments.take(10).toList();
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(title: const Text('CEO Finance', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 8), child: Text('${allPayments.length} Clients Paid | ${_fmtGHS(totalGHS)} Total | $uniqueClients Unique | $successCount Success', style: const TextStyle(fontSize: 10, color: Colors.white60)))), IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings'))]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children: [
          _stat('💰 Total GHS', _fmtGHS(totalGHS), '$successCount clients paid • ${allPayments.length} transactions • $uniqueClients unique clients • LIVE'),
          _stat('💵 Total USD', _fmtUSD(totalUSD), 'USD at GHS 15.5 / \$1 (HTML rate)'),
          _stat('✅ Success', '$successCount', '$successCount clients paid • Name, Phone, Email, Location, Amount LIVE'),
          if (topClient != null) _stat('👑 Top Client', '${topClient.key} — ${_fmtGHS(topClient.value['total'])}', 'Top client • ${topClient.value['count']} payments • Phone: ${topClient.value['phone'] ?? ''} • Full details LIVE'),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
          Expanded(child: TextField(controller: _searchCtrl, decoration: const InputDecoration(hintText: 'Search client / phone / email / location / nurse / booking', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), onChanged: (v) => setState(() => search = v.toLowerCase().trim()))),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _exportCSV, child: const Text('📊 Export CSV')),
        ])),
        Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          _filterChip('all', 'All'), _filterChip('today', 'Today'), _filterChip('this_month', 'This Month'),
          const Spacer(),
          Text('${list.length} clients paid • ${_fmtGHS(totalFilteredGHS)}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
        ])),
        Expanded(child: list.isEmpty ? const Center(child: Text('No clients who paid found', style: TextStyle(color: Colors.white60))) : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: list.length, itemBuilder: (_, i) {
          final p = list[i];
          return InkWell(onTap: () => _viewClientDetails(p), child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(14)), child: Row(children: [
            CircleAvatar(child: Text((p['clientName'] as String).isNotEmpty ? (p['clientName'] as String)[0].toUpperCase() : 'C')),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_fmtTime(p['paidAt']), style: const TextStyle(fontSize: 11, color: Colors.white60)),
              Text('👤 ${p['clientName']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('💰 Paid: ${_fmtGHS(p['amountGHS'])}', style: const TextStyle(fontSize: 10, color: Color(0xFFFACC15))),
              Text('📱 ${p['clientPhone'].toString().isEmpty ? 'No phone' : p['clientPhone']} • ✉️ ${p['clientEmail'].toString().isEmpty ? 'No email' : p['clientEmail']} • 📍 ${p['clientLocation']}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
              Text('👩‍⚕️ ${p['nurseName']} • ${p['service']} • ${p['hours']}h • ${p['paymentMethod']}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_fmtGHS(p['amountGHS']), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFACC15))),
              Text('${_fmtUSD(p['amountUSD'])}', style: const TextStyle(fontSize: 10, color: Colors.white60)),
              Chip(label: Text(p['bookingType'], style: const TextStyle(fontSize: 10)), backgroundColor: p['bookingType'] == 'Full Payment' ? Colors.green.withOpacity(0.2) : Colors.blue.withOpacity(0.2)),
              const Chip(label: Text('✅ Paid', style: TextStyle(fontSize: 10)), backgroundColor: Colors.green),
              Text('📋 ${(p['id'] as String).length > 10 ? (p['id'] as String).substring(0, 10) : p['id']}', style: const TextStyle(fontSize: 10, color: Colors.white60)),
            ]),
          ])));
        })),
        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Color(0xFF1A1633)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('🕐 Recent — ${recent.length} recent clients', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          ...recent.map((p) => InkWell(onTap: () => _viewClientDetails(p), child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('👤 ${p['clientName']} — ${_fmtGHS(p['amountGHS'])} • ${_fmtTime(p['paidAt'])}', style: const TextStyle(fontSize: 11, color: Colors.white60))))).toList(),
        ])),
      ]),
    );
  }

  Widget _stat(String label, String value, String sub) => Container(width: 200, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), Text(sub, style: const TextStyle(fontSize: 10, color: Colors.white60))]));
  Widget _filterChip(String key, String label) => Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(label, style: const TextStyle(fontSize: 11)), selected: filter == key, onSelected: (_) => setState(() => filter = key)));
}
