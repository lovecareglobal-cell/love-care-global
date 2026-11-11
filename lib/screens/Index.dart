
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;

void main() {
  runApp(const LoveCareApp());
}

class LoveCareApp extends StatelessWidget {
  const LoveCareApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Love Care Global',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0F0A1E),
        primaryColor: const Color(0xFFA855F7),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFA855F7), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class CeoPost {
  final String text;
  final String? videoUrl;
  final String? voiceUrl;
  final String displayType; // banner or ticker
  final String speed;
  const CeoPost({required this.text, this.videoUrl, this.voiceUrl, this.displayType = 'banner', this.speed = 'normal'});
}

// CHANGE THIS to your CEO video from CEO Control / Storage
const CeoPost ceoPost = CeoPost(
  text: 'Welcome to Love Care Global. Home Nursing, With Love. We are here for you and your family, 24/7.',
  videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
  displayType: 'banner',
);

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _showCeoBanner = true;
  bool _showTicker = false;
  bool _soundOn = true;

  // --- VIDEO WITH SOUND FIX (Web) ---
  // This is the Flutter version of your JS:
  // vd.muted = false; vd.volume = 1.0; vd.controls = true; vd.playsInline = true;
  Widget _buildVideoWithSound(String url) {
    if (!kIsWeb) {
      return Container(
        height: 220,
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: const Text('🎥 CEO Video\n(Sound works on Web)', textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
      );
    }
    // Unique view type per video
    final viewType = 'ceo-video-${url.hashCode}';
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final video = html.VideoElement()
        ..src = url
        ..controls = true
        ..autoplay = false
        ..muted = false // FIX: Sound ON, not muted
        ..volume = 1.0 // FIX: Full volume
        ..preload = 'metadata'
        ..setAttribute('playsinline', '')
        ..style.width = '100%'
        ..style.maxHeight = '500px'
        ..style.background = '#000'
        ..style.borderRadius = '12px';
      video.onLoadedData.listen((_) {
        video.volume = 1.0;
        video.muted = false;
      });
      video.onPlay.listen((_) {
        video.volume = 1.0;
        video.muted = false;
      });
      return video;
    });
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(height: 280, width: double.infinity, child: HtmlElementView(viewType: viewType)),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.black.withOpacity(0.7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('🔊 Sound ON - Tap ▶️ if no sound', style: TextStyle(fontSize: 10, color: Color(0xFF86EFAC), fontWeight: FontWeight.w700)),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), foregroundColor: Colors.black),
                onPressed: () {
                  setState(() => _soundOn = true);
                  // Re-trigger: browser needs user gesture, this button IS the gesture
                  html.window.alert('Sound is ON. Press Play on the video now.');
                },
                child: const Text('▶️ Play with Sound', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openCall(String url) {
    if (kIsWeb) html.window.open(url, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E0A3A),
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
        title: Row(children: [
          const CircleAvatar(backgroundColor: Color(0xFFFACC15), child: Text('LC', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900))),
          const SizedBox(width: 8),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Love Care Global', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            Text('Home Nursing, With Love.', style: TextStyle(fontSize: 10, color: Color(0xFFD8B4FE))),
          ]),
        ]),
        actions: [
          IconButton(icon: const Text('⋯', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), onPressed: () => _showDotsMenu(context)),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // CEO BANNER
              if (_showCeoBanner) _buildCeoBanner(),
              const SizedBox(height: 16),
              // HERO
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2A1A52), Color(0xFF1E0A3A)]), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.3))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('💜 Home Nursing,\nWith Love.', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 8),
                  const Text('Trusted nurses, carers & support for your family in Accra and beyond. Book in minutes.', style: TextStyle(color: Color(0xFFC4B5FD), fontSize: 13)),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7)), onPressed: () {}, child: const Text('Register', style: TextStyle(fontWeight: FontWeight.w900)))),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('Login', style: TextStyle(color: Color(0xFFD8B4FE))))),
                  ]),
                ]),
              ),
              const SizedBox(height: 18),
              const Text('Our Services', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 10),
              _buildFeatures(),
              const SizedBox(height: 18),
              const Text('⭐ What Families Say', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 10),
              _buildTestimonials(),
              const SizedBox(height: 80),
            ]),
          ),
          // FLOATING CALL BUTTONS
          Positioned(
            bottom: 20, right: 20,
            child: Column(children: [
              FloatingActionButton(backgroundColor: const Color(0xFF22C55E), onPressed: () => _openCall('tel:+233000000000'), child: const Icon(Icons.call, color: Colors.white)),
              const SizedBox(height: 10),
              FloatingActionButton(backgroundColor: const Color(0xFF25D366), onPressed: () => _openCall('https://wa.me/233000000000'), child: const Text('💬', style: TextStyle(fontSize: 22))),
            ]),
          ),
          // TICKER
          if (_showTicker)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(color: const Color(0xFFFACC15), padding: const EdgeInsets.all(10), child: Text('📢 ${ceoPost.text} — CEO: Asabere Peter', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700))),
            ),
        ],
      ),
    );
  }

  Widget _buildCeoBanner() {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.3))),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CircleAvatar(backgroundColor: Color(0xFFFACC15), child: Text('AP', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900))),
          const SizedBox(width: 10),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('👑 CEO Announcement — Asabere Peter', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)), Text('Just now • LoveCare Global', style: TextStyle(fontSize: 11, color: Color(0xFFA78BFA)))])),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _showCeoBanner = false)),
        ]),
        const SizedBox(height: 10),
        Text(ceoPost.text, style: const TextStyle(color: Color(0xFFEDE9FE), fontSize: 13, height: 1.5)),
        const SizedBox(height: 10),
        if (ceoPost.videoUrl != null) _buildVideoWithSound(ceoPost.videoUrl!),
        const SizedBox(height: 10),
        Row(children: [
          TextButton(onPressed: () => setState(() => _showTicker = !_showTicker), child: const Text('Show as Ticker')),
          TextButton(onPressed: () => setState(() => _showCeoBanner = false), child: const Text('Close', style: TextStyle(color: Colors.redAccent))),
        ]),
      ]),
    );
  }

  Widget _buildFeatures() {
    final feats = [
      ('🏠', 'Home Nursing', 'Professional nurses at your home, 24/7 care.'),
      ('👵', 'Elderly Care', 'Compassionate care for parents & grandparents.'),
      ('🩺', 'Post-Hospital Care', 'Recovery support after hospital discharge.'),
      ('👶', 'Child Care', 'Trusted nannies & child support.'),
      ('💊', 'Medication Help', 'Reminders & safe medication management.'),
      ('🚨', 'Emergency SOS', 'One-tap SOS to reach our team fast.'),
    ];
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.4),
      itemCount: feats.length,
      itemBuilder: (c, i) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.15))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(feats[i].\$1, style: const TextStyle(fontSize: 22)), const SizedBox(height: 6), Text(feats[i].\$2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)), const SizedBox(height: 4), Text(feats[i].\$3, style: const TextStyle(fontSize: 11, color: Color(0xFFA78BFA)))])
      ),
    );
  }

  Widget _buildTestimonials() {
    final t = [
      ('Ama K. — Accra', 'The nurse was so kind to my mother. Love Care Global is a blessing.'),
      ('Kwame M. — East Legon', 'Booked in 5 minutes, nurse came same day. Very professional.'),
      ('Efua A. — Osu', 'My father loves his carer. I can finally sleep in peace.'),
    ];
    return Column(children: t.map((e) => Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF140A1C), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('⭐⭐⭐⭐⭐', style: TextStyle(color: Color(0xFFFACC15), fontSize: 12)), const SizedBox(height: 6), Text(e.\$2, style: const TextStyle(color: Color(0xFFC4B5FD), fontSize: 12, height: 1.6)), const SizedBox(height: 6), Text(e.\$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11))]),
    )).toList());
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF120C24),
      child: ListView(padding: const EdgeInsets.all(14), children: [
        const SizedBox(height: 20),
        const Text('💜 Love Care Global', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const Text('Home Nursing, With Love.', style: TextStyle(color: Color(0xFFA78BFA))),
        const SizedBox(height: 20),
        _drawerItem('🏠 Home', () {}),
        _drawerItem('📝 Register', () {}),
        _drawerItem('🔑 Login', () {}),
        _drawerItem('📋 Consent Form', () {}, highlight: true),
        _drawerItem('🚨 SOS Emergency', () {}, danger: true),
        _drawerItem('🗑️ Delete Account', () {}, danger: true),
        _drawerItem('📞 Call Us', () => _openCall('tel:+233000000000')),
        _drawerItem('💬 WhatsApp', () => _openCall('https://wa.me/233000000000')),
      ]),
    );
  }

  Widget _drawerItem(String title, VoidCallback onTap, {bool highlight = false, bool danger = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: highlight ? const Color(0xFFA855F7) : danger ? Colors.red.withOpacity(0.15) : const Color(0xFF4C1D95).withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
      child: ListTile(title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: highlight ? const Color(0xFF1E0A3A) : danger ? const Color(0xFFFCA5A5) : const Color(0xFFD8B4FE))), onTap: onTap),
    );
  }

  void _showDotsMenu(BuildContext context) {
    showDialog(context: context, builder: (c) => AlertDialog(
      backgroundColor: const Color(0xFF1C1238),
      title: const Text('Menu', style: TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: const Text('Share App', style: TextStyle(color: Color(0xFFD8B4FE))), onTap: () => Navigator.pop(c)),
        ListTile(title: const Text('About CEO', style: TextStyle(color: Color(0xFFD8B4FE))), onTap: () => Navigator.pop(c)),
        ListTile(title: const Text('Exit', style: TextStyle(color: Color(0xFFFCA5A5))), onTap: () => Navigator.pop(c)),
      ]),
    ));
  }
}
