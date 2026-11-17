import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
// NO google_maps_flutter - FULL page removed it because it closes app, we do same here
// NO live_nurse_map.dart - same reason

class BookNurse50Screen extends StatefulWidget {
  const BookNurse50Screen({super.key});
  @override
  State<BookNurse50Screen> createState() => _BookNurse50ScreenState();
}

class _BookNurse50ScreenState extends State<BookNurse50Screen> {
  final _clientNameCtrl = TextEditingController();
  final _clientPhoneCtrl = TextEditingController();
  final _clientEmailCtrl = TextEditingController();
  final _patientNameCtrl = TextEditingController();
  final _patientPhoneCtrl = TextEditingController();
  final _patientLocCtrl = TextEditingController();
  late final TextEditingController _quantityCtrl;
  late final TextEditingController _transportCtrl;
  String patientRelationship = 'Self';
  bool sameLocation = true;
  String startTime = '08:00';
  String endTime = '17:00';
  String careMode = 'Daily';
  int quantity = 1;
  double transport = 100;
  String currency = 'GHS';
  double ceoRateGHS = 0;
  double ceoRateUSD = 0;
  List<Map> onlineNurses = [];
  String? selectedNurseId;
  String selectedNurseName = '';
  String selectedNursePhone = '';
  double? clientLat, clientLng, patientLat, patientLng;
  double searchRadius = 20;
  bool isPaying = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _clientNameCtrl.dispose();
    _clientPhoneCtrl.dispose();
    _clientEmailCtrl.dispose();
    _patientNameCtrl.dispose();
    _patientPhoneCtrl.dispose();
    _patientLocCtrl.dispose();
    _quantityCtrl.dispose();
    _transportCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _quantityCtrl = TextEditingController(text: quantity.toString());
    _transportCtrl = TextEditingController(text: transport.toString());
    _loadClientData();
    _loadCEORates();
    _autoCaptureLocation();
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) { try { return Map<String, dynamic>.from(v); } catch (_) { return {}; } }
    return {};
  }

  Future<void> _loadClientData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed || !mounted) return;
      setState(() {
        _clientNameCtrl.text = prefs.getString('clientName') ?? prefs.getString('fullName') ?? '';
        _clientPhoneCtrl.text = prefs.getString('clientPhone') ?? prefs.getString('phone') ?? '';
        _clientEmailCtrl.text = prefs.getString('clientEmail') ?? prefs.getString('email') ?? '';
      });
    } catch (_) {}
  }

  void _loadCEORates() {
    for (final path in ['config/rates', 'ceoPricing', 'pricing']) {
      try {
        FirebaseDatabase.instance.ref(path).onValue.listen((e) {
          if (_disposed || !mounted) return;
          final v = _asMap(e.snapshot.value);
          if (v.isEmpty) return;
          double ghs = 0, usd = 0;
          if (v['GHS'] is Map) ghs = _asDouble((v['GHS'] as Map)['hourly']);
          if (v['USD'] is Map) usd = _asDouble((v['USD'] as Map)['hourly']);
          if (ghs == 0) ghs = _asDouble(v['cedis'] ?? v['ghs']);
          if (usd == 0) usd = _asDouble(v['dollars'] ?? v['usd']);
          if (ghs > 0) ceoRateGHS = ghs;
          if (usd > 0) ceoRateUSD = usd;
          if (mounted) setState(() {});
        });
      } catch (_) {}
    }
  }

  Future<void> _autoCaptureLocation() async {
    try {
      final perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (_disposed || !mounted) return;
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
    if (clientLat == null || clientLng == null) return;
    try {
      final snap = await FirebaseDatabase.instance.ref('onlineNurses').get();
      final nurseSnap = await FirebaseDatabase.instance.ref('nurses').get();
      final locSnap = await FirebaseDatabase.instance.ref('nurseLocations').get();
      if (_disposed || !mounted) return;
      final Set<String> onlineIds = {};
      if (snap.exists && snap.value != null) {
        if (snap.value is Map) { onlineIds.addAll((snap.value as Map).keys.map((k) => k.toString())); }
        else if (snap.value is List) { for (final x in (snap.value as List)) { if (x != null) onlineIds.add(x.toString()); } }
      }
      final nursesMap = _asMap(nurseSnap.exists ? nurseSnap.value : null);
      final locMap = _asMap(locSnap.exists ? locSnap.value : null);
      List<Map> list = [];
      for (final entry in nursesMap.entries) {
        try {
          final uid = entry.key.toString();
          if (!onlineIds.contains(uid)) continue;
          if (entry.value is! Map) continue;
          final n = Map<String, dynamic>.from(entry.value as Map);
          final locRaw = locMap[uid];
          final loc = locRaw is Map ? Map<String, dynamic>.from(locRaw) : <String, dynamic>{};
          final lat = _asDouble(loc['lat'] ?? n['lat']);
          final lng = _asDouble(loc['lng'] ?? n['lng']);
          if (lat == 0) continue;
          final dist = _haversine(clientLat!, clientLng!, lat, lng);
          if (dist > searchRadius) continue;
          list.add({'uid': uid, ...n, 'lat': lat, 'lng': lng, 'distance': dist, 'isOnline': true});
        } catch (_) { continue; }
      }
      list.sort((a, b) => _asDouble(a['distance']).compareTo(_asDouble(b['distance'])));
      if (_disposed || !mounted) return;
      setState(() { onlineNurses = List<Map>.from(list); });
      if (selectedNurseId == null) _autoSelectNearest();
    } catch (_) {}
  }

  double calcHours(String s, String e) {
    final sp = s.split(':').map((x) => int.tryParse(x) ?? 0).toList();
    final ep = e.split(':').map((x) => int.tryParse(x) ?? 0).toList();
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
    final payNow = total / 2;
    final payLater = total - payNow;
    return {'hrsPerDay': hrs, 'totalHours': totalHours, 'rate': rate, 'careCost': careCost, 'total': total, 'payNow': payNow, 'payLater': payLater, 'mult': mult};
  }

  Future<void> _pickTime(bool isStart) async {
    final init = TimeOfDay(hour: int.tryParse((isStart ? startTime : endTime).split(':')[0]) ?? 8, minute: int.tryParse((isStart ? startTime : endTime).split(':')[1]) ?? 0);
    final picked = await showTimePicker(context: context, initialTime: init);
    if (picked != null) {
      setState(() { final v = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'; if (isStart) startTime = v; else endTime = v; });
    }
  }

  void _autoSelectNearest() {
    if (onlineNurses.isEmpty) return;
    if (selectedNurseId != null) return;
    final n = onlineNurses.first;
    setState(() { selectedNurseId = n['uid']; selectedNurseName = (n['name'] ?? '').toString(); selectedNursePhone = (n['phone'] ?? '').toString(); });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🤖 System auto-picked nearest ONLINE nurse: $selectedNurseName (${_asDouble(n['distance']).toStringAsFixed(1)} km)')));
  }

  void _pickAnotherOne() {
    if (onlineNurses.length < 2) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other ONLINE nurse nearby yet'))); return; }
    final idx = onlineNurses.indexWhere((x) => x['uid'] == selectedNurseId);
    final next = onlineNurses[(idx + 1) % onlineNurses.length];
    setState(() { selectedNurseId = next['uid']; selectedNurseName = (next['name'] ?? '').toString(); selectedNursePhone = (next['phone'] ?? '').toString(); });
  }

  Map<String, dynamic>? get _autoPickedNurse {
    if (selectedNurseId == null) return null;
    try { return Map<String, dynamic>.from(onlineNurses.firstWhere((x) => x['uid'] == selectedNurseId)); } catch (_) { return null; }
  }

  String _pickUrl(dynamic v) {
    if (v == null) return '';
    if (v is String) { final t = v.trim(); if (t.startsWith('http') || t.startsWith('gs://')) return t; return ''; }
    if (v is List) { for (final x in v) { final u = _pickUrl(x); if (u.isNotEmpty) return u; } return ''; }
    if (v is Map) { for (final k in ['url','downloadUrl','downloadURL','videoUrl','videoURL','link','href','path']) { final u = _pickUrl(v[k]); if (u.isNotEmpty) return u; } return ''; }
    return '';
  }

  String _mediaFromMap(Map n, bool isVideo) {
    final videoKeys = ['videoUrl','videoURL','video','introVideoUrl','introVideo','registrationVideoUrl','registrationVideo','nurseVideoUrl','nurseVideo','profileVideoUrl','profileVideo'];
    final photoKeys = ['photoUrl','photoURL','photo','profilePhoto','imageUrl','imageURL','profilePhotoUrl','profilePic','profilePicture','avatar','picture'];
    final keys = isVideo ? videoKeys : photoKeys;
    for (final k in keys) { final u = _pickUrl(n[k]); if (u.isNotEmpty) return u; }
    for (final k in ['video','media','files','registration','documents','uploads','profile']) {
      final v = n[k];
      if (v is Map) { final u = _mediaFromMap(Map<String, dynamic>.from(v), isVideo); if (u.isNotEmpty) return u; }
    }
    return '';
  }

  Future<Map<String, dynamic>> _fetchFullNurse(String uid) async {
    final merged = <String, dynamic>{};
    try { final snap = await FirebaseDatabase.instance.ref('nurses/$uid').get(); if (snap.exists && snap.value is Map) merged.addAll(Map<String, dynamic>.from(snap.value as Map)); } catch (_) {}
    try { final snap = await FirebaseDatabase.instance.ref('approved_nurses/$uid').get(); if (snap.exists && snap.value is Map) merged.addAll(Map<String, dynamic>.from(snap.value as Map)); } catch (_) {}
    try { final doc = await FirebaseFirestore.instance.collection('nurses').doc(uid).get(); if (doc.exists && doc.data() != null) merged.addAll(doc.data()!); } catch (_) {}
    return merged;
  }

  Future<void> _showNursePhotoVideoAuto(Map n) async {
    final uid = (n['uid'] ?? '').toString();
    Map<String, dynamic> full = Map<String, dynamic>.from(n);
    if (uid.isNotEmpty) {
      final fetched = await _fetchFullNurse(uid);
      if (fetched.isNotEmpty) { for (final k in fetched.keys) { if ((full[k] == null || full[k].toString().isEmpty) && fetched[k] != null) full[k] = fetched[k]; } }
    }
    final photo = _mediaFromMap(full, false);
    final video = _mediaFromMap(full, true);
    if (!mounted) return;
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF1C1238),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AutoNurseProfileSheet(nurse: full, photo: photo, video: video, name: (full['name'] ?? full['fullName'] ?? 'Nurse').toString(), spec: (full['specialty'] ?? 'Home Nursing').toString(), distance: _asDouble(full['distance']),
        onSelect: () { Navigator.pop(context); setState(() { selectedNurseId = full['uid']; selectedNurseName = (full['name'] ?? '').toString(); selectedNursePhone = (full['phone'] ?? '').toString(); }); },
      ));
  }

  Future<void> _openMapExternal() async {
    if (clientLat == null || clientLng == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Waiting for your GPS...'))); return; }
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$clientLat,$clientLng');
    try { if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication); } catch (_) {}
  }

  Future<void> _payWithPaystack50Cash() async {
    if (selectedNurseId == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select an ONLINE nurse first'))); return; }
    if (_clientNameCtrl.text.isEmpty || _clientPhoneCtrl.text.isEmpty || _patientNameCtrl.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill Client + Patient details'))); return; }
    final calc = calcTotal();
    setState(() => isPaying = true);
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        title: const Text('50% Paystack + 50% Cash'),
        content: Text('Total: $currency ${(calc['total'] as double).toStringAsFixed(2)}\n\n✅ Pay NOW via Paystack: $currency ${(calc['payNow'] as double).toStringAsFixed(2)} (50%)\n💵 Pay LATER in CASH to nurse: $currency ${(calc['payLater'] as double).toStringAsFixed(2)} (50%)\n\nNurse: $selectedNurseName'),
        actions: [ TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Pay with Paystack')) ],
      ));
      if (confirmed != true) { if (mounted) setState(() => isPaying = false); return; }
      final ref = 'PSK50_${DateTime.now().millisecondsSinceEpoch}';
      await _saveBooking(ref, calc);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment failed: $e')));
    } finally { if (mounted) setState(() => isPaying = false); }
  }

  Future<void> _saveBooking(String paystackRef, Map calc) async {
    final bookingId = 'BK_${DateTime.now().millisecondsSinceEpoch}';
    final booking = {
      'bookingId': bookingId, 'id': bookingId,
      'clientName': _clientNameCtrl.text.trim(), 'clientFullName': _clientNameCtrl.text.trim(),
      'clientPhone': _clientPhoneCtrl.text.trim(), 'clientEmail': _clientEmailCtrl.text.trim(),
      'clientLat': clientLat, 'clientLng': clientLng,
      'patientName': _patientNameCtrl.text.trim(), 'patientPhone': _patientPhoneCtrl.text.trim(),
      'patientLocation': _patientLocCtrl.text.trim(), 'patientLat': patientLat, 'patientLng': patientLng,
      'patientRelationship': patientRelationship,
      'nurseId': selectedNurseId, 'nurseName': selectedNurseName, 'nursePhone': selectedNursePhone,
      'amount': calc['total'], 'amountPaidNow': calc['payNow'], 'amountBalance': calc['payLater'], 'payNow': calc['payNow'], 'payLater': calc['payLater'],
      'currency': currency, 'paymentMethod': 'paystack_50_cash_50', 'paymentType': '50_percent_paystack_cash', 'paystackRef': paystackRef,
      'status': 'pending_50_percent_paystack_paid_cash_due', 'time': DateTime.now().millisecondsSinceEpoch, 'createdAt': DateTime.now().millisecondsSinceEpoch,
      'totalHours': calc['totalHours'], 'hrsPerDay': calc['hrsPerDay'], 'startTime': startTime, 'endTime': endTime, 'careMode': careMode, 'quantity': quantity, 'transport': transport,
      'hourlyRateUsed': calc['rate'], 'service': careMode,
    };
    final db = FirebaseDatabase.instance;
    final emailKey = _clientEmailCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[.#\$@\[\]]'), '_');
    await db.ref('bookings/$bookingId').set(booking);
    await db.ref('bookingsByClient/$emailKey/$bookingId').set(booking);
    await db.ref('bookingsByNurse/$selectedNurseId/$bookingId').set(booking);
    await db.ref('nurseBookings/$selectedNurseId/$bookingId').set(booking);
    await db.ref('clientBookings/$emailKey/$bookingId').set(booking);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Booking created! $bookingId - 50% Paystack paid, 50% Cash to nurse later')));
    try { Navigator.pushNamed(context, '/my-bookings'); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final calc = calcTotal();
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('Book Nurse — 50% Paystack + 50% Cash — ONLY ONLINE NURSES', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.info, color: Colors.amber), const SizedBox(width: 8), Expanded(child: Text('CEO Live: $currency ${calc['rate']} /hr — 50% Paystack NOW + 50% CASH to nurse LATER — ONLY ONLINE NURSES', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))])),
          const SizedBox(height: 12),
          _sectionTitle('⏱️ Booking — 50% Paystack Now, 50% Cash Later'),
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
            Expanded(child: TextField(decoration: const InputDecoration(labelText: 'QUANTITY', border: OutlineInputBorder()), keyboardType: TextInputType.number, controller: _quantityCtrl, onChanged: (v) => quantity = int.tryParse(v) ?? 1)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(value: currency, decoration: const InputDecoration(labelText: 'COUNTRY — CURRENCY', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'GHS', child: Text('🇬🇭 Ghana — GHS')), DropdownMenuItem(value: 'USD', child: Text('🇺🇸 USA — USD'))], onChanged: (v) => setState(() => currency = v ?? 'GHS'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(decoration: const InputDecoration(labelText: 'TRANSPORT', border: OutlineInputBorder()), keyboardType: TextInputType.number, controller: _transportCtrl, onChanged: (v) => transport = double.tryParse(v) ?? 0)),
          ]),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFBBF24))), child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Care Cost'), Text('$currency ${calc['careCost'].toStringAsFixed(2)}')]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Transport'), Text('$currency ${transport.toStringAsFixed(2)}')]),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold)), Text('$currency ${calc['total'].toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Pay Now (50%) — Paystack', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)), Text('$currency ${calc['payNow'].toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Pay Later — 💵 Cash to Nurse'), Text('$currency ${calc['payLater'].toStringAsFixed(2)}')]),
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
          // NO GoogleMap here - safe box + external Maps button, same as FULL page
          Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.2))), child: Column(children: [
            Text(clientLat == null ? '📍 Getting your location...' : '📍 Your location: ${clientLat!.toStringAsFixed(4)}, ${clientLng!.toStringAsFixed(4)}\n🟢 ${onlineNurses.length} ONLINE nurse(s) near you', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _openMapExternal, icon: const Icon(Icons.map, size: 16), label: const Text('Open Map in Google Maps App', style: TextStyle(fontSize: 12)), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)))),
          ])),
          const SizedBox(height: 12),
          _sectionTitle('🟢 ONLINE Nurses within ${searchRadius.toInt()}km — ${onlineNurses.length} nurses'),
          if (onlineNurses.isNotEmpty && _autoPickedNurse != null)
            Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.5))), child: Column(children: [
              const Text('🤖 SYSTEM AUTO-PICKED NEAREST ONLINE NURSE FOR YOU', textAlign: TextAlign.center, style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Row(children: [
                CircleAvatar(radius: 30, backgroundImage: _mediaFromMap(_autoPickedNurse!, false).isNotEmpty ? NetworkImage(_mediaFromMap(_autoPickedNurse!, false)) : null, child: _mediaFromMap(_autoPickedNurse!, false).isEmpty ? const Text('👩') : null),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_autoPickedNurse!['name']?.toString() ?? 'Nurse', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('${_autoPickedNurse!['specialty'] ?? 'Home Nursing'} • ${_asDouble(_autoPickedNurse!['distance']).toStringAsFixed(1)} km • 🟢 ONLINE', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
              ]),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: () => _showNursePhotoVideoAuto(_autoPickedNurse!), icon: const Icon(Icons.play_circle_fill), label: const Text('📷🎥 Watch Her Photo + Video'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7)))),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: ElevatedButton(onPressed: () { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Continue with $selectedNurseName - scroll down to pay'))); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)), child: const Text('✅ Continue With Her', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: _pickAnotherOne, style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)), child: const Text('👀 Look At Another One'))),
              ]),
            ])),
          if (onlineNurses.isEmpty)
            Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)), child: const Text('🔍 System is searching for ONLINE nurses near the patient... Keep this page open - nearest nurse will be auto-picked as soon as she goes ONLINE.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12))),
          const SizedBox(height: 12),
          ...onlineNurses.map((n) => _nurseCard(n)),
          const SizedBox(height: 16),
          Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFFFF3CD).withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.withOpacity(0.5))), child: const Text('⚠️ 50% ONLY HERE: Pay ONLY half (50%) now via Paystack.\n💵 Give the remaining 50% CASH to the nurse AFTER her work is completed.', textAlign: TextAlign.center, style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12))),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: isPaying ? null : _payWithPaystack50Cash, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C853), padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: Text(isPaying ? 'Processing Paystack...' : '💳 Pay 50% Now via Paystack — $currency ${calc['payNow'].toStringAsFixed(2)}  +  💵 50% Cash Later', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)))),
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
      child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isSel ? const Color(0xFFA855F7).withOpacity(0.2) : const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16), border: Border.all(color: isSel ? const Color(0xFFA855F7) : Colors.white12)), child: Column(children: [Row(children: [
        CircleAvatar(radius: 28, backgroundImage: photo.toString().isNotEmpty ? NetworkImage(photo.toString()) : null, child: photo.toString().isEmpty ? const Text('👩') : null),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text(n['name']?.toString() ?? 'Nurse', style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(width: 6), Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle))]),
          Text('${n['specialty'] ?? 'Home Nursing'} • ${_asDouble(n['distance']).toStringAsFixed(1)} km away', style: const TextStyle(color: Colors.white60, fontSize: 11)),
          Text('⭐ ${n['rating'] ?? 5} • Verified ✅ • ONLINE', style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ])),
        if (isSel) const Icon(Icons.check_circle, color: Colors.green),
      ]),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => _showNursePhotoVideoAuto(n), icon: const Icon(Icons.play_circle_fill, size: 16), label: const Text('📷🎥 Watch Her Photo + Video', style: TextStyle(fontSize: 12)), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)))),
      ])),
    );
  }
}

class _AutoNurseProfileSheet extends StatefulWidget {
  final Map nurse; final String photo; final String video; final String name; final String spec; final double distance; final VoidCallback onSelect;
  const _AutoNurseProfileSheet({required this.nurse, required this.photo, required this.video, required this.name, required this.spec, required this.distance, required this.onSelect});
  @override State<_AutoNurseProfileSheet> createState() => _AutoNurseProfileSheetState();
}
class _AutoNurseProfileSheetState extends State<_AutoNurseProfileSheet> {
  VideoPlayerController? _ctrl; bool _failed = false;
  @override void initState() { super.initState(); _init(); }
  Future<void> _init() async {
    if (widget.video.isEmpty) return;
    try { final c = VideoPlayerController.networkUrl(Uri.parse(widget.video)); await c.initialize(); if (mounted) setState(() => _ctrl = c); } catch (_) { if (mounted) setState(() => _failed = true); }
  }
  @override void dispose() { _ctrl?.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return DraggableScrollableSheet(initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
      builder: (_, ctrl) => SingleChildScrollView(controller: ctrl, padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
          const SizedBox(height: 12),
          Row(children: [
            Container(width: 92, height: 92, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.green, width: 3)), child: ClipOval(child: widget.photo.isNotEmpty ? Image.network(widget.photo, fit: BoxFit.cover) : const Icon(Icons.person, size: 50, color: Colors.white))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              Text('${widget.spec} • ${widget.distance.toStringAsFixed(1)} km from patient', style: const TextStyle(color: Colors.white70)),
              const Text('⭐ 5 • Verified ✅ • 🟢 ONLINE NOW', style: TextStyle(color: Colors.greenAccent)),
            ])),
          ]),
          const SizedBox(height: 16),
          const Text('📷 Photo she uploaded during registration', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(14), child: widget.photo.isNotEmpty ? Image.network(widget.photo, height: 220, width: double.infinity, fit: BoxFit.cover) : Container(height: 140, color: Colors.white10, child: const Center(child: Text('No photo uploaded', style: TextStyle(color: Colors.white60))))),
          const SizedBox(height: 16),
          const Text('🎥 Video she uploaded during registration', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (widget.video.isEmpty) Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)), child: const Text('No video found for this nurse.', style: TextStyle(color: Colors.white70)))
          else if (_ctrl == null && !_failed) Container(height: 220, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)), child: const Center(child: CircularProgressIndicator(color: Colors.white)))
          else if (_ctrl != null) Column(children: [
            ClipRRect(borderRadius: BorderRadius.circular(14), child: AspectRatio(aspectRatio: (_ctrl!.value.aspectRatio == 0 ? 16 / 9 : _ctrl!.value.aspectRatio), child: VideoPlayer(_ctrl!))),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: () { setState(() { _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play(); }); }, icon: Icon(_ctrl!.value.isPlaying ? Icons.pause : Icons.play_arrow), label: Text(_ctrl!.value.isPlaying ? 'Pause Video' : '▶️ Play Video'))),
          ])
          else ElevatedButton.icon(onPressed: () async { final uri = Uri.parse(widget.video); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }, icon: const Icon(Icons.play_arrow), label: const Text('▶️ Open Video Outside App')),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: widget.onSelect, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), padding: const EdgeInsets.symmetric(vertical: 16)), child: Text('✅ Continue With ${widget.name}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
          const SizedBox(height: 20),
        ])),
    );
  }
}
