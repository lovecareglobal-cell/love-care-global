import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// LIVE NURSE MAP - Uber style - NO API KEY - NO CRASH
// Nurse photo blinks + moves live as nurse moves
// Uses OpenStreetMap - free, no Google key needed
class LiveNurseMap extends StatefulWidget {
  final String nurseId;
  final String nurseName;
  final String nursePhoto;
  final double clientLat;
  final double clientLng;
  final double nurseLat;
  final double nurseLng;

  const LiveNurseMap({
    super.key,
    required this.nurseId,
    required this.nurseName,
    required this.nursePhoto,
    required this.clientLat,
    required this.clientLng,
    required this.nurseLat,
    required this.nurseLng,
  });

  @override
  State<LiveNurseMap> createState() => _LiveNurseMapState();
}

class _LiveNurseMapState extends State<LiveNurseMap> with SingleTickerProviderStateMixin {
  final MapController _mapCtrl = MapController();
  StreamSubscription? _sub;
  Timer? _blinkTimer;
  late double _nurseLat;
  late double _nurseLng;
  double _distKm = 0;
  bool _blink = true;
  bool _hasMovedOnce = false;

  @override
  void initState() {
    super.initState();
    _nurseLat = widget.nurseLat;
    _nurseLng = widget.nurseLng;
    _calcDist();
    _listenNurseLocation();
    // Blink every 700ms - like Uber LIVE pulse
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      setState(() => _blink = !_blink);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _blinkTimer?.cancel();
    _mapCtrl.dispose();
    super.dispose();
  }

  void _calcDist() {
    // Approx km - for display only, sorting already done in parent
    _distKm = ((_nurseLat - widget.clientLat).abs() + (_nurseLng - widget.clientLng).abs()) * 111;
  }

  void _listenNurseLocation() {
    try {
      // LISTEN LIVE - this is what makes photo MOVE like Uber
      _sub = FirebaseDatabase.instance.ref('nurseLocations/${widget.nurseId}').onValue.listen((e) {
        if (!mounted) return;
        try {
          final v = e.snapshot.value;
          if (v is! Map) return;
          final lat = double.tryParse('${v['lat']}') ?? 0;
          final lng = double.tryParse('${v['lng']}') ?? 0;
          if (lat == 0 || lng == 0) return;
          // If same position, no need rebuild
          if ((lat - _nurseLat).abs() < 0.00001 && (lng - _nurseLng).abs() < 0.00001) return;

          setState(() {
            _nurseLat = lat;
            _nurseLng = lng;
            _calcDist();
          });

          // Move map smoothly to nurse - like Uber follows car
          try {
            _mapCtrl.move(LatLng(lat, lng), _mapCtrl.camera.zoom);
          } catch (_) {}
          _hasMovedOnce = true;
        } catch (_) {}
      }, onError: (_) {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_nurseLat == 0) {
      return Container(
        height: 300,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
        child: const Center(child: Text('Waiting for nurse GPS...\nMake nurse GO ONLINE + Allow Location = Always', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70))),
      );
    }

    final nursePos = LatLng(_nurseLat, _nurseLng);
    final clientPos = LatLng(widget.clientLat, widget.clientLng);

    return Container(
      height: 320,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.5))),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: nursePos,
            initialZoom: 14,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
          ),
          children: [
            // OpenStreetMap tiles - FREE, NO API KEY
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.lovecare.global',
            ),
            // Dotted line nurse -> client
            PolylineLayer(polylines: [
              Polyline(points: [nursePos, clientPos], color: const Color(0xFFA855F7), strokeWidth: 4, pattern: const StrokePattern.dashed(segments: [10, 8])),
            ]),
            MarkerLayer(markers: [
              // CLIENT - Blue pin
              Marker(
                point: clientPos,
                width: 50,
                height: 50,
                child: const Column(children: [
                  Icon(Icons.location_pin, color: Colors.blue, size: 42),
                  Text('YOU', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue)),
                ]),
              ),
              // NURSE - BLINKING PHOTO - THIS MOVES LIKE UBER
              Marker(
                point: nursePos,
                width: 70,
                height: 80,
                child: Column(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 700),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _blink ? Colors.red : Colors.transparent,
                      border: Border.all(color: _blink ? Colors.white : Colors.red, width: 3),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 6)],
                    ),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundImage: widget.nursePhoto.isNotEmpty ? NetworkImage(widget.nursePhoto) : null,
                      backgroundColor: Colors.purple,
                      child: widget.nursePhoto.isEmpty ? const Text('👩', style: TextStyle(fontSize: 20)) : null,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                    child: Text(widget.nurseName.split(' ').first, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
            ]),
          ],
        ),

        // TOP CARD - Always visible, photo + distance live
        Positioned(
          top: 10, left: 10, right: 10,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.78), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Stack(children: [
                CircleAvatar(radius: 22, backgroundImage: widget.nursePhoto.isNotEmpty ? NetworkImage(widget.nursePhoto) : null, backgroundColor: Colors.purple, child: widget.nursePhoto.isEmpty ? const Text('👩') : null),
                Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: _blink ? Colors.greenAccent : Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
              ]),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${widget.nurseName} - 🟢 Coming', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                Text('${_distKm.toStringAsFixed(1)} km away • LIVE - updates every 10 sec', style: const TextStyle(color: Colors.greenAccent, fontSize: 11)),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)), child: const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
            ]),
          ),
        ),

        // BOTTOM - Zoom buttons
        Positioned(
          bottom: 10, right: 10,
          child: Column(children: [
            _zoomBtn(Icons.add, () { try { _mapCtrl.move(_mapCtrl.camera.center, _mapCtrl.camera.zoom + 1); } catch (_) {} }),
            const SizedBox(height: 6),
            _zoomBtn(Icons.remove, () { try { _mapCtrl.move(_mapCtrl.camera.center, _mapCtrl.camera.zoom - 1); } catch (_) {} }),
            const SizedBox(height: 6),
            _zoomBtn(Icons.my_location, () { try { _mapCtrl.move(nursePos, 15); } catch (_) {} }),
          ]),
        ),
      ]),
    );
  }

  Widget _zoomBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(width: 38, height: 38, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)]), child: Icon(icon, size: 20, color: Colors.black87)),
    );
  }
}
