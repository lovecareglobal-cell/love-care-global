
// live_nurse_map.dart - LIVE BLINKING NURSES MAP - NO GOOGLE MAPS SDK - CANNOT CRASH LIKE BEFORE
// Uses OpenStreetMap tiles via flutter_map 8.2.1 (already in your pubspec) - no Google key needed.
// Shows ONLINE nurses as pulsing / blinking dots, updates live as they move.
// Open from Book Nurse with: Navigator.push(context, MaterialPageRoute(builder: (_) => LiveNurseMap(clientLat: clientLat, clientLng: clientLng)));
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class LiveNurseMap extends StatefulWidget {
  final double? clientLat;
  final double? clientLng;
  const LiveNurseMap({super.key, this.clientLat, this.clientLng});
  @override
  State<LiveNurseMap> createState() => _LiveNurseMapState();
}

class _LiveNurseMapState extends State<LiveNurseMap> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  MapController? _mapCtrl;
  List<Map<String, dynamic>> _nurses = [];
  StreamSubscription? _sub;

  double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
  String _s(dynamic v) => v == null ? '' : v.toString();

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
    _mapCtrl = MapController();
    // LIVE STREAM: whenever a nurse goes ONLINE/OFFLINE or moves, this fires - markers move automatically
    _sub = FirebaseFirestore.instance.collection('nurses').where('isOnline', isEqualTo: true).snapshots().listen((snap) {
      if (!mounted) return;
      final list = snap.docs.map((d) {
        final m = d.data();
        m['uid'] = d.id;
        return m;
      }).where((m) => _d(m['lat']) != 0 && _d(m['lng']) != 0).toList();
      setState(() => _nurses = list);
    }, onError: (_) {});
  }

  @override
  void dispose() { _pulse.dispose(); _sub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cLat = widget.clientLat ?? 5.64867;
    final cLng = widget.clientLng ?? -0.21984;
    return Scaffold(
      backgroundColor: const Color(0xFF2A0A2E),
      appBar: AppBar(backgroundColor: const Color(0xFF4A0E4F), title: Text('Live Nurses - ${_nurses.length} ONLINE', style: const TextStyle(color: Colors.white)), leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context))),
      body: Column(children: [
        Container(width: double.infinity, padding: const EdgeInsets.all(10), color: const Color(0xFF4A0E4F), child: Row(children: [
          Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text('🟢 Blinking = ONLINE nurse. If nurse moves, dot moves live.', style: const TextStyle(color: Colors.white, fontSize: 13))),
          TextButton(onPressed: () { _mapCtrl?.move(LatLng(cLat, cLng), 15); }, child: const Text('My Location', style: TextStyle(color: Colors.yellow))),
        ])),
        Expanded(child: FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(initialCenter: LatLng(cLat, cLng), initialZoom: 14, maxZoom: 18, minZoom: 5),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.lovecare.global'),
            MarkerLayer(markers: [
              // YOU - blue dot
              Marker(point: LatLng(cLat, cLng), width: 50, height: 50, child: Column(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(10)), child: const Text('YOU', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))), const Icon(Icons.location_on, color: Colors.blue, size: 32)])),
              // NURSES - blinking / pulsing dots
              ..._nurses.map((n) => Marker(
                point: LatLng(_d(n['lat']), _d(n['lng'])),
                width: 90, height: 90,
                child: GestureDetector(
                  onTap: () => showDialog(context: context, builder: (_) => AlertDialog(backgroundColor: const Color(0xFF2A0A2E), title: Text(_s(n['name']).isEmpty ? 'Nurse' : _s(n['name']), style: const TextStyle(color: Colors.white)), content: Text('${_s(n['category'])} • ${_s(n['locationText'])}\nTap Book Nurse to book this nurse.', style: const TextStyle(color: Colors.white70)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))])),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)), child: Text(_s(n['name']).isEmpty ? 'Nurse' : _s(n['name']), overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                    AnimatedBuilder(animation: _pulse, builder: (_, __) {
                      final scale = 1.0 + (_pulse.value * 0.6);
                      final opacity = 1.0 - (_pulse.value * 0.7);
                      return Stack(alignment: Alignment.center, children: [
                        Container(width: 44 * scale, height: 44 * scale, decoration: BoxDecoration(color: Colors.green.withOpacity(opacity * 0.4), shape: BoxShape.circle)),
                        CircleAvatar(radius: 18, backgroundColor: Colors.green, backgroundImage: (_s(n['photoUrl']).isNotEmpty) ? NetworkImage(_s(n['photoUrl'])) : null, child: (_s(n['photoUrl']).isEmpty) ? const Icon(Icons.person, color: Colors.white) : null),
                        Positioned(top: 0, right: 0, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)))),
                      ]);
                    }),
                  ]),
                ),
              )).toList(),
            ]),
          ],
        )),
        Container(padding: const EdgeInsets.all(10), child: Text('Showing ${_nurses.length} ONLINE nurse(s) near you. Dots update automatically when nurse moves or goes online/offline.', style: const TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.center)),
      ]),
    );
  }
}
