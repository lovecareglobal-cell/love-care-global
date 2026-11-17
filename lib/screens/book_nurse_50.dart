import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../widget/live_nurse_map.dart';

// BOOK NURSE - 50% PAYMENT + SYSTEM PICK + UBER LIVE MAP
// - System Pick: system picks nearest ONLINE nurse for client
// - Photo + Video sheet: client sees nurse before paying
// - After Continue With Her: LIVE MAP shows blinking photo moving like Uber
// - NO Google Maps API key needed - uses flutter_map / OpenStreetMap
class BookNurse50 extends StatefulWidget {
  final String clientId;
  final String clientName;
  const BookNurse50({super.key, required this.clientId, required this.clientName});

  @override
  State<BookNurse50> createState() => _BookNurse50State();
}

class _BookNurse50State extends State<BookNurse50> {
  List<Map> onlineNurses = [];
  StreamSubscription? _nurseSub;
  double? clientLat;
  double? clientLng;
  String? selectedNurseId;
  String selectedNurseName = '';
  Map? _autoPickedNurse;
  bool _isLoading = true;
  bool _isPicking = false;
  VideoPlayerController? _videoCtrl;

  @override
  void initState() {
    super.initState();
    _getClientLocation();
    _listenOnlineNurses();
  }

  @override
  void dispose() {
    _nurseSub?.cancel();
    _videoCtrl?.dispose();
    super.dispose();
  }

  Future<void> _getClientLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        clientLat = pos.latitude;
        clientLng = pos.longitude;
      });
    } catch (_) {
      // Fallback Accra - client can still book, distance approx
      if (!mounted) return;
      setState(() {
        clientLat = 5.6487;
        clientLng = -0.2198;
      });
    }
  }

  void _listenOnlineNurses() {
    try {
      _nurseSub = FirebaseDatabase.instance.ref('nurses').onValue.listen((e) {
        if (!mounted) return;
        final v = e.snapshot.value;
        if (v is! Map) return;
        List<Map> list = [];
        v.forEach((key, val) {
          if (val is! Map) return;
          // Only ONLINE nurses
          if (val['isOnline'] == true || val['online'] == true || val['status'] == 'online') {
            final m = Map.from(val);
            m['uid'] = key.toString();
            list.add(m);
          }
        });
        setState(() {
          onlineNurses = list;
          _isLoading = false;
        });
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    // Simple approx - good for sorting nearest
    return ((lat1 - lat2).abs() + (lng1 - lng2).abs()) * 111;
  }

  void _systemPick() async {
    if (clientLat == null || clientLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Getting your location... try again in 2 sec')));
      return;
    }
    if (onlineNurses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No nurse ONLINE now. Try again in 5 mins.')));
      return;
    }
    setState(() => _isPicking = true);
    await Future.delayed(const Duration(seconds: 1));

    // Sort by distance - nearest first
    List<Map> sorted = List.from(onlineNurses);
    sorted.sort((a, b) {
      double da = _distanceKm(clientLat!, clientLng!, double.tryParse('${a['lat']}') ?? 0, double.tryParse('${a['lng']}') ?? 0);
      double db = _distanceKm(clientLat!, clientLng!, double.tryParse('${b['lat']}') ?? 0, double.tryParse('${b['lng']}') ?? 0);
      return da.compareTo(db);
    });

    final picked = sorted.first;
    if (!mounted) return;
    setState(() => _isPicking = false);
    _showNurseSheet(picked);
  }

  void _showNurseSheet(Map nurse) {
    final photo = (nurse['photoURL'] ?? nurse['photo'] ?? '').toString();
    final video = (nurse['videoURL'] ?? nurse['video'] ?? '').toString();
    final name = (nurse['name'] ?? nurse['fullName'] ?? 'Nurse').toString();
    final dist = _distanceKm(clientLat!, clientLng!, double.tryParse('${nurse['lat']}') ?? 0, double.tryParse('${nurse['lng']}') ?? 0);

    // Init video if exists
    _videoCtrl?.dispose();
    _videoCtrl = null;
    if (video.isNotEmpty && video.startsWith('http')) {
      _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(video))
        ..initialize().then((_) {
          if (mounted) setState(() {});
          _videoCtrl?.play();
        });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: const BoxDecoration(color: Color(0xFF1C1238), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(children: [
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 14),
            // PHOTO
            CircleAvatar(radius: 62, backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null, backgroundColor: Colors.purple, child: photo.isEmpty ? const Text('👩', style: TextStyle(fontSize: 40)) : null),
            const SizedBox(height: 10),
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            Text('${nurse['specialty'] ?? nurse['category'] ?? 'General Nurse'} • ${dist.toStringAsFixed(1)} km away', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(20)), child: const Text('🟢 ONLINE NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
            const SizedBox(height: 14),
            // VIDEO
            if (_videoCtrl != null && _videoCtrl!.value.isInitialized)
              Container(
                height: 220,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.black),
                clipBehavior: Clip.antiAlias,
                child: Stack(children: [
                  VideoPlayer(_videoCtrl!),
                  Positioned(bottom: 8, right: 8, child: GestureDetector(onTap: () { setState(() { _videoCtrl!.value.isPlaying ? _videoCtrl!.pause() : _videoCtrl!.play(); }); }, child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: Icon(_videoCtrl!.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white)))),
                ]),
              )
            else if (video.isNotEmpty)
              Container(height: 80, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)), child: const Center(child: Text('Loading video...', style: TextStyle(color: Colors.white70)))),
            const SizedBox(height: 14),
            Text('About: ${nurse['bio'] ?? nurse['about'] ?? 'Professional, caring nurse. Verified by Love Care Global.'}', style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Experience: ${nurse['experience'] ?? '2+ years'} • Rating: ⭐ ${nurse['rating'] ?? '4.9'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 18),
            // CONTINUE WITH HER - This is what shows LIVE MAP
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    selectedNurseId = nurse['uid'].toString();
                    selectedNurseName = name;
                    _autoPickedNurse = nurse;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You picked $name - Watch her LIVE on map below 👇')));
                },
                child: const Text('Continue With Her - Pay 50% Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Pick Another Nurse', style: TextStyle(color: Colors.white70))),
          ]),
        ),
      ),
    );
  }

  Future<void> _pay50() async {
    // TODO: Connect your existing Paystack 50% logic here
    // Keep your current paystack function - just call it with selected nurse
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pay 50% for $selectedNurseName - connect your Paystack here')));
  }

  Future<void> _openExternalMap() async {
    if (_autoPickedNurse == null) return;
    final lat = _autoPickedNurse!['lat'];
    final lng = _autoPickedNurse!['lng'];
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0A2E),
      appBar: AppBar(backgroundColor: const Color(0xFF1C1238), title: const Text('Book Nurse - Pay 50%', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), iconTheme: const IconThemeData(color: Colors.white)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.purple))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // HEADER
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Hello ${widget.clientName} 👋', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${onlineNurses.length} nurse(s) ONLINE now near you', style: const TextStyle(color: Colors.greenAccent)),
                    const SizedBox(height: 4),
                    const Text('Pay 50% now, pay balance after nurse arrives. System picks nearest nurse for you.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
                const SizedBox(height: 16),

                // SYSTEM PICK BUTTON
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: _isPicking ? null : _systemPick,
                    child: _isPicking
                        ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)), SizedBox(width: 10), Text('System is picking nearest nurse...', style: TextStyle(color: Colors.white))])
                        : const Text('🎯 SYSTEM PICK - Pick Nearest Nurse For Me', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 12),

                // UBER LIVE MAP - SHOW ONLY WHEN NURSE SELECTED
                if (selectedNurseId != null && clientLat != null && _autoPickedNurse != null)
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      CircleAvatar(radius: 20, backgroundImage: ((_autoPickedNurse!['photoURL'] ?? _autoPickedNurse!['photo'] ?? '').toString().isNotEmpty) ? NetworkImage((_autoPickedNurse!['photoURL'] ?? _autoPickedNurse!['photo'] ?? '').toString()) : null, backgroundColor: Colors.purple, child: ((_autoPickedNurse!['photoURL'] ?? _autoPickedNurse!['photo'] ?? '').toString().isEmpty) ? const Text('👩') : null),
                      const SizedBox(width: 8),
                      Expanded(child: Text('You picked $selectedNurseName - Watch her coming LIVE 👇', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    ]),
                    const SizedBox(height: 10),
                    LiveNurseMap(
                      nurseId: selectedNurseId!,
                      nurseName: selectedNurseName,
                      nursePhoto: (_autoPickedNurse!['photoURL'] ?? _autoPickedNurse!['photo'] ?? '').toString(),
                      clientLat: clientLat!,
                      clientLng: clientLng!,
                      nurseLat: double.tryParse('${_autoPickedNurse!['lat']}') ?? 0,
                      nurseLng: double.tryParse('${_autoPickedNurse!['lng']}') ?? 0,
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: ElevatedButton(onPressed: _pay50, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Pay 50% Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                      const SizedBox(width: 10),
                      Expanded(child: OutlinedButton(onPressed: _openExternalMap, style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white30), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Open in Google Maps', style: TextStyle(color: Colors.white))),
                    ]),
                    const SizedBox(height: 16),
                  ]),

                // ONLINE NURSES LIST - for manual view
                const Text('Online Nurses Near You', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (onlineNurses.isEmpty)
                  Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16)), child: const Center(child: Text('No nurse ONLINE now.\nTry again in 5 mins.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70))))
                else
                  ...onlineNurses.map((n) {
                    final photo = (n['photoURL'] ?? n['photo'] ?? '').toString();
                    final name = (n['name'] ?? n['fullName'] ?? 'Nurse').toString();
                    final dist = _distanceKm(clientLat ?? 0, clientLng ?? 0, double.tryParse('${n['lat']}') ?? 0, double.tryParse('${n['lng']}') ?? 0);
                    final isSelected = selectedNurseId == n['uid'].toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: isSelected ? const Color(0xFF3B1A6B) : const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16), border: Border.all(color: isSelected ? const Color(0xFFA855F7) : Colors.white12)),
                      child: Row(children: [
                        CircleAvatar(radius: 28, backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null, backgroundColor: Colors.purple, child: photo.isEmpty ? const Text('👩', style: TextStyle(fontSize: 22)) : null),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Text('${n['specialty'] ?? 'General Nurse'} • ${dist.toStringAsFixed(1)} km away', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          const Text('🟢 ONLINE', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        ])),
                        ElevatedButton(onPressed: () => _showNurseSheet(n), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('View', style: TextStyle(color: Colors.white))),
                      ]),
                    );
                  }),
              ]),
            ),
    );
  }
}
