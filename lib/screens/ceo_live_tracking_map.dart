import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// CEO Live Tracking Map - Flutter version of ceo-live-tracking-map.html
/// - Map: Leaflet + OpenStreetMap in HTML (center Accra 5.6037, -0.1870, zoom 11) -> Flutter: flutter_map + OSM tiles, same center/zoom
///   Add to pubspec: flutter_map, latlong2, url_launcher
/// - Loads: bookingPaths bookings / acceptedBookings / activeBookings / ceoBookings / ceoAcceptedBookings / bookingsFull / bookings50 / ceoBookingReceiver / allBookings
///   Only accepted: accepted==true || isAccepted || status accepted/enRoute/arrived/inService || acceptedAt present. Merge by lastUpdate (newer wins).
///   Nurse GPS merge: nurseLocations / nurseLiveLocations / liveNurseLocations / nurseTracking / nurses / tracking -> match by nurseId / nurse.id / nurseName, set nurseLat/nurseLng/lastUpdate
/// - normalizeBooking: statusRaw (status/bookingStatus/trackingStatus, default accepted) -> accepted / enRoute (enroute/en_route) / arrived / inService (inservice/in_service) / completed
///   nurseLat = nurseLat / nurse.lat / liveNurseLat ; nurseLng likewise ; clientLat = clientLat / client.lat / lat ; clientLng likewise
///   hours default 8, bookingType default Full Payment, totalGHS/totalUSD
/// - Distance: Haversine R=6371 (same as HTML calcDistance). ETA: calcETA 30 km/h fallback. calcSpeedETA: real speed from speedHistory (movedKm/timeH, <2km jump, <120 km/h, smoothing 0.7*old+0.3*new)
///   distance<0.3km -> "📍 ARRIVED / CLOSE", speed>3 -> eta = distance/speed*60 min, else eta = distance/25*60 min + "*" (estimated)
/// - Stats: "{total} Active | {accepted} Accepted | {enRoute} En Route" + Total / En Route / In Service / Active
/// - List: search (nurseName+clientName+id) + status filter (all/accepted/enRoute/arrived/inService) + top filter (all/accepted/enRoute/arrived/inService/completed) — same as HTML renderList
///   Card: 👩‍⚕️ nurse -> client, badge ✅ Accepted / 🚗 En Route / 📍 Arrived / 👩‍⚕️ In Service, service • hours • bookingType, ID • last GPS, distance • ETA • speed
/// - Select: centers map on nurse (zoom 14), opens tracking info, shows selected stats "📍 Tracking: {nurse} -> {client} — GPS LIVE"
/// - Tracking Info: Nurse LIVE GPS (lat/lng, speed, ETA, distance, last GPS, updates every 10s) + Client Location (lat/lng, distance/ETA/speed) + Call Nurse (tel:) + SOS -> /sos with {bookingId, nurseName, clientName, nurseLat, nurseLng, clientLat, clientLng, service, status, hours} + Refresh
/// - Map markers: 👩‍⚕️ nurse (pulse) with popup (name, LIVE GPS, ID, lat/lng, speed/ETA/distance, last GPS, SOS link) + client marker + purple route line nurse->client, fitBounds when no selection
/// - Live: attachLiveTracking — bookings / acceptedBookings / activeBookings / ceoBookings / ceoAcceptedBookings onChildChanged -> normalize, update/unshift, re-render, refresh tracking info if selected
/// - Deep link: route args {nurseId, bookingId} from CEO Bookings Progress -> auto-select that booking (same as HTML ?nurseId=&bookingId=)
/// - NO alert buttons — only Sound Settings.

class CEOLiveTrackingMapScreen extends StatefulWidget {
  final Map<String, dynamic>? params;
  const CEOLiveTrackingMapScreen({super.key, this.params});
  @override
  State<CEOLiveTrackingMapScreen> createState() => _CEOLiveTrackingMapScreenState();
}

class _CEOLiveTrackingMapScreenState extends State<CEOLiveTrackingMapScreen> {
  List<Map> activeBookings = [];
  String selectedBookingId = '';
  String searchQuery = '';
  String statusFilter = 'all';
  String currentFilter = 'all';
  final _searchCtrl = TextEditingController();
  final _mapCtrl = MapController();
  Map<String, Map> speedHistory = {};
  bool showSidebar = true;

  @override
  void initState() {
    super.initState();
    final args = widget.params;
    if (args != null) {
      if (args['bookingId'] != null) selectedBookingId = args['bookingId'].toString();
    }
    _loadAllBookings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['bookingId'] != null) {
      selectedBookingId = args['bookingId'].toString();
    }
  }

  double? _calcDistance(double? lat1, double? lon1, double? lat2, double? lon2) {
    if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return null;
    const R = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  Map _calcSpeedETA(String bookingId, double? nurseLat, double? nurseLng, double? clientLat, double? clientLng, int lastUpdate) {
    if (nurseLat == null || nurseLng == null || clientLat == null || clientLng == null) return {'speed': 0, 'eta': '--', 'etaMin': 0, 'distance': null};
    final distance = _calcDistance(nurseLat, nurseLng, clientLat, clientLng);
    double speed = 0;
    final prev = speedHistory[bookingId];
    if (prev != null && prev['lastLat'] != null) {
      final movedKm = _calcDistance(prev['lastLat'], prev['lastLng'], nurseLat, nurseLng) ?? 0;
      final timeH = (lastUpdate - (prev['lastTime'] as int)) / 1000 / 3600;
      if (timeH > 0 && movedKm < 2) {
        final instant = movedKm / timeH;
        if (instant < 120) {
          if (prev['speed'] == null || prev['speed'] == 0) prev['speed'] = instant;
          else prev['speed'] = (prev['speed'] as double) * 0.7 + instant * 0.3;
        }
      }
      speed = (prev['speed'] as double?) ?? 0;
    }
    speedHistory[bookingId] = {'lastLat': nurseLat, 'lastLng': nurseLng, 'lastTime': lastUpdate, 'speed': speed};
    int etaMin = 0; String eta = '--';
    if (distance != null && distance < 0.3) { eta = '📍 ARRIVED / CLOSE'; etaMin = 0; }
    else if (speed > 3 && distance != null) { etaMin = ((distance / speed) * 60).round(); eta = etaMin <= 1 ? '1 min' : '$etaMin min'; }
    else if (distance != null) { etaMin = ((distance / 25) * 60).round(); eta = etaMin <= 1 ? '1 min*' : '$etaMin min*'; }
    return {'speed': speed.round(), 'eta': eta, 'etaMin': etaMin, 'distance': distance};
  }

  Map? _normalizeBooking(String id, Map v) {
    if (v.isEmpty) return null;
    final statusRaw = ((v['status'] ?? v['bookingStatus'] ?? v['trackingStatus'] ?? 'accepted') as String).toLowerCase();
    String status = 'accepted';
    if (statusRaw.contains('enroute') || statusRaw.contains('en_route')) status = 'enRoute';
    else if (statusRaw.contains('arrived')) status = 'arrived';
    else if (statusRaw.contains('inservice') || statusRaw.contains('in_service')) status = 'inService';
    else if (statusRaw.contains('completed')) status = 'completed';
    else if (statusRaw.contains('accepted') || v['accepted'] == true) status = 'accepted';
    final nurseLat = (v['nurseLat'] ?? (v['nurse'] is Map ? (v['nurse'] as Map)['lat'] : null) ?? v['liveNurseLat'])?.toDouble();
    final nurseLng = (v['nurseLng'] ?? (v['nurse'] is Map ? (v['nurse'] as Map)['lng'] : null) ?? v['liveNurseLng'])?.toDouble();
    final clientLat = (v['clientLat'] ?? (v['client'] is Map ? (v['client'] as Map)['lat'] : null) ?? v['lat'])?.toDouble();
    final clientLng = (v['clientLng'] ?? (v['client'] is Map ? (v['client'] as Map)['lng'] : null) ?? v['lng'])?.toDouble();
    final lastUpdate = (v['lastUpdate'] ?? DateTime.now().millisecondsSinceEpoch) as num;
    final live = _calcSpeedETA(id, nurseLat, nurseLng, clientLat, clientLng, lastUpdate.toInt());
    return {'id': id, 'nurseName': v['nurseName'] ?? 'Nurse', 'nursePhone': v['nursePhone'] ?? '', 'nurseId': v['nurseId'] ?? v['nurseUid'] ?? '', 'clientName': v['clientName'] ?? 'Client', 'service': v['service'] ?? 'Nursing Care', 'bookingType': v['bookingType'] ?? 'Full Payment', 'status': status, 'nurseLat': nurseLat, 'nurseLng': nurseLng, 'clientLat': clientLat, 'clientLng': clientLng, 'distance': live['distance'], 'eta': live['eta'], 'speed': live['speed'], 'etaMin': live['etaMin'], 'hours': v['hours'] ?? '8', 'totalGHS': v['totalGHS'] ?? 0, 'totalUSD': v['totalUSD'] ?? 0, 'acceptedAt': v['acceptedAt'] ?? DateTime.now().millisecondsSinceEpoch, 'lastUpdate': lastUpdate, 'raw': v};
  }

  Future<void> _loadAllBookings() async {
    final bookingPaths = ['bookings', 'acceptedBookings', 'activeBookings', 'ceoBookings', 'ceoAcceptedBookings', 'bookingsFull', 'bookings50', 'ceoBookingReceiver', 'allBookings'];
    Map<String, Map> bookingMap = {};
    for (final path in bookingPaths) {
      try {
        final snap = await FirebaseDatabase.instance.ref(path).get();
        if (!snap.exists) continue;
        (snap.value as Map).forEach((k, val) {
          if (val is! Map) return;
          final v = Map<String, dynamic>.from(val);
          final isAccepted = v['accepted'] == true || v['isAccepted'] == true || v['status'] == 'accepted' || v['status'] == 'enRoute' || v['status'] == 'arrived' || v['status'] == 'inService' || v['acceptedAt'] != null;
          if (!isAccepted) return;
          if (!bookingMap.containsKey(k)) bookingMap[k] = v;
          else { final nt = (v['lastUpdate'] ?? 0) as num; final ot = (bookingMap[k]!['lastUpdate'] ?? 0) as num; if (nt >= ot) bookingMap[k] = {...bookingMap[k]!, ...v}; }
        });
      } catch (_) {}
    }
    // Nurse GPS merge
    for (final p in ['nurseLocations', 'nurseLiveLocations', 'liveNurseLocations', 'nurseTracking', 'nurses', 'tracking']) {
      try {
        final snap = await FirebaseDatabase.instance.ref(p).get();
        if (!snap.exists) continue;
        (snap.value as Map).forEach((nurseId, loc) {
          if (loc is! Map) return;
          final l = Map<String, dynamic>.from(loc);
          final lat = (l['lat'] ?? l['latitude'] ?? l['currentLat'] ?? l['liveLat'] ?? l['nurseLat'])?.toDouble();
          final lng = (l['lng'] ?? l['longitude'] ?? l['currentLng'] ?? l['liveLng'] ?? l['nurseLng'])?.toDouble();
          if (lat == null || lng == null) return;
          bookingMap.forEach((bid, b) {
            if (b['nurseId'] == nurseId || (b['nurse'] is Map && (b['nurse'] as Map)['id'] == nurseId) || b['nurseName'] == l['nurseName']) {
              b['nurseLat'] = lat; b['nurseLng'] = lng; b['lastUpdate'] = l['updatedAt'] ?? l['lastUpdate'] ?? DateTime.now().millisecondsSinceEpoch;
            }
          });
        });
      } catch (_) {}
    }
    final list = <Map>[];
    bookingMap.forEach((id, v) { final b = _normalizeBooking(id, v); if (b != null) list.add(b); });
    list.sort((a, b) => ((b['lastUpdate'] ?? 0) as num).compareTo((a['lastUpdate'] ?? 0) as num));
    setState(() => activeBookings = list);
    _attachLiveTracking();
    _toast('✅ CEO Tracking: ${list.length} active — SOS → sos + GPS LIVE');
  }

  void _attachLiveTracking() {
    for (final path in ['bookings', 'acceptedBookings', 'activeBookings', 'ceoBookings', 'ceoAcceptedBookings']) {
      FirebaseDatabase.instance.ref(path).onChildChanged.listen((e) {
        if (!e.snapshot.exists) return;
        final v = Map<String, dynamic>.from(e.snapshot.value as Map);
        final nb = _normalizeBooking(e.snapshot.key!, v);
        if (nb == null) return;
        final idx = activeBookings.indexWhere((b) => b['id'] == e.snapshot.key);
        setState(() {
          if (idx >= 0) activeBookings[idx] = {...activeBookings[idx], ...nb};
          else activeBookings.insert(0, nb);
        });
      });
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _formatTime(dynamic t) {
    if (t == null) return '';
    final d = DateTime.fromMillisecondsSinceEpoch((t as num).toInt());
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
  }

  String _statusText(String s) => s == 'accepted' ? '✅ Accepted' : s == 'enRoute' ? '🚗 En Route' : s == 'arrived' ? '📍 Arrived' : s == 'inService' ? '👩‍⚕️ In Service' : s;

  List<Map> get filtered {
    var list = List<Map>.from(activeBookings);
    if (statusFilter != 'all') list = list.where((b) => b['status'] == statusFilter).toList();
    if (currentFilter != 'all') list = list.where((b) => b['status'] == currentFilter).toList();
    if (searchQuery.isNotEmpty) list = list.where((b) => '${b['nurseName']} ${b['clientName']} ${b['id']}'.toLowerCase().contains(searchQuery)).toList();
    return list;
  }

  void _selectBooking(Map b) {
    setState(() { selectedBookingId = b['id']; showSidebar = false; });
    if (b['nurseLat'] != null && b['nurseLng'] != null) _mapCtrl.move(LatLng(b['nurseLat'], b['nurseLng']), 14);
    _showTrackingInfo(b);
  }

  void _showTrackingInfo(Map b) {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [CircleAvatar(child: Text((b['nurseName'] as String).isNotEmpty ? (b['nurseName'] as String)[0] : 'N')), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${b['nurseName']} → ${b['clientName']} — GPS LIVE from My Job Offer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Text('Booking ID: ${b['id']} • ${b['service']} • ${b['hours']}h', style: const TextStyle(color: Colors.white60, fontSize: 11))])), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: _gpsCard('👩‍⚕️ Nurse LIVE GPS', b['nurseLat'] != null ? '📍 ${b['nurseLat'].toStringAsFixed(5)}, ${b['nurseLng'].toStringAsFixed(5)}\n🏍️ ${b['speed'] ?? 0} km/h • ⏱️ ${b['eta']} • 📏 ${b['distance'] != null ? (b['distance'] as double).toStringAsFixed(1) + ' km' : ''}\n🕒 ${_formatTime(b['lastUpdate'])}\n🛰️ Updates every 10 seconds' : 'Waiting for GPS...', Colors.green)), const SizedBox(width: 8), Expanded(child: _gpsCard('👤 Client Location', b['clientLat'] != null ? '📍 ${b['clientLat'].toStringAsFixed(5)}, ${b['clientLng'].toStringAsFixed(5)}\n📏 ${b['distance'] != null ? (b['distance'] as double).toStringAsFixed(2).toString() + ' km' : ''} • ⏱️ ETA ${b['eta']} • 🏍️ ${b['speed'] ?? 0} km/h' : 'No client location', Colors.blue))]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [
        if ((b['nursePhone'] as String).isNotEmpty) ElevatedButton(onPressed: () => launchUrl(Uri.parse('tel:${b['nursePhone']}')), child: const Text('📞 Call Nurse')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () { Navigator.pop(context); Navigator.pushNamed(context, '/sos', arguments: {'bookingId': b['id'], 'nurseName': b['nurseName'], 'clientName': b['clientName'], 'nurseLat': b['nurseLat'], 'nurseLng': b['nurseLng'], 'clientLat': b['clientLat'], 'clientLng': b['clientLng'], 'service': b['service'], 'status': b['status'], 'hours': b['hours']}); }, child: const Text('🚨 SOS → SOS')),
        OutlinedButton(onPressed: () { Navigator.pop(context); _loadAllBookings(); }, child: const Text('🔄 Refresh')),
      ]),
    ])));
  }

  Widget _gpsCard(String title, String body, Color c) => Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: c.withOpacity(0.08), border: Border.all(color: c.withOpacity(0.3)), borderRadius: BorderRadius.circular(10)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: c, fontSize: 11)), const SizedBox(height: 4), Text(body, style: const TextStyle(fontSize: 11))]));

  @override
  Widget build(BuildContext context) {
    final total = activeBookings.length;
    final enRoute = activeBookings.where((b) => b['status'] == 'enRoute').length;
    final inService = activeBookings.where((b) => b['status'] == 'inService').length;
    final accepted = activeBookings.where((b) => b['status'] == 'accepted').length;
    final selected = activeBookings.firstWhere((b) => b['id'] == selectedBookingId, orElse: () => {});
    final markers = <Marker>[];
    final polylinePoints = <LatLng>[];
    for (final b in activeBookings) {
      if (b['nurseLat'] != null && b['nurseLng'] != null) markers.add(Marker(point: LatLng(b['nurseLat'], b['nurseLng']), width: 44, height: 44, child: GestureDetector(onTap: () => _selectBooking(b), child: const Stack(alignment: Alignment.center, children: [CircleAvatar(radius: 22, backgroundColor: Colors.purple, child: Text('👩‍⚕️', style: TextStyle(fontSize: 20))), Positioned(bottom: 0, right: 0, child: CircleAvatar(radius: 6, backgroundColor: Colors.green))]))));
      if (b['clientLat'] != null && b['clientLng'] != null) markers.add(Marker(point: LatLng(b['clientLat'], b['clientLng']), width: 36, height: 36, child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 36)));
      if (b['nurseLat'] != null && b['nurseLng'] != null && b['clientLat'] != null && b['clientLng'] != null) polylinePoints.addAll([LatLng(b['nurseLat'], b['nurseLng']), LatLng(b['clientLat'], b['clientLng'])]);
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('CEO Live Tracking Map', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 8), child: Row(children: [const CircleAvatar(radius: 5, backgroundColor: Colors.green), const SizedBox(width: 4), Text('$total Active | $accepted Accepted | $enRoute En Route', style: const TextStyle(fontSize: 10))]))), IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings')), IconButton(icon: Icon(showSidebar ? Icons.list : Icons.map), onPressed: () => setState(() => showSidebar = !showSidebar))]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(10), child: Row(children: [
          Expanded(child: TextField(controller: _searchCtrl, decoration: const InputDecoration(hintText: 'Search nurse / client / ID', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), onChanged: (v) => setState(() => searchQuery = v.toLowerCase().trim()))),
          const SizedBox(width: 8),
          DropdownButton<String>(value: statusFilter, items: const [DropdownMenuItem(value: 'all', child: Text('All')), DropdownMenuItem(value: 'accepted', child: Text('Accepted')), DropdownMenuItem(value: 'enRoute', child: Text('En Route')), DropdownMenuItem(value: 'arrived', child: Text('Arrived')), DropdownMenuItem(value: 'inService', child: Text('In Service')), DropdownMenuItem(value: 'completed', child: Text('Completed'))], onChanged: (v) => setState(() => statusFilter = v ?? 'all')),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _loadAllBookings, child: const Text('🔄 Refresh')),
        ])),
        if (selected.isNotEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(10), color: Colors.purple.withOpacity(0.15), child: Text('📍 Tracking: ${selected['nurseName']} → ${selected['clientName']} — GPS LIVE\nStatus: ${selected['status']} • ${selected['distance'] != null ? (selected['distance'] as double).toStringAsFixed(1) + ' km • ⏱️ ' + selected['eta'].toString() + ' • 🏍️ ' + (selected['speed'] ?? 0).toString() + ' km/h' : ''}\nLast GPS: ${_formatTime(selected['lastUpdate'])}', style: const TextStyle(fontSize: 11))),
        Expanded(child: Row(children: [
          if (showSidebar) SizedBox(width: 340, child: Column(children: [
            Padding(padding: const EdgeInsets.all(10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Active: $total • En Route: $enRoute • In Service: $inService', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), TextButton(onPressed: _loadAllBookings, child: const Text('Refresh'))])),
            Expanded(child: filtered.isEmpty ? const Center(child: Text('No active bookings after accept\nWhen client accepts booking, nurse appears here with LIVE GPS', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 12))) : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) { final b = filtered[i]; return InkWell(onTap: () => _selectBooking(b), child: Container(margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: b['id'] == selectedBookingId ? Colors.purple.withOpacity(0.2) : const Color(0xFF1A1633), borderRadius: BorderRadius.circular(14), border: Border.all(color: b['id'] == selectedBookingId ? Colors.purple : Colors.white10)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text('👩‍⚕️ ${b['nurseName']} → ${b['clientName']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(999)), child: Text(_statusText(b['status']), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))]), const SizedBox(height: 4), Text('${b['service']} • ${b['hours']}h • ${b['bookingType']}', style: const TextStyle(color: Colors.white60, fontSize: 11)), Text('ID: ${b['id'].toString().substring(0, b['id'].toString().length > 8 ? 8 : b['id'].toString().length)} • 🕒 ${_formatTime(b['lastUpdate'])}', style: const TextStyle(color: Colors.white60, fontSize: 10)), if (b['distance'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('📏 ${(b['distance'] as double).toStringAsFixed(1)} km • ⏱️ ${b['eta']} • 🏍️ ${b['speed'] ?? 0} km/h', style: const TextStyle(fontSize: 11)))]))); })),
          ])),
          Expanded(child: FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(initialCenter: const LatLng(5.6037, -0.1870), initialZoom: 11),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.lovecareglobal.app'),
              PolylineLayer(polylines: [Polyline(points: polylinePoints, color: Colors.purple, strokeWidth: 3)]),
              MarkerLayer(markers: markers),
            ],
          )),
        ])),
      ]),
    );
  }
}
