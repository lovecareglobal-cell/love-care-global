import 'package:flutter/material.dart';

class IndexScreen extends StatelessWidget {
  const IndexScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B3D91),
        title: const Text('LOVE CARE GLOBAL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                'https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?w=1200&q=80',
                height: 220, fit: BoxFit.cover,
                errorBuilder: (c, e, s) => Container(height: 220, color: const Color(0xFF0B3D91), child: const Center(child: Icon(Icons.favorite, color: Colors.white, size: 64))),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Home Nursing, With Love & Care', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0B3D91))),
            const SizedBox(height: 8),
            const Text('Trusted nurses at your home — Ghana & worldwide. Book a nurse, manage bookings, chat and get care.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.black54)),
            const SizedBox(height: 24),
            _btn(context, 'Register as Client', const Color(0xFF0B3D91)),
            const SizedBox(height: 12),
            _btn(context, 'Register as Nurse', const Color(0xFF00A651)),
            const SizedBox(height: 12),
            _btn(context, 'Login', Colors.black87),
            const SizedBox(height: 12),
            _btn(context, 'Book a Nurse', const Color(0xFFFF6B00)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: const Column(
                children: [
                  Row(children: [Icon(Icons.verified, color: Color(0xFF00A651)), SizedBox(width: 8), Expanded(child: Text('CEO-Approved Nurses Only'))]),
                  SizedBox(height: 10),
                  Row(children: [Icon(Icons.video_call, color: Color(0xFF0B3D91)), SizedBox(width: 8), Expanded(child: Text('Video-verified nurses with sound'))]),
                  SizedBox(height: 10),
                  Row(children: [Icon(Icons.location_on, color: Colors.red), SizedBox(width: 8), Expanded(child: Text('Live tracking & home visits'))]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(BuildContext context, String label, Color color) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      onPressed: () {},
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}
