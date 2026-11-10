import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

/// Home Screen - Same as index.html but in Flutter
/// Reads CEO banner from same Firebase RTDB: ceoHomePageCurrent / homePageBanner/current
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map? bannerData;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _listenToCEOBanner();
  }

  void _listenToCEOBanner() {
    // Listen to CEO banner - same path as PWA
    FirebaseDatabase.instance.ref('ceoHomePageCurrent').onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        setState(() => bannerData = data);
        _setupVideo(data);
      }
    });
    // Fallback: homePageBanner/current
    FirebaseDatabase.instance.ref('homePageBanner/current').onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && bannerData == null) {
        setState(() => bannerData = data);
        _setupVideo(data);
      }
    });
  }

  void _setupVideo(Map data) {
    final videoUrl = data['videoURL'] ?? data['video'] ?? data['videoUrl'] ?? (data['videos'] is List && (data['videos'] as List).isNotEmpty ? (data['videos'][0]['url'] ?? data['videos'][0]['data']) : null);
    if (videoUrl != null && videoUrl.toString().startsWith('http')) {
      _videoController?.dispose();
      _chewieController?.dispose();
      _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl.toString()));
      _videoController!.initialize().then((_) {
        setState(() {
          // Sound ON - volume 1.0, not muted (fixes PWA muted bug)
          _videoController!.setVolume(1.0);
          _chewieController = ChewieController(
            videoPlayerController: _videoController!,
            autoPlay: false,
            looping: false,
            showControls: true,
            allowFullScreen: true,
            allowMuting: true,
            placeholder: Container(color: Colors.black, child: const Center(child: Text('🔊 CEO Video - Tap Play', style: TextStyle(color: Colors.white)))),
          );
        });
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(
        title: const Text('👩‍⚕️ LOVE CARE GLOBAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF1A1633),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CEO Banner - Same as PWA ceoHomeBanner
            if (bannerData != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Color(int.parse((bannerData!['bgColor'] ?? '#1A1633').replaceAll('#', '0xFF'))),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFACC15), width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const CircleAvatar(child: Text('👑')),
                      const SizedBox(width: 10),
                      Expanded(child: Text('👑 ${bannerData!['senderName'] ?? 'CEO Announcement'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                    ]),
                    const SizedBox(height: 8),
                    Text(bannerData!['text']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 14)),
                    if (_chewieController != null) ...[
                      const SizedBox(height: 10),
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Chewie(controller: _chewieController!),
                      ),
                      const SizedBox(height: 6),
                      const Text('🔊 Sound ON - Tap 🔊 if no sound', style: TextStyle(color: Color(0xFF86EFAC), fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                    if (bannerData!['images'] != null && (bannerData!['images'] as List).isNotEmpty)
                      ...((bannerData!['images'] as List).map((img) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(img['url'] ?? img['data'] ?? '', height: 200, width: double.infinity, fit: BoxFit.cover)),
                      ))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text('Your health, our heart.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            const Text('Licensed nurses to your doorstep - 24/7 in 8 countries', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            _buildButton('📋 Book a Nurse', () => Navigator.pushNamed(context, '/login')),
            _buildButton('👩‍⚕️ Nurse Register', () => Navigator.pushNamed(context, '/register')),
            _buildButton('💬 Nurses Group Chat', () => Navigator.pushNamed(context, '/group-chat')),
            _buildButton('👑 CEO Control', () => Navigator.pushNamed(context, '/ceo')),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ),
    );
  }
}
