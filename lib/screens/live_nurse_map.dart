import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:video_player/video_player.dart';
import 'dart:math' as math;

// LIVE_NURSE_MAP - FIXED VIDEO NOT FOUND BUG
// Problem: Video dey for CEO Registration node, not for nurses node
// Fix: Map now searches nurses + registrations + pendingNurses + applications + documents/uploads
// And does DEEP search - even if video dey inside documents: {video: url}

double _asDouble(dynamic v, [double fb = 0]) {
  if (v == null) return fb;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fb;
}

double _hav(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

String _photoFrom(Map m) {
  for (final k in ['photoURL', 'photo', 'image', 'profilePic', 'avatar', 'photoUrl']) {
    final v = (m[k] ?? '').toString();
    if (v.isNotEmpty && v.startsWith('http')) return v;
  }
  // Deep search for photo inside documents/uploads
  final deep = _deepFind(m, ['photo', 'image']);
  if (deep.isNotEmpty) return deep;
  return '';
}

// ===== DEEP VIDEO SEARCH - THE MAIN FIX =====
String _videoFrom(Map m) {
  // 1. Direct keys - all possible names your registration fit use
  for (final k in ['introVideoUrl', 'introVideo', 'videoUrl', 'video', 'profileVideo', 'profileVideoUrl', 'intro_video', 'nurseVideo', 'intro_video_url', 'videoLink', 'introVideoURL', 'videoURL', 'introUrl', 'selfieVideo']) {
    final v = (m[k] ?? '').toString();
    if (v.isNotEmpty && v.startsWith('http') && (v.contains('.mp4') || v.contains('.mov') || v.contains('.webm') || v.contains('video') || v.contains('blob') || v.contains('firebasestorage') || v.contains('storage'))) return v;
    if (v.isNotEmpty && v.startsWith('http')) return v; // accept any http if key says video
  }
  // 2. Deep search inside nested maps: documents, uploads, files, credentials, attachments
  for (final parent in ['documents', 'uploads', 'files', 'credentials', 'attachments', 'media', 'docs']) {
    if (m[parent] is Map) {
      final sub = Map.from(m[parent] as Map);
      for (final entry in sub.entries) {
        final key = entry.key.toString().toLowerCase();
        final val = entry.value;
        if (key.contains('video')) {
          if (val is String && val.startsWith('http')) return val;
          if (val is Map) {
            for (final v in val.values) { if (v.toString().startsWith('http')) return v.toString(); }
          }
        }
        // If sub-map itself has url + type video
        if (val is Map && val['url'] != null && (key.contains('video') || val['type'].toString().toLowerCase().contains('video'))) return val['url'].toString();
      }
    }
  }
  // 3. Generic deep scan - any string value that looks like video file
  final deep = _deepFindVideo(m);
  if (deep.isNotEmpty) return deep;
  return '';
}

String _deepFind(Map m, List<String> wantKeys) {
  for (final e in m.entries) {
    final k = e.key.toString().toLowerCase();
    final v = e.value;
    if (v is String && v.startsWith('http') && wantKeys.any((w) => k.contains(w))) return v;
    if (v is Map) { final r = _deepFind(Map.from(v), wantKeys); if (r.isNotEmpty) return r; }
  }
  return '';
}

String _deepFindVideo(Map m) {
  for (final e in m.entries) {
    final k = e.key.toString().toLowerCase();
    final v = e.value;
    if (v is String && v.startsWith('http') && (v.contains('.mp4') || v.contains('.mov') || v.contains('.webm') || v.contains('video'))) return v;
    if (v is Map) { final r = _deepFindVideo(Map.from(v)); if (r.isNotEmpty) return r; }
    if (v is List) { for (final item in v) { if (item is Map) { final r = _deepFindVideo(Map.from(item)); if (r.isNotEmpty) return r; } else if (item.toString().startsWith('http') && item.toString().contains('.mp4')) return item.toString(); } }
  }
  return '';
}

String _avatarEmoji(Map n) {
  final g = (n['gender'] ?? n['sex'] ?? '').toString().toLowerCase();
  if (g.contains('female') || g.contains('woman') || g.contains('she')) return '👩';
  if (g.contains('male') || g.contains('man') || g.contains('he')) return '👨';
  return '👩‍⚕️';
}

// ============ 1. SYSTEM PICK SCREEN ============
class LiveNurseMap extends StatefulWidget {
  final double? patientLat;
  final double? patientLng;
  final double? clientLat;
  final double? clientLng;
  final double searchRadiusKm;
  final bool autoPickNearest;
  const LiveNurseMap({super.key, this.patientLat, this.patientLng, this.clientLat, this.clientLng, this.searchRadiusKm = 20, this.autoPickNearest = true});
  @override
  State<LiveNurseMap> createState() => _LiveNurseMapState();
}

class _LiveNurseMapState extends State<LiveNurseMap> {
  final MapController _ctrl = MapController();
  StreamSubscription? _sub;
  Timer? _blinkTimer;
  bool _blink = true;
  List<Map> _nurses = [];
  String? _selectedUid;

  @override
  void initState() {
    super.initState();
    _listenLive();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) { if (mounted) setState(() => _blink = !_blink); });
  }

  @override
  void dispose() { _sub?.cancel(); _blinkTimer?.cancel(); _ctrl.dispose(); super.dispose(); }

  void _listenLive() {
    _sub = FirebaseDatabase.instance.ref('nurseLocations').onValue.listen((e) async {
      try {
        final locMap = e.snapshot.value is Map ? Map.from(e.snapshot.value as Map) : {};
        final ns = await FirebaseDatabase.instance.ref('nurses').get();
        final nursesMap = ns.value is Map ? Map.from(ns.value as Map) : {};

        // ===== FIX: ALSO FETCH CEO REGISTRATION NODES - WHERE KUSI VIDEO DEY =====
        Map<String, Map> regMap = {};
        for (final node in ['registrations', 'nurseRegistrations', 'pendingNurses', 'nurseApplications', 'applications', 'ceoRegistrations', 'registrationCenter', 'nurse_registration', 'users']) {
          try {
            final r = await FirebaseDatabase.instance.ref(node).get();
            if (r.value is Map) {
              final m = Map.from(r.value as Map);
              for (final en in m.entries) {
                final key = en.key.toString();
                if (en.value is Map) regMap[key] = Map.from(en.value as Map);
                // Also handle email-keyed or nested by uid inside
                if (en.value is Map && (en.value as Map)['uid'] != null) {
                  regMap[(en.value as Map)['uid'].toString()] = Map.from(en.value as Map);
                }
              }
            }
          } catch (_) {}
        }

        final onSnap = await FirebaseDatabase.instance.ref('onlineNurses').get();
        final Set<String> online = {};
        if (onSnap.value is Map) online.addAll((onSnap.value as Map).keys.map((k) => k.toString()));
        if (onSnap.value is List) { for (final x in onSnap.value as List) { if (x != null) online.add(x.toString()); } }

        List<Map> list = [];
        for (final entry in locMap.entries) {
          final uid = entry.key.toString();
          if (online.isNotEmpty && !online.contains(uid)) continue;
          if (entry.value is! Map) continue;
          final loc = Map.from(entry.value as Map);
          final lat = _asDouble(loc['lat'] ?? loc['latitude'] ?? loc['gpsLat']);
          final lng = _asDouble(loc['lng'] ?? loc['longitude'] ?? loc['gpsLng']);
          if (lat == 0 && lng == 0) continue;
          final n = nursesMap[uid] is Map ? Map.from(nursesMap[uid] as Map) : <String, dynamic>{};
          final plat = widget.patientLat ?? widget.clientLat ?? 0;
          final plng = widget.patientLng ?? widget.clientLng ?? 0;
          final dist = _hav(plat, plng, lat, lng);
          if (dist > widget.searchRadiusKm) continue;

          // Merge registration data - so video from CEO center go show for client
          Map<String, dynamic> merged = Map<String, dynamic>.from(n);
          // Try match by uid, and also by email / name / phone
          Map? reg;
          if (regMap.containsKey(uid)) reg = regMap[uid];
          if (reg == null) {
            for (final rm in regMap.values) {
              if (rm['email'] != null && n['email'] != null && rm['email'].toString().toLowerCase() == n['email'].toString().toLowerCase()) { reg = rm; break; }
              if (rm['name'] != null && n['name'] != null && rm['name'].toString().toLowerCase() == n['name'].toString().toLowerCase()) { reg = rm; break; }
              if (rm['phone'] != null && n['phone'] != null && rm['phone'].toString() == n['phone'].toString()) { reg = rm; break; }
            }
          }
          if (reg != null) {
            for (final k in reg.keys) {
              if (!merged.containsKey(k) || merged[k] == null || merged[k].toString().isEmpty) merged[k] = reg[k];
            }
            // If nurses node no get video but registration get am, copy am
            final regVideo = _videoFrom(Map.from(reg));
            if (regVideo.isNotEmpty) { merged['introVideoUrl'] = regVideo; merged['videoUrl'] = regVideo; }
            final regPhoto = _photoFrom(Map.from(reg));
            if (regPhoto.isNotEmpty && _photoFrom(merged).isEmpty) merged['photoURL'] = regPhoto;
          }

          list.add({'uid': uid, ...merged, 'lat': lat, 'lng': lng, 'distance': dist});
        }
        list.sort((a, b) => _asDouble(a['distance']).compareTo(_asDouble(b['distance'])));
        if (!mounted) return;
        setState(() { _nurses = list; });
        if (widget.autoPickNearest && _selectedUid == null && list.isNotEmpty) {
          _selectedUid = list.first['uid'].toString();
        }
      } catch (_) {}
    });
  }

  Future<void> _showNurseVideo(Map n) async {
    final nurseName = (n['name'] ?? 'Nurse').toString().trim();
    final photo = _photoFrom(n);
    final videoUrl = _videoFrom(n);
    final bio = (n['bio'] ?? n['about'] ?? n['description'] ?? '').toString();
    final exp = (n['experience'] ?? n['years'] ?? '').toString();
    final rating = _asDouble(n['rating'] ?? n['stars'] ?? 4.8, 4.8);
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NurseVideoDialog(
        nurseName: nurseName, photo: photo, videoUrl: videoUrl, bio: bio, experience: exp, rating: rating, distance: _asDouble(n['distance']),
        onContinue: () { Navigator.pop(ctx); Navigator.pop(context, Map<String, dynamic>.from(n)); },
        onClose: () => Navigator.pop(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plat = widget.patientLat ?? widget.clientLat ?? 5.6487;
    final plng = widget.patientLng ?? widget.clientLng ?? -0.2198;
    final center = LatLng(plat, plng);
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('System Pick - Watch Nurses Moving LIVE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633)),
      body: Column(children: [
        Container(width: double.infinity, padding: const EdgeInsets.all(10), color: const Color(0xFF1C1238), child: Text('🟢 ${_nurses.length} ONLINE nurses moving LIVE • Tap a photo to pick a nurse', textAlign: TextAlign.center, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12))),
        Expanded(
          child: FlutterMap(
            mapController: _ctrl,
            options: MapOptions(initialCenter: center, initialZoom: 13),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.lovecare.global'),
              MarkerLayer(markers: [
                Marker(point: center, width: 60, height: 60, child: const Column(children: [Icon(Icons.location_pin, color: Colors.blue, size: 42), Text('PATIENT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue))])),
                ..._nurses.map((n) {
                  final photo = _photoFrom(n);
                  final isSel = _selectedUid == n['uid'].toString();
                  return Marker(
                    point: LatLng(_asDouble(n['lat']), _asDouble(n['lng'])),
                    width: 72, height: 82,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedUid = n['uid'].toString()),
                      child: Column(children: [
                        AnimatedContainer(duration: const Duration(milliseconds: 700), padding: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, color: _blink ? Colors.red : Colors.transparent, border: Border.all(color: isSel ? Colors.greenAccent : (_blink ? Colors.white : Colors.red), width: 3)), child: CircleAvatar(radius: 24, backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null, backgroundColor: Colors.purple, child: photo.isEmpty ? Text(_avatarEmoji(n), style: const TextStyle(fontSize: 20)) : null)),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)), child: Text('${(n['name'] ?? 'Nurse').toString().split(' ').first} • ${_asDouble(n['distance']).toStringAsFixed(1)}km', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                      ]),
                    ),
                  );
                }),
              ]),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF1C1238),
          child: Column(children: [
            if (_selectedUid != null)
              ..._nurses.where((x) => x['uid'].toString() == _selectedUid).map((n) {
                final nurseName = (n['name'] ?? 'Nurse').toString().trim();
                final hasVideo = _videoFrom(n).isNotEmpty;
                return Row(children: [
                  CircleAvatar(radius: 24, backgroundImage: _photoFrom(n).isNotEmpty ? NetworkImage(_photoFrom(n)) : null, backgroundColor: Colors.purple, child: _photoFrom(n).isEmpty ? Text(_avatarEmoji(n)) : null),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(nurseName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), Text('${_asDouble(n['distance']).toStringAsFixed(1)} km away • 🟢 ONLINE ${hasVideo ? '• 🎬 Video' : '• No Video'}', style: const TextStyle(color: Colors.greenAccent, fontSize: 12))])),
                  const SizedBox(width: 8),
                  Flexible(child: ElevatedButton(onPressed: () => _showNurseVideo(n), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)), child: Text('Continue With Nurse $nurseName', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)))),
                ]);
              }),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () { if (_nurses.length > 1) { final idx = _nurses.indexWhere((x) => x['uid'].toString() == _selectedUid); setState(() => _selectedUid = _nurses[(idx + 1) % _nurses.length]['uid'].toString()); } }, child: const Text('👀 Look At Another One', style: TextStyle(color: Colors.white)))),
          ]),
        ),
      ]),
    );
  }
}

// ============ VIDEO POPUP DIALOG ============
class _NurseVideoDialog extends StatefulWidget {
  final String nurseName; final String photo; final String videoUrl; final String bio; final String experience; final double rating; final double distance; final VoidCallback onContinue; final VoidCallback onClose;
  const _NurseVideoDialog({required this.nurseName, required this.photo, required this.videoUrl, required this.bio, required this.experience, required this.rating, required this.distance, required this.onContinue, required this.onClose});
  @override
  State<_NurseVideoDialog> createState() => _NurseVideoDialogState();
}

class _NurseVideoDialogState extends State<_NurseVideoDialog> {
  VideoPlayerController? _ctrl; bool _isPlaying = false; bool _loadFailed = false;
  @override
  void initState() {
    super.initState();
    if (widget.videoUrl.isNotEmpty) {
      _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
        ..initialize().then((_) { if (!mounted) return; setState(() {}); _ctrl?.play(); setState(() => _isPlaying = true); }).catchError((_) { if (mounted) setState(() => _loadFailed = true); });
    }
  }
  @override
  void dispose() { _ctrl?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final hasVideo = widget.videoUrl.isNotEmpty && !_loadFailed;
    return Dialog(
      backgroundColor: const Color(0xFF1A1633),
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 8, 0), child: Row(children: [CircleAvatar(radius: 22, backgroundImage: widget.photo.isNotEmpty ? NetworkImage(widget.photo) : null, backgroundColor: Colors.purple, child: widget.photo.isEmpty ? const Text('👩‍⚕️') : null), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Meet Nurse ${widget.nurseName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)), Text('⭐ ${widget.rating.toStringAsFixed(1)} • ${widget.distance.toStringAsFixed(1)} km away • 🟢 ONLINE', style: const TextStyle(color: Colors.greenAccent, fontSize: 12))])), IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close, color: Colors.white))])),
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12), height: 280,
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)), clipBehavior: Clip.antiAlias,
            child: hasVideo
                ? Stack(children: [Center(child: _ctrl != null && _ctrl!.value.isInitialized ? AspectRatio(aspectRatio: _ctrl!.value.aspectRatio, child: VideoPlayer(_ctrl!)) : const CircularProgressIndicator(color: Colors.purple)), Positioned.fill(child: GestureDetector(onTap: () { if (_ctrl == null) return; if (_ctrl!.value.isPlaying) { _ctrl!.pause(); setState(() => _isPlaying = false); } else { _ctrl!.play(); setState(() => _isPlaying = true); } }, child: Center(child: !_isPlaying ? Container(padding: const EdgeInsets.all(14), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.play_arrow, color: Colors.white, size: 42)) : const SizedBox()))), Positioned(bottom: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)), child: const Row(children: [Icon(Icons.videocam, color: Colors.red, size: 14), SizedBox(width: 4), Text('INTRO VIDEO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))])) )])
                : Container(width: double.infinity, decoration: BoxDecoration(image: widget.photo.isNotEmpty ? DecorationImage(image: NetworkImage(widget.photo), fit: BoxFit.cover) : null), child: Stack(children: [if (widget.photo.isEmpty) const Center(child: Text('👩‍⚕️', style: TextStyle(fontSize: 80))), Positioned(bottom: 10, left: 0, right: 0, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)), child: Text(widget.videoUrl.isEmpty ? '🎬 No video yet from Nurse ${widget.nurseName}' : '⚠️ Video no load - check internet', style: const TextStyle(color: Colors.white, fontSize: 11)))))])),
          ),
          if (widget.bio.isNotEmpty || widget.experience.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (widget.experience.isNotEmpty) Text('Experience: ${widget.experience}', style: const TextStyle(color: Colors.white70, fontSize: 13)), if (widget.bio.isNotEmpty) ...[const SizedBox(height: 4), Text(widget.bio, style: const TextStyle(color: Colors.white70, fontSize: 13))]])),
          const SizedBox(height: 16),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: double.infinity, child: ElevatedButton(onPressed: widget.onContinue, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text('Continue To Book Nurse ${widget.nurseName} ➜', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))))),
          TextButton(onPressed: widget.onClose, child: const Text('Look At Another Nurse', style: TextStyle(color: Colors.white70))),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }
}

// ============ 2. EMBEDDED UBER MAP ============
class UberLiveMap extends StatefulWidget {
  final String nurseId; final String nurseName; final String nursePhoto; final double patientLat; final double patientLng; final String nurseGender;
  const UberLiveMap({super.key, required this.nurseId, required this.nurseName, required this.nursePhoto, required this.patientLat, required this.patientLng, this.nurseGender = ''});
  @override
  State<UberLiveMap> createState() => _UberLiveMapState();
}

class _UberLiveMapState extends State<UberLiveMap> {
  final MapController _ctrl = MapController(); StreamSubscription? _sub; Timer? _blinkTimer; bool _blink = true; double _nLat = 0, _nLng = 0, _dist = 0;
  @override
  void initState() {
    super.initState();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) { if (mounted) setState(() => _blink = !_blink); });
    _sub = FirebaseDatabase.instance.ref('nurseLocations/${widget.nurseId}').onValue.listen((e) {
      if (!mounted) return; final v = e.snapshot.value; if (v is! Map) return;
      final lat = _asDouble(v['lat'] ?? v['latitude'] ?? v['gpsLat']); final lng = _asDouble(v['lng'] ?? v['longitude'] ?? v['gpsLng']);
      if (lat == 0 || lng == 0) return; if ((lat - _nLat).abs() < 0.00001 && (lng - _nLng).abs() < 0.00001) return;
      setState(() { _nLat = lat; _nLng = lng; _dist = _hav(widget.patientLat, widget.patientLng, lat, lng); });
      try { _ctrl.move(LatLng(lat, lng), _ctrl.camera.zoom); } catch (_) {}
    });
  }
  @override
  void dispose() { _sub?.cancel(); _blinkTimer?.cancel(); _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (_nLat == 0) return Container(height: 120, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)), child: const Center(child: Text('Waiting for nurse GPS... Make nurse GO ONLINE + Location = Always', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12))));
    final nursePos = LatLng(_nLat, _nLng); final patientPos = LatLng(widget.patientLat, widget.patientLng); final genderMap = {'gender': widget.nurseGender};
    return Container(height: 300, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.5))), clipBehavior: Clip.antiAlias, child: Stack(children: [FlutterMap(mapController: _ctrl, options: MapOptions(initialCenter: nursePos, initialZoom: 14), children: [TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.lovecare.global'), PolylineLayer(polylines: [Polyline(points: [nursePos, patientPos], color: const Color(0xFFA855F7), strokeWidth: 4, pattern: StrokePattern.dashed(segments: [10, 8]))]), MarkerLayer(markers: [Marker(point: patientPos, width: 50, height: 50, child: const Column(children: [Icon(Icons.location_pin, color: Colors.blue, size: 42), Text('PATIENT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue))])), Marker(point: nursePos, width: 72, height: 82, child: Column(children: [AnimatedContainer(duration: const Duration(milliseconds: 700), padding: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, color: _blink ? Colors.red : Colors.transparent, border: Border.all(color: _blink ? Colors.white : Colors.red, width: 3)), child: CircleAvatar(radius: 24, backgroundImage: widget.nursePhoto.isNotEmpty ? NetworkImage(widget.nursePhoto) : null, backgroundColor: Colors.purple, child: widget.nursePhoto.isEmpty ? Text(_avatarEmoji(genderMap), style: const TextStyle(fontSize: 20)) : null)), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)), child: Text(widget.nurseName.split(' ').first, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))]))])]), Positioned(top: 10, left: 10, right: 10, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black.withOpacity(0.78), borderRadius: BorderRadius.circular(12)), child: Row(children: [CircleAvatar(radius: 18, backgroundImage: widget.nursePhoto.isNotEmpty ? NetworkImage(widget.nursePhoto) : null, backgroundColor: Colors.purple, child: widget.nursePhoto.isEmpty ? Text(_avatarEmoji(genderMap)) : null), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${widget.nurseName} - 🟢 Coming', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)), Text('${_dist.toStringAsFixed(1)} km away • LIVE', style: const TextStyle(color: Colors.greenAccent, fontSize: 11))])), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)), child: const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)))])))]));
  }
}
