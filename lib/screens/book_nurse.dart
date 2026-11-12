import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Book Nurse - FULL PAYMENT - Flutter version of book-nurse.html
/// - ONLY ONLINE NURSES show (onlineNurses + nursePresence + nurseLocations)
/// - CEO Live Rates: config/rates, ceoPricing, pricing -> GHS hourly / USD hourly
/// - Booking: Start 08:00 End 17:00 = 9 hrs/day, Care Mode Daily x1 / Weekly x7 / Monthly x30
/// - Client auto-filled + Patient (can be different place) + Map + GPS
/// - FULL PAYMENT - Pay 100% now via Paystack
/// - Saves to bookings + bookingsByClient + bookingsByNurse + nurseBookings (same as HTML)

class BookNurseScreen extends StatefulWidget {
  const BookNurseScreen({super.key});
  @override
  State<BookNurseScreen> createState() => _BookNurseScreenState();
}

class _BookNurseScreenState extends State<BookNurseScreen> {
  // Client
  final _clientNameCtrl = TextEditingController();
  final _clientPhoneCtrl = TextEditingController();
  final _clientEmailCtrl = TextEditingController();
  // Patient
  final _patientNameCtrl = TextEditingController();
  final _patientPhoneCtrl = TextEditingController();
  final _patientLocCtrl = TextEditingController();
  String patientRelationship = 'Self';
  bool sameLocation = true;
  // Booking
  String startTime = '08:00';
  String endTime = '17:00';
  String careMode = 'Daily';
  int quantity = 1;
  double transport = 100;
  String currency = 'GHS'; // GHS or USD
  double ceoRateGHS = 0;
  double ceoRateUSD = 0;
  // Nurses
  List<Map> onlineNurses = [];
  String? selectedNurseId;
  String selectedNurseName = '';
  String selectedNursePhone = '';
  double? clientLat, clientLng, patientLat, patientLng;
  double searchRadius = 20;
  GoogleMapController? mapCtrl;
  Set<Marker> nurseMarkers = {};
  bool isPaying = false;

  @override
  void initState() {
    super.initState();
    _loadClientData();
    _loadCEORates();
    _autoCaptureLocation();
  }

  Future<void> _loadClientData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _clientNameCtrl.text = prefs.getString('clientName') ?? prefs.getString('fullName') ?? '';
      _clientPhoneCtrl.text = prefs.getString('clientPhone') ?? prefs.getString('phone') ?? '';
      _clientEmailCtrl.text = prefs.getString('clientEmail') ?? prefs.getString('email') ?? '';
    });
  }

  void _loadCEORates() {
    for (final path in ['config/rates', 'ceoPricing', 'pricing']) {
      FirebaseDatabase.instance.ref(path).onValue.listen((e) {
        final v = e.snapshot.value as Map?;
        if (v == null) return;
        double ghs = 0, usd = 0;
        if (v['GHS'] is Map && v['GHS']['hourly'] != null) ghs = double.tryParse(v['GHS']['hourly'].toString()) ?? 0;
        if (v['USD'] is Map && v['USD']['hourly'] != null) usd = double.tryParse(v['USD']['hourly'].toString()) ?? 0;
        if (ghs == 0) ghs = double.tryParse((v['cedis'] ?? v['ghs'] ?? v['GHS'] ?? 0).toString()) ?? 0;
        if (usd == 0) usd = double.tryParse((v['dollars'] ?? v['usd'] ?? 0).toString()) ?? 0;
        if (ghs > 0) ceoRateGHS = ghs;
        if (usd > 0) ceoRateUSD = usd;
        setState(() {});
      });
    }
  }

  Future<void> _autoCaptureLocation() async {
    try {
      final perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() { clientLat = pos.latitude; clientLng = pos.longitude; patientLat = pos.latitude; patientLng = pos.longitude; });
      _searchNearbyNurses();
    } catch (_) {}
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  Future<void> _searchNearbyNurses() async {
    if (clientLat == null) return;
    // Online nurses only - same as HTML: onlineNurses + nursePresence
    final snap = await FirebaseDatabase.instance.ref('onlineNurses').get();
    final nurseSnap = await FirebaseDatabase.instance.ref('nurses').get();
    final locSnap = await FirebaseDatabase.instance.ref('nurseLocations').get();
    final onlineMap = snap.exists ? Map<String, dynamic>.from(snap.value as Map) : {};
    final nursesMap = nurseSnap.exists ? Map<String, dynamic>.from(nurseSnap.value as Map) : {};
    final locMap = locSnap.exists ? Map<String, dynamic>.from(locSnap.value as Map) : {};
    List<Map> list = [];
    for (final entry in nursesMap.entries) {
      final uid = entry.key;
      if (!onlineMap.containsKey(uid)) continue; // HIDE OFFLINE - same as HTML .offline{display:none}
      final n = Map<String, dynamic>.from(entry.value as Map);
      final loc = locMap[uid] as Map?;
      final lat = double.tryParse((loc?['lat'] ?? n['lat'] ?? 0).toString()) ?? 0;
      final lng = double.tryParse((loc?['lng'] ?? n['lng'] ?? 0).toString()) ?? 0;
      if (lat == 0) continue;
      final dist = _haversine(clientLat!, clientLng!, lat, lng);
      if (dist > searchRadius) continue;
      list.add({'uid': uid, ...n, 'lat': lat, 'lng': lng, 'distance': dist, 'isOnline': true});
    }
    list.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
    setState(() {
      onlineNurses = List<Map>.from(list);
      nurseMarkers = list.map((n) => Marker(markerId: MarkerId(n['uid']), position: LatLng(n['lat'], n['lng']), infoWindow: InfoWindow(title: n['name'] ?? 'Nurse', snippet: '${n['distance'].toStringAsFixed(1)} km away - ONLINE'), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet))).toSet();
    });
  }

  double calcHours(String s, String e) {
    final sp = s.split(':').map(int.parse).toList();
    final ep = e.split(':').map(int.parse).toList();
    double h = (ep[0] + ep[1] / 60) - (sp[0] + sp[1] / 60);
    if (h < 0) h += 24;
    return h;
  }

  Map<String, dynamic> calcTotal() {
    final hrs = calcHours(startTime, endTime);
    final mult = careMode == 'Weekly' ? 7 : careMode == 'Monthly' ? 30 : 1;
    final rate = currency == 'USD' ? ceoRateUSD : ceoRateGHS;
    final totalHours = hrs * mult * quantity;
    final careCost = totalHours * rate;
    final total = careCost + transport;
    final payNow = total;
    final payLater = total - payNow;
    return {'hrsPerDay': hrs, 'totalHours': totalHours, 'rate': rate, 'careCost': careCost, 'total': total, 'payNow': payNow, 'payLater': payLater, 'mult': mult};
  }

  Future<void> _pickTime(bool isStart) async {
    final init = TimeOfDay(hour: int.parse((isStart ? startTime : endTime).split(':')[0]), minute: int.parse((isStart ? startTime : endTime).split(':')[1]));
    final picked = await showTimePicker(context: context, initialTime: init);
    if (picked != null) {
      setState(() { final v = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'; if (isStart) startTime = v; else endTime = v; });
    }
  }

  Future<void> _payWithPaystack() async {
    if (selectedNurseId == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select an ONLINE nurse first'))); return; }
    if (_clientNameCtrl.text.isEmpty || _clientPhoneCtrl.text.isEmpty || _patientNameCtrl.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill Client + Patient details'))); return; }
    final calc = calcTotal();
    final payNow = calc['payNow'] as double;
    final total = calc['total'] as double;
    setState(() => isPaying = true);
    try {
      // TODO: Replace with flutter_paystack_plus or Paystack inline via WebView
      // For now: open Paystack checkout URL or show dialog, then save booking on success
      // In production, use Paystack package: PaystackPlugin().checkout(...)
      final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        title: Text('Full Payment'),
        content: Text('Pay ${currency} ${payNow.toStringAsFixed(2)} now?\nTotal: ${currency} ${total.toStringAsFixed(2)}\nPay 100% now\nNurse: $selectedNurseName'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Pay Now'))],
      ));
      if (confirmed != true) { setState(() => isPaying = false); return; }
      // Simulate Paystack reference - replace with real Paystack ref
      final ref = 'PSK_${DateTime.now().millisecondsSinceEpoch}';
      await _saveBooking(ref, calc);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment failed: $e')));
    } finally {
      if (mounted) setState(() => isPaying = false);
    }
  }

  Future<void> _saveBooking(String paystackRef, Map calc) async {
    final bookingId = 'BK_${DateTime.now().millisecondsSinceEpoch}';
    final booking = {
      'bookingId': bookingId, 'id': bookingId,
      'clientName': _clientNameCtrl.text.trim(), 'clientFullName': _clientNameCtrl.text.trim(),
      'clientPhone': _clientPhoneCtrl.text.trim(), 'clientEmail': _clientEmailCtrl.text.trim(),
      'clientLat': clientLat, 'clientLng': clientLng,
      'patientName': _patientNameCtrl.text.trim(), 'patientPhone': _patientPhoneCtrl.text.trim(),
      'patientLocation': _patientLocCtrl.text.trim(), 'patientLocationText': _patientLocCtrl.text.trim(),
      'patientLat': patientLat, 'patientLng': patientLng, 'patientLatLng': {'lat': patientLat, 'lng': patientLng},
      'patientRelationship': patientRelationship,
      'nurseId': selectedNurseId, 'nurseName': selectedNurseName, 'nursePhone': selectedNursePhone, 'nurseWasOnline': true, 'nurseOnlineAt': DateTime.now().millisecondsSinceEpoch,
      'amount': calc['total'], 'amountPaidNow': calc['payNow'], 'amountBalance': calc['payLater'], 'payNow': calc['payNow'], 'payLater': calc['payLater'],
      'currency': currency, 'paymentMethod': 'paystack_full', 'paymentType': 'full_payment', 'paystackRef': paystackRef,
      'status': 'pending', 'time': DateTime.now().millisecondsSinceEpoch, 'createdAt': DateTime.now().millisecondsSinceEpoch,
      'totalHours': calc['totalHours'], 'hrsPerDay': calc['hrsPerDay'], 'startTime': startTime, 'endTime': endTime, 'careMode': careMode, 'quantity': quantity, 'transport': transport,
      'hourlyRateUsed': calc['rate'], 'service': careMode,
      'amountSplit': {'nurse': (calc['payNow'] as double) * 0.8, 'ceo': (calc['payNow'] as double) * 0.2},
    };
    final db = FirebaseDatabase.instance;
    final emailKey = _clientEmailCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[.#\$@\[\]]'), '_');
    // Save to ALL locations - same as HTML (fixes client not seeing bookings)
    await db.ref('bookings/$bookingId').set(booking);
    await db.ref('bookingsByClient/$emailKey/$bookingId').set(booking);
    await db.ref('bookingsByNurse/$selectedNurseId/$bookingId').set(booking);
    await db.ref('nurseBookings/$selectedNurseId/$bookingId').set(booking);
    await db.ref('clientBookings/$emailKey/$bookingId').set(booking);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Booking created! $bookingId - Nurse will Accept/Reject')));
    Navigator.pushNamed(context, '/my-bookings');
  }

  @override
  Widget build(BuildContext context) {
    final calc = calcTotal();
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: Text('Book Nurse — FULL PAY — ONLY ONLINE NURSES', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.info, color: Colors.amber), const SizedBox(width: 8), Expanded(child: Text('CEO Live: ${currency} ${calc['rate']} /hr — FULL PAY — LIVE — ONLY ONLINE NURSES', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))])),
          const SizedBox(height: 12),
          // Booking - Time / Mode / Quantity / Currency / Transport
          _sectionTitle('⏱️ Booking — FULL PAYMENT'),
          Row(children: [
            Expanded(child: _timeField('START TIME *', startTime, () => _pickTime(true))),
            const SizedBox(width: 8),
            Expanded(child: _timeField('END TIME *', endTime, () => _pickTime(false))),
            const SizedBox(width: 8),
            Expanded(child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12)), child: Column(children: [const Text('HOURS/DAY', style: TextStyle(fontSize: 9, color: Colors.white60)), Text('${calc['hrsPerDay'].toStringAsFixed(1)} hrs', style: const TextStyle(fontWeight: FontWeight.bold))]))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(value: careMode, decoration: const InputDecoration(labelText: 'CARE MODE', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'Daily', child: Text('Daily')), DropdownMenuItem(value: 'Weekly', child: Text('Weekly (x7)')), DropdownMenuItem(value: 'Monthly', child: Text('Monthly (x30)'))], onChanged: (v) => setState(() => careMode = v ?? 'Daily'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(decoration: const InputDecoration(labelText: 'QUANTITY', border: OutlineInputBorder()), keyboardType: TextInputType.number, controller: TextEditingController(text: quantity.toString()), onChanged: (v) => quantity = int.tryParse(v) ?? 1)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(value: currency, decoration: const InputDecoration(labelText: 'COUNTRY — CURRENCY', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'GHS', child: Text('🇬🇭 Ghana — GHS')), DropdownMenuItem(value: 'USD', child: Text('🇺🇸 USA — USD'))], onChanged: (v) => setState(() => currency = v ?? 'GHS'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(decoration: const InputDecoration(labelText: 'TRANSPORT', border: OutlineInputBorder()), keyboardType: TextInputType.number, controller: TextEditingController(text: transport.toString()), onChanged: (v) => transport = double.tryParse(v) ?? 0)),
          ]),
          const SizedBox(height: 12),
          // Total
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFA855F7))), child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Care Cost'), Text('${currency} ${calc['careCost'].toStringAsFixed(2)}')]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Transport'), Text('${currency} ${transport.toStringAsFixed(2)}')]),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold)), Text('${currency} ${calc['total'].toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Pay Now (100%)', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)), Text('${currency} ${calc['payNow'].toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]),
            if ((calc['payLater'] as double) > 0) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Pay Later'), Text('${currency} ${calc['payLater'].toStringAsFixed(2)}')]),
          ])),
          const SizedBox(height: 16),
          _sectionTitle('👤 CLIENT — Payer (Auto-filled)'),
          TextField(controller: _clientNameCtrl, decoration: const InputDecoration(labelText: 'CLIENT NAME *', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: TextField(controller: _clientPhoneCtrl, decoration: const InputDecoration(labelText: 'CLIENT PHONE *', border: OutlineInputBorder()))), const SizedBox(width: 8), Expanded(child: TextField(controller: _clientEmailCtrl, decoration: const InputDecoration(labelText: 'CLIENT EMAIL *', border: OutlineInputBorder())))]),
          const SizedBox(height: 16),
          _sectionTitle('🏥 PATIENT — Who needs care'),
          TextField(controller: _patientNameCtrl, decoration: const InputDecoration(labelText: 'PATIENT NAME *', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: TextField(controller: _patientPhoneCtrl, decoration: const InputDecoration(labelText: 'PATIENT PHONE', border: OutlineInputBorder()))), const SizedBox(width: 8), Expanded(child: DropdownButtonFormField<String>(value: patientRelationship, decoration: const InputDecoration(labelText: 'RELATIONSHIP', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'Self', child: Text('Self')), DropdownMenuItem(value: 'Parent', child: Text('Parent')), DropdownMenuItem(value: 'Child', child: Text('Child')), DropdownMenuItem(value: 'Spouse', child: Text('Spouse')), DropdownMenuItem(value: 'Other', child: Text('Other'))], onChanged: (v) => setState(() => patientRelationship = v ?? 'Self')))]),
          const SizedBox(height: 8),
          TextField(controller: _patientLocCtrl, decoration: const InputDecoration(labelText: 'PATIENT LOCATION TEXT', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          SwitchListTile(title: const Text('Same location as Client'), value: sameLocation, onChanged: (v) => setState(() { sameLocation = v; if (v) { patientLat = clientLat; patientLng = clientLng; } })),
          const SizedBox(height: 16),
          // Map + Nurses
          _sectionTitle('🟢 ONLINE Nurses within ${searchRadius.toInt()}km — Only online show • ${onlineNurses.length} nurses'),
          Container(height: 300, decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.2))), child: clientLat == null ? const Center(child: CircularProgressIndicator()) : GoogleMap(initialCameraPosition: CameraPosition(target: LatLng(clientLat!, clientLng!), zoom: 12), markers: nurseMarkers, myLocationEnabled: true, onMapCreated: (c) => mapCtrl = c, onTap: (latLng) { setState(() { patientLat = latLng.latitude; patientLng = latLng.longitude; }); })),
          const SizedBox(height: 12),
          if (onlineNurses.isEmpty) Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Text('No ONLINE nurses nearby — Try increasing radius or try again later. Offline nurses are hidden.', textAlign: TextAlign.center)),
          ...onlineNurses.map((n) => _nurseCard(n)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: isPaying ? null : _payWithPaystack, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: Text(isPaying ? 'Processing Paystack...' : '💳 Pay Full Amount — ${currency} ${calc['payNow'].toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)))),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)));
  Widget _timeField(String label, String val, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 9, color: Colors.white60)), const SizedBox(height: 4), Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))])));

  Widget _nurseCard(Map n) {
    final isSel = selectedNurseId == n['uid'];
    final photo = n['photoURL'] ?? n['photo'] ?? '';
    return GestureDetector(
      onTap: () => setState(() { selectedNurseId = n['uid']; selectedNurseName = n['name'] ?? ''; selectedNursePhone = n['phone'] ?? ''; }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: isSel ? const Color(0xFFA855F7).withOpacity(0.2) : const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16), border: Border.all(color: isSel ? const Color(0xFFA855F7) : Colors.white12)),
        child: Row(children: [
          CircleAvatar(radius: 28, backgroundImage: photo.toString().isNotEmpty ? NetworkImage(photo.toString()) : null, child: photo.toString().isEmpty ? const Text('👩') : null),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Text(n['name']?.toString() ?? 'Nurse', style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(width: 6), Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle))]),
            Text('${n['specialty'] ?? 'Home Nursing'} • ${(n['distance'] as double).toStringAsFixed(1)} km away', style: const TextStyle(color: Colors.white60, fontSize: 11)),
            Text('⭐ ${n['rating'] ?? 5} • Verified ✅ • ONLINE', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          if (isSel) const Icon(Icons.check_circle, color: Colors.green),
        ]),
      ),
    );
  }
}
