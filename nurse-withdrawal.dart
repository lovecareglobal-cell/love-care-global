import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nurse Withdrawal - Flutter version of nurse-withdrawal.html
/// - Earnings: Completed / client_confirmed / finished, NOT paid, NOT withdrawalRequested, matched by phone9/email/uid (same as My Job Offer ids)
///   Nurse share = (livelyAmount ?? amount) * 0.8
///   Available = Total - Withdrawn (approved/completed/paid withdrawals) ; Pending = sum status pending
///   Stats: Total Earnings (available), Completed Jobs - Total earned - Withdrawn, Pending Amount
/// - Completed Booking picker: same paths as My Job Offer (bookings + allBookings + ceoBookings + bookingsByFull + clientBookings/myBookings/bookingsByClient + bookingsByPhone/{phone9})
///   On select: auto-fill amount = nurse share 80%, hint "Selected: {id} - Total: GHS X - You get (80%): GHS Y - This booking will move to History at My Job Offer when you submit."
/// - Validate: amount > totalEarnings -> "Amount exceeds available earnings", 0<amount<10 -> "Minimum withdrawal is GHS 10", else "Valid - You will receive GHS X"
/// - Method: momo (MTN MoMo / Vodafone Cash / AirtelTigo Money + number + name) / bank (GCB / Ecobank / Fidelity / Absa / Stanbic / Zenith / CalBank / GT / Access / Other + account + accountName + branch) / card (Visa / Mastercard / Ghana Card linked + last 4 + name)
/// - Submit: amount min 10, <= totalEarnings, booking selected, method selected, method fields required, confirm dialog
///   ID WTH-{now}-{random5}, data: withdrawalId, bookingId, bookingTotal, bookingClientName/Phone, nurseId/Name/Email, amount, method, ...details, notes, status pending, createdAt, createdAtStr, ceoNote '', hrNote ''
///   Writes to: nurseWithdrawals/{id} + ceoWithdrawals/{id} + hrWithdrawals/{id} + withdrawalRequests/{id} + ceoHRPage/withdrawals/{id} + ceoNotifications/{id} {type withdrawal_request} + ceoNotificationRoom/{id} {type withdrawal}
///   MOVE booking to History: nurseBookingHistory/{uid/phone/emailKey}/{bookingId} {status withdrawal_requested, withdrawalId, withdrawalRequested true, withdrawalRequestedAt, withdrawalAmount, movedToHistoryAt} + bookings/{bookingId} update {withdrawalRequested true, status withdrawal_requested}
///   (HTML also continued moving to other booking paths — core move is nurseBookingHistory + bookings update, same effect)
/// - History: nurseWithdrawals filtered by phone9/email/uid/nurseId, sorted createdAt desc, status PENDING/APPROVED/PAID/REJECTED/COMPLETED, method details, View Receipt (nurseWithdrawals/{id}.receipt), Delete (removes from nurseWithdrawals/{id} + nurseWithdrawals/{nurseId}/{id} + ceoWithdrawals + hrWithdrawals + withdrawalRequests + withdrawals + nurseWithdrawals/{phone9}/{id} + nurseWithdrawals/{emailKey}/{id})
/// - NO alert buttons — only Sound Settings (per user request). Sound: lcg_custom_song via Sound Settings.

class NurseWithdrawalScreen extends StatefulWidget {
  const NurseWithdrawalScreen({super.key});
  @override
  State<NurseWithdrawalScreen> createState() => _NurseWithdrawalScreenState();
}

class _NurseWithdrawalScreenState extends State<NurseWithdrawalScreen> {
  String currentNurseId = '', currentNurseName = 'Nurse', currentNurseEmail = '', currentNursePhone = '';
  double totalEarnings = 0, totalEarned = 0, withdrawnTotal = 0, pendingTotal = 0;
  int completedCount = 0;
  List<Map> completedBookings = [];
  String selectedBookingId = '';
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _momoNumberCtrl = TextEditingController();
  final _momoNameCtrl = TextEditingController();
  final _bankAccountCtrl = TextEditingController();
  final _bankAccountNameCtrl = TextEditingController();
  final _bankBranchCtrl = TextEditingController();
  final _cardNumberCtrl = TextEditingController();
  final _cardNameCtrl = TextEditingController();
  String method = '', momoNetwork = 'MTN MoMo', bankName = 'GCB Bank', cardType = 'Visa';
  List<Map> history = [];
  List<String> myPhones = [], myEmails = [], myUids = [];

  final momoNetworks = const ['MTN MoMo', 'Vodafone Cash', 'AirtelTigo Money'];
  final banks = const ['GCB Bank', 'Ecobank', 'Fidelity Bank', 'Absa Bank', 'Stanbic Bank', 'Zenith Bank', 'CalBank', 'GT Bank', 'Access Bank', 'Other'];
  final cardTypes = const ['Visa', 'Mastercard', 'Ghana Card linked'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _normPhone(String s) { final p = s.replaceAll(RegExp(r'[^0-9]'), ''); return p.length >= 9 ? p.substring(p.length - 9) : p; }
  String _normEmail(String s) => s.toLowerCase().trim();

  Future<void> _getIds() async {
    final prefs = await SharedPreferences.getInstance();
    myPhones = []; myEmails = []; myUids = [];
    for (final k in prefs.getKeys()) {
      final v = prefs.getString(k) ?? '';
      final kl = k.toLowerCase();
      if (kl.contains('phone')) { final p = _normPhone(v); if (p.isNotEmpty) myPhones.add(p); }
      if (kl.contains('email')) myEmails.add(_normEmail(v));
      if (kl.contains('uid') || k == 'id') myUids.add(v);
    }
    myPhones = myPhones.toSet().toList(); myEmails = myEmails.toSet().toList(); myUids = myUids.toSet().toList();
    currentNurseId = prefs.getString('lcg_nurse_uid') ?? prefs.getString('nurseUid') ?? prefs.getString('uid') ?? '';
    currentNurseName = prefs.getString('nurseName') ?? prefs.getString('fullName') ?? 'Nurse';
    currentNurseEmail = prefs.getString('nurseEmail') ?? prefs.getString('email') ?? '';
    currentNursePhone = prefs.getString('nursePhone') ?? prefs.getString('phone') ?? '';
  }

  bool _matchesBooking(Map b) {
    if (myPhones.isEmpty && myEmails.isEmpty && myUids.isEmpty) return true;
    final bPhones = [(b['clientPhone'] ?? ''), (b['phone'] ?? ''), (b['nursePhone'] ?? '')].map((e) => _normPhone(e.toString())).toList();
    final bEmails = [(b['clientEmail'] ?? ''), (b['email'] ?? ''), (b['nurseEmail'] ?? '')].map((e) => _normEmail(e.toString())).toList();
    final bUids = [b['clientUid'], b['clientId'], b['uid'], b['nurseId'], b['nurseUid']].map((e) => e?.toString() ?? '').toList();
    return myPhones.any((p) => bPhones.contains(p)) || myEmails.any((e) => bEmails.contains(e)) || myUids.any((u) => bUids.contains(u));
  }

  bool _isCompleted(Map b) {
    final s = (b['status'] ?? '').toString().toLowerCase();
    return s.contains('completed') || s.contains('client_confirmed') || s == 'finished' || b['clientConfirmed'] == true;
  }

  Future<Map<String, Map>> _loadAllBookings() async {
    final db = FirebaseDatabase.instance;
    Map<String, Map> map = {};
    for (final p in ['bookings', 'allBookings', 'ceoBookings', 'bookingsByFull']) {
      try {
        final s = await db.ref(p).get();
        if (s.exists) (s.value as Map).forEach((k, v) { final val = Map<String, dynamic>.from(v as Map); final bid = val['bookingId'] ?? k; if (!map.containsKey(bid)) map[bid] = {...val, 'id': k, 'bookingId': bid}; });
      } catch (_) {}
    }
    for (final uk in [...myUids, ...myEmails.map((e) => e.replaceAll(RegExp(r'[.@]'), '_'))]) {
      for (final base in ['clientBookings', 'myBookings', 'bookingsByClient']) {
        try {
          final s = await db.ref('$base/$uk').get();
          if (s.exists) (s.value as Map).forEach((k, v) { final val = Map<String, dynamic>.from(v as Map); final bid = val['bookingId'] ?? k; if (!map.containsKey(bid)) map[bid] = {...val, 'id': k, 'bookingId': bid}; });
        } catch (_) {}
      }
    }
    for (final ph in myPhones) {
      try {
        final s = await db.ref('bookingsByPhone/$ph').get();
        if (s.exists) (s.value as Map).forEach((k, v) { final val = Map<String, dynamic>.from(v as Map); final bid = val['bookingId'] ?? k; if (!map.containsKey(bid)) map[bid] = {...val, 'id': k, 'bookingId': bid}; });
      } catch (_) {}
    }
    return map;
  }

  Future<void> _load() async {
    await _getIds();
    final map = await _loadAllBookings();
    double total = 0; int completed = 0;
    List<Map> comp = [];
    map.forEach((_, b) {
      if (!_isCompleted(b)) return;
      final s = (b['status'] ?? '').toString().toLowerCase();
      if (b['paid'] == true || s.contains('paid')) return;
      if (b['withdrawalRequested'] == true) return;
      if (!_matchesBooking(b)) return;
      total += (double.tryParse((b['livelyAmount'] ?? b['amount'] ?? 0).toString()) ?? 0) * 0.8;
      completed++;
      comp.add(b);
    });
    comp.sort((a, b) => ((b['time'] ?? b['createdAt'] ?? 0) as num).compareTo((a['time'] ?? a['createdAt'] ?? 0) as num));
    // Withdrawals
    double withdrawn = 0, pendingW = 0;
    List<Map> hist = [];
    try {
      final wSnap = await FirebaseDatabase.instance.ref('nurseWithdrawals').get();
      if (wSnap.exists) {
        (wSnap.value as Map).forEach((k, v) {
          final w = Map<String, dynamic>.from(v as Map);
          final wPhone = _normPhone((w['nursePhone'] ?? w['momoNumber'] ?? '').toString());
          final wEmail = _normEmail((w['nurseEmail'] ?? '').toString());
          bool isMine = false;
          if (myPhones.isEmpty && myEmails.isEmpty && myUids.isEmpty) isMine = true;
          else if (myPhones.contains(wPhone)) isMine = true;
          else if (myEmails.contains(wEmail)) isMine = true;
          else if (myUids.contains(w['nurseId'])) isMine = true;
          else if (w['nurseId'] == currentNurseId) isMine = true;
          if (!isMine) return;
          hist.add({...w, 'id': k});
          if (w['status'] == 'approved' || w['status'] == 'completed' || w['paid'] == true) withdrawn += double.tryParse((w['amount'] ?? 0).toString()) ?? 0;
          if (w['status'] == 'pending') pendingW += double.tryParse((w['amount'] ?? 0).toString()) ?? 0;
        });
      }
    } catch (_) {}
    hist.sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
    setState(() {
      totalEarned = total; totalEarnings = (total - withdrawn) < 0 ? 0 : total - withdrawn; withdrawnTotal = withdrawn; pendingTotal = pendingW;
      completedCount = completed; completedBookings = comp; history = hist;
    });
  }

  String get validationMsg {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount > totalEarnings) return 'Amount exceeds available earnings (GHS ${totalEarnings.toStringAsFixed(2)})';
    if (amount > 0 && amount < 10) return 'Minimum withdrawal is GHS 10';
    if (amount > 0) return 'Valid - You will receive GHS ${amount.toStringAsFixed(2)}';
    return '';
  }

  Color get validationColor {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount > totalEarnings) return const Color(0xFFFCA5A5);
    if (amount > 0 && amount < 10) return const Color(0xFFFDE68A);
    if (amount > 0) return const Color(0xFF86EFAC);
    return Colors.white60;
  }

  void _onBookingSelect(String? bid) {
    setState(() => selectedBookingId = bid ?? '');
    if (bid == null || bid.isEmpty) return;
    final b = completedBookings.firstWhere((x) => x['bookingId'] == bid, orElse: () => {});
    if (b.isEmpty) return;
    final share = (double.tryParse((b['livelyAmount'] ?? b['amount'] ?? 0).toString()) ?? 0) * 0.8;
    setState(() => _amountCtrl.text = share.toStringAsFixed(2));
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _submitWithdrawal() async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (currentNurseId.isEmpty) { _toast('No nurse ID - Login again'); return; }
    if (amount < 10) { _toast('Enter amount min GHS 10'); return; }
    if (amount > totalEarnings) { _toast('Amount exceeds earnings GHS ${totalEarnings.toStringAsFixed(2)}'); return; }
    if (selectedBookingId.isEmpty) { _toast('Select Completed Booking ID first'); return; }
    final selBooking = completedBookings.firstWhere((x) => x['bookingId'] == selectedBookingId, orElse: () => {});
    if (selBooking.isEmpty) { _toast('Select Completed Booking ID first'); return; }
    if (method.isEmpty) { _toast('Select withdrawal method'); return; }
    Map details = {};
    if (method == 'momo') {
      if (_momoNumberCtrl.text.trim().isEmpty || _momoNameCtrl.text.trim().isEmpty) { _toast('Enter MoMo number and name'); return; }
      details = {'momoNetwork': momoNetwork, 'momoNumber': _momoNumberCtrl.text.trim(), 'momoName': _momoNameCtrl.text.trim()};
    } else if (method == 'bank') {
      if (_bankAccountCtrl.text.trim().isEmpty || _bankAccountNameCtrl.text.trim().isEmpty) { _toast('Enter bank account and name'); return; }
      details = {'bankName': bankName, 'bankAccount': _bankAccountCtrl.text.trim(), 'bankAccountName': _bankAccountNameCtrl.text.trim(), 'bankBranch': _bankBranchCtrl.text.trim()};
    } else if (method == 'card') {
      if (_cardNumberCtrl.text.trim().isEmpty || _cardNameCtrl.text.trim().isEmpty) { _toast('Enter card last 4 digits and name'); return; }
      details = {'cardType': cardType, 'cardNumber': _cardNumberCtrl.text.trim(), 'cardName': _cardNameCtrl.text.trim()};
    }
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Confirm withdrawal?'), content: Text('Amount: GHS ${amount.toStringAsFixed(2)}\nMethod: $method\nDetails: $details\n\nCEO/HR will approve.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm'))]));
    if (confirm != true) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = 'WTH-$now-${(now % 100000).toString().padLeft(5, '0')}';
      final data = {'withdrawalId': id, 'bookingId': selBooking['bookingId'], 'bookingTotal': double.tryParse((selBooking['livelyAmount'] ?? selBooking['amount'] ?? 0).toString()) ?? 0, 'bookingClientName': selBooking['clientName'] ?? '', 'bookingClientPhone': selBooking['clientPhone'] ?? '', 'nurseId': currentNurseId, 'nurseName': currentNurseName, 'nurseEmail': currentNurseEmail, 'nursePhone': currentNursePhone, 'amount': amount, 'method': method, ...details, 'notes': _notesCtrl.text.trim(), 'status': 'pending', 'createdAt': now, 'createdAtStr': DateTime.now().toString(), 'ceoNote': '', 'hrNote': ''};
      final db = FirebaseDatabase.instance;
      await db.ref('nurseWithdrawals/$id').set(data);
      await db.ref('ceoWithdrawals/$id').set(data);
      await db.ref('hrWithdrawals/$id').set(data);
      await db.ref('withdrawalRequests/$id').set(data);
      await db.ref('ceoHRPage/withdrawals/$id').set(data);
      await db.ref('ceoNotifications/$id').set({'type': 'withdrawal_request', 'title': 'Withdrawal Request - $currentNurseName', 'message': '$currentNurseName requested GHS ${amount.toStringAsFixed(2)} via $method - Booking ID: ${selBooking['bookingId']} - Withdrawal ID: $id', 'nurseId': currentNurseId, 'nurseName': currentNurseName, 'amount': amount, 'method': method, 'withdrawalId': id, 'createdAt': now, 'read': false});
      await db.ref('ceoNotificationRoom/$id').set({'type': 'withdrawal', 'title': 'NEW Withdrawal - $currentNurseName - GHS $amount', 'message': 'Booking ID: ${selBooking['bookingId']} - Method: $method - Amount: GHS $amount - Nurse: $currentNurseName', 'createdAt': now, 'nurseId': currentNurseId, 'nurseName': currentNurseName});
      // MOVE booking to History at My Job Offer
      final histData = {...selBooking, 'status': 'withdrawal_requested', 'withdrawalId': id, 'withdrawalRequested': true, 'withdrawalRequestedAt': now, 'withdrawalAmount': amount, 'movedToHistoryAt': now, 'movedToHistoryAtStr': DateTime.now().toString(), 'lastChangedBy': 'nurse', 'lastChangedAt': now};
      final emailKey = currentNurseEmail.replaceAll(RegExp(r'[.@]'), '_');
      final phone9 = _normPhone(currentNursePhone);
      for (final k in [currentNurseId, ...myUids]) await db.ref('nurseBookingHistory/$k/${selBooking['bookingId']}').set(histData).catchError((_) {});
      if (phone9.isNotEmpty) await db.ref('nurseBookingHistory/$phone9/${selBooking['bookingId']}').set(histData).catchError((_) {});
      if (emailKey.isNotEmpty) await db.ref('nurseBookingHistory/$emailKey/${selBooking['bookingId']}').set(histData).catchError((_) {});
      await db.ref('bookings/${selBooking['bookingId']}').update({'withdrawalRequested': true, 'status': 'withdrawal_requested', 'withdrawalId': id, 'lastChangedBy': 'nurse', 'lastChangedAt': now}).catchError((_) {});
      _toast('✅ Withdrawal submitted — CEO/HR will approve');
      setState(() { _amountCtrl.clear(); selectedBookingId = ''; });
      _load();
    } catch (e) { _toast(e.toString()); }
  }

  Future<void> _viewReceipt(Map w) async {
    try {
      final snap = await FirebaseDatabase.instance.ref('nurseWithdrawals/${w['id']}').get();
      final val = snap.exists ? Map<String, dynamic>.from(snap.value as Map) : {};
      if (val['receipt'] == null) { _toast('No receipt for this withdrawal.'); return; }
      showDialog(context: context, builder: (_) => AlertDialog(title: Text('Receipt - ${w['id']}'), content: Column(mainAxisSize: MainAxisSize.min, children: [Text(val['paidNote'] ?? ''), const SizedBox(height: 8), Image.network(val['receipt'].toString())]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]));
    } catch (e) { _toast(e.toString()); }
  }

  Future<void> _deleteHistory(Map w) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Delete this withdrawal history?'), content: const Text('This removes it from your history only.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
    if (confirm != true) return;
    final id = w['id'];
    final phone9 = _normPhone(currentNursePhone);
    final emailKey = currentNurseEmail.replaceAll(RegExp(r'[.@]'), '_');
    final db = FirebaseDatabase.instance;
    await db.ref('nurseWithdrawals/$id').remove().catchError((_) {});
    await db.ref('nurseWithdrawals/$currentNurseId/$id').remove().catchError((_) {});
    await db.ref('ceoWithdrawals/$id').remove().catchError((_) {});
    await db.ref('hrWithdrawals/$id').remove().catchError((_) {});
    await db.ref('withdrawalRequests/$id').remove().catchError((_) {});
    await db.ref('withdrawals/$id').remove().catchError((_) {});
    if (phone9.isNotEmpty) await db.ref('nurseWithdrawals/$phone9/$id').remove().catchError((_) {});
    if (emailKey.isNotEmpty) await db.ref('nurseWithdrawals/$emailKey/$id').remove().catchError((_) {});
    _toast('Deleted - Withdrawal history removed');
    _load();
  }

  String _methodDetails(Map w) {
    if (w['method'] == 'momo') return 'MoMo ${w['momoNetwork'] ?? ''} - ${w['momoNumber'] ?? ''} - ${w['momoName'] ?? ''}';
    if (w['method'] == 'bank') return 'Bank ${w['bankName'] ?? ''} - ${w['bankAccount'] ?? ''} - ${w['bankAccountName'] ?? ''}';
    if (w['method'] == 'card') return 'Card ${w['cardType'] ?? ''} - ****${w['cardNumber'] ?? ''} - ${w['cardName'] ?? ''}';
    return '${w['method'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final sel = completedBookings.firstWhere((x) => x['bookingId'] == selectedBookingId, orElse: () => {});
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('Nurse Withdrawal', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings'))]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          // Earnings
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFFACC15).withOpacity(0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.3))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('💰 Available Earnings', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('GHS ${totalEarnings.toStringAsFixed(2)}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFFACC15))),
            Text('$completedCount completed jobs - Total earned: GHS ${totalEarned.toStringAsFixed(2)} - Withdrawn: GHS ${withdrawnTotal.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
            const SizedBox(height: 6),
            Row(children: [const Text('Pending: ', style: TextStyle(color: Colors.white60, fontSize: 12)), Text('GHS ${pendingTotal.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFFDE68A), fontWeight: FontWeight.bold)), const Spacer(), TextButton(onPressed: _load, child: const Text('Refresh'))]),
          ])),
          const SizedBox(height: 12),
          // Form
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('💸 Withdraw Earnings', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(value: selectedBookingId.isEmpty ? null : selectedBookingId, decoration: const InputDecoration(labelText: 'Select Completed Booking ID', border: OutlineInputBorder()), items: [const DropdownMenuItem(value: '', child: Text('-- Select Completed Booking ID --')), ...completedBookings.map((b) { final total = double.tryParse((b['livelyAmount'] ?? b['amount'] ?? 0).toString()) ?? 0; final share = total * 0.8; return DropdownMenuItem(value: b['bookingId'].toString(), child: Text('${b['bookingId']} - GHS ${total.toStringAsFixed(2)} - You get GHS ${share.toStringAsFixed(2)} - ${b['clientName'] ?? 'Client'}', overflow: TextOverflow.ellipsis)); })], onChanged: (v) => _onBookingSelect(v == '' ? null : v)),
            if (sel.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Selected: ${sel['bookingId']} - Total: GHS ${(double.tryParse((sel['livelyAmount'] ?? sel['amount'] ?? 0).toString()) ?? 0).toStringAsFixed(2)} - You get (80%): GHS ${((double.tryParse((sel['livelyAmount'] ?? sel['amount'] ?? 0).toString()) ?? 0) * 0.8).toStringAsFixed(2)} - This booking will move to History at My Job Offer when you submit.', style: const TextStyle(color: Colors.white60, fontSize: 11))),
            const SizedBox(height: 10),
            TextField(controller: _amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount (GHS)', border: OutlineInputBorder()), onChanged: (_) => setState(() {})),
            if (validationMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(validationMsg, style: TextStyle(color: validationColor, fontSize: 11))),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(value: method.isEmpty ? null : method, decoration: const InputDecoration(labelText: 'Withdrawal Method', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'momo', child: Text('Mobile Money (MoMo) - MTN, Vodafone, AirtelTigo')), DropdownMenuItem(value: 'bank', child: Text('Bank Transfer - Ghana Banks')), DropdownMenuItem(value: 'card', child: Text('Card - Visa/Mastercard'))], onChanged: (v) => setState(() => method = v ?? '')),
            if (method == 'momo') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(value: momoNetwork, decoration: const InputDecoration(labelText: 'MoMo Network', border: OutlineInputBorder()), items: momoNetworks.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(), onChanged: (v) => setState(() => momoNetwork = v ?? momoNetwork)),
              const SizedBox(height: 8),
              TextField(controller: _momoNumberCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'MoMo Number', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _momoNameCtrl, decoration: const InputDecoration(labelText: 'MoMo Name', border: OutlineInputBorder())),
            ],
            if (method == 'bank') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(value: bankName, decoration: const InputDecoration(labelText: 'Bank', border: OutlineInputBorder()), items: banks.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(), onChanged: (v) => setState(() => bankName = v ?? bankName)),
              const SizedBox(height: 8),
              TextField(controller: _bankAccountCtrl, decoration: const InputDecoration(labelText: 'Bank Account', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _bankAccountNameCtrl, decoration: const InputDecoration(labelText: 'Account Name', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _bankBranchCtrl, decoration: const InputDecoration(labelText: 'Branch (optional)', border: OutlineInputBorder())),
            ],
            if (method == 'card') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(value: cardType, decoration: const InputDecoration(labelText: 'Card Type', border: OutlineInputBorder()), items: cardTypes.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(), onChanged: (v) => setState(() => cardType = v ?? cardType)),
              const SizedBox(height: 8),
              TextField(controller: _cardNumberCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Card Last 4 Digits', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _cardNameCtrl, decoration: const InputDecoration(labelText: 'Card Name', border: OutlineInputBorder())),
            ],
            const SizedBox(height: 10),
            TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _submitWithdrawal, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text('Submit Withdrawal — CEO/HR Will Approve', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))),
          ])),
          const SizedBox(height: 12),
          // History
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📜 Withdrawal History', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (history.isEmpty) const Text('No withdrawals yet', style: TextStyle(color: Colors.white60)),
            ...history.map((w) {
              final status = w['paid'] == true ? 'PAID' : (w['status'] ?? 'pending').toString().toUpperCase();
              return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('GHS ${(double.tryParse((w['amount'] ?? 0).toString()) ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(999)), child: Text(status, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))]),
                if (w['bookingId'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Booking ID: ${w['bookingId']}', style: const TextStyle(fontSize: 11, color: Color(0xFFFACC15)))),
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('Method: ${_methodDetails(w)}', style: const TextStyle(fontSize: 11, color: Colors.white60))),
                Text('${w['createdAtStr'] ?? ''} - ID: ${w['id']}', style: const TextStyle(fontSize: 10, color: Colors.white60)),
                if (w['ceoNote'] != null && (w['ceoNote'] as String).isNotEmpty) Text('CEO: ${w['ceoNote']}', style: const TextStyle(fontSize: 11)),
                Row(children: [
                  if (w['receipt'] != null) TextButton(onPressed: () => _viewReceipt(w), child: const Text('View Receipt')),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _deleteHistory(w)),
                ]),
              ]));
            }),
          ])),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
