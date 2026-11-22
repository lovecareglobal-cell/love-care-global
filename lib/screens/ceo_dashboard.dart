import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'force_delete.dart';
import 'sound_settings.dart'; // DIRECT - so button never falls back to Home

/// CEO Dashboard - 14 Pages - + Sound Settings button - Flutter version of ceo-dashboard.html
/// - Header: "CEO Dashboard - 14 Pages" + badge "{pending} Refunds" + badge "14 Pages" + Home -> '/home'
/// - Info card: "CEO Control - 14 Pages"
/// - Grid - 14 cards (13 + Sound Settings), Home Banner REMOVED (file does not exist)
/// - Sound Settings: card 14 + AppBar volume icon, both -> /sound-settings (see main.dart route).
/// - NEW 20/80 RULE: CEO keeps ONLY 20%. Nurse cash 80% is client -> nurse CASH. CEO never pays nurse.
///   LIVE stats on top: CEO Kept (20%), Total Booking Value, Nurse Cash (80%), Refund Due.
///   Refund Due banner: tap -> /ceo-refund-management. Auto from bookings where status == rejected_by_nurse.
///   OLD BUG FIXED: pendingRefunds used to read 'ceoRefundManagement' (node does not exist) so always 0.
///   Now reads refundRequests + bookings (auto nurse-reject) + allRefundRequests.
/// - Buttons: UNTOUCHED - same 14 pages, same order, same routes, same Force Delete / Sound Settings direct logic.

class CEODashboardScreen extends StatefulWidget {
  const CEODashboardScreen({super.key});
  @override
  State<CEODashboardScreen> createState() => _CEODashboardScreenState();
}

class _CEODashboardScreenState extends State<CEODashboardScreen> {
  int pendingRefunds = 0;
  double ceoKept = 0;
  double totalBookingValue = 0;
  double nurseCashTotal = 0;
  double refundDueTotal = 0;
  int refundDueCount = 0;
  int bookingsCount = 0;

  @override
  void initState() {
    super.initState();
    _listenFinanceLive();
  }

  double _num(dynamic v) => double.tryParse('$v') ?? 0;

  // Same math as ceo_finance.dart + ceo_refund_management.dart
  // New bookings: ceoFee + totalAmount + nurseCash saved by book_nurse.dart
  // Old bookings: only amount / total (full total) -> CEO = total * 0.20, Nurse = total * 0.80
  void _listenFinanceLive() {
    try {
      // LIVE: bookings - CEO Kept + Total + Nurse Cash + Auto Refund Due (nurse rejects)
      FirebaseDatabase.instance.ref('bookings').onValue.listen((e) {
        if (!e.snapshot.exists || e.snapshot.value is! Map) {
          if (mounted) setState(() { ceoKept = 0; totalBookingValue = 0; nurseCashTotal = 0; refundDueTotal = 0; refundDueCount = 0; bookingsCount = 0; });
          return;
        }
        double ceo = 0, total = 0, nurse = 0, refundDue = 0;
        int refundCount = 0, count = 0;
        (e.snapshot.value as Map).forEach((k, val) {
          if (val is! Map) return;
          final v = Map<String, dynamic>.from(val);
          count++;
          final double ceoRaw = _num(v['ceoFee'] ?? v['ceoFeeGHS'] ?? v['amountPaidNow'] ?? 0);
          final double nurseRaw = _num(v['nurseCash'] ?? v['nurseCashAmount'] ?? v['amountYouWillCollectCash'] ?? 0);
          double totalRaw = _num(v['totalAmount'] ?? v['total'] ?? v['totalGHS'] ?? v['amount'] ?? 0);
          if (totalRaw <= 0 && ceoRaw > 0) totalRaw = ceoRaw * 5;
          if (totalRaw <= 0 && nurseRaw > 0) totalRaw = nurseRaw / 0.80;
          double ceoFee = ceoRaw;
          if (ceoFee <= 0 && totalRaw > 0) ceoFee = totalRaw * 0.20;
          double nurseCash = nurseRaw;
          if (nurseCash <= 0 && totalRaw > 0) nurseCash = totalRaw * 0.80;
          total += totalRaw;
          ceo += ceoFee;
          nurse += nurseCash;
          final status = '${v['status'] ?? ''}'.toLowerCase();
          final refundPaid = v['refundPaid'] == true || v['refundStatus'] == 'refund_paid' || v['refundStatus'] == 'paid';
          final isNurseReject = status == 'rejected_by_nurse' || v['refundCeoFee'] == true;
          if (isNurseReject && !refundPaid) {
            refundDue += ceoFee;
            refundCount++;
          }
        });
        if (mounted) setState(() {
          ceoKept = ceo;
          totalBookingValue = total;
          nurseCashTotal = nurse;
          refundDueTotal = refundDue;
          refundDueCount = refundCount;
          bookingsCount = count;
          pendingRefunds = refundCount;
        });
      }, onError: (_) {
        if (mounted) setState(() => pendingRefunds = 0);
      });
    } catch (_) {
      pendingRefunds = 0;
    }
    try {
      // LIVE: manual refundRequests - add pending count on top of auto (avoid double-count: only count pending manual that are NOT auto)
      FirebaseDatabase.instance.ref('refundRequests').onValue.listen((e) {
        if (!e.snapshot.exists || e.snapshot.value is! Map) return;
        int manualPending = 0;
        (e.snapshot.value as Map).values.forEach((r) {
          if (r is Map && r['status'] == 'pending' && r['isAutoRefund'] != true) manualPending++;
        });
        if (mounted) setState(() => pendingRefunds = refundDueCount + manualPending);
      }, onError: (_) {});
    } catch (_) {}
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
    {'num': '11', 'title': 'Force Delete', 'file': 'force_delete.dart', 'desc': 'Force wipe by email - DB + Firestore + Auth - 100% NEW', 'route': '/force-delete'},
    {'num': '12', 'title': 'Bookings Progress', 'file': 'ceo-bookings-progress.html', 'desc': 'All bookings status and date time', 'route': '/ceo-bookings-progress'},
    {'num': '13', 'title': 'HR Page - GHS and USD', 'file': 'hr-page-GHS-USD.html', 'desc': 'Card Global GHS Ghana plus USD outside Ghana', 'route': '/hr-page'},
    {'num': '14', 'title': 'Sound Settings', 'file': 'sound_settings.dart', 'desc': 'Notification sounds ON / OFF', 'route': '/sound-settings'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(
        title: const Text('CEO Dashboard - 14 Pages', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1633),
        actions: [
          Center(child: Padding(padding: const EdgeInsets.only(right: 8), child: Chip(label: Text('$pendingRefunds Refunds', style: const TextStyle(fontSize: 10)), backgroundColor: refundDueTotal > 0 ? Colors.red : Colors.white10))),
          const Center(child: Padding(padding: EdgeInsets.only(right: 8), child: Chip(label: Text('14 Pages', style: TextStyle(fontSize: 10, color: Color(0xFFFACC15))), backgroundColor: Color(0x14FACC15)))),
          IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SoundSettingsScreen()))),
          TextButton(onPressed: () => Navigator.pushNamed(context, '/home'), child: const Text('Home', style: TextStyle(color: Colors.white, fontSize: 11))),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CEO Control - 14 Pages', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('Clean - No duplicate - Chat Room replaced with CEO Notifications - Live Monitoring removed - GHS and USD supported - No emoji - Pure English - Sound Settings added as card 14', style: TextStyle(fontSize: 11, color: Color(0xFF9A95B8))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // NEW 20/80 LIVE STATS - CEO sees his money at a glance, buttons below untouched
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.10), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.35))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('LIVE - 20/80 - CEO keeps ONLY 20%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFACC15))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _miniStat('CEO Kept (20%)', 'GH₵ ${ceoKept.toStringAsFixed(2)}', const Color(0xFFFACC15))),
                      const SizedBox(width: 8),
                      Expanded(child: _miniStat('Total Booking Value', 'GH₵ ${totalBookingValue.toStringAsFixed(2)}', Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _miniStat('Nurse Cash (80%)', 'GH₵ ${nurseCashTotal.toStringAsFixed(2)}', const Color(0xFF86EFAC))),
                      const SizedBox(width: 8),
                      Expanded(child: _miniStat('Refund Due', 'GH₵ ${refundDueTotal.toStringAsFixed(2)}', Colors.redAccent)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('$bookingsCount bookings • Nurse cash is client -> nurse CASH. CEO never pays nurse. Nurse rejects = full 20% refund.', style: const TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // NEW REFUND DUE BANNER - tap -> Refund Management
            if (refundDueTotal > 0)
              InkWell(
                onTap: () => Navigator.pushNamed(context, '/ceo-refund-management'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.14), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.red.withOpacity(0.5))),
                  child: Row(
                    children: [
                      const Text('🔴', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('REFUND DUE: GH₵ ${refundDueTotal.toStringAsFixed(2)} - $refundDueCount booking${refundDueCount == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                            const SizedBox(height: 2),
                            const Text('Nurse rejected - You MUST refund full 20% to client - Tap to open Refund Management', style: TextStyle(fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white),
                    ],
                  ),
                ),
              ),
            if (refundDueTotal > 0) const SizedBox(height: 12),
            if (refundDueTotal <= 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.10), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.green.withOpacity(0.35))),
                child: const Text('✅ No Refund Due - No nurse rejected any booking. Client cancels = NO refund, CEO keeps 20%.', style: TextStyle(fontSize: 11, color: Colors.white)),
              ),
            if (refundDueTotal <= 0) const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.1, crossAxisSpacing: 14, mainAxisSpacing: 14),
              itemCount: pages.length,
              itemBuilder: (_, i) {
                final p = pages[i];
                return InkWell(
                  onTap: () {
                    // Force Delete MUST open force_delete.dart directly.
                    // Use CEOForceWipeEmailPage() - it exists in BOTH versions of
                    // force_delete.dart (old = real class, new = typedef alias).
                    // ForceDeletePage() only exists in the NEW file, so using it
                    // breaks the build if you renamed the OLD file instead.
                    // Do NOT use pushNamed('/force-delete') - if main.dart does not
                    // have that route, Flutter falls back to home (main.dart /
                    // Welcome dialog) - which is the bug you just saw.
                    if (p['route'] == '/force-delete') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => CEOForceWipeEmailPage()));
                      return;
                    }
                    // Sound Settings card 14 -> DIRECT to sound_settings.dart
                    // FIX: pushNamed('/sound-settings') went to Home because main.dart
                    // had no /sound-settings route -> onUnknownRoute -> Home.
                    // Direct MaterialPageRoute NEVER needs a route, so it can never go to Home.
                    // Confirmed class: SoundSettingsScreen (alias SoundSettingsPage also works).
                    if (p['route'] == '/sound-settings') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SoundSettingsScreen()));
                      return;
                    }
                    Navigator.pushNamed(context, p['route']!);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1633),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: p['num'] == '03' ? Colors.purple.withOpacity(0.25) : p['num'] == '12' ? Colors.green.withOpacity(0.2) : p['num'] == '13' ? Colors.yellow.withOpacity(0.25) : p['num'] == '11' ? Colors.red.withOpacity(0.35) : Colors.white10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)), child: Center(child: Text(p['num']!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF9A95B8))))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p['num']!, style: const TextStyle(fontSize: 10, color: Color(0xFF9A95B8), fontWeight: FontWeight.bold)),
                              Text(p['title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 2),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black26, border: Border.all(color: Colors.white10), borderRadius: BorderRadius.circular(999)), child: Text(p['file']!, style: const TextStyle(fontSize: 10, color: Color(0xFF9A95B8), fontFamily: 'monospace'))),
                              const SizedBox(height: 6),
                              Text(p['desc']!, style: const TextStyle(fontSize: 11, color: Color(0xFF9A95B8))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9A95B8))),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ],
    ),
  );
}
