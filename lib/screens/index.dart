import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class IndexScreen extends StatelessWidget {
  const IndexScreen({super.key});
  DatabaseReference ref(String path) => FirebaseDatabase.instance.ref(path);

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF150A2E);
    const card = Color(0xFF241245);
    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton(heroTag: 'chat', onPressed: () { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat opening soon'))); }, backgroundColor: const Color(0xFF00C853), child: const Icon(Icons.chat, color: Colors.white)),
        const SizedBox(height: 12),
        FloatingActionButton(heroTag: 'call', onPressed: () { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Calling Love Care Global...'))); }, backgroundColor: const Color(0xFF00C853), child: const Icon(Icons.call, color: Colors.white)),
      ]),
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 100), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // TOP BAR
        Row(children: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.menu, color: Colors.white, size: 32)),
          const SizedBox(width: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(color: const Color(0xFF7B2FFF), borderRadius: BorderRadius.circular(12)), child: const Row(children: [Icon(Icons.medical_services, color: Colors.white, size: 18), SizedBox(width: 6), Text('PROFESSIONAL\nONLINE NURSE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, height: 1.1))])),
          const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFF1E3A1E), borderRadius: BorderRadius.circular(20)), child: const Text('👋 Hi,\nMichael', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF7CFF7C), fontWeight: FontWeight.bold, fontSize: 12))),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const _SimplePage(title: 'SOS', subtitle: 'Emergency SOS - Your location will be sent to the nearest approved nurse & CEO.'))); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), child: const Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 14),
        // CEO BANNER - LIVE FROM FIREBASE: ceo_banner/{name, message, image, date}
        StreamBuilder<DatabaseEvent>(
          stream: ref('ceo_banner').onValue,
          builder: (c, snap) {
            final v = snap.data?.snapshot.value;
            final m = v is Map ? Map<String, dynamic>.from(v as Map) : <String, dynamic>{};
            final name = (m['name'] ?? 'Asabere Peter').toString();
            final msg = (m['message'] ?? 'CEO: Asabere Peter').toString();
            final date = (m['date'] ?? '05/11/2026, 2:48:19 pm').toString();
            final img = (m['image'] ?? 'https://images.unsplash.com/photo-1622253692010-333f2da6031d?w=900&q=80').toString();
            return Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), padding: const EdgeInsets.all(12), child: Column(children: [
              Row(children: [const CircleAvatar(backgroundColor: Colors.amber, radius: 22, child: Text('AP', style: TextStyle(fontWeight: FontWeight.bold))), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('👑 $name — CEO', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), Text('$date • CEO: $name', style: const TextStyle(fontSize: 11, color: Colors.black54))])), IconButton(onPressed: () {}, icon: const Icon(Icons.close))]),
              const SizedBox(height: 8),
              Text('📢 — 👑 $msg', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('FEATURING OUR\nOFFICIAL UNIFORM', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black, height: 1.0)),
              const Text('LoveCareGlobal', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF3A0A5A))),
              const Text('Your Health, Our Heart', style: TextStyle(color: Color(0xFF0E7C7B), fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(img, height: 300, width: double.infinity, fit: BoxFit.cover, errorBuilder: (cc,e,s) => Container(height: 300, color: const Color(0xFFE8D5FF), child: const Center(child: Icon(Icons.person, size: 100, color: Color(0xFF3A0A5A)))))),
            ]));
          },
        ),
        const SizedBox(height: 18),
        const Text('Welcome to', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
        const Text('LOVE CARE\nGLOBAL HOME\nNURSING', style: TextStyle(color: Color(0xFFC99CFF), fontSize: 36, fontWeight: FontWeight.bold, height: 1.0)),
        const SizedBox(height: 10),
        const Text('Your health, our heart.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 6),
        const Text('We bring licensed nurses right to your doorstep — compassionate, professional care in 8 countries, 24/7. Now with live tracking, secure Paystack, and 2-step verified nurses.', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
        const SizedBox(height: 18),
        _actionCard(context, title: 'Join as Nurse', sub: 'Verified, earn with jobs — GPS + video profile', btn1: 'Register (2 steps)', page1: const _SimplePage(title: 'Register as Nurse', subtitle: 'Step 1: Photo, Phone, Video, National ID + CV. Step 2: CEO approval. No login without CEO approval.'), btn2: 'Login', page2: const _SimplePage(title: 'Nurse Login', subtitle: 'Login with phone & password. Only CEO-approved nurses can login.')),
        const SizedBox(height: 14),
        _actionCard(context, title: 'Book a Nurse', sub: 'See photo/video/rating before you pay', btn1: 'Register', page1: const _SimplePage(title: 'Register as Client', subtitle: 'Create your client account to book a nurse.'), btn2: 'Login', page2: const _SimplePage(title: 'Client Login', subtitle: 'Login with phone & password to manage bookings.')),
        const SizedBox(height: 18),
        _feature('⚡', 'Secure Paystack + Pay on Delivery', 'Pay GHS/USD + new 50% online option. No double booking — availability lock.'),
        const SizedBox(height: 12),
        _feature('💜', '2-Step Verified Nurses', 'Photo, ID, Licence, Video checked by CEO. Only approved nurses show ONLINE.'),
        const SizedBox(height: 18),
        // RATINGS - LIVE FROM FIREBASE: ratings/ (each child = one rating)
        const Text('👩‍⚕️ Client Ratings on Nurses — High Rank', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 6),
        StreamBuilder<DatabaseEvent>(
          stream: ref('ratings').onValue,
          builder: (c, snap) {
            final v = snap.data?.snapshot.value;
            int count = 0; double avg = 0;
            if (v is Map) { count = v.length; double sum = 0; v.forEach((k, val) { if (val is Map && val['stars'] != null) sum += double.tryParse(val['stars'].toString()) ?? 0; }); if (count > 0) avg = sum / count; }
            if (count == 0) {
              return Column(children: [const Text('🟢 LIVE • Sorted by highest •  0  nurses rated', style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)), const SizedBox(height: 10), Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)), child: const Column(children: [Icon(Icons.star, color: Colors.amber, size: 48), SizedBox(height: 8), Text('No ratings yet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)), SizedBox(height: 6), Text('Real client ratings will appear here after bookings are completed.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)), Text('Verified bookings only', style: TextStyle(color: Colors.white54))]))]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('🟢 LIVE • Sorted by highest •  $count  nurses rated • Avg ${avg.toStringAsFixed(1)} ⭐', style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)), const SizedBox(height: 10), Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)), child: Row(children: [const Icon(Icons.star, color: Colors.amber, size: 44), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$avg ⭐ Average', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)), Text('$count verified ratings from clients', style: const TextStyle(color: Colors.white54))]))]))]);
          },
        ),
        const SizedBox(height: 10),
        const Text('⭐ Ratings reflect live from Firebase / ratings — Verified bookings only', style: TextStyle(color: Colors.amber, fontSize: 12)),
        const SizedBox(height: 14),
        // APPROVED NURSES COUNT - LIVE: nurses/ where status == approved
        StreamBuilder<DatabaseEvent>(
          stream: ref('nurses').onValue,
          builder: (c, snap) {
            final v = snap.data?.snapshot.value;
            int approved = 0; int total = 0;
            if (v is Map) { total = v.length; v.forEach((k, val) { if (val is Map && val['status']?.toString() == 'approved') approved++; }); }
            return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)), child: Text('✅ $approved approved nurses ONLINE • $total total in Firebase', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)));
          },
        ),
      ]))),
    );
  }
  Widget _actionCard(BuildContext context, {required String title, required String sub, required String btn1, required Widget page1, required String btn2, required Widget page2}) {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF241245), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)), const SizedBox(height: 4), Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 13)), const SizedBox(height: 12), Row(children: [Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC99CFF), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => page1)); }, child: Text(btn1, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))), const SizedBox(width: 10), Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3A2A5A), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => page2)); }, child: Text(btn2, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),])]));
  }
  Widget _feature(String emoji, String title, String sub) {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF241245), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(emoji, style: const TextStyle(fontSize: 22)), const SizedBox(height: 6), Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)), const SizedBox(height: 4), Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 13))]));
  }
}
class _SimplePage extends StatelessWidget {
  final String title; final String subtitle;
  const _SimplePage({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF150A2E), appBar: AppBar(backgroundColor: const Color(0xFF7B2FFF), title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), iconTheme: const IconThemeData(color: Colors.white)), body: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 10), Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 15)), const SizedBox(height: 20), const TextField(style: TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Full Name', labelStyle: TextStyle(color: Colors.white70), border: OutlineInputBorder(), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white38)))), const SizedBox(height: 12), const TextField(style: TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Phone', labelStyle: TextStyle(color: Colors.white70), border: OutlineInputBorder(), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white38))), keyboardType: TextInputType.phone), const SizedBox(height: 12), const TextField(style: TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Password', labelStyle: TextStyle(color: Colors.white70), border: OutlineInputBorder(), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white38))), obscureText: true), const SizedBox(height: 20), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC99CFF), padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: () { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved - Full form coming next'))); }, child: const Text('Continue', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))), const SizedBox(height: 12), TextButton(onPressed: () { Navigator.pop(context); }, child: const Text('Back to Home', style: TextStyle(color: Colors.white)))])));
  }
}
