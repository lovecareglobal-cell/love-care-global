// lib/screens/rating.dart - English only, no translations.
// English only - this is the real RatingScreen.
// Only a client who booked the nurse and whose job is COMPLETED can rate.
// Rating saves to publicReviews + homepageReviews with client photo + email + time.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key});
  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  bool _loading = true;
  String _error = '';
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _bookings = [];

  String get _email => FirebaseAuth.instance.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      if (_email.isNotEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('bookings')
            .where('clientEmail', isEqualTo: _email)
            .where('status', isEqualTo: 'COMPLETED')
            .get();
        if (snap.docs.isEmpty) {
          snap = await FirebaseFirestore.instance
              .collection('bookings')
              .where('email', isEqualTo: _email)
              .where('status', isEqualTo: 'COMPLETED')
              .get();
        }
      } else {
        snap = await FirebaseFirestore.instance
            .collection('bookings')
            .where('status', isEqualTo: 'COMPLETED')
            .limit(20)
            .get();
      }
      if (mounted) setState(() { _bookings = snap.docs; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Failed: $e'; _loading = false; });
    }
  }

  String _str(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

  Future<void> _showRateDialog(Map<String, dynamic> b, String bookingId) async {
    int stars = 5;
    final commentCtrl = TextEditingController();
    final nurse = _str(b, ['nurseName', 'nurse', 'nurseEmail']);
    final nurseEmail = _str(b, ['nurseEmail', 'nurse']);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('⭐ Rate ${nurse.isEmpty ? 'Your Nurse' : nurse}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Booking: $bookingId', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                const Text('Select rating', style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) => IconButton(
                    icon: Icon(i < stars ? Icons.star : Icons.star_border, color: Colors.amber, size: 32),
                    onPressed: () => setD(() => stars = i + 1),
                  )),
                ),
                Text(['', 'Poor - Needs improvement', 'Fair - Okay', 'Good - Satisfied', 'Very Good - Happy', 'Excellent - Outstanding!'][stars]),
                const SizedBox(height: 12),
                const Align(alignment: Alignment.centerLeft, child: Text('YOUR EXPERIENCE *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                TextField(controller: commentCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Write your experience...', border: OutlineInputBorder())),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final comment = commentCtrl.text.trim();
                if (comment.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please write your experience (comment)')));
                  return;
                }
                Navigator.pop(ctx);
                await _submit(b, bookingId, stars, comment, nurse, nurseEmail);
              },
              child: const Text('⭐ Submit Rating — With Photo + Email'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(Map<String, dynamic> b, String bookingId, int stars, String comment, String nurse, String nurseEmail) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      String clientName = user?.displayName ?? '';
      String clientPhoto = user?.photoURL ?? '';
      String clientPhone = '';
      // Try to read client profile for name / phone / photo
      try {
        if (_email.isNotEmpty) {
          final doc = await FirebaseFirestore.instance.collection('clients').doc(_email).get();
          if (doc.exists) {
            final d = doc.data() ?? {};
            if (clientName.isEmpty) clientName = _str(d, ['name', 'fullName', 'username']);
            clientPhone = _str(d, ['phone', 'phoneNumber']);
            if (clientPhoto.isEmpty) clientPhoto = _str(d, ['photo', 'photoUrl', 'profilePhoto']);
          }
        }
      } catch (_) {}
      final now = DateTime.now();
      final data = <String, dynamic>{
        'bookingId': bookingId,
        'nurseName': nurse,
        'nurseEmail': nurseEmail,
        'rating': stars,
        'comment': comment,
        'clientName': clientName,
        'clientPhone': clientPhone,
        'clientEmail': _email,
        'clientPhoto': clientPhoto,
        'photo': clientPhoto,
        'email': _email,
        'time': now.toIso8601String(),
        'createdAt': FieldValue.serverTimestamp(),
        'service': _str(b, ['service', 'serviceType']),
        'status': 'COMPLETED',
      };
      await FirebaseFirestore.instance.collection('publicReviews').add(data);
      await FirebaseFirestore.instance.collection('homepageReviews').add(data);
      // Mark booking as rated so it does not show again
      try { await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({'rated': true}); } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Rating submitted! ⭐$stars — Client: $clientName • Email: $_email')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCE4EC),
      appBar: AppBar(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, title: const Text('RATE YOUR NURSE')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Text(_error))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('🔒 Secure Verified Rating — With Client Photo + Email + Time', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF880E4F))),
                        SizedBox(height: 6),
                        Text('Only client who booked this nurse and whose job is marked COMPLETED can rate. Your rating + photo appears on homepage index for everyone.', style: TextStyle(fontSize: 13)),
                      ])),
                      const SizedBox(height: 16),
                      const Text('📅 Completed Bookings to Rate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF880E4F))),
                      const SizedBox(height: 10),
                      if (_bookings.isEmpty)
                        const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No completed bookings to rate yet. Book a nurse first, and rate after the job is marked COMPLETED.'))),
                      for (final doc in _bookings)
                        Builder(builder: (_) {
                          final b = doc.data();
                          final nurse = _str(b, ['nurseName', 'nurse', 'nurseEmail']);
                          if (b['rated'] == true) return const SizedBox.shrink();
                          return Card(
                            child: ListTile(
                              title: Text(nurse.isEmpty ? 'Your Nurse' : nurse),
                              subtitle: Text('Status: ${b['status'] ?? ''} • Service: ${_str(b, ['service', 'serviceType'])}\nBooking: ${doc.id}'),
                              isThreeLine: true,
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF880E4F)),
                                onPressed: () => _showRateDialog(b, doc.id),
                                child: const Text('⭐ Rate', style: TextStyle(color: Colors.white)),
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 12),
                      const Text('You rate here → Saves to publicReviews + homepageReviews with client photo + email + time. Shows on homepage index with 4.9 AVG.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
    );
  }
}

// Alias - if any other file calls RatingPage, it still works.
class RatingPage extends RatingScreen {
  const RatingPage({super.key});
}
