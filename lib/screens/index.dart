import 'package:flutter/material.dart';

class IndexScreen extends StatefulWidget {
  const IndexScreen({super.key});
  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('LOVE CARE GLOBAL'), backgroundColor: const Color(0xFFA855F7)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('LOVE CARE GLOBAL', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
            const Text('HOME NURSING', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFFC084FC))),
            const SizedBox(height: 10),
            const Text('Welcome to LOVE CARE GLOBAL HOME NURSING. Book a verified nurse to your home, or join as a nurse. Live Tracking + GPS, Paystack 50%, 2-Step Verified.', style: TextStyle(color: Color(0xFFD8B4FE), fontSize: 16)),
            const SizedBox(height: 20),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), padding: const EdgeInsets.all(16)), onPressed: () {}, child: const Text('JOIN AS NURSE - Register')),
            const SizedBox(height: 10),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.all(16)), onPressed: () {}, child: const Text('BOOK A NURSE - Book Now')),
            const SizedBox(height: 10),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.all(16)), onPressed: () {}, child: const Text('JOIN AS CLIENT - Register')),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () {}, child: const Text('Nurse Login')),
            OutlinedButton(onPressed: () {}, child: const Text('Client Login')),
            OutlinedButton(onPressed: () {}, child: const Text('CEO Dashboard')),
            const SizedBox(height: 20),
            const Text('Why Love Care?', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const Text('Live Tracking + GPS\nPaystack 50%\n2-Step Verified - Photo + Phone + Video + CEO Approval\nBackground Notifications', style: TextStyle(color: Color(0xFFB9A6E6), fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

typedef HomeScreen = IndexScreen;
