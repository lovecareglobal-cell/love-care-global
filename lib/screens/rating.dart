import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rate Your Nurse - Flutter version of rating.html
/// Only client who booked this nurse + job marked COMPLETED can rate.
/// Rating + photo appears on homepage index for everyone.
/// Saves to: ratings/{nurseId}/{bookingId} + clientRatings + ratingsAll + publicReviews + homepageReviews + clientReviews/{emailKey}/{bookingId}
/// + clientBookings/{phoneKey}/{bookingId} + bookings/{bookingId} (isRated, ratingValue, ratingComment)
/// + nurses/{nurseId} avg rating + reviewCount

class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key});
  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  String clientName = 'Client', clientPhone = '', clientEmail = '', clientPhoto = '', clientUid = '';
  List<Map> myBookings = [];
  String? currentBookingId;
  String currentNurseId = '';
  int currentRating = 0;
  final _commentCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _photoCtrl = TextEditingController();
  String result = '';
  bool isSubmitting = false;
  bool showForm = false;

  final ratingTexts = {1: 'Poor - Needs improvement', 2: 'Fair - Okay', 3: 'Good - Satisfied', 4: 'Very Good - Happy', 5: 'Excellent - Outstanding!'};

  @override
  void initState() {
    super.initState();
    _loadClient();
  }

  Future<bool> _loadClient() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      clientPhone = prefs.getString('clientPhone') ?? prefs.getString('phone') ?? prefs.getString('userPhone') ?? '';
      clientName = prefs.getString('clientName') ?? prefs.getString('fullName') ?? prefs.getString('lcg_client_name') ?? 'Client';
      clientEmail = prefs.getString('clientEmail') ?? prefs.getString('email') ?? prefs.getString('userEmail') ?? '';
      clientPhoto = prefs.getString('clientPhotoUrl') ?? prefs.getString('clientPhoto') ?? prefs.getString('photoUrl') ?? prefs.getString('photo') ?? '';
      clientUid = prefs.getString('clientUid') ?? prefs.getString('uid') ?? '';
      _nameCtrl.text = clientName;
      _phoneCtrl.text = clientPhone;
      _emailCtrl.text = clientEmail;
      _photoCtrl.text = clientPhoto;
    });
    if (clientPhone.isEmpty) return false;
    await _loadBookingsToRate();
    return true;
  }

  Future<void> _loadBookingsToRate() async {
    final phoneKey = clientPhone.replaceAll(RegExp(r'[^0-9]'), '');
    List<Map> bookings = [];
    try {
      final snap = await FirebaseDatabase.instance.ref('clientBookings/$phoneKey').get();
      if (snap.exists) {
        (snap.value as Map).forEach((k, v) => bookings.add({'id': k, ...Map<String, dynamic>.from(v as Map)}));
      }
      final snap2 = await FirebaseDatabase.instance.ref('bookings').get();
      if (snap2.exists) {
        (snap2.value as Map).forEach((k, v) {
          final val = Map<String, dynamic>.from(v as Map);
          final bPhone = (val['clientPhone'] ?? val['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
          if ((bPhone == phoneKey || (phoneKey.length >= 9 && bPhone.endsWith(phoneKey.substring(phoneKey.length - 9)))) && !bookings.any((b) => b['id'] == k)) {
            bookings.add({'id': k, ...val});
          }
        });
      }
      setState(() => myBookings = bookings);
    } catch (_) {}
  }

  List<Map> get toRate => myBookings.where((b) {
    final s = (b['status'] ?? '').toString().toLowerCase();
    return (s == 'completed' || s == 'done' || b['completedAt'] != null) && b['isRated'] != true;
  }).toList();

  List<Map> get rated => myBookings.where((b) => b['isRated'] == true).toList();

  void _startRating(String bookingId) {
    final b = myBookings.firstWhere((x) => x['id'] == bookingId);
    setState(() {
      currentBookingId = bookingId;
      currentNurseId = b['nurseId'] ?? b['selectedNurseId'] ?? '';
      showForm = true;
      currentRating = 0;
      result = '';
    });
  }

  void _cancelRating() => setState(() { showForm = false; currentBookingId = null; currentNurseId = ''; currentRating = 0; });

  Future<void> _submitRating() async {
    if (currentRating == 0) { setState(() => result = 'Please select 1-5 stars'); return; }
    if (currentBookingId == null) { setState(() => result = 'No booking selected'); return; }
    final comment = _commentCtrl.text.trim();
    if (comment.isEmpty) { setState(() => result = 'Please write your experience (comment)'); return; }
    setState(() { isSubmitting = true; result = ''; });
    try {
      final booking = myBookings.firstWhere((b) => b['id'] == currentBookingId);
      final phoneKey = clientPhone.replaceAll(RegExp(r'[^0-9]'), '');
      final cName = _nameCtrl.text.trim().isEmpty ? clientName : _nameCtrl.text.trim();
      final cPhone = _phoneCtrl.text.trim().isEmpty ? clientPhone : _phoneCtrl.text.trim();
      final cEmail = _emailCtrl.text.trim().isEmpty ? clientEmail : _emailCtrl.text.trim();
      final cPhoto = _photoCtrl.text.trim().isEmpty ? (clientPhoto.isEmpty ? (booking['clientPhotoUrl'] ?? booking['clientPhoto'] ?? '') : clientPhoto) : _photoCtrl.text.trim();
      final now = DateTime.now().millisecondsSinceEpoch;
      final ratingData = {
        'bookingId': currentBookingId,
        'nurseId': currentNurseId.isNotEmpty ? currentNurseId : (booking['nurseId'] ?? ''),
        'nurseName': booking['nurseName'] ?? booking['selectedNurseName'] ?? '',
        'service': booking['service'] ?? 'Home Nursing',
        'clientPhone': cPhone, 'clientPhoneKey': phoneKey, 'phone': cPhone,
        'clientName': cName, 'client': cName, 'clientFullName': cName, 'clientDisplayName': cName,
        'clientEmail': cEmail, 'email': cEmail, 'clientMail': cEmail,
        'clientPhotoUrl': cPhoto, 'clientPhoto': cPhoto, 'photoUrl': cPhoto, 'clientAvatar': cPhoto, 'clientProfilePhoto': cPhoto, 'clientImage': cPhoto,
        'clientUid': clientUid.isNotEmpty ? clientUid : (booking['clientUid'] ?? ''),
        'patientName': booking['patientName'] ?? '', 'patientPhone': booking['patientPhone'] ?? '', 'patientLocation': booking['patientLocation'] ?? '',
        'ratingValue': currentRating, 'rating': currentRating, 'ratingComment': comment, 'text': comment,
        'ratedAt': now, 'ratedAtISO': DateTime.now().toIso8601String(), 'ratingTime': now, 'ratingTimeFormatted': DateTime.now().toString(), 'ratingTimeDisplay': TimeOfDay.now().format(context),
        'date': DateTime.now().toIso8601String().split('T')[0],
        'timestamp': now, 'timeOfRating': now,
        'bookingTime': booking['time'] ?? booking['createdAt'] ?? now, 'bookingTimeFormatted': booking['time'] != null ? DateTime.fromMillisecondsSinceEpoch((booking['time'] as num).toInt()).toString() : '',
        'loc': 'Ghana', 'verifiedBooking': true, 'showOnIndex': true, 'source': 'rating.dart — with photo email',
        'originalBookingId': currentBookingId,
      };
      final db = FirebaseDatabase.instance;
      final nid = currentNurseId.isNotEmpty ? currentNurseId : (booking['nurseId'] ?? 'unknown');
      final emailKey = cEmail.isNotEmpty ? cEmail.replaceAll(RegExp(r'[.#\$@\[\]]'), '_') : phoneKey;
      await db.ref('ratings/$nid/$currentBookingId').set(ratingData);
      await db.ref('clientRatings/$currentBookingId').set(ratingData);
      await db.ref('ratingsAll/$currentBookingId').set(ratingData);
      await db.ref('publicReviews/$currentBookingId').set(ratingData);
      await db.ref('homepageReviews/$currentBookingId').set(ratingData);
      await db.ref('clientReviews/$emailKey/$currentBookingId').set(ratingData);
      await db.ref('clientBookings/$phoneKey/$currentBookingId').update({'isRated': true, 'ratingValue': currentRating, 'ratingComment': comment, 'ratedAt': now, 'clientPhotoUrl': cPhoto, 'clientEmail': cEmail});
      await db.ref('bookings/$currentBookingId').update({'isRated': true, 'ratingValue': currentRating, 'ratingComment': comment, 'ratedAt': now, 'clientPhotoUrl': cPhoto, 'clientEmail': cEmail}).catchError((_) {});
      // Update nurse avg
      final snap = await db.ref('ratings/$nid').get();
      if (snap.exists) {
        double total = 0; int count = 0;
        (snap.value as Map).forEach((_, v) { total += double.tryParse((Map<String, dynamic>.from(v as Map)['ratingValue'] ?? 0).toString()) ?? 0; count++; });
        final avg = count > 0 ? total / count : currentRating.toDouble();
        await db.ref('nurses/$nid').update({'rating': double.parse(avg.toStringAsFixed(1)), 'reviewCount': count, 'lastRatedAt': now}).catchError((_) {});
      }
      setState(() => result = '✅ Rating submitted! ⭐$currentRating — Client: $cName • Phone: $cPhone • Email: $cEmail • Photo: ${cPhoto.isNotEmpty ? 'YES' : 'NO'} • Time: ${DateTime.now()}\n"$comment" — Now appears on homepage with your photo!');
      _commentCtrl.clear();
      await _loadBookingsToRate();
      Future.delayed(const Duration(milliseconds: 2500), () { if (mounted) Navigator.pushNamed(context, '/', arguments: {'scrollTo': 'reviews'}); });
    } catch (e) {
      setState(() => result = 'Failed: $e');
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('RATE YOUR NURSE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [TextButton(onPressed: () => Navigator.pushNamed(context, '/client-dashboard'), child: const Text('Dashboard', style: TextStyle(color: Color(0xFFD8B4FE))))]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF4C1D95).withOpacity(0.25), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.25))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🔒 Secure Verified Rating — With Client Photo + Email + Time', style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('Only client who booked this nurse and whose job is marked COMPLETED can rate. Your rating + photo appears on homepage index for everyone.', style: TextStyle(color: Color(0xFFFACC15), fontSize: 11)),
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFFACC15).withOpacity(0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.2))), child: Row(children: [
              CircleAvatar(radius: 24, backgroundImage: clientPhoto.isNotEmpty ? NetworkImage(clientPhoto) : null, child: clientPhoto.isEmpty ? Text(clientName.isNotEmpty ? clientName[0] : 'C') : null),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(clientName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Text(clientPhone.isEmpty ? 'Not found' : clientPhone, style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11)), Text(clientEmail.isEmpty ? 'No email' : clientEmail, style: const TextStyle(color: Colors.white60, fontSize: 11))])),
            ])),
          ])),
          const SizedBox(height: 12),
          // Bookings to rate
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📅 Completed Bookings to Rate', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (clientPhone.isEmpty) const Text('❌ No phone found. Please book first.', style: TextStyle(color: Color(0xFFFCA5A5))),
            if (clientPhone.isNotEmpty && myBookings.isEmpty) const Text('Loading completed bookings...', style: TextStyle(color: Color(0xFFA78BFA))),
            if (clientPhone.isNotEmpty && myBookings.isNotEmpty && toRate.isEmpty) ...[
              Text('✅ All completed jobs rated! ${rated.length} ratings — they appear on homepage.', style: const TextStyle(color: Color(0xFF86EFAC))),
              ...rated.map((b) => Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.green.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withOpacity(0.2))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${b['id']} — ${b['nurseName'] ?? ''}  ${'⭐' * ((b['ratingValue'] ?? 5) as int)}', style: const TextStyle(fontWeight: FontWeight.bold)), Text(b['ratingComment'] ?? '', style: const TextStyle(fontSize: 12))]))),
            ],
            ...toRate.map((b) => Container(
              margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.3))),
              child: Row(children: [
                CircleAvatar(backgroundImage: (b['clientPhotoUrl'] ?? clientPhoto).toString().isNotEmpty ? NetworkImage((b['clientPhotoUrl'] ?? clientPhoto).toString()) : null, child: (b['clientPhotoUrl'] ?? clientPhoto).toString().isEmpty ? Text(clientName.isNotEmpty ? clientName[0] : 'C') : null),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${b['id']} — ${b['nurseName'] ?? b['selectedNurseName'] ?? 'Nurse'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Text('Status: ${b['status'] ?? ''} • Service: ${b['service'] ?? 'Home Nursing'}', style: const TextStyle(color: Colors.white60, fontSize: 11))])),
                ElevatedButton(onPressed: () => _startRating(b['id']), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15)), child: const Text('⭐ Rate', style: TextStyle(color: Colors.black))),
              ]),
            )),
          ])),
          if (showForm) ...[
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFFACC15), width: 2)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('⭐ Rate ${myBookings.firstWhere((b) => b['id'] == currentBookingId)['nurseName'] ?? 'Nurse'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text('Booking: $currentBookingId • ${DateTime.now()}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) {
                final n = i + 1;
                return GestureDetector(onTap: () => setState(() => currentRating = n), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(n <= currentRating ? '★' : '☆', style: TextStyle(fontSize: 36, color: n <= currentRating ? const Color(0xFFFACC15) : Colors.grey))));
              })),
              Center(child: Text(currentRating == 0 ? 'Select rating' : ratingTexts[currentRating]!, style: const TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold))),
              const SizedBox(height: 12),
              const Text('YOUR EXPERIENCE *', style: TextStyle(color: Color(0xFFC4B5FD), fontSize: 11, fontWeight: FontWeight.bold)),
              TextField(controller: _commentCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Write your experience...', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              const Text('CLIENT NAME', style: TextStyle(color: Color(0xFFC4B5FD), fontSize: 11, fontWeight: FontWeight.bold)),
              TextField(controller: _nameCtrl, decoration: const InputDecoration(border: OutlineInputBorder())),
              const SizedBox(height: 8),
              const Text('CLIENT PHONE', style: TextStyle(color: Color(0xFFC4B5FD), fontSize: 11, fontWeight: FontWeight.bold)),
              TextField(controller: _phoneCtrl, decoration: const InputDecoration(border: OutlineInputBorder())),
              const SizedBox(height: 8),
              const Text('CLIENT EMAIL', style: TextStyle(color: Color(0xFFC4B5FD), fontSize: 11, fontWeight: FontWeight.bold)),
              TextField(controller: _emailCtrl, decoration: const InputDecoration(border: OutlineInputBorder())),
              const SizedBox(height: 8),
              const Text('CLIENT PHOTO URL', style: TextStyle(color: Color(0xFFC4B5FD), fontSize: 11, fontWeight: FontWeight.bold)),
              TextField(controller: _photoCtrl, decoration: const InputDecoration(border: OutlineInputBorder())),
              const SizedBox(height: 12),
              if (result.isNotEmpty) Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: result.startsWith('✅') ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Text(result, style: const TextStyle(fontSize: 12))),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: ElevatedButton(onPressed: isSubmitting ? null : _submitRating, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(isSubmitting ? '⏳ Submitting...' : '⭐ Submit Rating — With Photo + Email', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)))),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _cancelRating, child: const Text('Cancel')),
              ]),
            ])),
          ],
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)), child: const Text('You rate here → Saves to publicReviews + homepageReviews with client photo + email + time\nShows on homepage index with 4.9 AVG', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11))),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
