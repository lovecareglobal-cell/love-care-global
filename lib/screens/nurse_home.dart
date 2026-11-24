import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// NURSE HOME - GO ONLINE + SEND GPS EVERY 10 SEC = MAKES UBER MAP MOVE
// - Nurse taps GO ONLINE -> app starts sending lat/lng to nurseLocations/{uid} every 10 sec
// - Client side LiveNurseMap / UberLiveMap listens to that node -> photo MOVES like Uber
// - If nurse goes OFFLINE or closes app without GO OFFLINE, photo stops moving
// - Location MUST be = Always, else Android stops GPS when app minimized

class NurseHomeScreen extends StatefulWidget {
  const NurseHomeScreen({super.key});
  @override
  State<NurseHomeScreen> createState() => _NurseHomeScreenState();
}

class _NurseHomeScreenState extends State<NurseHomeScreen> {
  String nurseId = '';
  String nurseName = '';
  String nursePhoto = '';
  bool isOnline = false;
  bool _isLoading = true;
  double? _lat, _lng;
  String _gpsText = 'GPS not started';
  Timer? _gpsTimer;
  StreamSubscription<Position>? _posStream;
  StreamSubscription? _bookingSub;
  List<Map> myBookings = [];
  int _todayEarnings = 0;

  @override
  void initState() {
    super.initState();
    _loadNurse();
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _posStream?.cancel();
    _bookingSub?.cancel();
    super.dispose();
  }

  Future<void> _loadNurse() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();
      String uid = user?.uid ?? prefs.getString('nurseId') ?? prefs.getString('uid') ?? '';
      if (uid.isEmpty) {
        // Fallback: try to read from stored email
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }
      nurseId = uid;
      // Load profile
      final snap = await FirebaseDatabase.instance.ref('nurses/$uid').get();
      if (snap.exists && snap.value is Map) {
        final m = Map.from(snap.value as Map);
        nurseName = (m['name'] ?? m['fullName'] ?? prefs.getString('nurseName') ?? 'Nurse').toString();
        nursePhoto = (m['photoURL'] ?? m['photo'] ?? m['profilePic'] ?? '').toString();
      } else {
        nurseName = prefs.getString('nurseName') ?? prefs.getString('fullName') ?? 'Nurse';
      }
      // Check if already online (app was closed without GO OFFLINE)
      final onSnap = await FirebaseDatabase.instance.ref('onlineNurses/$uid').get();
      bool wasOnline = onSnap.exists;
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (wasOnline) {
        // Auto-resume GPS - so map keeps moving even after restart
        _goOnline(silent: true);
      }
      _listenBookings();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _listenBookings() {
    if (nurseId.isEmpty) return;
    _bookingSub = FirebaseDatabase.instance.ref('bookingsByNurse/$nurseId').onValue.listen((e) {
      if (!mounted) return;
      final v = e.snapshot.value;
      if (v is! Map) return;
      List<Map> list = [];
      v.forEach((k, val) {
        if (val is Map) {
          final m = Map.from(val);
          m['bookingId'] = k.toString();
          list.add(m);
        }
      });
      list.sort((a, b) => (b['createdAt'] ?? b['time'] ?? 0).toString().compareTo((a['createdAt'] ?? a['time'] ?? 0).toString()));
      setState(() => myBookings = list);
    });
  }

  Future<bool> _checkLocationPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      if (!mounted) return false;
      showDialog(context: context, builder: (_) => AlertDialog(
        title: const Text('Location = Always Needed'),
        content: const Text('For Uber live map to work, you MUST set Location = Always.\n\nGo to Settings > Apps > Love Care Global > Location > Allow all the time.\n\nIf you put "While Using App", your photo will STOP moving when you minimize app.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')), ElevatedButton(onPressed: () { Navigator.pop(context); Geolocator.openAppSettings(); }, child: const Text('Open Settings'))],
      ));
      return false;
    }
    if (perm == LocationPermission.denied) return false;
    // Ask for Always - this is what keeps GPS running in background
    if (perm == LocationPermission.whileInUse) {
      if (!mounted) return true; // Still allow, but warn
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Please change Location to ALWAYS in Settings, else map will stop when you minimize app'), duration: Duration(seconds: 5)));
    }
    return true;
  }

  // ===== GO ONLINE - START SENDING GPS EVERY 10 SEC =====
  Future<void> _goOnline({bool silent = false}) async {
    if (nurseId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login first as nurse')));
      return;
    }
    final ok = await _checkLocationPermission();
    if (!ok && !silent) return;

    try {
      // 1. Get first position immediately - so client sees you instantly
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _lat = pos.latitude;
      _lng = pos.longitude;
      await _sendLocation(pos.latitude, pos.longitude);

      // 2. Mark ONLINE in 3 places - client list checks all 3
      await FirebaseDatabase.instance.ref('onlineNurses/$nurseId').set(true);
      await FirebaseDatabase.instance.ref('nursePresence/$nurseId').set({'isOnline': true, 'lastSeen': DateTime.now().millisecondsSinceEpoch});
      await FirebaseDatabase.instance.ref('nurses/$nurseId/isOnline').set(true);
      await FirebaseDatabase.instance.ref('nurses/$nurseId/lat').set(pos.latitude);
      await FirebaseDatabase.instance.ref('nurses/$nurseId/lng').set(pos.longitude);

      // 3. TIMER every 10 sec - THIS MAKES UBER PHOTO MOVE
      _gpsTimer?.cancel();
      _gpsTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
        try {
          final p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
          await _sendLocation(p.latitude, p.longitude);
        } catch (_) {}
      });

      // 4. STREAM - also send immediately when nurse moves (faster than 10 sec)
      _posStream?.cancel();
      _posStream = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)).listen((p) async {
        await _sendLocation(p.latitude, p.longitude);
      });

      if (!mounted) return;
      setState(() { isOnline = true; _gpsText = '🟢 LIVE - Sending GPS every 10 sec\n${_lat?.toStringAsFixed(5)}, ${_lng?.toStringAsFixed(5)}'; });
      if (!silent) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🟢 You are ONLINE - Clients can now see you moving LIVE on map')));
    } catch (e) {
      if (!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GPS failed: $e - Turn ON Location + Internet')));
    }
  }

  Future<void> _sendLocation(double lat, double lng) async {
    if (nurseId.isEmpty) return;
    try {
      _lat = lat;
      _lng = lng;
      // THIS NODE is what client Uber map listens to: nurseLocations/{uid}
      await FirebaseDatabase.instance.ref('nurseLocations/$nurseId').set({
        'lat': lat,
        'lng': lng,
        'latitude': lat,
        'longitude': lng,
        'gpsLat': lat,
        'gpsLng': lng,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'isOnline': true,
      });
      // Also keep nurses/{uid} lat/lng fresh for list sorting
      await FirebaseDatabase.instance.ref('nurses/$nurseId/lat').set(lat);
      await FirebaseDatabase.instance.ref('nurses/$nurseId/lng').set(lng);
      if (mounted) setState(() => _gpsText = '🟢 LIVE - Last sent: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}\n${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}');
    } catch (_) {}
  }

  // ===== GO OFFLINE - STOP SENDING GPS =====
  Future<void> _goOffline() async {
    _gpsTimer?.cancel();
    _posStream?.cancel();
    try {
      await FirebaseDatabase.instance.ref('onlineNurses/$nurseId').remove();
      await FirebaseDatabase.instance.ref('nursePresence/$nurseId').set({'isOnline': false, 'lastSeen': DateTime.now().millisecondsSinceEpoch});
      await FirebaseDatabase.instance.ref('nurses/$nurseId/isOnline').set(false);
      // Keep last location, but mark offline so client hides you
      await FirebaseDatabase.instance.ref('nurseLocations/$nurseId/isOnline').set(false);
    } catch (_) {}
    if (!mounted) return;
    setState(() { isOnline = false; _gpsText = '🔴 OFFLINE - Clients cannot see you'; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🔴 You are OFFLINE')));
  }

  Future<void> _acceptReject(Map b, String status) async {
    final id = b['bookingId'].toString();
    try {
      // Update in all 5 booking locations (same as client save)
      final emailKey = (b['clientEmail'] ?? '').toString().toLowerCase().replaceAll(RegExp(r'[.#\$@\[\]]'), '_');
      await FirebaseDatabase.instance.ref('bookings/$id/status').set(status);
      if (emailKey.isNotEmpty) await FirebaseDatabase.instance.ref('bookingsByClient/$emailKey/$id/status').set(status);
      await FirebaseDatabase.instance.ref('bookingsByNurse/$nurseId/$id/status').set(status);
      await FirebaseDatabase.instance.ref('nurseBookings/$nurseId/$id/status').set(status);
      if (emailKey.isNotEmpty) await FirebaseDatabase.instance.ref('clientBookings/$emailKey/$id/status').set(status);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status == 'accepted' ? '✅ Booking accepted - Go to patient now, your photo will move on client map' : '❌ Booking rejected')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFF0E0A1C), body: Center(child: CircularProgressIndicator(color: Colors.purple)));
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('Nurse Home', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), backgroundColor: const Color(0xFF1A1633), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () { if (isOnline && _lat != null) _sendLocation(_lat!, _lng!); })]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // PROFILE
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              CircleAvatar(radius: 32, backgroundImage: nursePhoto.isNotEmpty ? NetworkImage(nursePhoto) : null, backgroundColor: Colors.purple, child: nursePhoto.isEmpty ? const Text('👩', style: TextStyle(fontSize: 28)) : null),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nurseName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                Text(isOnline ? '🟢 ONLINE - Clients can see you LIVE' : '🔴 OFFLINE - Go ONLINE to get bookings', style: TextStyle(color: isOnline ? Colors.greenAccent : Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_gpsText, style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ])),
            ]),
          ),
          const SizedBox(height: 16),

          // GO ONLINE / OFFLINE - BIG BUTTON
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isOnline ? _goOffline : () => _goOnline(),
              style: ElevatedButton.styleFrom(backgroundColor: isOnline ? Colors.red : const Color(0xFF22C55E), padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: Text(isOnline ? '🔴 GO OFFLINE - Stop Receiving Bookings' : '🟢 GO ONLINE - Start Receiving Bookings', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.withOpacity(0.4))),
            child: const Text('⚠️ For Uber map to move: 1) GO ONLINE  2) Location = ALWAYS (Settings > Location > Allow all the time)  3) Keep Internet ON  4) Do NOT force-close app', textAlign: TextAlign.center, style: TextStyle(color: Colors.amber, fontSize: 12)),
          ),
          const SizedBox(height: 8),
          // TEST MY LOCATION BUTTON
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                try {
                  final p = await Geolocator.getCurrentPosition();
                  await _sendLocation(p.latitude, p.longitude);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('📍 Location sent: ${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)} - Client map will move now')));
                } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GPS failed: $e'))); }
              },
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white30), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('📍 Send My Location Now (Test)', style: TextStyle(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 20),

          // BOOKINGS
          const Text('My Bookings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (myBookings.isEmpty)
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14)), child: const Center(child: Text('No bookings yet.\nGo ONLINE to receive bookings.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60))))
          else
            ...myBookings.map((b) {
              final status = (b['status'] ?? 'pending').toString();
              Color statusColor = status == 'accepted' ? Colors.green : status == 'rejected' ? Colors.red : Colors.orange;
              return Container(
                margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${b['patientName'] ?? b['clientName'] ?? 'Patient'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(20)), child: Text(status.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                  ]),
                  const SizedBox(height: 4),
                  Text('${b['patientLocation'] ?? ''} • ${b['startTime'] ?? ''} - ${b['endTime'] ?? ''} • ${b['careMode'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  Text('${b['currency'] ?? 'GHS'} ${b['amount'] ?? ''} • ${b['paymentType'] ?? ''} • Paid Now: ${b['currency'] ?? 'GHS'} ${b['payNow'] ?? b['amountPaidNow'] ?? ''} • Balance: ${b['currency'] ?? 'GHS'} ${b['payLater'] ?? b['amountBalance'] ?? ''}', style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (status == 'pending')
                    Row(children: [
                      Expanded(child: ElevatedButton(onPressed: () => _acceptReject(b, 'accepted'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('✅ Accept', style: TextStyle(color: Colors.white)))),
                      const SizedBox(width: 8),
                      Expanded(child: ElevatedButton(onPressed: () => _acceptReject(b, 'rejected'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('❌ Reject', style: TextStyle(color: Colors.white)))),
                    ])
                  else if (status == 'accepted')
                    Container(width: double.infinity, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: const Text('✅ Accepted - Go to patient now. Keep app OPEN + Internet ON so your photo moves on client map.', textAlign: TextAlign.center, style: TextStyle(color: Colors.greenAccent, fontSize: 12))),
                ]),
              );
            }),
        ]),
      ),
    );
  }
}
