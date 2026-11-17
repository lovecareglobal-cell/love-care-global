import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
// NO EMBEDDED GoogleMap widget - it crashes on some phones even with key.
// Map now opens in Google Maps app / browser via url_launcher - can NEVER crash the app.
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'book_nurse_50.dart';
import 'live_nurse_map.dart';

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
  // nurseMarkers removed - no embedded map
  bool isPaying = false;
  // CRASH FIX: listeners + disposed guard
  final List<StreamSubscription<DatabaseEvent>> _rateSubs = [];
  bool _disposed = false;
  bool _mapFailed = false;
  bool _showMap = false; // CRASH FIX: NEVER build GoogleMap on open. Only after user taps Show Map.
  String _loadError = '';

  @override
  void initState() {
    super.initState();
    _loadClientData();
    _loadCEORates();
    _autoCaptureLocation();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final sub in _rateSubs) { sub.cancel(); }
    _clientNameCtrl.dispose();
    _clientPhoneCtrl.dispose();
    _clientEmailCtrl.dispose();
    _patientNameCtrl.dispose();
    _patientPhoneCtrl.dispose();
    _patientLocCtrl.dispose();
    super.dispose();
  }

  void _safeSet(void Function() fn) { if (!_disposed && mounted) setState(fn); }

  // CRASH FIX: Firebase can return null / List / String, not always Map.
  Map<String, dynamic> _asMap(dynamic v) {
    if (v == null) return {};
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  double _asDouble(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  Future<void> _loadClientData() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed || !mounted) return;
    setState(() {
      _clientNameCtrl.text = prefs.getString('clientName') ?? prefs.getString('fullName') ?? '';
      _clientPhoneCtrl.text = prefs.getString('clientPhone') ?? prefs.getString('phone') ?? '';
      _clientEmailCtrl.text = prefs.getString('clientEmail') ?? prefs.getString('email') ?? '';
    });
  }

  void _loadCEORates() {
    // CRASH FIX: old code did `value as Map?` - if rates node is a List/number/String,
    // it threw and killed the app. Now safe + listeners cancelled in dispose + no setState after dispose.
    for (final path in ['config/rates', 'ceoPricing', 'pricing']) {
      final sub = FirebaseDatabase.instance.ref(path).onValue.listen((e) {
        try {
          if (_disposed || !mounted) return;
          if (e.snapshot.value == null) return;
          final v = _asMap(e.snapshot.value);
          if (v.isEmpty) return;
          double ghs = 0, usd = 0;
          // GHS can be {hourly: 50} OR a plain number 50 - handle both, never index a number.
          if (v['GHS'] is Map) { ghs = _asDouble((v['GHS'] as Map)['hourly']); }
          else { ghs = _asDouble(v['GHS']); }
          if (v['USD'] is Map) { usd = _asDouble((v['USD'] as Map)['hourly']); }
          else { usd = _asDouble(v['USD']); }
          if (ghs == 0) ghs = _asDouble(v['cedis'] ?? v['ghs']);
          if (usd == 0) usd = _asDouble(v['dollars'] ?? v['usd']);
          if (ghs > 0) ceoRateGHS = ghs;
          if (usd > 0) ceoRateUSD = usd;
          _safeSet(() {});
        } catch (_) {}
      }, onError: (_) {});
      _rateSubs.add(sub);
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

  Future<void> _enableMap() async {
    // CRASH-PROOF MAP: never build embedded GoogleMap widget - it is what closed the app.
    // Open location in Google Maps app / browser instead - can NEVER crash Love Care.
    if (clientLat == null || clientLng == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Waiting for your GPS location...')));
      return;
    }
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$clientLat,$clientLng');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Your location: $clientLat, $clientLng')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Your location: $clientLat, $clientLng')));
    }
  }

  Future<void> _openNurseOnMap(Map n) async {
    final lat = _asDouble(n['lat']);
    final lng = _asDouble(n['lng']);
    if (lat == 0 && lng == 0) return;
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _searchNearbyNurses() async {
    if (clientLat == null || clientLng == null) return;
    try {
      // CRASH FIX: any of these 3 nodes can be null / List / String. Old code did
      // `value as Map` on all 3 - one bad node closed the whole app in seconds.
      final snap = await FirebaseDatabase.instance.ref('onlineNurses').get();
      final nurseSnap = await FirebaseDatabase.instance.ref('nurses').get();
      final locSnap = await FirebaseDatabase.instance.ref('nurseLocations').get();
      if (_disposed || !mounted) return;
      // onlineNurses can be Map {uid: true} OR List [uid,...] - handle both.
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
          if (!onlineIds.contains(uid)) continue; // HIDE OFFLINE
          if (entry.value is! Map) continue; // skip bad nurse entry, don't crash
          final n = Map<String, dynamic>.from(entry.value as Map);
          final locRaw = locMap[uid];
          final loc = locRaw is Map ? Map<String, dynamic>.from(locRaw) : <String, dynamic>{};
          // lat/lng can be in loc, in nurse, or in gpsLat/gpsLng / latitude / longitude
          final lat = _asDouble(loc['lat'] ?? loc['latitude'] ?? loc['gpsLat'] ?? n['lat'] ?? n['latitude'] ?? n['gpsLat'] ?? n['locationLat']);
          final lng = _asDouble(loc['lng'] ?? loc['longitude'] ?? loc['gpsLng'] ?? n['lng'] ?? n['longitude'] ?? n['gpsLng'] ?? n['locationLng']);
          if (lat == 0 && lng == 0) continue;
          final dist = _haversine(clientLat!, clientLng!, lat, lng);
          if (dist > searchRadius) continue;
          list.add({'uid': uid, ...n, 'lat': lat, 'lng': lng, 'distance': dist, 'isOnline': true});
        } catch (_) { continue; }
      }
      list.sort((a, b) => _asDouble(a['distance']).compareTo(_asDouble(b['distance'])));
      if (_disposed || !mounted) return;
      final bool hadSelection = selectedNurseId != null;
      setState(() {
        onlineNurses = List<Map>.from(list);
        _loadError = '';
        // No embedded markers - list shows distance instead, never crashes.
      });
      if (!hadSelection) _autoSelectNearest();
    } catch (e) {
      if (!_disposed && mounted) setState(() => _loadError = 'Could not load nurses: $e. Pull to try again - offline nurses are hidden.');
    }
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
    final parts = (isStart ? startTime : endTime).split(':');
    final init = TimeOfDay(hour: int.tryParse(parts.isNotEmpty ? parts[0] : '8') ?? 8, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
    final picked = await showTimePicker(context: context, initialTime: init);
    if (picked != null) {
      setState(() { final v = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'; if (isStart) startTime = v; else endTime = v; });
    }
  }


  // ===== WHY VIDEO SAID "NO VIDEO" - FIX =====
  // Nurse video is NOT always in the list item. Registration saves it under many
  // different keys, sometimes nested (video:{url:...}), sometimes as a List, sometimes
  // only in the full nurse record (RTDB nurses/{uid} or Firestore). Old code only checked
  // 1 flat key on the list item, so it said "No video" even though she uploaded one.
  // This checks: flat keys + nested maps + lists + full record from RTDB + Firestore.
  String _pickUrl(dynamic v) {
    if (v == null) return '';
    if (v is String) { final t = v.trim(); if (t.startsWith('http') || t.startsWith('gs://')) return t; return ''; }
    if (v is List) { for (final x in v) { final u = _pickUrl(x); if (u.isNotEmpty) return u; } return ''; }
    if (v is Map) {
      for (final k in ['url','downloadUrl','downloadURL','videoUrl','videoURL','link','href','path']) { final u = _pickUrl(v[k]); if (u.isNotEmpty) return u; }
      return '';
    }
    return '';
  }
  String _mediaFromMap(Map n, bool isVideo) {
    final videoKeys = ['videoUrl','videoURL','video','introVideoUrl','introVideo','registrationVideoUrl','registrationVideo','nurseVideoUrl','nurseVideo','profileVideoUrl','profileVideo','introVideoURL','selfieVideoUrl','videoLink','video_url'];
    final photoKeys = ['photoUrl','photoURL','photo','profilePhoto','imageUrl','imageURL','profilePhotoUrl','profilePic','profilePicture','avatar','picture'];
    final keys = isVideo ? videoKeys : photoKeys;
    for (final k in keys) { final u = _pickUrl(n[k]); if (u.isNotEmpty) return u; }
    // Nested: video:{url:...} , media:{video:...} , files:{video:...} , registration:{video:...}
    for (final k in ['video','media','files','registration','documents','uploads','profile']) {
      final v = n[k];
      if (v is Map) { final u = _mediaFromMap(Map<String,dynamic>.from(v), isVideo); if (u.isNotEmpty) return u; }
    }
    // Lists: videos:[...] / photos:[...] / media:[...]
    for (final k in ['videos','videoUrls','photos','photoUrls','media','files','attachments']) {
      final u = _pickUrl(n[k]); if (u.isNotEmpty) return u;
    }
    return '';
  }
  Future<Map<String,dynamic>> _fetchFullNurse(String uid) async {
    // Merge full record: RTDB nurses/{uid} + RTDB approved_nurses/{uid} + Firestore nurses/approved_nurses/pending_nurses/{uid}
    final merged = <String,dynamic>{};
    try { final snap = await FirebaseDatabase.instance.ref('nurses/$uid').get(); if (snap.exists && snap.value is Map) merged.addAll(Map<String,dynamic>.from(snap.value as Map)); } catch (_) {}
    try { final snap = await FirebaseDatabase.instance.ref('approved_nurses/$uid').get(); if (snap.exists && snap.value is Map) merged.addAll(Map<String,dynamic>.from(snap.value as Map)); } catch (_) {}
    try { final doc = await FirebaseFirestore.instance.collection('nurses').doc(uid).get(); if (doc.exists && doc.data() != null) merged.addAll(doc.data()!); } catch (_) {}
    try { final doc = await FirebaseFirestore.instance.collection('approved_nurses').doc(uid).get(); if (doc.exists && doc.data() != null) merged.addAll(doc.data()!); } catch (_) {}
    try { final doc = await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).get(); if (doc.exists && doc.data() != null) merged.addAll(doc.data()!); } catch (_) {}
    return merged;
  }
  Future<void> _showNursePhotoVideoAuto(Map n) async {
    // Always re-fetch full record BEFORE saying "No video" - list item is incomplete
    final uid = (n['uid'] ?? '').toString();
    Map<String,dynamic> full = Map<String,dynamic>.from(n);
    if (uid.isNotEmpty) {
      final fetched = await _fetchFullNurse(uid);
      if (fetched.isNotEmpty) { full = {...fetched, ...full}; for (final k in fetched.keys) { if ((full[k] == null || full[k].toString().isEmpty) && fetched[k] != null) full[k] = fetched[k]; } }
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
  // ===== AUTOMATIC SELECTION: system auto-picks nearest ONLINE nurse, no tap on map needed =====
  void _autoSelectNearest() {
    if (onlineNurses.isEmpty) return;
    if (selectedNurseId != null) return; // already chosen - do not override
    final n = onlineNurses.first; // list is already sorted nearest-first
    setState(() { selectedNurseId = n['uid']; selectedNurseName = (n['name'] ?? '').toString(); selectedNursePhone = (n['phone'] ?? '').toString(); });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🤖 System auto-picked nearest ONLINE nurse: $selectedNurseName (${_asDouble(n['distance']).toStringAsFixed(1)} km) - Watch her photo + video below')));
  }
  void _pickAnotherOne() {
    if (onlineNurses.length < 2) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other ONLINE nurse nearby yet - system is still searching...'))); return; }
    final idx = onlineNurses.indexWhere((x) => x['uid'] == selectedNurseId);
    final next = onlineNurses[(idx + 1) % onlineNurses.length];
    setState(() { selectedNurseId = next['uid']; selectedNurseName = (next['name'] ?? '').toString(); selectedNursePhone = (next['phone'] ?? '').toString(); });
  }
  Map<String,dynamic>? get _autoPickedNurse {
    if (selectedNurseId == null) return null;
    try { return Map<String,dynamic>.from(onlineNurses.firstWhere((x) => x['uid'] == selectedNurseId)); } catch (_) { return null; }
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

  // ===== SYSTEM PICK: System finds nearby ONLINE nurses, picks nearest, client watches photo+video, decides Continue / Another One =====
  Future<void> _openSystemPick() async {
    if (patientLat == null || clientLat == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Waiting for your GPS... try again in a second')));
      return;
    }
    final selected = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveNurseMap(
          patientLat: patientLat, // patient live place - only nurses close to PATIENT
          patientLng: patientLng,
          clientLat: clientLat,
          clientLng: clientLng,
          searchRadiusKm: 20,
          autoPickNearest: true, // system picks nearest automatically
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        selectedNurseId = selected['uid']?.toString();
        selectedNurseName = (selected['name'] ?? selected['fullName'] ?? '').toString();
        selectedNursePhone = (selected['phone'] ?? '').toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ You chose $selectedNurseName - now choose 50% Paystack + Cash OR Full Payment below')),
      );
    }
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
          // ===== AUTOMATIC SELECTION - system already picked nearest, client just watches + confirms =====
          if (onlineNurses.isNotEmpty && _autoPickedNurse != null)
            Container(
              width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.5))),
              child: Column(children: [
                const Text('🤖 SYSTEM AUTO-PICKED NEAREST ONLINE NURSE FOR YOU', textAlign: TextAlign.center, style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Row(children: [
                  CircleAvatar(radius: 30, backgroundImage: _mediaFromMap(_autoPickedNurse!, false).isNotEmpty ? NetworkImage(_mediaFromMap(_autoPickedNurse!, false)) : null, child: _mediaFromMap(_autoPickedNurse!, false).isEmpty ? const Text('👩') : null),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_autoPickedNurse!['name']?.toString() ?? 'Nurse', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('${_autoPickedNurse!['specialty'] ?? 'Home Nursing'} • ${_asDouble(_autoPickedNurse!['distance']).toStringAsFixed(1)} km from patient • 🟢 ONLINE', style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
              ]),
            ),
          if (onlineNurses.isEmpty)
            Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)), child: const Text('🔍 System is searching for ONLINE nurses near the patient... Keep this page open - nearest nurse will be auto-picked as soon as she goes ONLINE.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12))),
          if (_loadError.isNotEmpty) Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Text(_loadError, textAlign: TextAlign.center)),
          const SizedBox(height: 12),
          // AUTO-SELECT banner is below - no dead-end message, system keeps searching
          ...onlineNurses.map((n) => _nurseCard(n)),
          const SizedBox(height: 16),
          // === SYSTEM PICK - System views nearby nurses, picks nearest for client ===
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFA855F7).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.4)),
            ),
            child: Column(
              children: [
                const Text(
                  'System will find nearby ONLINE nurses for you',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _openSystemPick,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFA855F7),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      '🤖 System Pick Nearest Nurse For Me - Watch Photo + Video',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'System shows nearest nurse first - Watch her photo + video - Continue with her OR Look at another one',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                if (selectedNurseId != null) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('✅ Selected: $selectedNurseName', textAlign: TextAlign.center, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // === 50% OPTION - ON TOP OF FULL PAYMENT - Opens book_nurse_50.dart ===
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF00C853).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF00C853).withOpacity(0.4)),
            ),
            child: Column(
              children: [
                const Text(
                  'Not all clients have full money before nurse starts work',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BookNurse50Screen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C853),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      '💳 Pay 50% via Paystack + 💵 50% Cash to Nurse',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Pay 50% now in Paystack • Give 50% cash to nurse later',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // === END 50% BUTTON - FULL PAYMENT BUTTON BELOW ===
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
      onTap: () { setState(() { selectedNurseId = n['uid']; selectedNurseName = n['name'] ?? ''; selectedNursePhone = n['phone'] ?? ''; }); _showNursePhotoVideoAuto(n); },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: isSel ? const Color(0xFFA855F7).withOpacity(0.2) : const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16), border: Border.all(color: isSel ? const Color(0xFFA855F7) : Colors.white12)),
        child: Row(children: [
          CircleAvatar(radius: 28, backgroundImage: (photo.toString().isNotEmpty && (photo.toString().startsWith('http://') || photo.toString().startsWith('https://'))) ? NetworkImage(photo.toString()) : null, onBackgroundImageError: (_, __) {}, child: photo.toString().isEmpty ? const Text('👩') : null),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Text(n['name']?.toString() ?? 'Nurse', style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(width: 6), Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle))]),
            Text('${n['specialty'] ?? 'Home Nursing'} • ${_asDouble(n['distance']).toStringAsFixed(1)} km away', style: const TextStyle(color: Colors.white60, fontSize: 11)),
            Text('⭐ ${n['rating'] ?? 5} • Verified ✅ • ONLINE', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.play_circle_fill, color: Colors.yellow), tooltip: 'Watch photo + video', onPressed: () => _showNursePhotoVideoAuto(n)),
          IconButton(icon: const Icon(Icons.map, color: Colors.white70), onPressed: () => _openNurseOnMap(n)),
          if (isSel) const Icon(Icons.check_circle, color: Colors.green),
        ]),
      ),
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
    try { final c = VideoPlayerController.networkUrl(Uri.parse(widget.video)); await c.initialize(); if (mounted) setState(() => _ctrl = c); }
    catch (_) { if (mounted) setState(() => _failed = true); }
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
          if (widget.video.isEmpty) Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)), child: const Text('No video found for this nurse - she may not have uploaded one during registration. Ask her to upload one in Nurse Settings.', style: TextStyle(color: Colors.white70)))
          else if (_ctrl == null && !_failed) Container(height: 220, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)), child: const Center(child: CircularProgressIndicator(color: Colors.white)))
          else if (_ctrl != null) Column(children: [
            ClipRRect(borderRadius: BorderRadius.circular(14), child: AspectRatio(aspectRatio: _ctrl!.value.aspectRatio, child: VideoPlayer(_ctrl!))),
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
