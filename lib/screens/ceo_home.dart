import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

// CEO HOME - CONTROL ROOM
// - See: Total Nurses, ONLINE now, Total Bookings, Today's Earnings, Pending Approvals
// - CEO Live Rates: Change GHS / USD hourly rate -> clients see new price instantly (book_nurse.dart listens to config/rates)
// - Approve / Reject new nurses
// - See ALL bookings + who paid FULL / 50% + balance
// - See ALL nurses + force OFFLINE if needed

class CEOHomeScreen extends StatefulWidget {
  const CEOHomeScreen({super.key});
  @override
  State<CEOHomeScreen> createState() => _CEOHomeScreenState();
}

class _CEOHomeScreenState extends State<CEOHomeScreen> {
  bool _isLoading = true;
  int totalNurses = 0;
  int onlineNursesCount = 0;
  int totalBookings = 0;
  int todayBookings = 0;
  int pendingNurses = 0;
  double todayEarnings = 0;
  double totalEarnings = 0;
  double ceoShareToday = 0;
  double rateGHS = 0;
  double rateUSD = 0;
  List<Map> onlineNursesList = [];
  List<Map> allBookings = [];
  List<Map> pendingNurseList = [];
  int _tab = 0; // 0 Dashboard, 1 Nurses, 2 Bookings, 3 Rates, 4 Approvals

  final _ghsCtrl = TextEditingController();
  final _usdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _ghsCtrl.dispose();
    _usdCtrl.dispose();
    super.dispose();
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      // 1. RATES
      final rateSnap = await FirebaseDatabase.instance.ref('config/rates').get();
      if (rateSnap.exists && rateSnap.value is Map) {
        final m = Map.from(rateSnap.value as Map);
        if (m['GHS'] is Map) rateGHS = _asDouble((m['GHS'] as Map)['hourly']);
        else rateGHS = _asDouble(m['GHS']);
        if (m['USD'] is Map) rateUSD = _asDouble((m['USD'] as Map)['hourly']);
        else rateUSD = _asDouble(m['USD']);
        _ghsCtrl.text = rateGHS > 0 ? rateGHS.toStringAsFixed(0) : '';
        _usdCtrl.text = rateUSD > 0 ? rateUSD.toStringAsFixed(0) : '';
      }

      // 2. NURSES + ONLINE
      final nurseSnap = await FirebaseDatabase.instance.ref('nurses').get();
      final onlineSnap = await FirebaseDatabase.instance.ref('onlineNurses').get();
      Set<String> onlineIds = {};
      if (onlineSnap.exists && onlineSnap.value is Map) onlineIds.addAll((onlineSnap.value as Map).keys.map((k) => k.toString()));
      if (onlineSnap.exists && onlineSnap.value is List) { for (final x in onlineSnap.value as List) { if (x != null) onlineIds.add(x.toString()); } }

      List<Map> onList = [];
      if (nurseSnap.exists && nurseSnap.value is Map) {
        final nm = Map.from(nurseSnap.value as Map);
        totalNurses = nm.length;
        for (final e in nm.entries) {
          if (onlineIds.contains(e.key.toString())) {
            if (e.value is Map) {
              final m = Map.from(e.value as Map);
              m['uid'] = e.key.toString();
              onList.add(m);
            }
          }
        }
      }
      onlineNursesCount = onList.length;
      onlineNursesList = onList;

      // 3. BOOKINGS
      final bookSnap = await FirebaseDatabase.instance.ref('bookings').get();
      List<Map> books = [];
      double tot = 0, today = 0, ceoToday = 0;
      int todayCount = 0;
      final now = DateTime.now();
      final startToday = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      if (bookSnap.exists && bookSnap.value is Map) {
        final bm = Map.from(bookSnap.value as Map);
        for (final e in bm.entries) {
          if (e.value is Map) {
            final m = Map.from(e.value as Map);
            m['bookingId'] = e.key.toString();
            books.add(m);
            double paid = _asDouble(m['payNow'] ?? m['amountPaidNow'] ?? m['amount']);
            tot += paid;
            int created = int.tryParse((m['createdAt'] ?? m['time'] ?? 0).toString()) ?? 0;
            if (created >= startToday) {
              today += paid;
              todayCount++;
              ceoToday += paid * 0.2; // CEO 20%
            }
          }
        }
      }
      books.sort((a, b) => (b['createdAt'] ?? b['time'] ?? 0).toString().compareTo((a['createdAt'] ?? a['time'] ?? 0).toString()));
      totalBookings = books.length;
      todayBookings = todayCount;
      totalEarnings = tot;
      todayEarnings = today;
      ceoShareToday = ceoToday;
      allBookings = books;

      // 4. PENDING NURSES - waiting for CEO approval
      final pendSnap = await FirebaseDatabase.instance.ref('pending_nurses').get();
      // Also check Firestore pending via RTDB mirror - if you use Firestore only, this will be 0, use RTDB
      List<Map> pend = [];
      if (pendSnap.exists && pendSnap.value is Map) {
        final pm = Map.from(pendSnap.value as Map);
        for (final e in pm.entries) {
          if (e.value is Map) {
            final m = Map.from(e.value as Map);
            m['uid'] = e.key.toString();
            pend.add(m);
          }
        }
      }
      pendingNurses = pend.length;
      pendingNurseList = pend;

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveRates() async {
    final ghs = double.tryParse(_ghsCtrl.text.trim()) ?? 0;
    final usd = double.tryParse(_usdCtrl.text.trim()) ?? 0;
    if (ghs <= 0 && usd <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter at least one rate')));
      return;
    }
    try {
      // Save to ALL 3 places - book_nurse.dart listens to all 3, so price updates instantly
      final data = {'GHS': {'hourly': ghs}, 'USD': {'hourly': usd}, 'cedis': ghs, 'dollars': usd, 'updatedAt': DateTime.now().millisecondsSinceEpoch};
      await FirebaseDatabase.instance.ref('config/rates').set(data);
      await FirebaseDatabase.instance.ref('ceoPricing').set(data);
      await FirebaseDatabase.instance.ref('pricing').set(data);
      setState(() { rateGHS = ghs; rateUSD = usd; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Rates saved! Clients now see GHS $ghs /hr, USD $usd /hr instantly')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _approveNurse(Map n) async {
    final uid = n['uid'].toString();
    try {
      // Move pending -> nurses + approved_nurses
      await FirebaseDatabase.instance.ref('nurses/$uid').set({...n, 'approved': true, 'approvedAt': DateTime.now().millisecondsSinceEpoch});
      await FirebaseDatabase.instance.ref('approved_nurses/$uid').set({...n, 'approved': true});
      await FirebaseDatabase.instance.ref('pending_nurses/$uid').remove();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Approved ${n['name'] ?? 'Nurse'} - She can now GO ONLINE')));
      _loadAll();
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'))); }
  }

  Future<void> _rejectNurse(Map n) async {
    final uid = n['uid'].toString();
    try {
      await FirebaseDatabase.instance.ref('pending_nurses/$uid').remove();
      await FirebaseDatabase.instance.ref('rejected_nurses/$uid').set({...n, 'rejectedAt': DateTime.now().millisecondsSinceEpoch});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Nurse rejected')));
      _loadAll();
    } catch (_) {}
  }

  Future<void> _forceOffline(Map n) async {
    final uid = n['uid'].toString();
    try {
      await FirebaseDatabase.instance.ref('onlineNurses/$uid').remove();
      await FirebaseDatabase.instance.ref('nurses/$uid/isOnline').set(false);
      await FirebaseDatabase.instance.ref('nurseLocations/$uid/isOnline').set(false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🔴 ${n['name'] ?? 'Nurse'} forced OFFLINE')));
      _loadAll();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFF0E0A1C), body: Center(child: CircularProgressIndicator(color: Colors.purple)));
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(
        title: const Text('CEO Dashboard 👑', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF1A1633),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll), IconButton(icon: const Icon(Icons.logout), onPressed: () async { await FirebaseAuth.instance.signOut(); })],
      ),
      body: _tab == 0 ? _buildDashboard() : _tab == 1 ? _buildNurses() : _tab == 2 ? _buildBookings() : _tab == 3 ? _buildRates() : _buildApprovals(),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1A1633),
        selectedItemColor: const Color(0xFFA855F7),
        unselectedItemColor: Colors.white54,
        currentIndex: _tab,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.medical_services), label: 'Nurses'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Bookings'),
          BottomNavigationBarItem(icon: Icon(Icons.attach_money), label: 'Rates'),
          BottomNavigationBarItem(icon: Icon(Icons.verified), label: 'Approvals'),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, String sub, Color color, IconData icon) {
    return Expanded(child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.4))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 6), Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)]), const SizedBox(height: 6), Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)), Text(sub, style: const TextStyle(color: Colors.white60, fontSize: 11))])));
  }

  Widget _buildDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Welcome CEO 👑', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Today: $todayBookings booking(s) • GHS ${todayEarnings.toStringAsFixed(0)} collected • Your 20%: GHS ${ceoShareToday.toStringAsFixed(0)}', style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Live Rates: GHS $rateGHS /hr • USD $rateUSD /hr', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ])),
        const SizedBox(height: 14),
        Row(children: [_statCard('ONLINE NOW', '$onlineNursesCount', 'of $totalNurses nurses', Colors.green, Icons.circle), const SizedBox(width: 10), _statCard('TODAY', '$todayBookings', 'bookings today', Colors.purple, Icons.calendar_today)]),
        const SizedBox(height: 10),
        Row(children: [_statCard('TODAY EARNINGS', 'GHS ${todayEarnings.toStringAsFixed(0)}', 'Total paid today', Colors.amber, Icons.attach_money), const SizedBox(width: 10), _statCard('TOTAL EARNINGS', 'GHS ${totalEarnings.toStringAsFixed(0)}', '$totalBookings bookings', Colors.blue, Icons.account_balance_wallet)]),
        const SizedBox(height: 10),
        Row(children: [_statCard('YOUR 20% TODAY', 'GHS ${ceoShareToday.toStringAsFixed(0)}', 'CEO share', Colors.greenAccent, Icons.percent), const SizedBox(width: 10), _statCard('PENDING', '$pendingNurses', 'nurses to approve', Colors.orange, Icons.hourglass_top)]),
        const SizedBox(height: 16),
        const Text('🟢 ONLINE Nurses Now', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (onlineNursesList.isEmpty) Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12)), child: const Center(child: Text('No nurse ONLINE now.', style: TextStyle(color: Colors.white60))))
        else ...onlineNursesList.take(5).map((n) => _nurseRow(n)),
        const SizedBox(height: 16),
        const Text('Latest Bookings', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (allBookings.isEmpty) Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12)), child: const Center(child: Text('No bookings yet.', style: TextStyle(color: Colors.white60))))
        else ...allBookings.take(3).map((b) => _bookingRow(b)),
      ]),
    );
  }

  Widget _nurseRow(Map n) {
    final photo = (n['photoURL'] ?? n['photo'] ?? '').toString();
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12)), child: Row(children: [
      CircleAvatar(radius: 24, backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null, backgroundColor: Colors.purple, child: photo.isEmpty ? const Text('👩') : null),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text((n['name'] ?? 'Nurse').toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), Text('${n['specialty'] ?? 'Home Nursing'} • ${n['phone'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 12)), const Text('🟢 ONLINE', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold))])),
      TextButton(onPressed: () => _forceOffline(n), child: const Text('Force Offline', style: TextStyle(color: Colors.red))),
    ]));
  }

  Widget _bookingRow(Map b) {
    final status = (b['status'] ?? 'pending').toString();
    final is50 = (b['paymentType'] ?? '').toString().contains('50');
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text('${b['nurseName'] ?? 'Nurse'} → ${b['patientName'] ?? ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: status == 'accepted' ? Colors.green : Colors.orange, borderRadius: BorderRadius.circular(20)), child: Text(status.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))]),
      const SizedBox(height: 4),
      Text('${b['currency'] ?? 'GHS'} ${_asDouble(b['amount']).toStringAsFixed(2)} Total • ${is50 ? '50% Paystack + 50% Cash' : 'FULL Paystack'} • Paid: ${b['currency'] ?? 'GHS'} ${_asDouble(b['payNow'] ?? b['amountPaidNow']).toStringAsFixed(2)} • Balance: ${b['currency'] ?? 'GHS'} ${_asDouble(b['payLater'] ?? b['amountBalance']).toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
      Text('Client: ${b['clientName'] ?? ''} • ${b['clientPhone'] ?? ''} • ${b['bookingId'] ?? ''}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
    ]));
  }

  Widget _buildNurses() {
    return SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ONLINE Nurses ($onlineNursesCount / $totalNurses)', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      if (onlineNursesList.isEmpty) Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12)), child: const Center(child: Text('No nurse ONLINE now.', style: TextStyle(color: Colors.white60))))
      else ...onlineNursesList.map((n) => _nurseRow(n)),
    ]));
  }

  Widget _buildBookings() {
    return SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('All Bookings ($totalBookings)', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text('Total Collected: GHS ${totalEarnings.toStringAsFixed(2)} • Today: GHS ${todayEarnings.toStringAsFixed(2)}', style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      if (allBookings.isEmpty) Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12)), child: const Center(child: Text('No bookings yet.', style: TextStyle(color: Colors.white60))))
      else ...allBookings.map((b) => _bookingRow(b)),
    ]));
  }

  Widget _buildRates() {
    return SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('CEO Live Rates 👑', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      const Text('Change here -> Client Book Nurse page price changes INSTANTLY. No app update needed.', style: TextStyle(color: Colors.white60, fontSize: 12)),
      const SizedBox(height: 16),
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14)), child: Column(children: [
        TextField(controller: _ghsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '🇬🇭 Ghana - GHS per Hour', border: OutlineInputBorder(), hintText: 'e.g. 50')),
        const SizedBox(height: 12),
        TextField(controller: _usdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '🇺🇸 USA - USD per Hour', border: OutlineInputBorder(), hintText: 'e.g. 15')),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saveRates, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('💾 Save Rates - Update All Clients Instantly', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
      ])),
      const SizedBox(height: 16),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Current Live: GHS $rateGHS /hr • USD $rateUSD /hr', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Example: Client books 9 hrs (08:00-17:00) Daily x1 = 9 hrs x GHS 50 = GHS 450 + Transport 100 = GHS 550 Total. 50% = GHS 275 now, GHS 275 cash later.', style: TextStyle(color: Colors.white70, fontSize: 12)),
      ])),
    ]));
  }

  Widget _buildApprovals() {
    return SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Pending Approvals ($pendingNurses)', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      const Text('Approve -> Nurse can GO ONLINE. Reject -> Nurse cannot book.', style: TextStyle(color: Colors.white60, fontSize: 12)),
      const SizedBox(height: 12),
      if (pendingNurseList.isEmpty) Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12)), child: const Center(child: Text('No pending nurses.\nAll nurses approved ✅', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60))))
      else ...pendingNurseList.map((n) {
        final photo = (n['photoURL'] ?? n['photo'] ?? '').toString();
        return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14)), child: Column(children: [
          Row(children: [
            CircleAvatar(radius: 28, backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null, backgroundColor: Colors.purple, child: photo.isEmpty ? const Text('👩') : null),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text((n['name'] ?? n['fullName'] ?? 'Nurse').toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), Text('${n['specialty'] ?? ''} • ${n['phone'] ?? ''} • ${n['email'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 12))])),
          ]),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: ElevatedButton(onPressed: () => _approveNurse(n), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('✅ Approve', style: TextStyle(color: Colors.white)))), const SizedBox(width: 8), Expanded(child: ElevatedButton(onPressed: () => _rejectNurse(n), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('❌ Reject', style: TextStyle(color: Colors.white))))]),
        ]));
      }),
    ]));
  }
}
