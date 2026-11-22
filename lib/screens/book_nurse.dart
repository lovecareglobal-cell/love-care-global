import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Book Nurse - 20/80 RULE
/// Client pays ONLY 20% CEO fee in app to book.
/// Nurse cash 80% is paid CASH by client to nurse AFTER work.
/// CEO NEVER pays nurse. 50% DELETED. Increase Payment DELETED.

class BookNurseScreen extends StatefulWidget {
  const BookNurseScreen({super.key});
  @override
  State<BookNurseScreen> createState() => _BookNurseScreenState();
}

class _BookNurseScreenState extends State<BookNurseScreen> {
  List<Map<String, dynamic>> nurses = [];
  Map<String, dynamic>? selectedNurse;
  bool isLoading = true;
  String search = '';
  String selectedService = 'General Nursing';
  int days = 1;
  double hrsPerDay = 8;
  String clientName = '';
  String clientPhone = '';
  String clientEmail = '';
  String clientLocation = '';
  String clientUid = '';

  final List<String> services = [
    'General Nursing',
    'Elderly Care',
    'Post-Surgery Care',
    'Baby / Child Care',
    'Wound Care',
    'Physiotherapy Support',
    'Night Nurse',
  ];

  @override
  void initState() {
    super.initState();
    _loadClient();
    _loadNurses();
  }

  Future<void> _loadClient() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;
      clientUid = user?.uid ?? prefs.getString('lcg_client_uid') ?? prefs.getString('clientUid') ?? '';
      clientName = prefs.getString('clientName') ?? prefs.getString('fullName') ?? user?.displayName ?? 'Client';
      clientPhone = prefs.getString('clientPhone') ?? prefs.getString('phone') ?? '';
      clientEmail = prefs.getString('clientEmail') ?? prefs.getString('email') ?? user?.email ?? '';
      clientLocation = prefs.getString('clientLocation') ?? prefs.getString('placeName') ?? prefs.getString('location') ?? 'Accra, Ghana';
      if (clientUid.isNotEmpty) {
        try {
          final doc = await FirebaseFirestore.instance.collection('clients').doc(clientUid).get();
          if (doc.exists && doc.data() != null) {
            final d = doc.data()!;
            if ((d['fullName'] ?? '').toString().isNotEmpty) clientName = d['fullName'].toString();
            if ((d['phone'] ?? '').toString().isNotEmpty) clientPhone = d['phone'].toString();
            if ((d['email'] ?? '').toString().isNotEmpty) clientEmail = d['email'].toString();
            if ((d['location'] ?? '').toString().isNotEmpty) clientLocation = d['location'].toString();
          }
        } catch (_) {}
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _loadNurses() {
    FirebaseDatabase.instance.ref('onlineNurses').onValue.listen((e) {
      if (!e.snapshot.exists || e.snapshot.value is! Map) {
        if (mounted) setState(() { nurses = []; isLoading = false; });
        return;
      }
      final map = e.snapshot.value as Map;
      final list = <Map<String, dynamic>>[];
      map.forEach((k, val) {
        if (val is! Map) return;
        final v = Map<String, dynamic>.from(val);
        final isOnline = v['isOnline'] == true || v['online'] == true;
        final isAvailable = v['isAvailable'] != false && v['isBooked'] != true && v['isBusy'] != true;
        if (!isOnline) return;
        if (!isAvailable) return;
        list.add({...v, 'id': k.toString()});
      });
      list.sort((a, b) => (a['fullName'] ?? a['name'] ?? '').toString().compareTo((b['fullName'] ?? b['name'] ?? '').toString()));
      if (mounted) setState(() { nurses = list; isLoading = false; });
    }, onError: (_) {
      if (mounted) setState(() => isLoading = false);
    });
    // Fallback: also check nurses node if onlineNurses is empty
    FirebaseDatabase.instance.ref('nurses').onValue.listen((e) {
      if (nurses.isNotEmpty) return;
      if (!e.snapshot.exists || e.snapshot.value is! Map) return;
      final map = e.snapshot.value as Map;
      final list = <Map<String, dynamic>>[];
      map.forEach((k, val) {
        if (val is! Map) return;
        final v = Map<String, dynamic>.from(val);
        final isOnline = v['isOnline'] == true || v['online'] == true;
        final isAvailable = v['isAvailable'] != false && v['isBooked'] != true && v['isBusy'] != true;
        if (!isOnline || !isAvailable) return;
        list.add({...v, 'id': k.toString()});
      });
      if (list.isNotEmpty && mounted) setState(() => nurses = list);
    });
  }

  double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  double _ratePerHour(Map<String, dynamic> n) {
    double r = _num(n['ratePerHour'] ?? n['hourlyRate'] ?? n['pricePerHour'] ?? n['rate'] ?? 0);
    if (r > 0) return r;
    double d = _num(n['dailyRate'] ?? n['ratePerDay'] ?? 0);
    if (d > 0) return d / 8;
    return 50;
  }

  Map<String, double> _calc(Map<String, dynamic> n) {
    final rate = _ratePerHour(n);
    final total = rate * hrsPerDay * days;
    final ceoFee = total * 0.20;
    final nurseCash = total * 0.80;
    return {
      'ratePerHour': rate,
      'totalAmount': total,
      'total': total,
      'ceoFee': ceoFee,
      'nurseCash': nurseCash,
      'hrsPerDay': hrsPerDay,
      'days': days.toDouble(),
    };
  }

  List<Map<String, dynamic>> get filtered {
    var list = List<Map<String, dynamic>>.from(nurses);
    if (search.trim().isNotEmpty) {
      final q = search.toLowerCase();
      list = list.where((n) {
        final name = '${n['fullName'] ?? n['name'] ?? ''}'.toLowerCase();
        final spec = '${n['specialty'] ?? ''}'.toLowerCase();
        final loc = '${n['placeName'] ?? n['location'] ?? ''}'.toLowerCase();
        return name.contains(q) || spec.contains(q) || loc.contains(q);
      }).toList();
    }
    return list;
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _bookNurse() async {
    if (selectedNurse == null) {
      _toast('Select a nurse first');
      return;
    }
    final n = selectedNurse!;
    final calc = _calc(n);
    final now = DateTime.now().millisecondsSinceEpoch;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Booking - 20% Only'),
        content: Text(
          'Nurse: ${n['fullName'] ?? n['name'] ?? 'Nurse'}\n'
          'Service: $selectedService\n'
          'Days: $days • ${hrsPerDay.toStringAsFixed(1)} hrs/day\n\n'
          'Total Booking: GHS ${calc['totalAmount']!.toStringAsFixed(2)}\n'
          'You Pay Now (20% CEO Fee): GHS ${calc['ceoFee']!.toStringAsFixed(2)}\n'
          'You Pay Nurse CASH Later (80%): GHS ${calc['nurseCash']!.toStringAsFixed(2)}\n\n'
          'If nurse rejects, you get FULL 20% refund.\n'
          'If you cancel, CEO keeps 20%.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Pay 20% & Book')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final ref = FirebaseDatabase.instance.ref('bookings').push();
      final bookingId = ref.key ?? 'BK$now';
      final data = <String, dynamic>{
        'bookingId': bookingId,
        'id': bookingId,
        'status': 'pending',
        'createdAt': now,
        'time': now,
        'clientUid': clientUid,
        'clientId': clientUid,
        'clientName': clientName,
        'clientPhone': clientPhone,
        'clientEmail': clientEmail,
        'clientLocation': clientLocation,
        'location': clientLocation,
        'nurseId': n['id'],
        'selectedNurseId': n['id'],
        'nurseName': n['fullName'] ?? n['name'] ?? 'Nurse',
        'nursePhone': n['phone'] ?? '',
        'nurseEmail': n['email'] ?? '',
        'nursePhoto': n['photoUrl'] ?? n['photo'] ?? '',
        'service': selectedService,
        'serviceType': selectedService,
        'days': days,
        'hrsPerDay': hrsPerDay,
        'hours': hrsPerDay * days,
        'ratePerHour': calc['ratePerHour'],
        'amount': calc['totalAmount'],
        'totalAmount': calc['totalAmount'],
        'total': calc['totalAmount'],
        'totalGHS': calc['totalAmount'],
        'ceoFee': calc['ceoFee'],
        'ceoFeeGHS': calc['ceoFee'],
        'amountPaidNow': calc['ceoFee'],
        'payNow': calc['ceoFee'],
        'nurseCash': calc['nurseCash'],
        'nurseCashAmount': calc['nurseCash'],
        'amountYouWillCollectCash': calc['nurseCash'],
        'currency': 'GHS',
        'paid': true,
        'isPaid': true,
        'paymentStatus': 'paid',
        'paymentMethod': 'Paystack / Mobile Money - 20% CEO Fee',
        'bookingType': '20% CEO Fee',
        'refundCeoFee': false,
        'refundStatus': 'none',
        'lastChangedBy': 'client',
        'lastChangedUid': clientUid,
        'lastChangedAt': now,
      };
      await ref.set(data);
      // Also mirror for CEO Finance / CEO Bookings Progress
      try {
        await FirebaseDatabase.instance.ref('ceoBookings/$bookingId').set(data);
      } catch (_) {}
      try {
        await FirebaseDatabase.instance.ref('paidBookings/$bookingId').set(data);
      } catch (_) {}
      // Sound trigger to nurse
      try {
        await FirebaseDatabase.instance.ref('soundTriggers/nurse').push().set({
          'fromRole': 'client',
          'fromUid': clientUid,
          'time': now,
          'bookingId': bookingId,
          'status': 'pending',
          'title': 'New Booking - $selectedService',
        });
      } catch (_) {}

      if (!mounted) return;
      _toast('Booked! You paid 20% (GHS ${calc['ceoFee']!.toStringAsFixed(2)}). Pay nurse GHS ${calc['nurseCash']!.toStringAsFixed(2)} CASH after work.');
      Navigator.pushNamed(context, '/my-bookings');
    } catch (e) {
      _toast('Booking failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    Map<String, double>? calc;
    if (selectedNurse != null) calc = _calc(selectedNurse!);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(
        title: const Text('Book Nurse - Pay 20% Only', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1633),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          // Search + Service
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => search = v),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search nurse / specialty / location...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF1C1238),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedService,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1C1238),
                      style: const TextStyle(color: Colors.white),
                      items: services.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) => setState(() => selectedService = v ?? selectedService),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Days + Hours selectors
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: [
                        const Text('DAYS', style: TextStyle(fontSize: 9, color: Colors.white60)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(icon: const Icon(Icons.remove, size: 18), onPressed: () => setState(() { if (days > 1) days--; })),
                            Text('$days', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            IconButton(icon: const Icon(Icons.add, size: 18), onPressed: () => setState(() => days++)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: [
                        const Text('HOURS/DAY', style: TextStyle(fontSize: 9, color: Colors.white60)),
                        Text('${calc != null ? calc['hrsPerDay']!.toStringAsFixed(1) : hrsPerDay.toStringAsFixed(1)} hrs', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Text('Hours per day: ', style: TextStyle(fontSize: 12, color: Colors.white60)),
                Expanded(
                  child: Slider(
                    value: hrsPerDay,
                    min: 1,
                    max: 24,
                    divisions: 23,
                    label: '${hrsPerDay.toStringAsFixed(0)} hrs',
                    onChanged: (v) => setState(() => hrsPerDay = v),
                  ),
                ),
                Text('${hrsPerDay.toStringAsFixed(0)}h', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // 20/80 explainer
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.10), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.35))),
            child: const Text(
              'You pay ONLY 20% now to book. Pay nurse 80% CASH after work. CEO never pays nurse. Nurse rejects = FULL 20% refund. You cancel = CEO keeps 20%.',
              style: TextStyle(fontSize: 11, color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          // Selected nurse + calc
          if (selectedNurse != null && calc != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFACC15).withOpacity(0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.4))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Selected: ${selectedNurse!['fullName'] ?? selectedNurse!['name'] ?? 'Nurse'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('Total Booking: GHS ${calc['totalAmount']!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                  Text('You Pay Now (20% CEO Fee): GHS ${calc['ceoFee']!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFACC15))),
                  Text('Pay Nurse CASH Later (80%): GHS ${calc['nurseCash']!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: Color(0xFF86EFAC))),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _bookNurse,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15)),
                      child: Text('Pay GHS ${calc['ceoFee']!.toStringAsFixed(2)} & Book Now', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFACC15)))
                : list.isEmpty
                    ? const Center(child: Text('No nurses online now. Try again later.', style: TextStyle(color: Colors.white60)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final n = list[i];
                          final c = _calc(n);
                          final isSel = selectedNurse != null && selectedNurse!['id'] == n['id'];
                          return InkWell(
                            onTap: () => setState(() => selectedNurse = n),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSel ? const Color(0xFFFACC15).withOpacity(0.15) : const Color(0xFF1C1238),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isSel ? const Color(0xFFFACC15) : Colors.white10, width: isSel ? 2 : 1),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 26,
                                    backgroundImage: ((n['photoUrl'] ?? n['photo'] ?? '').toString().isNotEmpty) ? NetworkImage((n['photoUrl'] ?? n['photo']).toString()) : null,
                                    child: ((n['photoUrl'] ?? n['photo'] ?? '').toString().isEmpty) ? Text(((n['fullName'] ?? n['name'] ?? 'N').toString().isNotEmpty) ? (n['fullName'] ?? n['name']).toString()[0] : 'N') : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${n['fullName'] ?? n['name'] ?? 'Nurse'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        Text('${n['specialty'] ?? 'General Nursing'} • ${n['placeName'] ?? n['location'] ?? ''}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                                        const SizedBox(height: 4),
                                        Text('GHS ${c['ratePerHour']!.toStringAsFixed(2)}/hr • Total GHS ${c['totalAmount']!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Color(0xFFA78BFA))),
                                        Text('Pay Now 20%: GHS ${c['ceoFee']!.toStringAsFixed(2)} • Nurse Cash 80%: GHS ${c['nurseCash']!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Color(0xFF86EFAC))),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(999)),
                                    child: const Text('ONLINE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
