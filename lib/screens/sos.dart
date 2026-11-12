import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

/// SOS Emergency - Flutter version of sos.html
/// - GPS auto-capture on open, fallback Accra 5.6037, -0.1870 if GPS fails (same as HTML)
/// - Saves sos_lat / sos_lng to SharedPreferences
/// - Buttons: Call Police 112, Call Ambulance 193, Find Nearby Police, Open in Google Maps, Share Location (WhatsApp / Share)

class SOSScreen extends StatefulWidget {
  const SOSScreen({super.key});
  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> {
  double? lat, lng, acc;
  String locText = 'Getting location...';
  String accText = '';

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  Future<void> _getLocation() async {
    setState(() => locText = 'Locating...');
    try {
      final perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() { lat = 5.6037; lng = -0.1870; locText = '❌ GPS failed: Permission denied - Using Accra fallback'; });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 10));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('sos_lat', pos.latitude);
      await prefs.setDouble('sos_lng', pos.longitude);
      setState(() {
        lat = pos.latitude; lng = pos.longitude; acc = pos.accuracy;
        locText = '✅ Location captured:\n${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}';
        accText = 'Accuracy: ${acc!.toStringAsFixed(0)}m • ${DateTime.now()} - Ready to open in Google Maps';
      });
    } catch (e) {
      setState(() { lat = 5.6037; lng = -0.1870; locText = '❌ GPS failed: $e - Please enable location'; });
    }
  }

  Future<void> _call(String number) async {
    final url = Uri.parse('tel:$number');
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  Future<void> _findNearbyPolice() async {
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📍 Getting your location first... Allow GPS')));
      await _getLocation();
      await Future.delayed(const Duration(milliseconds: 1500));
    }
    final la = lat ?? 5.6037, lo = lng ?? -0.1870;
    final url = Uri.parse('https://www.google.com/maps/search/police+station+near+me/@$la,$lo,15z');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _openInGoogleMaps() async {
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📍 No GPS yet, opening Accra - Allow location for your exact spot')));
      final url = Uri.parse('https://www.google.com/maps/search/police+station/@5.6037,-0.1870,14z');
      if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
      return;
    }
    final url = Uri.parse('https://www.google.com/maps?q=$lat,$lng&z=16');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _shareLocation() async {
    if (lat == null || lng == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📍 Allow GPS first'))); return; }
    final msg = '🚨 SOS EMERGENCY - LOVE CARE GLOBAL\nI need help! My live location:\nhttps://www.google.com/maps?q=$lat,$lng\nAccuracy: ${acc != null ? acc!.toStringAsFixed(0) + 'm' : ''}\nTime: ${DateTime.now()}\nPolice: 112';
    await Share.share(msg, subject: 'SOS - My Location');
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ SOS location copied! Paste to WhatsApp or SMS')));
  }

  @override
  Widget build(BuildContext context) {
    final locStr = lat != null ? '${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}' : 'No GPS yet';
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('🚨 SOS Emergency', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red.withOpacity(0.22))), child: Column(children: [
            const Text('🚨 SOS EMERGENCY', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 8),
            const Text('Tap a button below to get help fast. Your GPS location is captured automatically.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFA78BFA), fontSize: 12)),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)), child: Column(children: [Text(locText, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)), const SizedBox(height: 6), Text(accText, style: const TextStyle(color: Colors.white60, fontSize: 11))])),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _getLocation, icon: const Icon(Icons.my_location), label: const Text('📍 Refresh GPS Location'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7)))),
          ])),
          const SizedBox(height: 12),
          // Emergency calls
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(children: [
            const Text('📞 Emergency Calls — Ghana', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _callBtn('🚓 Call Police — 112', '112', Colors.red),
            _callBtn('🚑 Call Ambulance — 193', '193', Colors.orange),
            _callBtn('🔥 Call Fire Service — 191', '191', Colors.deepOrange),
            _callBtn('📞 Call CEO — Love Care Global', '+233544121814', const Color(0xFFA855F7)),
          ])),
          const SizedBox(height: 12),
          // Maps + Share
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(children: [
            const Text('📍 Location & Police', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _findNearbyPolice, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), child: const Text('👮 Find Nearby Police Station'))),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _openInGoogleMaps, style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('🗺️ Open My Location in Google Maps'))),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _shareLocation, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)), child: const Text('💬 Share SOS Location — WhatsApp / SMS'))),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => _copyText('🚨 SOS EMERGENCY - LOVE CARE GLOBAL\nI need help! My live location:\nhttps://www.google.com/maps?q=$lat,$lng\nPolice: 112'), child: const Text('📋 Copy SOS Location Text'))),
            const SizedBox(height: 8),
            Text('Location: $locStr', style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ])),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _callBtn(String label, String number, Color color) => Padding(padding: const EdgeInsets.only(bottom: 8), child: SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => _call(number), style: ElevatedButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)))));
}
