import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

/// Index Screen - FULL Flutter version of index.html (index_4.html) - HOME PAGE
/// - Welcome: LOVE CARE GLOBAL HOME NURSING
/// - CEO Banner: ceoHomePageCurrent + homePageBanner/current (video with sound)
/// - Roles: Join as Nurse / Book a Nurse
/// - Features: Live Tracking + GPS, Paystack 50%, 2-Step Verified
/// - Client Ratings on Nurses - High Rank (from RTDB)
/// - Drawer: Home, About, Services, How It Works, Contact, Consent, Privacy, Terms, Refund, Delete Account, SOS

class IndexScreen extends StatefulWidget {
  const IndexScreen({super.key});
  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  Map? bannerData;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  List<Map> topNurses = [];
  bool showBanner = true;

  @override
  void initState() {
    super.initState();
    _listenBanner();
    _loadTopNurses();
  }

  void _listenBanner() {
    FirebaseDatabase.instance.ref('ceoHomePageCurrent').onValue.listen((e) {
      final d = e.snapshot.value as Map?;
      if (d != null && (d['active'] == true || d['isHomePage'] == true)) {
        setState(() { bannerData = d; showBanner = true; });
        _setupVideo(d);
      }
    });
    FirebaseDatabase.instance.ref('homePageBanner/current').onValue.listen((e) {
      final d = e.snapshot.value as Map?;
      if (d != null && bannerData == null) {
        setState(() { bannerData = d; showBanner = true; });
        _setupVideo(d);
      }
    });
  }

  void _setupVideo(Map data) {
    final vUrl = data['videoURL'] ?? data['video'] ?? data['videoUrl'] ?? (data['videos'] is List && (data['videos'] as List).isNotEmpty ? (data['videos'][0]['url'] ?? data['videos'][0]['data']) : null);
    if (vUrl != null && vUrl.toString().startsWith('http')) {
      _videoController?.dispose();
      _chewieController?.dispose();
      _videoController = VideoPlayerController.networkUrl(Uri.parse(vUrl.toString()));
      _videoController!.initialize().then((_) {
        if (!mounted) return;
        _videoController!.setVolume(1.0);
        setState(() {
          _chewieController = ChewieController(
            videoPlayerController: _videoController!,
            autoPlay: false, looping: false, showControls: true, allowFullScreen: true, allowMuting: true,
            placeholder: Container(color: Colors.black, child: const Center(child: Text('🔊 CEO Video - Tap Play', style: TextStyle(color: Colors.white)))),
          );
        });
      });
    }
  }

  void _loadTopNurses() {
    // Top rated nurses - same as PWA Client Ratings section
    FirebaseDatabase.instance.ref('nurses').orderByChild('rating').limitToLast(10).onValue.listen((e) {
      final data = e.snapshot.value as Map?;
      if (data == null) return;
      final list = data.entries.map((en) => {...(en.value as Map), 'uid': en.key}).where((n) => n['isApproved'] == true || n['approved'] == true || n['canLogin'] == true).toList();
      list.sort((a, b) => ((b['rating'] ?? 5.0) as num).compareTo((a['rating'] ?? 5.0) as num));
      setState(() => topNurses = List<Map>.from(list));
    });
  }

  @override
  void dispose() { _videoController?.dispose(); _chewieController?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(
        title: const Text('LOVE CARE GLOBAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF1A1633),
        actions: [
          IconButton(icon: const Icon(Icons.notifications), onPressed: () => Navigator.pushNamed(context, '/sound-settings')),
          IconButton(icon: const Icon(Icons.person), onPressed: () => Navigator.pushNamed(context, '/login')),
        ],
      ),
      drawer: _buildDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // CEO Banner - same as PWA ceoHomeBanner
          if (bannerData != null && showBanner) _buildCEOBanner(),
          // Welcome
          Container(
            width: double.infinity, padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1E0A3A), Color(0xFF2A1A52)]), borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Welcome to', style: TextStyle(color: Colors.white70, fontSize: 16)),
              const Text('LOVE CARE GLOBAL\nHOME NURSING', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, height: 1.1)),
              const SizedBox(height: 8),
              const Text('Your health, our heart.\nWe bring licensed nurses right to your doorstep — compassionate, professional care in 8 countries, 24/7. Now with live tracking, secure Paystack, and 2-step verified nurses.', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _roleCard('Join as Nurse', 'Verified, earn with jobs — GPS + video profile', 'Register (2 steps)', '/register', 'Login', '/login')),
                const SizedBox(width: 10),
                Expanded(child: _roleCard('Book a Nurse', 'See photo/video/rating before you pay', 'Register', '/register', 'Login', '/login')),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          // Features grid - same as PWA grid3
          GridView.count(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.85,
            children: [
              _feat('📍', 'Live Tracking + GPS Verified', 'Track nurse in real time.'),
              _feat('⚡', 'Secure Paystack + Pay on Delivery', 'Pay GHS/USD + 50% online.'),
              _feat('✅', '2-Step Verified Nurses', 'Photo, ID, Licence, Video checked by CEO.'),
            ],
          ),
          const SizedBox(height: 20),
          // Ratings
          Row(children: [const Text('👩‍⚕️ Client Ratings on Nurses — High Rank', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)), const Spacer(), TextButton(onPressed: () => Navigator.pushNamed(context, '/sound-settings'), child: const Text('See all'))]),
          const SizedBox(height: 8),
          if (topNurses.isEmpty) Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(12)), child: const Text('No approved nurses yet — CEO must approve nurses first.', style: TextStyle(color: Colors.white60))),
          ...topNurses.take(5).map((n) => _nurseCard(n)),
          const SizedBox(height: 20),
          // SOS + Contact
          Row(children: [
            Expanded(child: ElevatedButton.icon(onPressed: () => Navigator.pushNamed(context, '/sound-settings'), icon: const Icon(Icons.emergency), label: const Text('SOS Emergency'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: () => Navigator.pushNamed(context, '/sound-settings'), icon: const Icon(Icons.call), label: const Text('+233544121814'))),
          ]),
          const SizedBox(height: 30),
          const Center(child: Text('LOVE CARE GLOBAL • Your health, our heart • CEO: Asabere Peter', style: TextStyle(color: Colors.white38, fontSize: 10))),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => Navigator.pushNamed(context, '/group-chat'), backgroundColor: const Color(0xFFA855F7), icon: const Icon(Icons.chat), label: const Text('Nurses Chat')),
    );
  }

  Widget _buildCEOBanner() {
    final bgHex = (bannerData!['bgColor'] ?? '#1A1633').toString().replaceAll('#', '');
    final bgColor = Color(int.parse('0xFF$bgHex'));
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFACC15), width: 2)),
      child: Column(children: [
        ListTile(
          leading: const CircleAvatar(child: Text('👑')),
          title: Text('👑 ${bannerData!['senderName'] ?? 'CEO Announcement — Asabere Peter'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
          subtitle: const Text('Just now • LoveCare Global', style: TextStyle(color: Colors.white60, fontSize: 10)),
          trailing: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => showBanner = false)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(bannerData!['text']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            if (_chewieController != null) ...[
              const SizedBox(height: 10),
              AspectRatio(aspectRatio: 16/9, child: Chewie(controller: _chewieController!)),
              const SizedBox(height: 6),
              const Text('🔊 Sound ON - Tap 🔊 if no sound', style: TextStyle(color: Color(0xFF86EFAC), fontSize: 10, fontWeight: FontWeight.bold)),
            ],
            if (bannerData!['images'] is List) ...[(bannerData!['images'] as List).map((img) => Padding(padding: const EdgeInsets.only(top: 8), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(img['url'] ?? img['data'] ?? '', height: 200, width: double.infinity, fit: BoxFit.cover))))],
          ]),
        ),
      ]),
    );
  }

  Widget _roleCard(String title, String desc, String btn1, String route1, String btn2, String route2) {
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
      const SizedBox(height: 4),
      Text(desc, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pushNamed(context, route1), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), padding: const EdgeInsets.symmetric(vertical: 6)), child: Text(btn1, style: const TextStyle(fontSize: 11)))),
      const SizedBox(height: 4),
      SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => Navigator.pushNamed(context, route2), child: Text(btn2, style: const TextStyle(fontSize: 11, color: Colors.white)))),
    ]));
  }

  Widget _feat(String emoji, String title, String desc) {
    return Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(12)), child: Column(children: [Text(emoji, style: const TextStyle(fontSize: 18)), const SizedBox(height: 6), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white)), const SizedBox(height: 4), Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 10))]));
  }

  Widget _nurseCard(Map n) {
    final photo = n['photoURL'] ?? n['photo'] ?? '';
    final rating = (n['rating'] ?? 5.0).toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        CircleAvatar(radius: 28, backgroundImage: photo.toString().isNotEmpty ? NetworkImage(photo.toString()) : null, child: photo.toString().isEmpty ? const Text('👩') : null),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(n['name']?.toString() ?? 'Nurse', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          Text('${n['country'] ?? ''} • ${n['specialty'] ?? 'General Nurse'}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
          Row(children: [const Icon(Icons.star, color: Colors.amber, size: 14), Text(' $rating • Verified ✅', style: const TextStyle(color: Colors.white70, fontSize: 11))]),
        ])),
        ElevatedButton(onPressed: () => Navigator.pushNamed(context, '/sound-settings'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7)), child: const Text('Book')),
      ]),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF1A1633),
      child: ListView(children: [
        const DrawerHeader(decoration: BoxDecoration(color: Color(0xFF1A1633)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('LOVE CARE GLOBAL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)), SizedBox(height: 6), Text('Your health, our heart', style: TextStyle(color: Colors.white60))])),
        _drawerItem('🏠 Home', () {}),
        _drawerItem('ℹ️ About', () {}),
        _drawerItem('🩺 Services', () {}),
        _drawerItem('❓ How It Works', () {}),
        _drawerItem('📞 Contact - +233544121814', () {}),
        _drawerItem('📝 Consent Form', () {}),
        _drawerItem('🔒 Privacy', () {}),
        _drawerItem('📜 Terms', () {}),
        _drawerItem('💰 Refund', () {}),
        _drawerItem('🗑️ Delete Account', () {}),
        _drawerItem('🚨 SOS Emergency', () {}, isSOS: true),
      ]),
    );
  }

  Widget _drawerItem(String title, VoidCallback onTap, {bool isSOS = false}) {
    return ListTile(title: Text(title, style: TextStyle(color: isSOS ? Colors.red : Colors.white)), onTap: onTap);
  }
}

// Alias so old name still works:
typedef HomeScreen = IndexScreen;
