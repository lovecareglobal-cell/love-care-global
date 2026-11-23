import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'live_nurse_map.dart';

/// Book Nurse - 20/80 RULE
/// - ONLY ONLINE NURSES show
/// - CEO Live Rates: config/rates, ceoPricing, pricing
/// - Booking: Start 08:00 End 17:00 = 9 hrs/day, Care Mode Daily x1 / Weekly x7 / Monthly x30
/// - Client auto-filled + Patient (can be different place) + Map + GPS
/// - 20/80: Client pays ONLY 20% CEO fee now via Paystack. Nurse cash 80% = client -> nurse CASH after work.
/// - Saves to bookings + bookingsByClient + bookingsByNurse + nurseBookings
/// - UBER LIVE MAP: selected nurse photo blinks + moves live

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
  final _clientLocCtrl = TextEditingController();
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
  String currency = 'GHS';
  double ceoRateGHS = 0;
  double ceoRateUSD = 0;
  // Nurses
  List<Map> onlineNurses = [];
  String? selectedNurseId;
  String selectedNurseName = '';
  String selectedNursePhone = '';
  double? clientLat, clientLng, patientLat, patientLng;
  double searchRadius = 20;
  bool isPaying = false;
  final List<StreamSubscription<DatabaseEvent>> _rateSubs = [];
  bool _disposed = false;
  bool _mapFailed = false;
  bool _showMap = false;
  String _loadError = '';
  bool _isLoadingClient = true;

  @override
  void initState() {
    super.initState();
    _loadClientData();
    _loadCEORates();
    _autoCaptureLocation();
    // FIX: If client edits, patient auto-updates when sameLocation = ON
    _clientNameCtrl.addListener(() { if (sameLocation) _applyClientToPatient(); });
    _clientPhoneCtrl.addListener(() { if (sameLocation) _applyClientToPatient(); });
    _clientLocCtrl.addListener(() { if (sameLocation) _applyClientToPatient(); });
  }

  @override
  void dispose() {
    _disposed = true;
    for (final sub in _rateSubs) { sub.cancel(); }
    _clientNameCtrl.dispose();
    _clientPhoneCtrl.dispose();
    _clientEmailCtrl.dispose();
    _clientLocCtrl.dispose();
    _patientNameCtrl.dispose();
    _patientPhoneCtrl.dispose();
    _patientLocCtrl.dispose();
    super.dispose();
  }

  void _safeSet(void Function() fn) { if (!_disposed && mounted) setState(fn); }

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

  // ============ FIX 1: AUTO-FILL CLIENT ============
  Future<void> _loadClientData() async {
    final prefs = await SharedPreferences.getInstance();
    String name = prefs.getString('clientName') ?? prefs.getString('fullName') ?? '';
    String phone = prefs.getString('clientPhone') ?? prefs.getString('phone') ?? '';
    String email = prefs.getString('clientEmail') ?? prefs.getString('email') ?? '';
    String loc = prefs.getString('clientLocation') ?? prefs.getString('location') ?? '';

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (email.isEmpty) email = user.email ?? '';
        if (phone.isEmpty) phone = user.phoneNumber ?? '';
        if (name.isEmpty && user.displayName != null && user.displayName!.isNotEmpty) name = user.displayName!;

        // Firestore: users / clients / customers - where signup truly saves name
        for (final col in ['users', 'clients', 'customers']) {
          try {
            final doc = await FirebaseFirestore.instance.collection(col).doc(user.uid).get();
            if (doc.exists && doc.data() != null) {
              final d = doc.data()!;
              if (name.isEmpty) name = (d['fullName'] ?? d['name'] ?? d['clientName'] ?? d['displayName'] ?? '').toString();
              if (phone.isEmpty) phone = (d['phone'] ?? d['phoneNumber'] ?? d['mobile'] ?? d['clientPhone'] ?? '').toString();
              if (email.isEmpty) email = (d['email'] ?? '').toString();
              if (loc.isEmpty) loc = (d['location'] ?? d['address'] ?? d['clientLocation'] ?? '').toString();
              if (name.isNotEmpty) break;
            }
          } catch (_) {}
        }
        // Firestore by email fallback
        if (name.isEmpty && email.isNotEmpty) {
          for (final col in ['users', 'clients', 'customers']) {
            try {
              final q = await FirebaseFirestore.instance.collection(col).where('email', isEqualTo: email).limit(1).get();
              if (q.docs.isNotEmpty) {
                final d = q.docs.first.data();
                if (name.isEmpty) name = (d['fullName'] ?? d['name'] ?? d['clientName'] ?? '').toString();
                if (phone.isEmpty) phone = (d['phone'] ?? d['phoneNumber'] ?? '').toString();
                if (loc.isEmpty) loc = (d['location'] ?? d['address'] ?? '').toString();
                break;
              }
            } catch (_) {}
          }
        }
        // Realtime DB fallback: users/<uid>
        if (name.isEmpty || phone.isEmpty) {
          try {
            final snap = await FirebaseDatabase.instance.ref('users/${user.uid}').get();
            if (snap.exists && snap.value is Map) {
              final d = Map<String, dynamic>.from(snap.value as Map);
              if (name.isEmpty) name = (d['fullName'] ?? d['name'] ?? d['clientName'] ?? '').toString();
              if (phone.isEmpty) phone = (d['phone'] ?? d['phoneNumber'] ?? '').toString();
              if (email.isEmpty) email = (d['email'] ?? '').toString();
              if (loc.isEmpty) loc = (d['location'] ?? d['address'] ?? '').toString();
            }
          } catch (_) {}
        }
        await prefs.setString('clientName', name);
        await prefs.setString('clientPhone', phone);
        await prefs.setString('clientEmail', email);
        await prefs.setString('clientLocation', loc);
      }
    } catch (_) {}

    if (_disposed || !mounted) return;
    setState(() {
      _clientNameCtrl.text = name;
      _clientPhoneCtrl.text = phone;
      _clientEmailCtrl.text = email;
      _clientLocCtrl.text = loc;
      _isLoadingClient = false;
    });
    if (sameLocation) _applyClientToPatient();
  }

  // ============ FIX 2: SAME LOCATION = SAME PERSON ============
  void _applyClientToPatient() {
    _patientNameCtrl.text = _clientNameCtrl.text;
    _patientPhoneCtrl.text = _clientPhoneCtrl.text;
    _patientLocCtrl.text = _clientLocCtrl.text;
    patientRelationship = 'Self';
    patientLat = clientLat;
    patientLng = clientLng;
    _safeSet(() {});
  }

  void _onSameLocationChanged(bool v) {
    setState(() => sameLocation = v);
    if (v) {
      _applyClientToPatient();
    } else {
      _patientNameCtrl.clear();
      _patientPhoneCtrl.clear();
      _patientLocCtrl.clear();
      patientRelationship = 'Parent';
      patientLat = null;
      patientLng = null;
      _safeSet(() {});
    }
  }

  void _loadCEORates() {
    for (final path in ['config/rates', 'ceoPricing', 'pricing']) {
      final sub = FirebaseDatabase.instance.ref(path).onValue.listen((e) {
        try {
          if (_disposed || !mounted) return;
          if (e.snapshot.value == null) return;
          final v = _asMap(e.snapshot.value);
          if (v.isEmpty) return;
          double ghs = 0, usd = 0;
          if (v['GHS'] is Map) { ghs = _asDouble((v['GHS'] as Map)['hourly']); } else { ghs = _asDouble(v['GHS']); }
          if (v['USD'] is Map) { usd = _asDouble((v['USD'] as Map)['hourly']); } else { usd = _asDouble(v['USD']); }
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
      setState(() {
        clientLat = pos.latitude; clientLng = pos.longitude;
        patientLat = pos.latitude; patientLng = pos.longitude;
        if (_clientLocCtrl.text.isEmpty) {
          _clientLocCtrl.text = 'Current Location (${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)})';
        }
      });
      if (sameLocation) _applyClientToPatient();
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

  String _mediaFromMap(Map n, bool isVideo) {
    if (isVideo) {
      return (n['video'] ?? n['videoUrl'] ?? n['introVideo'] ?? '').toString();
    }
    return (n['photo'] ?? n['photoUrl'] ?? n['image'] ?? n['profilePhoto'] ?? n['avatar'] ?? '').toString();
  }

  Future<void> _searchNearbyNurses() async {
    if (patientLat == null || patientLng == null) return;
    try {
      final db = FirebaseDatabase.instance;
      // Try onlineNurses + nursePresence + nurseLocations
      final snap = await db.ref('onlineNurses').get();
      final presence = await db.ref('nursePresence').get();
      final locs = await db.ref('nurseLocations').get();
      final nursesMap = <String, Map>{};

      if (snap.exists && snap.value is Map) {
        final m = Map<String, dynamic>.from(snap.value as Map);
        for (final e in m.entries) {
          if (e.value is Map) nursesMap[e.key.toString()] = Map<String, dynamic>.from(e.value as Map);
        }
      }
      // Merge presence
      if (presence.exists && presence.value is Map) {
        final m = Map<String, dynamic>.from(presence.value as Map);
        for (final e in m.entries) {
          if (e.value is Map) {
            final d = Map<String, dynamic>.from(e.value as Map);
            final online = d['online'] == true || d['isOnline'] == true || d['status'] == 'online';
            if (!online) continue;
            nursesMap[e.key.toString()] = {...?nursesMap[e.key.toString()], ...d, 'uid': e.key.toString()};
          }
        }
      }
      // Merge locations
      if (locs.exists && locs.value is Map) {
        final m = Map<String, dynamic>.from(locs.value as Map);
        for (final e in m.entries) {
          if (e.value is Map && nursesMap.containsKey(e.key.toString())) {
            nursesMap[e.key.toString()]!.addAll(Map<String, dynamic>.from(e.value as Map));
          }
        }
      }
      // Also try Firestore nurses collection if RTDB empty
      if (nursesMap.isEmpty) {
        try {
          final q = await FirebaseFirestore.instance.collection('nurses').where('isOnline', isEqualTo: true).limit(50).get();
          for (final d in q.docs) {
            nursesMap[d.id] = {...d.data(), 'uid': d.id};
          }
        } catch (_) {}
      }

      final List<Map> list = [];
      for (final entry in nursesMap.entries) {
        final n = entry.value;
        final lat = _asDouble(n['lat'] ?? n['latitude']);
        final lng = _asDouble(n['lng'] ?? n['longitude']);
        if (lat == 0 && lng == 0) continue;
        final dist = _haversine(patientLat!, patientLng!, lat, lng);
        if (dist > searchRadius) continue;
        n['uid'] = entry.key;
        n['distance'] = dist;
        n['lat'] = lat;
        n['lng'] = lng;
        list.add(n);
      }
      list.sort((a, b) => _asDouble(a['distance']).compareTo(_asDouble(b['distance'])));
      if (_disposed || !mounted) return;
      setState(() {
        onlineNurses = list;
        if (list.isNotEmpty && selectedNurseId == null) {
          selectedNurseId = list.first['uid']?.toString();
          selectedNurseName = (list.first['name'] ?? list.first['fullName'] ?? 'Nurse').toString();
          selectedNursePhone = (list.first['phone'] ?? list.first['phoneNumber'] ?? '').toString();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  void _pickAnotherOne() {
    if (onlineNurses.length <= 1) return;
    final idx = onlineNurses.indexWhere((x) => x['uid'] == selectedNurseId);
    final next = onlineNurses[(idx + 1) % onlineNurses.length];
    setState(() {
      selectedNurseId = next['uid']?.toString();
      selectedNurseName = (next['name'] ?? next['fullName'] ?? 'Nurse').toString();
      selectedNursePhone = (next['phone'] ?? next['phoneNumber'] ?? '').toString();
    });
  }

  Map<String, dynamic>? get _autoPickedNurse {
    if (selectedNurseId == null) return null;
    try { return Map<String, dynamic>.from(onlineNurses.firstWhere((x) => x['uid'] == selectedNurseId)); } catch (_) { return null; }
  }

  Map<String, dynamic> calcTotal() {
    final rate = currency == 'GHS' ? (ceoRateGHS > 0 ? ceoRateGHS : 50) : (ceoRateUSD > 0 ? ceoRateUSD : 5);
    double hrsPerDay = 9; // 08:00 - 17:00
    int multiplier = 1;
    if (careMode == 'Weekly') multiplier = 7;
    if (careMode == 'Monthly') multiplier = 30;
    final totalHours = hrsPerDay * multiplier * quantity;
    final base = rate * totalHours;
    final total = base + transport;
    final ceoFee = total * 0.20;
    final nurseCash = total * 0.80;
    final payNow = ceoFee;
    final payLater = nurseCash;
    return {
      'rate': rate, 'totalHours': totalHours, 'hrsPerDay': hrsPerDay,
      'total': total, 'ceoFee': ceoFee, 'nurseCash': nurseCash,
      'payNow': payNow, 'payLater': payLater,
    };
  }

  Future<void> _showNursePhotoVideoAuto(Map n) async {
    final photo = _mediaFromMap(n, false);
    final video = _mediaFromMap(n, true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1B2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AutoNurseProfileSheet(
        name: (n['name'] ?? n['fullName'] ?? 'Nurse').toString(),
        spec: (n['specialty'] ?? 'Home Nursing').toString(),
        distance: _asDouble(n['distance']),
        photo: photo,
        video: video,
      ),
    );
  }

  Future<void> _payWithPaystack() async {
    if (sameLocation) _applyClientToPatient();
    if (selectedNurseId == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select an ONLINE nurse first'))); return; }
    if (_clientNameCtrl.text.isEmpty || _clientPhoneCtrl.text.isEmpty || _patientNameCtrl.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill Client + Patient details'))); return; }
    final calc = calcTotal();
    final payNow = calc['payNow'] as double;
    final total = calc['total'] as double;
    final nurseCash = calc['nurseCash'] as double;
    setState(() => isPaying = true);
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        title: const Text('Pay 20% Only'),
        content: Text('Pay $currency ${payNow.toStringAsFixed(2)} now?\nTotal: $currency ${total.toStringAsFixed(2)}\nPay 20% CEO Fee now\nPay Nurse $currency ${nurseCash.toStringAsFixed(2)} CASH after work\nNurse: $selectedNurseName'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Pay Now'))],
      ));
      if (confirmed != true) { setState(() => isPaying = false); return; }
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
      'clientLocation': _clientLocCtrl.text.trim(), 'clientLocationText': _clientLocCtrl.text.trim(),
      'clientLat': clientLat, 'clientLng': clientLng,
      'patientName': _patientNameCtrl.text.trim(), 'patientPhone': _patientPhoneCtrl.text.trim(),
      'patientLocation': _patientLocCtrl.text.trim(), 'patientLocationText': _patientLocCtrl.text.trim(),
      'patientLat': patientLat, 'patientLng': patientLng, 'patientLatLng': {'lat': patientLat, 'lng': patientLng},
      'patientRelationship': patientRelationship,
      'nurseId': selectedNurseId, 'nurseName': selectedNurseName, 'nursePhone': selectedNursePhone, 'nurseWasOnline': true, 'nurseOnlineAt': DateTime.now().millisecondsSinceEpoch,
      'amount': calc['total'], 'totalAmount': calc['total'], 'total': calc['total'], 'totalGHS': calc['total'],
      'ceoFee': calc['ceoFee'], 'ceoFeeGHS': calc['ceoFee'],
      'nurseCash': calc['nurseCash'], 'nurseCashAmount': calc['nurseCash'], 'amountYouWillCollectCash': calc['nurseCash'],
      'amountPaidNow': calc['payNow'], 'amountBalance': calc['payLater'], 'payNow': calc['payNow'], 'payLater': calc['payLater'],
      'currency': currency, 'paymentMethod': 'paystack_20', 'paymentType': '20_percent_ceo_fee', 'paystackRef': paystackRef,
      'status': 'pending', 'time': DateTime.now().millisecondsSinceEpoch, 'createdAt': DateTime.now().millisecondsSinceEpoch,
      'totalHours': calc['totalHours'], 'hrsPerDay': calc['hrsPerDay'], 'startTime': startTime, 'endTime': endTime, 'careMode': careMode, 'quantity': quantity, 'transport': transport,
      'hourlyRateUsed': calc['rate'], 'service': careMode,
      'userId': FirebaseAuth.instance.currentUser?.uid,
      'refundCeoFee': false, 'refundStatus': 'none',
    };
    try {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).set(booking);
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      await FirebaseFirestore.instance.collection('bookingsByClient').doc(uid).collection('items').doc(bookingId).set(booking);
      if (selectedNurseId != null) {
        await FirebaseFirestore.instance.collection('bookingsByNurse').doc(selectedNurseId).collection('items').doc(bookingId).set(booking);
        await FirebaseFirestore.instance.collection('nurseBookings').doc(selectedNurseId).collection('items').doc(bookingId).set(booking);
      }
      try {
        final db = FirebaseDatabase.instance;
        await db.ref('bookings/$bookingId').set(booking);
        await db.ref('bookingsByClient/$uid/$bookingId').set(booking);
        if (selectedNurseId != null) {
          await db.ref('bookingsByNurse/$selectedNurseId/$bookingId').set(booking);
          await db.ref('nurseBookings/$selectedNurseId/$bookingId').set(booking);
        }
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Booking saved! Pay 20% done. Pay nurse 80% cash after work.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.purple)),
  );

  @override
  Widget build(BuildContext context) {
    final calc = calcTotal();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F1FB),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
        title: const Text('Book Nurse', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // CLIENT
          _sectionTitle('👤 CLIENT — Auto-filled from your account'),
          if (_isLoadingClient)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Text('Loading your saved details...', style: TextStyle(color: Colors.grey))]),
            ),
          TextField(controller: _clientNameCtrl, decoration: const InputDecoration(labelText: 'CLIENT NAME *', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: TextField(controller: _clientPhoneCtrl, decoration: const InputDecoration(labelText: 'CLIENT PHONE *', border: OutlineInputBorder()))), const SizedBox(width: 8), Expanded(child: TextField(controller: _clientEmailCtrl, decoration: const InputDecoration(labelText: 'CLIENT EMAIL *', border: OutlineInputBorder())))]),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: TextField(controller: _clientLocCtrl, decoration: const InputDecoration(labelText: 'CLIENT LOCATION TEXT', border: OutlineInputBorder()))), const SizedBox(width: 8), ElevatedButton.icon(onPressed: _enableMap, icon: const Icon(Icons.map), label: const Text('Map'))]),
          const SizedBox(height: 16),

          // PATIENT
          _sectionTitle('🏥 PATIENT — Who needs care'),
          TextField(controller: _patientNameCtrl, enabled: !sameLocation, decoration: InputDecoration(labelText: 'PATIENT NAME *', border: const OutlineInputBorder(), filled: sameLocation, fillColor: Colors.purple.shade50)),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: TextField(controller: _patientPhoneCtrl, enabled: !sameLocation, decoration: InputDecoration(labelText: 'PATIENT PHONE', border: const OutlineInputBorder(), filled: sameLocation, fillColor: Colors.purple.shade50))), const SizedBox(width: 8), Expanded(child: DropdownButtonFormField<String>(value: patientRelationship, decoration: const InputDecoration(labelText: 'RELATIONSHIP', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'Self', child: Text('Self')), DropdownMenuItem(value: 'Parent', child: Text('Parent')), DropdownMenuItem(value: 'Child', child: Text('Child')), DropdownMenuItem(value: 'Spouse', child: Text('Spouse')), DropdownMenuItem(value: 'Other', child: Text('Other'))], onChanged: sameLocation ? null : (v) => setState(() => patientRelationship = v ?? 'Self'))))]),
          const SizedBox(height: 8),
          TextField(controller: _patientLocCtrl, enabled: !sameLocation, decoration: InputDecoration(labelText: 'PATIENT LOCATION TEXT', border: const OutlineInputBorder(), filled: sameLocation, fillColor: Colors.purple.shade50)),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Same location as Client'),
            subtitle: Text(sameLocation ? '✅ Patient = Client - auto-copied, no typing needed' : 'Patient is different person / place - type patient details'),
            value: sameLocation,
            activeColor: Colors.purple,
            onChanged: _onSameLocationChanged,
          ),
          const SizedBox(height: 16),

          // BOOKING DETAILS
          _sectionTitle('📅 Booking Details — 08:00 to 17:00 = 9 hrs/day'),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(value: careMode, decoration: const InputDecoration(labelText: 'CARE MODE', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'Daily', child: Text('Daily x1')), DropdownMenuItem(value: 'Weekly', child: Text('Weekly x7')), DropdownMenuItem(value: 'Monthly', child: Text('Monthly x30'))], onChanged: (v) => setState(() => careMode = v ?? 'Daily'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(decoration: const InputDecoration(labelText: 'QUANTITY / DAYS', border: OutlineInputBorder()), keyboardType: TextInputType.number, controller: TextEditingController(text: quantity.toString()), onChanged: (v) => quantity = int.tryParse(v) ?? 1)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(value: currency, decoration: const InputDecoration(labelText: 'CURRENCY', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'GHS', child: Text('GHS - Cedis')), DropdownMenuItem(value: 'USD', child: Text('USD - Dollars'))], onChanged: (v) => setState(() => currency = v ?? 'GHS'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(decoration: const InputDecoration(labelText: 'TRANSPORT (GHS)', border: OutlineInputBorder()), keyboardType: TextInputType.number, controller: TextEditingController(text: transport.toStringAsFixed(0)), onChanged: (v) => transport = double.tryParse(v) ?? 100)),
          ]),
          const SizedBox(height: 12),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.purple.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total: $currency ${calc['total'].toStringAsFixed(2)}  •  Hours: ${calc['totalHours']} hrs', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Pay NOW (20% CEO Fee): $currency ${calc['payNow'].toStringAsFixed(2)}', style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
              Text('Pay Nurse CASH after work (80%): $currency ${calc['nurseCash'].toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(height: 16),

          // ONLINE NURSES
          _sectionTitle('🟢 ONLINE Nurses within ${searchRadius.toInt()}km — Only online show • ${onlineNurses.length} nurses'),
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
                    Text(_autoPickedNurse!['name']?.toString() ?? _autoPickedNurse!['fullName']?.toString() ?? 'Nurse', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
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
                const SizedBox(height: 10),
                if (_autoPickedNurse != null && patientLat != null && patientLng != null)
                  UberLiveMap(
                    nurseId: selectedNurseId ?? '',
                    nurseName: selectedNurseName,
                    nursePhoto: _mediaFromMap(_autoPickedNurse!, false),
                    patientLat: patientLat!,
                    patientLng: patientLng!,
                  ),
              ]),
            ),
          if (onlineNurses.isEmpty)
            Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)), child: const Text('🔍 System is searching for ONLINE nurses near the patient... Keep this page open. If none, increase radius or try later.')),
          if (_loadError.isNotEmpty) Text(_loadError, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          if (onlineNurses.isNotEmpty)
            ...onlineNurses.map((n) => Card(
              color: (n['uid'] == selectedNurseId) ? Colors.purple.shade100 : Colors.white,
              child: ListTile(
                leading: CircleAvatar(backgroundImage: _mediaFromMap(n, false).isNotEmpty ? NetworkImage(_mediaFromMap(n, false)) : null, child: _mediaFromMap(n, false).isEmpty ? const Text('👩') : null),
                title: Text((n['name'] ?? n['fullName'] ?? 'Nurse').toString()),
                subtitle: Text('${n['specialty'] ?? 'Home Nursing'} • ${_asDouble(n['distance']).toStringAsFixed(1)} km • 🟢 ONLINE'),
                trailing: const Icon(Icons.check_circle, color: Colors.green),
                onTap: () => setState(() { selectedNurseId = n['uid']?.toString(); selectedNurseName = (n['name'] ?? n['fullName'] ?? 'Nurse').toString(); selectedNursePhone = (n['phone'] ?? '').toString(); }),
              ),
            )),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: isPaying ? null : _payWithPaystack,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: isPaying ? const CircularProgressIndicator(color: Colors.white) : Text('Pay 20% Now — $currency ${calc['payNow'].toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 8),
          const Center(child: Text('Nurse collects 80% CASH from you after work. CEO never pays nurse.', style: TextStyle(fontSize: 12, color: Colors.grey))),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}

class _AutoNurseProfileSheet extends StatefulWidget {
  final String name; final String spec; final double distance; final String photo; final String video;
  const _AutoNurseProfileSheet({required this.name, required this.spec, required this.distance, required this.photo, required this.video});
  @override
  State<_AutoNurseProfileSheet> createState() => _AutoNurseProfileSheetState();
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
          if (widget.video.isNotEmpty && _ctrl != null)
            AspectRatio(
              aspectRatio: _ctrl!.value.aspectRatio,
              child: Stack(children: [
                VideoPlayer(_ctrl!),
                Center(child: IconButton(icon: Icon(_ctrl!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 64, color: Colors.white), onPressed: () => setState(() => _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play()))),
              ]),
            )
          else if (widget.video.isNotEmpty && !_failed)
            const Center(child: CircularProgressIndicator())
          else if (widget.photo.isNotEmpty)
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(widget.photo, height: 280, width: double.infinity, fit: BoxFit.cover)),
          const SizedBox(height: 16),
          const Text('This nurse is ONLINE now and nearest to patient. Continue with her to pay 20% CEO fee only.', style: TextStyle(color: Colors.white70)),
        ]),
      ),
    );
  }
}
