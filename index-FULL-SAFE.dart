import 'package:flutter/material.dart';

/// FULL-LOOK Home Page - SAFE version
/// Looks like real home page, but uses ONLY material.
/// No video_player, no chewie, no firebase_database.
/// So it CANNOT fail to compile. Banner shows as image, video opens on tap.
class IndexScreen extends StatefulWidget {
  const IndexScreen({super.key});
  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  // Top nurses - will come from Firebase later, static for now so build stays green
  final List<Map<String, String>> topNurses = [
    {'name': 'Nurse Ama', 'role': 'Home Care Nurse - Accra', 'rating': '4.9', 'img': 'https://i.pravatar.cc/150?img=47'},
    {'name': 'Nurse Kofi', 'role': 'Elderly Care - Kumasi', 'rating': '4.8', 'img': 'https://i.pravatar.cc/150?img=12'},
    {'name': 'Nurse Efua', 'role': 'Postnatal Care - Takoradi', 'rating': '4.9', 'img': 'https://i.pravatar.cc/150?img=32'},
  ];

  void _tap(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('LOVE CARE GLOBAL'), backgroundColor: const Color(0xFFA855F7)),
      drawer: Drawer(
        backgroundColor: const Color(0xFF1E1533),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(decoration: BoxDecoration(color: Color(0xFFA855F7)), child: Text('LOVE CARE GLOBAL\nHOME NURSING', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900))),
            _drawerItem('🏠 Home', () {}),
            _drawerItem('ℹ️ About', () {}),
            _drawerItem('🛎️ Services', () {}),
            _drawerItem('⚙️ How It Works', () {}),
            _drawerItem('📞 Contact', () {}),
            _drawerItem('✅ Consent', () {}),
            _drawerItem('🔒 Privacy', () {}),
            _drawerItem('📄 Terms', () {}),
            _drawerItem('💳 Refund', () {}),
            _drawerItem('🗑️ Delete Account', () {}),
            _drawerItem('🆘 SOS', () {}),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('LOVE CARE GLOBAL', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
            const Text('HOME NURSING', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFFC084FC))),
            const SizedBox(height: 8),
            const Text('Welcome to LOVE CARE GLOBAL HOME NURSING. Book a verified nurse to your home, or join as a nurse.', style: TextStyle(color: Color(0xFFD8B4FE), fontSize: 16)),
            const SizedBox(height: 16),
            // CEO BANNER - image for now, tap to play video later
            GestureDetector(
              onTap: () => _tap('CEO Banner Video - will play with sound in next update'),
              child: Container(
                height: 180,
                decoration: BoxDecoration(color: const Color(0xFF2A1F45), borderRadius: BorderRadius.circular(16), image: const DecorationImage(image: NetworkImage('https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?w=800'), fit: BoxFit.cover)),
                child: Container(
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.35), borderRadius: BorderRadius.circular(16)),
                  alignment: Alignment.center,
                  child: const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.play_circle_fill, size: 64, color: Colors.white), SizedBox(height: 6), Text('▶ CEO BANNER VIDEO - Tap to Play with Sound', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center)]),
                ),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), padding: const EdgeInsets.all(16)), onPressed: () => _tap('Join as Nurse - upload nurse_register.dart to lib/screens/ to open it'), child: const Text('👩‍⚕️ JOIN AS NURSE - Register')),
            const SizedBox(height: 10),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.all(16)), onPressed: () => _tap('Book a Nurse - upload book_nurse.dart to lib/screens/ to open it'), child: const Text('🛏️ BOOK A NURSE - Book Now')),
            const SizedBox(height: 10),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.all(16)), onPressed: () => _tap('Join as Client - upload client_register.dart to lib/screens/ to open it'), child: const Text('👤 JOIN AS CLIENT - Register')),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => _tap('Nurse Login'), child: const Text('🔑 Nurse Login')),
            OutlinedButton(onPressed: () => _tap('Client Login'), child: const Text('🔑 Client Login')),
            OutlinedButton(onPressed: () => _tap('CEO Dashboard'), child: const Text('👑 CEO Dashboard')),
            const SizedBox(height: 20),
            const Text('✨ Why Love Care?', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _feature('📍 Live Tracking + GPS', 'Track your nurse live on the map.'),
            _feature('💳 Paystack 50%', 'Pay 50% to book, 50% after care.'),
            _feature('✅ 2-Step Verified', 'Photo + Phone + Video + CEO Approval.'),
            _feature('🔔 Background Notifications', 'Flutter notifies you even when app is closed.'),
            const SizedBox(height: 20),
            const Text('⭐ Top Rated Nurses - Client Ratings', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...topNurses.map((n) => Card(
              color: const Color(0xFF1E1533),
              child: ListTile(
                leading: CircleAvatar(backgroundImage: NetworkImage(n['img']!)),
                title: Text(n['name']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(n['role']!, style: const TextStyle(color: Color(0xFFB9A6E6))),
                trailing: Text('⭐ ${n['rating']}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              ),
            )),
            const SizedBox(height: 20),
            const Text('LOVE CARE GLOBAL • Same Firebase as PWA • Photo + Phone + Video + CEO Approval required', style: TextStyle(color: Color(0xFFB9A6E6), fontSize: 12), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(String title, VoidCallback onTap) {
    return ListTile(title: Text(title, style: const TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); onTap(); });
  }

  Widget _feature(String title, String sub) {
    return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF2A1F45), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(sub, style: const TextStyle(color: Color(0xFFB9A6E6)))]));
  }
}

typedef HomeScreen = IndexScreen;
