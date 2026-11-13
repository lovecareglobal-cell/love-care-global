// lib/widgets/lovecare_widget.dart
// Converted from web/widget.html — LoveCare Widget
// Usage:
//   LoveCareWidget(
//     onBookNurse: () => Navigator.pushNamed(context, '/book-nurse'),
//     onMyBookings: () => Navigator.pushNamed(context, '/my-bookings'),
//     onAlerts: () => Navigator.pushNamed(context, '/alerts'),
//     onSOS: () => Navigator.pushNamed(context, '/sos'),
//   )
//
// Put widget-data.json in web/ (next to index.html) like before.
// On Flutter Web it is fetched from ./widget-data.json.
// For mobile/desktop, add it to pubspec.yaml assets and it falls back to rootBundle.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// ---------- Models — match widget-data.json exactly ----------
class Nurse {
  final String fullName;
  final String photoURL;
  final double rating;
  final double distance;
  final List<String> services;
  final bool isAvailable;
  Nurse({required this.fullName, required this.photoURL, required this.rating, required this.distance, required this.services, required this.isAvailable});
  factory Nurse.fromJson(Map<String, dynamic> j) => Nurse(
    fullName: j['fullName'] ?? '',
    photoURL: j['photoURL'] ?? '',
    rating: (j['rating'] as num? ?? 0).toDouble(),
    distance: (j['distance'] as num? ?? 0).toDouble(),
    services: List<String>.from(j['services'] ?? []),
    isAvailable: j['isAvailable'] ?? false,
  );
}

class AlertItem {
  final String title;
  final String body;
  final bool isRead;
  AlertItem({required this.title, required this.body, required this.isRead});
  factory AlertItem.fromJson(Map<String, dynamic> j) => AlertItem(
    title: j['title'] ?? '',
    body: j['body'] ?? '',
    isRead: j['isRead'] ?? true,
  );
}

class WidgetData {
  final int availableNow;
  final List<Nurse> nearbyNurses;
  final List<AlertItem> alerts;
  WidgetData({required this.availableNow, required this.nearbyNurses, required this.alerts});
  factory WidgetData.fromJson(Map<String, dynamic> j) => WidgetData(
    availableNow: j['stats']?['availableNow'] ?? 0,
    nearbyNurses: (j['nearbyNurses'] as List? ?? []).map((e) => Nurse.fromJson(e)).toList(),
    alerts: (j['alerts'] as List? ?? []).map((e) => AlertItem.fromJson(e)).toList(),
  );
}

Future<WidgetData> fetchWidgetData() async {
  // Web: same file your HTML used — web/widget-data.json
  try {
    final res = await http.get(Uri.parse('widget-data.json'));
    if (res.statusCode == 200) return WidgetData.fromJson(jsonDecode(res.body));
  } catch (_) {}
  // Mobile / fallback: assets/widget-data.json (add to pubspec.yaml)
  try {
    final raw = await rootBundle.loadString('assets/widget-data.json');
    return WidgetData.fromJson(jsonDecode(raw));
  } catch (_) {
    // Same as HTML .catch(()=>{}) — show empty widget, never crash
    return WidgetData(availableNow: 0, nearbyNurses: [], alerts: []);
  }
}

// ---------- Widget — same colours as widget.html ----------
class LoveCareWidget extends StatefulWidget {
  final VoidCallback? onBookNurse;
  final VoidCallback? onMyBookings;
  final VoidCallback? onAlerts;
  final VoidCallback? onSOS;
  const LoveCareWidget({super.key, this.onBookNurse, this.onMyBookings, this.onAlerts, this.onSOS});
  @override
  State<LoveCareWidget> createState() => _LoveCareWidgetState();
}

class _LoveCareWidgetState extends State<LoveCareWidget> {
  late Future<WidgetData> _future;
  @override
  void initState() { super.initState(); _future = fetchWidgetData(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E0A1C), // body background from HTML
      padding: const EdgeInsets.all(12),
      child: FutureBuilder<WidgetData>(
        future: _future,
        builder: (context, snap) {
          final data = snap.data ?? WidgetData(availableNow: 342, nearbyNurses: [], alerts: []);
          final unreadAlert = data.alerts.isNotEmpty && !data.alerts.first.isRead ? data.alerts.first : null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('LOVE CARE GLOBAL', style: TextStyle(color: Color(0xFFF3E8FF), fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('${data.availableNow} nurses available now', style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 12)),
              const SizedBox(height: 8),
              // Card 1 — Nearby Nurses
              _card(
                title: 'Nearby Nurses',
                child: data.nearbyNurses.isEmpty
                  ? const Text('No nurses nearby yet', style: TextStyle(color: Colors.white70, fontSize: 12))
                  : Column(children: data.nearbyNurses.take(3).map(_nurseRow).toList()),
              ),
              // Card 2 — Quick Actions
              _card(
                title: 'Quick Actions',
                child: Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    _actionBtn('📅 Book Nurse', widget.onBookNurse),
                    _actionBtn('📍 My Bookings', widget.onMyBookings),
                    _actionBtn('🔔 Alerts', widget.onAlerts),
                    _actionBtn('🆘 SOS', widget.onSOS),
                  ],
                ),
              ),
              // Card 3 — Alert, hidden unless unread (same as display:none in HTML)
              if (unreadAlert != null)
                _card(
                  title: '',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(unreadAlert.title, style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(unreadAlert.body, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xD91C1238), // rgba(28,18,56,.85)
        border: Border.all(color: const Color(0x1FA855F7)), // rgba(168,85,247,.12)
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 6),
          ],
          child,
        ],
      ),
    );
  }

  Widget _nurseRow(Nurse n) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0x800E0A1C), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: n.photoURL.isNotEmpty ? NetworkImage(n.photoURL) : null,
            // onerror="this.src='./icon-192.png'" in HTML
            onBackgroundImageError: (_, __) {},
            child: n.photoURL.isEmpty ? const Icon(Icons.person, size: 20) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.fullName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('⭐ ${n.rating} • ${n.distance}km • ${n.services.isNotEmpty ? n.services.first : ''}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                Text(
                  n.isAvailable ? '✅ Available' : '⏰ Busy',
                  style: TextStyle(fontSize: 11, color: n.isAvailable ? const Color(0xFF4ADE80) : const Color(0xFFF87171)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, VoidCallback? onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFA855F7),
        foregroundColor: const Color(0xFF1E0A3A),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
      child: Text(label),
    );
  }
}
