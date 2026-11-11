import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Refund Query - Flutter version of refund-query.html
/// REAL REQUEST FORM - NOT history page. Policy page is refund.html.
/// Flow: Select Booking -> Reason + Details + Amount + Method + Destination -> Submit
/// Saves: refundRequests/{id} + allRefundRequests/{id} + bookings/{id}/refundRequested
/// With: Client Photo Name Phone Email + Patient + Nurse + Booking ID + Amount + Reason + Time
/// Policy: 100% before accept, 50% within 24h after accept, 0% after service starts (100% if nurse no-show)

class RefundQueryScreen extends StatefulWidget {
  const RefundQueryScreen({super.key});
  @override
  State<RefundQueryScreen> createState() => _RefundQueryScreenState();
}

class _RefundQueryScreenState extends State<RefundQueryScreen> {
  String clientName = 'ASABERE PETER';
  String clientPhone = '+233502957280';
  String clientEmail = 'lovecareglobal@gmail.com';
  String clientPhoto = '';
  Map<String, Map> allBookings = {};
  String? selectedBookingId;
  Map? selectedBooking;
  List<Map> refundHistory = [];
  String refundReason = '';
  String refundMethod = 'momo';
  final _detailsCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _destinationCtrl = TextEditingController();
  String status = '';
  bool isStatusOk = true;
  bool isSubmitting = false;

  final List<Map<String, String>> reasons = [
    {'value': 'nurse_rejected', 'label': '❌ Nurse Rejected My Booking — Need Refund'},
    {'value': 'nurse_no_show', 'label': '🚫 Nurse Did Not Show Up — No Service'},
    {'value': 'cancelled_before_accept', 'label': '⏳ I Cancelled Before Nurse Accepted — 100% Refund'},
    {'value': 'cancelled_within_24h', 'label': '⏰ Cancelled Within 24h After Acceptance — 50% Refund'},
    {'value': 'double_payment', 'label': '💳 Double Payment / Wrong Amount'},
    {'value': 'increase_rate', 'label': '💰 Want to Increase Rate — Refund old, book new'},
    {'value': 'other', 'label': '📝 Other Reason'},
  ];

  @override
  void initState() {
    super.initState();
    _loadClientAndBookings();
    _loadRefundHistory();
  }

  Future<void> _loadClientAndBookings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      clientPhone = prefs.getString('clientPhone') ?? prefs.getString('phone') ?? '+233502957280';
      clientName = prefs.getString('clientName') ?? prefs.getString('fullName') ?? 'ASABERE PETER';
      clientEmail = prefs.getString('clientEmail') ?? prefs.getString('email') ?? 'lovecareglobal@gmail.com';
      clientPhoto = prefs.getString('clientPhotoUrl') ?? prefs.getString('clientPhoto') ?? prefs.getString('photoUrl') ?? '';
    });
    try {
      final snap = await FirebaseDatabase.instance.ref('bookings').get();
      final snap2 = await FirebaseDatabase.instance.ref('allBookings').get();
      Map<String, dynamic> bookings = {};
      if (snap.exists) bookings.addAll(Map<String, dynamic>.from(snap.value as Map));
      if (snap2.exists) bookings.addAll(Map<String, dynamic>.from(snap2.value as Map));
      final myPhoneDigits = clientPhone.replaceAll(RegExp(r'[^0-9]'), '');
      Map<String, Map> filtered = {};
      bookings.forEach((id, val) {
        final b = Map<String, dynamic>.from(val as Map);
        final bPhone = (b['clientPhone'] ?? b['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
        final phoneMatch = bPhone.isNotEmpty && myPhoneDigits.isNotEmpty && (bPhone == myPhoneDigits || (bPhone.length >= 9 && myPhoneDigits.length >= 9 && bPhone.substring(bPhone.length - 9) == myPhoneDigits.substring(myPhoneDigits.length - 9)));
        final emailMatch = b['clientEmail'] != null && clientEmail.isNotEmpty && b['clientEmail'].toString().toLowerCase() == clientEmail.toLowerCase();
        if (phoneMatch || emailMatch) filtered[id] = b;
      });
      setState(() => allBookings = filtered);
    } catch (e) {
      setState(() => status = 'Error loading bookings: $e');
    }
  }

  void _onBookingSelect(String? id) {
    setState(() {
      selectedBookingId = id;
      selectedBooking = id == null ? null : allBookings[id];
      if (selectedBooking != null) {
        _amountCtrl.text = (selectedBooking!['amount'] ?? 0).toString();
      }
    });
  }

  Future<void> _submitRefund() async {
    if (selectedBookingId == null) { setState(() { status = '❌ Select a booking first!'; isStatusOk = false; }); return; }
    if (refundReason.isEmpty) { setState(() { status = '❌ Select refund reason!'; isStatusOk = false; }); return; }
    if (_detailsCtrl.text.trim().isEmpty) { setState(() { status = '❌ Explain details!'; isStatusOk = false; }); return; }
    setState(() { status = '⏳ Submitting refund request with client photo name phone email + patient + nurse...'; isStatusOk = true; isSubmitting = true; });
    try {
      final b = selectedBooking!;
      final refundId = 'RFD_${DateTime.now().millisecondsSinceEpoch}_$selectedBookingId';
      final refundData = {
        'refundId': refundId,
        'bookingId': b['bookingId'] ?? selectedBookingId,
        'bookingKey': selectedBookingId,
        'status': 'pending',
        'reason': refundReason,
        'details': _detailsCtrl.text.trim(),
        'amount': double.tryParse(_amountCtrl.text.trim()) ?? (b['amount'] ?? 0),
        'currency': b['currency'] ?? 'GHS',
        'method': refundMethod,
        'destination': _destinationCtrl.text.trim(),
        'clientName': b['clientName'] ?? clientName,
        'clientPhone': b['clientPhone'] ?? b['phone'] ?? clientPhone,
        'clientEmail': b['clientEmail'] ?? clientEmail,
        'clientPhotoUrl': b['clientPhotoUrl'] ?? b['clientPhoto'] ?? clientPhoto,
        'clientPhoto': b['clientPhotoUrl'] ?? clientPhoto,
        'patientName': b['patientName'] ?? '',
        'patientPhone': b['patientPhone'] ?? '',
        'patientLocation': b['patientLocation'] ?? '',
        'patientLat': b['patientLat'],
        'patientLng': b['patientLng'],
        'nurseName': b['nurseName'] ?? '',
        'nursePhone': b['nursePhone'] ?? '',
        'nursePhotoUrl': b['nursePhotoUrl'] ?? '',
        'nurseId': b['nurseId'] ?? '',
        'paystackRef': b['paystackRef'] ?? '',
        'bookingStatus': b['status'] ?? '',
        'bookingTime': b['time'] ?? DateTime.now().millisecondsSinceEpoch,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'createdAtStr': DateTime.now().toString(),
        'clientLat': b['clientLat'],
        'clientLng': b['clientLng'],
      };
      await FirebaseDatabase.instance.ref('refundRequests/$refundId').set(refundData);
      await FirebaseDatabase.instance.ref('bookings/$selectedBookingId').update({'refundRequested': true, 'refundId': refundId, 'refundReason': refundReason, 'refundStatus': 'pending', 'refundRequestedAt': DateTime.now().millisecondsSinceEpoch});
      await FirebaseDatabase.instance.ref('allRefundRequests/$refundId').set(refundData);
      setState(() {
        status = '✅ Refund request submitted! ID: $refundId\nClient: $clientName • Phone: $clientPhone • Email: $clientEmail • Photo: ${clientPhoto.isNotEmpty ? 'YES' : 'NO'}\nBooking: ${b['bookingId'] ?? selectedBookingId} • Amount: GHS ${_amountCtrl.text} • Reason: $refundReason\nCEO will process via Paystack within 3-5 days. Check history below + alerts.';
        isStatusOk = true;
        _detailsCtrl.clear();
      });
      _loadRefundHistory();
    } catch (e) {
      setState(() { status = '❌ Error: $e'; isStatusOk = false; });
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  Future<void> _loadRefundHistory() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('refundRequests').get();
      if (!snap.exists) { setState(() => refundHistory = []); return; }
      final all = snap.value as Map;
      final myPhoneDigits = clientPhone.replaceAll(RegExp(r'[^0-9]'), '');
      List<Map> mine = [];
      all.forEach((k, val) {
        final r = Map<String, dynamic>.from(val as Map);
        final bPhone = (r['clientPhone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
        if (bPhone.isNotEmpty && myPhoneDigits.isNotEmpty && bPhone.length >= 9 && myPhoneDigits.length >= 9 && bPhone.substring(bPhone.length - 9) == myPhoneDigits.substring(myPhoneDigits.length - 9)) {
          mine.add(r);
        }
      });
      mine.sort((a, b) => (b['createdAt'] as num).compareTo(a['createdAt'] as num));
      setState(() => refundHistory = mine);
    } catch (_) {}
  }

  Future<void> _openWhatsApp() async {
    final url = Uri.parse('https://wa.me/233544121814?text=Hello%20CEO%20I%20want%20refund%20for%20booking%20${selectedBookingId ?? ''}');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Color _statusColor(String s) {
    if (s == 'approved' || s == 'paid') return Colors.green;
    if (s == 'rejected') return Colors.red;
    return Colors.amber;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(
        title: const Text('Refund Request', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1633),
        actions: [TextButton(onPressed: () {}, child: const Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Client Card
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFFB923C).withOpacity(0.08), borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFFB923C).withOpacity(0.2))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('💰 Request Refund — Client Photo Name Phone Email Saved', style: TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 10),
            Row(children: [
              CircleAvatar(radius: 24, backgroundImage: clientPhoto.isNotEmpty ? NetworkImage(clientPhoto) : null, child: clientPhoto.isEmpty ? Text(clientName.isNotEmpty ? clientName[0] : 'C') : null),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(clientName, style: const TextStyle(fontWeight: FontWeight.bold)), Text(clientPhone, style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11)), Text(clientEmail, style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 10))])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFFACC15).withOpacity(0.15), borderRadius: BorderRadius.circular(20)), child: const Text('YOU', style: TextStyle(fontSize: 9, color: Color(0xFFFDE68A)))),
            ]),
            const SizedBox(height: 8),
            Text('${allBookings.length} bookings found for $clientName • $clientPhone • Photo: ${clientPhoto.isNotEmpty ? 'YES' : 'NO'} — Select one to request refund', style: const TextStyle(color: Colors.grey, fontSize: 10)),
          ])),
          const SizedBox(height: 12),
          // Booking Select
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(22)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📅 Select Booking to Refund', style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('Choose booking that was rejected or nurse didn\'t show. Refund policy: 100% before accept, 50% within 24h after accept, 0% after service starts (100% if nurse no-show).', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(value: selectedBookingId, decoration: const InputDecoration(labelText: 'Your Bookings (Rejected / Accepted / Pending)', border: OutlineInputBorder()), items: allBookings.entries.map((e) {
              final b = e.value;
              return DropdownMenuItem(value: e.key, child: Text('${b['bookingId'] ?? e.key} • ${b['status'] ?? 'pending'} • ${b['nurseName'] ?? 'Nurse'} • ${b['currency'] ?? 'GHS'} ${b['amount'] ?? 0}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis));
            }).toList(), onChanged: _onBookingSelect, hint: const Text('— Select Booking for Refund —')),
            if (selectedBooking != null) ...[
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${selectedBooking!['bookingId'] ?? selectedBookingId} — ${selectedBooking!['status'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                Text('Nurse: ${selectedBooking!['nurseName'] ?? ''} • ${selectedBooking!['nursePhone'] ?? ''}', style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11)),
                Text('Patient: ${selectedBooking!['patientName'] ?? ''} • ${selectedBooking!['patientLocation'] ?? ''} • Amount: ${selectedBooking!['currency'] ?? 'GHS'} ${selectedBooking!['amount'] ?? 0}', style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11)),
                Text('PayRef: ${selectedBooking!['paystackRef'] ?? ''}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
              ])),
            ],
          ])),
          const SizedBox(height: 12),
          // Refund Form
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFFACC15), width: 2)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📝 Refund Request Form — Where Client Requests Refund', style: TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold, fontSize: 14)),
            const Text('This is NOT history! This is where you REQUEST refund. Fill form + submit. CEO will process via Paystack.', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11)),
            const SizedBox(height: 12),
            const Text('REFUND REASON *', style: TextStyle(color: Color(0xFFFACC15), fontSize: 11, fontWeight: FontWeight.bold)),
            DropdownButtonFormField<String>(value: refundReason.isEmpty ? null : refundReason, decoration: const InputDecoration(border: OutlineInputBorder()), items: reasons.map((r) => DropdownMenuItem(value: r['value'], child: Text(r['label']!, style: const TextStyle(fontSize: 12)))).toList(), onChanged: (v) => setState(() => refundReason = v ?? ''), hint: const Text('— Select Reason —')),
            const SizedBox(height: 12),
            const Text('DETAILS *', style: TextStyle(color: Color(0xFFFACC15), fontSize: 11, fontWeight: FontWeight.bold)),
            TextField(controller: _detailsCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Explain what happened...', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            const Text('REFUND AMOUNT', style: TextStyle(color: Color(0xFFFACC15), fontSize: 11, fontWeight: FontWeight.bold)),
            TextField(controller: _amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 12),
            const Text('REFUND METHOD', style: TextStyle(color: Color(0xFFFACC15), fontSize: 11, fontWeight: FontWeight.bold)),
            DropdownButtonFormField<String>(value: refundMethod, decoration: const InputDecoration(border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'momo', child: Text('📱 MoMo — Ghana (MTN/Vodafone/Airtel)')), DropdownMenuItem(value: 'card', child: Text('💳 Card — Outside Ghana')), DropdownMenuItem(value: 'paystack_original', child: Text('↩️ Original Paystack Method'))], onChanged: (v) => setState(() => refundMethod = v ?? 'momo')),
            const SizedBox(height: 12),
            const Text('MoMo Number / Card Details for Refund', style: TextStyle(color: Color(0xFFFACC15), fontSize: 11, fontWeight: FontWeight.bold)),
            TextField(controller: _destinationCtrl, decoration: const InputDecoration(hintText: 'E.g. MTN MoMo: 024XXXXXXX or Card ending', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            if (status.isNotEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isStatusOk ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Text(status, style: TextStyle(color: isStatusOk ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5), fontSize: 11))),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: isSubmitting ? null : _submitRefund, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(isSubmitting ? 'Submitting...' : '💰 Submit Refund Request — With Client Photo Name Phone Email', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: ElevatedButton.icon(onPressed: _openWhatsApp, icon: const Icon(Icons.chat), label: const Text('WhatsApp CEO', style: TextStyle(fontSize: 11)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.notifications), label: const Text('Go to Alerts', style: TextStyle(fontSize: 11)))),
            ]),
          ])),
          const SizedBox(height: 12),
          // History
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(22)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📜 Your Refund Requests History', style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('Shows all refunds you requested with status: pending / approved / rejected / paid', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11)),
            const SizedBox(height: 10),
            if (refundHistory.isEmpty) const Text('No refund requests yet — Submit form above', style: TextStyle(color: Colors.grey)),
            ...refundHistory.map((r) => Container(
              margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14), border: Border.all(color: _statusColor(r['status'].toString()).withOpacity(0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Expanded(child: Text('${r['refundId']} — ${r['bookingId']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12))), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: _statusColor(r['status'].toString()), borderRadius: BorderRadius.circular(20)), child: Text(r['status'].toString().toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))]),
                const SizedBox(height: 6),
                Text('Reason: ${r['reason']} • Amount: ${r['currency']} ${r['amount']} • Method: ${r['method']} • ${r['createdAtStr']}', style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11)),
                Text('Client: ${r['clientName']} • ${r['clientPhone']} • ${r['clientEmail']} • Photo: ${r['clientPhotoUrl'] != null && r['clientPhotoUrl'].toString().isNotEmpty ? 'YES' : 'NO'}', style: const TextStyle(color: Colors.white60, fontSize: 10)),
                Text('Patient: ${r['patientName'] ?? ''} • Nurse: ${r['nurseName'] ?? ''} • Details: ${r['details']}', style: const TextStyle(color: Colors.white60, fontSize: 10)),
              ]),
            )),
          ])),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(style: BorderStyle.solid, color: const Color(0xFFA855F7).withOpacity(0.2))), child: const Text('How Refund Request Works (Not History!):\n1. Client selects booking (Rejected / No-show / Cancelled)\n2. Client fills reason + amount + MoMo/card + details\n3. Submit → Saves to refundRequests/{id} + bookings/{id}/refundRequested\n4. CEO sees in CEO Dashboard → Processes via Paystack → Updates: approved / paid\n5. Client sees status here + gets alert\n6. WhatsApp CEO button for quick follow-up', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 10))),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
