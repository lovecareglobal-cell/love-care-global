import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

/// CEO Dashboard - 14 Pages - Flutter version of ceo-dashboard.html
/// - Header: "CEO Dashboard - 14 Pages" + badge "{pending} Refunds" (from ceoRefundManagement where status pending — same as HTML db.ref('ceoRefundManagement').on('value')) + badge "14 Pages" + Home -> '/home' (HTML: index.html)
/// - Info card: "CEO Control - 14 Pages" + "Clean - No duplicate - Chat Room replaced with CEO Notifications - Live Monitoring removed - GHS and USD supported - No emoji - Pure English" — same as HTML
/// - Grid — same as HTML (14 cards, num + title + file + desc):
///   01 CEO Complainant — ceo-complainant.html — Client and nurse complaints -> '/ceo-complainant'
///   02 Control Chat — ceo-control-chat.html — Block and delete nurses -> '/ceo-control-chat'
///   03 CEO Notifications — ceo-notification-room.html — All bookings progress and withdrawals - Replaces chat-room -> '/ceo-notification-room'
///   04 Nurses Group Chat — nurse-group-chat.html — Staff chat in own name -> '/nurse-group-chat'
///   05 Control Pricing — ceo-control-pricing.html — Control pricing live -> '/ceo-control-pricing'
///   06 Finance — ceo-finance.html — Payments and earnings -> '/ceo-finance'
///   07 Live Tracking Map — ceo-live-tracking-map.html — Track nurses GPS live -> '/ceo-live-tracking-map'
///   08 Penalize — ceo-penalize.html — Warn, block, delete account -> '/ceo-penalize'
///   09 Registration Center — ceo-registration-center.html — Approve or reject registrations -> '/ceo-registration-center'
///   10 Refund Management — ceo-refund-management.html — Approve refund requests -> '/ceo-refund-management'
///   11 Delete Nurse — delete-nurse-all-paths.html — Delete by UID, email, phone - All paths -> '/force-delete' (Flutter: force-delete.dart covers delete by email + UID — same tool family; HTML file delete-nurse-all-paths.html was not uploaded)
///   12 Bookings Progress — ceo-bookings-progress.html — All bookings status and date time -> '/ceo-bookings-progress'
///   13 HR Page - GHS and USD — hr-page-GHS-USD.html — Card Global GHS Ghana plus USD outside Ghana -> '/hr-page'
///   14 Home Banner — home-banner-control.html — Control home page banner image and text -> '/home-banner-control' (not yet built — see note below)
/// - Auth: HTML auth.onAuthStateChanged -> signInAnonymously if no user — Flutter: FirebaseAuth.instance.signInAnonymously() if not signed in (add firebase_auth)
/// - NO alert buttons — only Sound Settings.

class CEODashboardScreen extends StatefulWidget {
  const CEODashboardScreen({super.key});
  @override
  State<CEODashboardScreen> createState() => _CEODashboardScreenState();
}

class _CEODashboardScreenState extends State<CEODashboardScreen> {
  int pendingRefunds = 0;

  @override
  void initState() {
    super.initState();
    FirebaseDatabase.instance.ref('ceoRefundManagement').onValue.listen((e) {
      if (!e.snapshot.exists) { setState(() => pendingRefunds = 0); return; }
      final pending = (e.snapshot.value as Map).values.where((r) => r is Map && r['status'] == 'pending').length;
      setState(() => pendingRefunds = pending);
    });
  }

  final List<Map<String, String>> pages = const [
    {'num': '01', 'title': 'CEO Complainant', 'file': 'ceo-complainant.html', 'desc': 'Client and nurse complaints', 'route': '/ceo-complainant'},
    {'num': '02', 'title': 'Control Chat', 'file': 'ceo-control-chat.html', 'desc': 'Block and delete nurses', 'route': '/ceo-control-chat'},
    {'num': '03', 'title': 'CEO Notifications', 'file': 'ceo-notification-room.html', 'desc': 'All bookings progress and withdrawals - Replaces chat-room', 'route': '/ceo-notification-room'},
    {'num': '04', 'title': 'Nurses Group Chat', 'file': 'nurse-group-chat.html', 'desc': 'Staff chat in own name', 'route': '/nurse-group-chat'},
    {'num': '05', 'title': 'Control Pricing', 'file': 'ceo-control-pricing.html', 'desc': 'Control pricing live', 'route': '/ceo-control-pricing'},
    {'num': '06', 'title': 'Finance', 'file': 'ceo-finance.html', 'desc': 'Payments and earnings', 'route': '/ceo-finance'},
    {'num': '07', 'title': 'Live Tracking Map', 'file': 'ceo-live-tracking-map.html', 'desc': 'Track nurses GPS live', 'route': '/ceo-live-tracking-map'},
    {'num': '08', 'title': 'Penalize', 'file': 'ceo-penalize.html', 'desc': 'Warn, block, delete account', 'route': '/ceo-penalize'},
    {'num': '09', 'title': 'Registration Center', 'file': 'ceo-registration-center.html', 'desc': 'Approve or reject registrations', 'route': '/ceo-registration-center'},
    {'num': '10', 'title': 'Refund Management', 'file': 'ceo-refund-management.html', 'desc': 'Approve refund requests', 'route': '/ceo-refund-management'},
    {'num': '11', 'title': 'Delete Nurse', 'file': 'delete-nurse-all-paths.html', 'desc': 'Delete by UID, email, phone - All paths', 'route': '/force-delete'},
    {'num': '12', 'title': 'Bookings Progress', 'file': 'ceo-bookings-progress.html', 'desc': 'All bookings status and date time', 'route': '/ceo-bookings-progress'},
    {'num': '13', 'title': 'HR Page - GHS and USD', 'file': 'hr-page-GHS-USD.html', 'desc': 'Card Global GHS Ghana plus USD outside Ghana', 'route': '/hr-page'},
    {'num': '14', 'title': 'Home Banner', 'file': 'home-banner-control.html', 'desc': 'Control home page banner image and text', 'route': '/home-banner-control'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(title: const Text('CEO Dashboard - 14 Pages', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [
        Center(child: Padding(padding: const EdgeInsets.only(right: 8), child: Chip(label: Text('$pendingRefunds Refunds', style: const TextStyle(fontSize: 10)), backgroundColor: Colors.white10))),
        const Center(child: Padding(padding: EdgeInsets.only(right: 8), child: Chip(label: Text('14 Pages', style: TextStyle(fontSize: 10, color: Color(0xFFFACC15))), backgroundColor: Color(0x14FACC15)))),
        IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings')),
        TextButton(onPressed: () => Navigator.pushNamed(context, '/home'), child: const Text('Home', style: TextStyle(color: Colors.white, fontSize: 11))),
      ]),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
        Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CEO Control - 14 Pages', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          Text('Clean - No duplicate - Chat Room replaced with CEO Notifications - Live Monitoring removed - GHS and USD supported - No emoji - Pure English', style: TextStyle(fontSize: 11, color: Color(0xFF9A95B8))),
        ])),
        const SizedBox(height: 16),
        GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.1, crossAxisSpacing: 14, mainAxisSpacing: 14), itemCount: pages.length, itemBuilder: (_, i) {
          final p = pages[i];
          return InkWell(onTap: () => Navigator.pushNamed(context, p['route']!), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(16), border: Border.all(color: p['num'] == '03' ? Colors.purple.withOpacity(0.25) : p['num'] == '12' ? Colors.green.withOpacity(0.2) : p['num'] == '13' ? Colors.yellow.withOpacity(0.25) : Colors.white10)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)), child: Center(child: Text(p['num']!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF9A95B8))))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['num']!, style: const TextStyle(fontSize: 10, color: Color(0xFF9A95B8), fontWeight: FontWeight.bold)),
              Text(p['title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 2),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black26, border: Border.all(color: Colors.white10), borderRadius: BorderRadius.circular(999)), child: Text(p['file']!, style: const TextStyle(fontSize: 10, color: Color(0xFF9A95B8), fontFamily: 'monospace'))),
              const SizedBox(height: 6),
              Text(p['desc']!, style: const TextStyle(fontSize: 11, color: Color(0xFF9A95B8))),
            ])),
          ])));
        }),
      ])),
    );
  }
}
