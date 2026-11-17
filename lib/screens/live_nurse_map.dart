
// lib/screens/live_nurse_map.dart
// LIVE MAP - Only ONLINE nurses CLOSE to PATIENT (within 20km), photo BLINKING, moves LIVE
// Tap a nurse photo -> Bottom sheet shows her REGISTRATION PHOTO + VIDEO, then SELECT her.
// Uses OpenStreetMap (flutter_map) - no Google SDK, no crash. Works with RTDB + Firestore.
// Nurse dashboard already sends GPS every 10s + on 10m move -> dot moves live.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

class LiveNurseMap extends StatefulWidget {
  final double? patientLat;
  final double? patientLng;
  final double? clientLat;
  final double? clientLng;
  final double searchRadiusKm; // default 20km - only close nurses
  final bool autoPickNearest; // true = system picks nearest nurse for client automatically
  const LiveNurseMap({super.key, this.patientLat, this.patientLng, this.clientLat, this.clientLng, this.searchRadiusKm = 20, this.autoPickNearest = false});
  @override
  State<LiveNurseMap> createState() => _LiveNurseMapState();
}

class _LiveNurseMapState extends State<LiveNurseMap> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  final MapController _mapCtrl = MapController();
  List<Map<String, dynamic>> _closeNurses = [];
  List<Map<String, dynamic>> _allOnline = [];
  StreamSubscription? _fsSub;
  StreamSubscription? _rtdbSub;
  bool _loading = true;
  int _currentIndex = 0; // which nurse system is showing now
  bool _autoSheetShown = false;

  double _d(dynamic v) { if (v == null) return 0; if (v is num) return v.toDouble(); return double.tryParse(v.toString()) ?? 0; }
  String _s(dynamic v) => v == null ? '' : v.toString();
  double _distKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; final dLat = (lat2 - lat1) * math.pi / 180; final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat/2)*math.sin(dLat/2) + math.cos(lat1*math.pi/180)*math.cos(lat2*math.pi/180)*math.sin(dLon/2)*math.sin(dLon/2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1-a));
  }
  String _photoOf(Map m) => _s(m['photoUrl']).isNotEmpty ? _s(m['photoUrl']) : _s(m['photo']).isNotEmpty ? _s(m['photo']) : _s(m['photoURL']).isNotEmpty ? _s(m['photoURL']) : _s(m['profilePhoto']).isNotEmpty ? _s(m['profilePhoto']) : _s(m['imageUrl']);
  // Video uploaded during nurse registration - try every possible key
  String _videoOf(Map m) {
    for (final k in ['videoUrl','videoURL','video','introVideoUrl','introVideo','registrationVideoUrl','registrationVideo','nurseVideoUrl','nurseVideo','profileVideoUrl','profileVideo']) {
      if (_s(m[k]).isNotEmpty) return _s(m[k]);
    }
    return '';
  }
  String _nameOf(Map m) => _s(m['name']).isNotEmpty ? _s(m['name']) : _s(m['fullName']).isNotEmpty ? _s(m['fullName']) : _s(m['displayName']).isNotEmpty ? _s(m['displayName']) : 'Nurse';
  String _specOf(Map m) => _s(m['specialty']).isNotEmpty ? _s(m['specialty']) : _s(m['specialtyType']).isNotEmpty ? _s(m['specialtyType']) : _s(m['category']).isNotEmpty ? _s(m['category']) : 'General Nursing';

  double get _pLat => widget.patientLat ?? widget.clientLat ?? 5.64871;
  double get _pLng => widget.patientLng ?? widget.clientLng ?? -0.21984;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _listenLive();
  }
  @override
  void dispose() { _pulse.dispose(); _fsSub?.cancel(); _rtdbSub?.cancel(); super.dispose(); }

  void _listenLive() {
    // 1) Firestore - nurse_dashboard writes here every 10s while ONLINE
    _fsSub = FirebaseFirestore.instance.collection('nurses').where('isOnline', isEqualTo: true).snapshots().listen((snap) {
      _mergeFirestore(snap.docs.map((d){ final m = Map<String,dynamic>.from(d.data()); m['uid']=d.id; return m; }).toList());
    }, onError: (_) {});
    // 2) RTDB - fallback / older nurses: liveNurseLocations + onlineNurses
    _rtdbSub = FirebaseDatabase.instance.ref('liveNurseLocations').onValue.listen((e) {
      if (!e.snapshot.exists) return;
      final map = Map<String,dynamic>.from(e.snapshot.value as Map);
      final list = map.entries.map((en){ final m = Map<String,dynamic>.from(en.value as Map); m['uid']=en.key; return m; }).toList();
      _mergeRtdb(list);
    });
  }

  // Keep ONE list: Firestore is primary, RTDB fills gaps (nurse with no Firestore doc yet)
  final Map<String, Map<String,dynamic>> _byUid = {};
  void _applyFilter() {
    final out = <Map<String,dynamic>>[];
    for (final m in _byUid.values) {
      final lat = _d(m['lat']) != 0 ? _d(m['lat']) : _d(m['latitude']);
      final lng = _d(m['lng']) != 0 ? _d(m['lng']) : _d(m['longitude']);
      if (lat == 0 || lng == 0) continue;
      final dist = _distKm(_pLat, _pLng, lat, lng);
      // ONLY CLOSE NURSES - within radius of PATIENT live place
      if (dist > widget.searchRadiusKm) continue;
      out.add({...m, 'lat': lat, 'lng': lng, 'distance': dist});
    }
    out.sort((a,b) => (_d(a['distance'])).compareTo(_d(b['distance'])));
    if (!mounted) return;
    final wasEmpty = _closeNurses.isEmpty;
    setState(() { _closeNurses = out; _allOnline = _byUid.values.toList(); _loading = false; });
    // SYSTEM AUTO-PICK: when list first loads, system shows NEAREST nurse automatically
    // Client does NOT have to hunt on map - system does it for him
    if (widget.autoPickNearest && !_autoSheetShown && out.isNotEmpty) {
      _autoSheetShown = true;
      _currentIndex = 0;
      // Wait for map to build, then open nearest nurse sheet
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _closeNurses.isNotEmpty) _showNurseSheet(_closeNurses[0], showAutoBanner: true);
      });
    }
    // If nurse list changed and current index out of range, clamp it
    if (_currentIndex >= _closeNurses.length) _currentIndex = 0;
  }
  void _mergeFirestore(List<Map<String,dynamic>> list) {
    for (final m in list) { final uid = _s(m['uid']); if (uid.isEmpty) continue; _byUid[uid] = {...?_byUid[uid], ...m}; }
    _applyFilter();
  }
  void _mergeRtdb(List<Map<String,dynamic>> list) {
    for (final m in list) { final uid = _s(m['uid']); if (uid.isEmpty) continue; if (_byUid.containsKey(uid)) continue; _byUid[uid] = m; }
    _applyFilter();
  }

  // ===== SYSTEM PICK / TAP NURSE -> PHOTO + VIDEO SHEET =====
  // Client watches photo + video, then decides:
  //   [Continue with this nurse] -> returns this nurse to Book Nurse
  //   [Look at Another One] -> closes sheet, opens NEXT nearest nurse
  void _showNextNurse() {
    if (_closeNurses.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _closeNurses.length;
    _showNurseSheet(_closeNurses[_currentIndex], showAutoBanner: true);
  }
  void _showNurseSheet(Map<String,dynamic> n, {bool showAutoBanner = false}) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF1C1238),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NurseProfileSheet(
        nurse: n, photo: _photoOf(n), video: _videoOf(n), name: _nameOf(n), spec: _specOf(n), distance: _d(n['distance']),
        position: _closeNurses.indexWhere((x) => _s(x['uid']) == _s(n['uid'])) + 1, // 1st, 2nd, 3rd...
        totalClose: _closeNurses.length,
        showAutoBanner: showAutoBanner,
        onSelect: () { Navigator.pop(context); Navigator.pop(context, n); }, // Continue with this nurse -> Book Nurse
        onNext: () { Navigator.pop(context); Future.delayed(const Duration(milliseconds: 250), () { if (mounted) _showNextNurse(); }); }, // Look at another one -> next nearest
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A0A2E),
      appBar: AppBar(backgroundColor: const Color(0xFF4A0E4F),
        title: Text('Live Nurses Near Patient - ${_closeNurses.length} close', style: const TextStyle(color: Colors.white, fontSize: 15)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context))),
      body: Column(children: [
        Container(width: double.infinity, padding: const EdgeInsets.all(10), color: const Color(0xFF4A0E4F),
          child: Row(children: [
            Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text('🟢 Blinking photo = ONLINE + CLOSE to patient (within ${widget.searchRadiusKm.toInt()}km). Photo moves live when nurse moves. Tap photo to watch video + photo.', style: const TextStyle(color: Colors.white, fontSize: 12))),
            TextButton(onPressed: () => _mapCtrl.move(LatLng(_pLat, _pLng), 14), child: const Text('Patient', style: TextStyle(color: Colors.yellow))),
          ])),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator(color: Colors.white)) : FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(initialCenter: LatLng(_pLat, _pLng), initialZoom: 13, maxZoom: 18, minZoom: 5),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.lovecare.global'),
            // Patient pin - BLUE
            MarkerLayer(markers: [
              Marker(point: LatLng(_pLat, _pLng), width: 70, height: 70,
                child: Column(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(10)), child: const Text('PATIENT', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))), const Icon(Icons.location_on, color: Colors.blue, size: 36)])),
              // Close ONLINE nurses - BLINKING PHOTO, MOVES LIVE
              ..._closeNurses.map((n) => Marker(
                point: LatLng(_d(n['lat']), _d(n['lng'])),
                width: 120, height: 115,
                child: GestureDetector(
                  onTap: () { _currentIndex = _closeNurses.indexWhere((x) => _s(x['uid']) == _s(n['uid'])); if (_currentIndex < 0) _currentIndex = 0; _showNurseSheet(n); },
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                      child: Text('${_nameOf(n)} • ${_d(n['distance']).toStringAsFixed(1)} km', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                    AnimatedBuilder(animation: _pulse, builder: (_, __) {
                      final scale = 1.0 + (_pulse.value * 0.55);
                      final opacity = 1.0 - (_pulse.value * 0.65);
                      return Stack(alignment: Alignment.center, children: [
                        Container(width: 52 * scale, height: 52 * scale, decoration: BoxDecoration(color: Colors.green.withOpacity(opacity * 0.45), shape: BoxShape.circle)),
                        Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
                          child: ClipOval(child: _photoOf(n).isNotEmpty ? Image.network(_photoOf(n), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white)) : const Icon(Icons.person, color: Colors.white))),
                        Positioned(top: 0, right: 2, child: Container(width: 11, height: 11, decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)))),
                        if (_videoOf(n).isNotEmpty) Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle), child: const Icon(Icons.play_arrow, color: Colors.white, size: 12))),
                      ]);
                    }),
                  ]),
                ),
              )).toList(),
            ]),
          ],
        )),
        // SYSTEM PICK BAR - one tap, system shows nearest nurse for you
        Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), color: const Color(0xFF1C1238),
          child: Row(children: [
            Expanded(child: Text(_closeNurses.isEmpty ? 'System is looking for nearby ONLINE nurses...' : 'System found ${_closeNurses.length} nearby nurse(s). Nearest: ${_nameOf(_closeNurses.first)} - ${_d(_closeNurses.first['distance']).toStringAsFixed(1)} km', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: () { if (_closeNurses.isEmpty) return; _currentIndex = 0; _showNurseSheet(_closeNurses[0], showAutoBanner: true); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7)), child: const Text('🤖 System Pick For Me', style: TextStyle(color: Colors.white, fontSize: 12))),
          ])),
        Container(padding: const EdgeInsets.all(10),
          child: _closeNurses.isEmpty
            ? Text('No ONLINE nurse within ${widget.searchRadiusKm.toInt()}km of patient yet. ${_allOnline.length} online far away - hidden. Try again in a minute or increase radius.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12))
            : Text('Showing ${_closeNurses.length} ONLINE nurse(s) CLOSE to patient. Nearest: ${_nameOf(_closeNurses.first)} - ${_d(_closeNurses.first['distance']).toStringAsFixed(1)} km away. Tap photo to watch video.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12))),
        // Quick list - also tap to watch video + select
        if (_closeNurses.isNotEmpty) Container(height: 92, padding: const EdgeInsets.only(bottom: 8),
          child: ListView(scrollDirection: Axis.horizontal, children: _closeNurses.map((n) => GestureDetector(onTap: () { _currentIndex = _closeNurses.indexWhere((x) => _s(x['uid']) == _s(n['uid'])); if (_currentIndex < 0) _currentIndex = 0; _showNurseSheet(n); },
            child: Container(width: 210, margin: const EdgeInsets.only(left: 10), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                ClipOval(child: _photoOf(n).isNotEmpty ? Image.network(_photoOf(n), width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person)) : const Icon(Icons.person))),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_nameOf(n), overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  Text('${_specOf(n)} • ${_d(n['distance']).toStringAsFixed(1)} km', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  Text(_videoOf(n).isNotEmpty ? '▶️ Tap to watch video + photo' : '📷 Tap to see photo', style: const TextStyle(color: Colors.yellow, fontSize: 11)),
                ])),
              ])))).toList())),
      ]),
    );
  }
}

// ===== NURSE PROFILE SHEET - REGISTRATION PHOTO + VIDEO =====
class _NurseProfileSheet extends StatefulWidget {
  final Map<String,dynamic> nurse; final String photo; final String video; final String name; final String spec; final double distance; final VoidCallback onSelect; final VoidCallback onNext;
  final int position; final int totalClose; final bool showAutoBanner;
  const _NurseProfileSheet({required this.nurse, required this.photo, required this.video, required this.name, required this.spec, required this.distance, required this.onSelect, required this.onNext, this.position = 1, this.totalClose = 1, this.showAutoBanner = false});
  @override State<_NurseProfileSheet> createState() => _NurseProfileSheetState();
}
class _NurseProfileSheetState extends State<_NurseProfileSheet> {
  VideoPlayerController? _videoCtrl;
  bool _videoFailed = false;
  @override void initState() { super.initState(); _initVideo(); }
  Future<void> _initVideo() async {
    if (widget.video.isEmpty) return;
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.video));
      await c.initialize();
      if (!mounted) return;
      setState(() => _videoCtrl = c);
    } catch (_) { if (mounted) setState(() => _videoFailed = true); }
  }
  @override void dispose() { _videoCtrl?.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final n = widget.nurse;
    final phone = (n['phone'] ?? '').toString();
    final place = (n['placeName'] ?? n['location'] ?? '').toString();
    final rating = (n['rating'] ?? 5).toString();
    return DraggableScrollableSheet(initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
      builder: (_, ctrl) => SingleChildScrollView(controller: ctrl, padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
          const SizedBox(height: 12),
          if (widget.showAutoBanner) Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFA855F7).withOpacity(0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFA855F7))),
            child: Text('🤖 System picked this nurse for you - Nearest to patient (${widget.position} of ${widget.totalClose} nearby). Watch her photo + video, then decide: Continue with her OR look at another one.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
          if (widget.showAutoBanner) const SizedBox(height: 10),
          Text('Nurse ${widget.position} of ${widget.totalClose} nearby', style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 6),
          Row(children: [
            // BIG REGISTRATION PHOTO
            GestureDetector(onTap: () { if (widget.photo.isNotEmpty) showDialog(context: context, builder: (_) => Dialog(backgroundColor: Colors.black, child: Image.network(widget.photo))); },
              child: Container(width: 92, height: 92, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.green, width: 3)),
                child: ClipOval(child: widget.photo.isNotEmpty ? Image.network(widget.photo, fit: BoxFit.cover) : const Icon(Icons.person, size: 50, color: Colors.white)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              Text('${widget.spec} • ${widget.distance.toStringAsFixed(1)} km from patient', style: const TextStyle(color: Colors.white70)),
              Text('⭐ $rating • Verified ✅ • 🟢 ONLINE NOW', style: const TextStyle(color: Colors.greenAccent)),
              if (place.isNotEmpty) Text('📍 $place', style: const TextStyle(color: Colors.white60, fontSize: 12)),
              if (phone.isNotEmpty) Text('📞 $phone', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ])),
          ]),
          const SizedBox(height: 16),
          const Text('📷 Photo she uploaded during registration', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          GestureDetector(onTap: () { if (widget.photo.isNotEmpty) showDialog(context: context, builder: (_) => Dialog(backgroundColor: Colors.black, child: Image.network(widget.photo))); },
            child: ClipRRect(borderRadius: BorderRadius.circular(14), child: widget.photo.isNotEmpty ? Image.network(widget.photo, height: 220, width: double.infinity, fit: BoxFit.cover) : Container(height: 140, color: Colors.white10, child: const Center(child: Text('No photo uploaded', style: TextStyle(color: Colors.white60)))))),
          const SizedBox(height: 6),
          const Text('Tap photo to view full size', style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 16),
          const Text('🎥 Video she uploaded during registration', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (widget.video.isEmpty)
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)), child: const Text('No video uploaded during registration for this nurse.', style: TextStyle(color: Colors.white70)))
          else if (_videoCtrl == null && !_videoFailed)
            Container(height: 220, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)), child: const Center(child: CircularProgressIndicator(color: Colors.white)))
          else if (_videoCtrl != null)
            Column(children: [
              ClipRRect(borderRadius: BorderRadius.circular(14), child: AspectRatio(aspectRatio: _videoCtrl!.value.aspectRatio, child: VideoPlayer(_videoCtrl!))),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: ElevatedButton.icon(onPressed: () { setState(() { _videoCtrl!.value.isPlaying ? _videoCtrl!.pause() : _videoCtrl!.play(); }); }, icon: Icon(_videoCtrl!.value.isPlaying ? Icons.pause : Icons.play_arrow), label: Text(_videoCtrl!.value.isPlaying ? 'Pause Video' : '▶️ Play Video'))),
                const SizedBox(width: 8),
                IconButton(onPressed: () async { final uri = Uri.parse(widget.video); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }, icon: const Icon(Icons.open_in_new, color: Colors.white), tooltip: 'Open video outside'),
              ]),
            ])
          else
            ElevatedButton.icon(onPressed: () async { final uri = Uri.parse(widget.video); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }, icon: const Icon(Icons.play_arrow), label: const Text('▶️ Open Video Outside App')),
          const SizedBox(height: 20),
          // DECIDE: Continue with her OR Look at another one
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: widget.onSelect, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), padding: const EdgeInsets.symmetric(vertical: 16)), child: Text('✅ Continue With ${widget.name}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15)))),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: OutlinedButton(onPressed: widget.onNext, style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: Colors.white54)), child: Text(widget.totalClose > 1 ? '👀 Look At Another One (${widget.position} of ${widget.totalClose}) - See Next Nurse' : '👀 Look At Another One - No More Nearby Nurses', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)))),
          const SizedBox(height: 8),
          const Text('Continue = back to Book Nurse with her already selected, then choose 50% Paystack + Cash OR Full Payment.\nAnother One = watch next nearest nurse\'s photo + video.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 20),
        ])),
    );
  }
}
