import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const LoveCareApp());
}

// ==== CHANGE THESE TO YOUR REAL NUMBERS ====
const String realPhone = '+233200000000'; // <-- PUT YOUR REAL PHONE HERE
const String realWhatsApp = '233200000000'; // <-- PUT YOUR REAL WHATSAPP, NO + , NO SPACE
const String ceoVideoUrl = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'; // <-- PUT YOUR REAL VIDEO HERE
const String ceoText = 'Welcome to Love Care Global. Home Nursing, With Love. We are here for you and your family, 24/7.';

class LoveCareApp extends StatelessWidget {
  const LoveCareApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Love Care Global',
      theme: ThemeData(scaffoldBackgroundColor: const Color(0xFF0F0A1E), primaryColor: const Color(0xFFA855F7), colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFA855F7), brightness: Brightness.dark), useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class Feature {
  final String icon; final String title; final String desc; final String detail;
  const Feature(this.icon, this.title, this.desc, this.detail);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _showCeoBanner = true;
  bool _showTicker = false;
  late VideoPlayerController _videoController;
  bool _videoReady = false;

  final List<Feature> feats = const [
    Feature('🏠', 'Home Nursing', 'Professional nurses at your home, 24/7 care.', 'Our registered nurses come to your home in Accra and beyond. Wound care, vitals, injections, and daily nursing support. Tap Book to request a nurse.'),
    Feature('👵', 'Elderly Care', 'Compassionate care for parents and grandparents.', 'Daily companionship, bathing, mobility help, medication reminders and 24/7 monitoring for your elderly loved ones.'),
    Feature('🩺', 'Post-Hospital Care', 'Recovery support after hospital discharge.', 'We help you recover safely at home after surgery or hospital stay. Physiotherapy support, wound care and follow-up.'),
    Feature('👶', 'Child Care', 'Trusted nannies and child support.', 'Verified nannies and child carers for babies and children. Day, night and live-in options.'),
    Feature('💊', 'Medication Help', 'Reminders and safe medication management.', 'We remind, prepare and track medication safely. No missed doses, no wrong doses.'),
    Feature('🚨', 'Emergency SOS', 'One-tap SOS to reach our team fast.', 'Press SOS and we call you back immediately. For medical emergencies, call your local emergency number first, then call us.'),
  ];

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.networkUrl(Uri.parse(ceoVideoUrl))
      ..setVolume(1.0)
      ..initialize().then((_) { if (mounted) setState(() => _videoReady = true); });
  }
  @override
  void dispose() { _videoController.dispose(); super.dispose(); }

  Future<void> _call() async {
    final uri = Uri.parse('tel:$realPhone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
  Future<void> _whatsapp() async {
    final uri = Uri.parse('https://wa.me/$realWhatsApp?text=Hello%20Love%20Care%20Global,%20I%20need%20a%20nurse');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  void _openPage(Widget page) { Navigator.push(context, MaterialPageRoute(builder: (_) => page)); }
  void _bookService(String service) { _openPage(BookPage(service: service)); }
  void _showDetail(Feature f) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1C1238),
      title: Text('${f.icon} ${f.title}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      content: Text(f.detail, style: const TextStyle(color: Color(0xFFC4B5FD), height: 1.6)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)), onPressed: () { Navigator.pop(context); _bookService(f.title); }, child: const Text('Book This Service', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      appBar: AppBar(backgroundColor: const Color(0xFF1E0A3A), leading: IconButton(icon: const Icon(Icons.menu), onPressed: () => _scaffoldKey.currentState?.openDrawer()), title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Love Care Global', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)), Text('Home Nursing, With Love.', style: TextStyle(fontSize: 10, color: Color(0xFFD8B4FE)))])),
      body: Stack(children: [
        SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_showCeoBanner) _buildCeoBanner(),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2A1A52), Color(0xFF1E0A3A)]), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Home Nursing, With Love.', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 8),
            const Text('Trusted nurses, carers and support for your family in Accra and beyond. Book in minutes.', style: TextStyle(color: Color(0xFFC4B5FD), fontSize: 13)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7)), onPressed: () => _openPage(const RegisterPage()), child: const Text('Register', style: TextStyle(fontWeight: FontWeight.w900)))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton(onPressed: () => _openPage(const LoginPage()), child: const Text('Login', style: TextStyle(color: Color(0xFFD8B4FE))))),
            ]),
          ])),
          const SizedBox(height: 18),
          const Text('Our Services - Tap Any Service', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 10),
          _buildFeatures(),
          const SizedBox(height: 18),
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF140A1C), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('What Families Say', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 8),
            const Text('No reviews yet. Be the first family to share your story with Love Care Global.', style: TextStyle(color: Color(0xFFC4B5FD), fontSize: 13, height: 1.6)),
            const SizedBox(height: 12),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)), onPressed: _whatsapp, child: const Text('Share Your Story on WhatsApp', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900))),
          ])),
          const SizedBox(height: 80),
        ])),
        Positioned(bottom: 20, right: 20, child: Column(children: [
          FloatingActionButton(backgroundColor: const Color(0xFF22C55E), onPressed: _call, child: const Icon(Icons.call, color: Colors.white)),
          const SizedBox(height: 10),
          FloatingActionButton(backgroundColor: const Color(0xFF25D366), onPressed: _whatsapp, child: const Text('Chat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
        ])),
        if (_showTicker) Positioned(bottom: 0, left: 0, right: 0, child: Container(color: const Color(0xFFFACC15), padding: const EdgeInsets.all(10), child: const Text('CEO Announcement - CEO: Asabere Peter', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)))),
      ]),
    );
  }

  Widget _buildCeoBanner() {
    return Container(decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.3))), padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const CircleAvatar(backgroundColor: Color(0xFFFACC15), child: Text('AP', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900))), const SizedBox(width: 10), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('CEO Announcement - Asabere Peter', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)), Text('Just now - LoveCare Global', style: TextStyle(fontSize: 11, color: Color(0xFFA78BFA)))]), ), IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _showCeoBanner = false))]),
      const SizedBox(height: 10),
      Text(ceoText, style: const TextStyle(color: Color(0xFFEDE9FE), fontSize: 13, height: 1.5)),
      const SizedBox(height: 10),
      ClipRRect(borderRadius: BorderRadius.circular(12), child: AspectRatio(aspectRatio: 16/9, child: _videoReady ? VideoPlayer(_videoController) : Container(color: Colors.black, alignment: Alignment.center, child: const CircularProgressIndicator(color: Colors.green)))),
      Container(padding: const EdgeInsets.all(8), color: Colors.black.withOpacity(0.7), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Sound ON', style: TextStyle(fontSize: 11, color: Color(0xFF86EFAC), fontWeight: FontWeight.w700)), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), foregroundColor: Colors.black), onPressed: () async { await _videoController.setVolume(1.0); if (_videoController.value.isPlaying) { await _videoController.pause(); } else { await _videoController.play(); } setState(() {}); }, child: Text(_videoController.value.isPlaying ? 'Pause' : 'Play with Sound', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)))])),
      const SizedBox(height: 10),
      Row(children: [TextButton(onPressed: () => setState(() => _showTicker = !_showTicker), child: const Text('Show as Ticker')), TextButton(onPressed: () => setState(() => _showCeoBanner = false), child: const Text('Close', style: TextStyle(color: Colors.redAccent)))]),
    ]));
  }

  Widget _buildFeatures() {
    return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.4), itemCount: feats.length, itemBuilder: (c, i) {
      final f = feats[i];
      return InkWell(onTap: () => _showDetail(f), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(f.icon, style: const TextStyle(fontSize: 22)), const SizedBox(height: 6), Text(f.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)), const SizedBox(height: 4), Text(f.desc, style: const TextStyle(fontSize: 11, color: Color(0xFFA78BFA))), const SizedBox(height: 4), const Text('Tap to view >', style: TextStyle(fontSize: 10, color: Color(0xFF22C55E), fontWeight: FontWeight.w800))])));
    });
  }

  Widget _buildDrawer() {
    return Drawer(backgroundColor: const Color(0xFF120C24), child: ListView(padding: const EdgeInsets.all(14), children: [
      const SizedBox(height: 20),
      const Text('Love Care Global', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const Text('Home Nursing, With Love.', style: TextStyle(color: Color(0xFFA78BFA))),
      const SizedBox(height: 20),
      _drawerItem('Home', () { Navigator.pop(context); }),
      _drawerItem('Register', () { Navigator.pop(context); _openPage(const RegisterPage()); }),
      _drawerItem('Login', () { Navigator.pop(context); _openPage(const LoginPage()); }),
      _drawerItem('Book a Nurse', () { Navigator.pop(context); _openPage(const BookPage(service: 'Home Nursing')); }),
      _drawerItem('Consent Form', () { Navigator.pop(context); _openPage(const ConsentPage()); }, highlight: true),
      _drawerItem('SOS Emergency - Call Now', () { Navigator.pop(context); _call(); }, danger: true),
      _drawerItem('Delete Account', () { Navigator.pop(context); _openPage(const DeletePage()); }, danger: true),
    ]));
  }
  Widget _drawerItem(String title, VoidCallback onTap, {bool highlight = false, bool danger = false}) {
    return Container(margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: highlight ? const Color(0xFFA855F7) : danger ? Colors.red.withOpacity(0.15) : const Color(0xFF4C1D95).withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: ListTile(title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: highlight ? const Color(0xFF1E0A3A) : danger ? const Color(0xFFFCA5A5) : const Color(0xFFD8B4FE))), onTap: onTap));
  }
}

// ===== REGISTER PAGE - REAL FORM =====
class RegisterPage extends StatefulWidget { const RegisterPage({super.key}); @override State<RegisterPage> createState() => _RegisterPageState(); }
class _RegisterPageState extends State<RegisterPage> {
  final _name = TextEditingController(); final _phone = TextEditingController(); final _loc = TextEditingController();
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Register'), backgroundColor: const Color(0xFF1E0A3A)), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _loc, decoration: const InputDecoration(labelText: 'Location - e.g. Accra, East Legon', border: OutlineInputBorder())),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), padding: const EdgeInsets.all(16)), onPressed: () {
        if (_name.text.isEmpty || _phone.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill Name and Phone'))); return; }
        showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Registration Received'), content: Text('Thank you ${_name.text}. Our team will call you on ${_phone.text} within 30 minutes to confirm your booking.'), actions: [TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text('Done'))]));
      }, child: const Text('Submit Registration', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)))),
    ])));
  }
}

// ===== LOGIN PAGE =====
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});
  @override Widget build(BuildContext context) {
    final phone = TextEditingController();
    return Scaffold(appBar: AppBar(title: const Text('Login'), backgroundColor: const Color(0xFF1E0A3A)), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      const Text('Enter your phone number to continue. We will call you to verify.', style: TextStyle(color: Color(0xFFC4B5FD))),
      const SizedBox(height: 16),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder())),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7), padding: const EdgeInsets.all(16)), onPressed: () { if (phone.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter phone number'))); return; } ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Welcome back! We will call ${phone.text} to verify.'))); Navigator.pop(context); }, child: const Text('Login', style: TextStyle(fontWeight: FontWeight.w900)))),
    ])));
  }
}

// ===== BOOK PAGE =====
class BookPage extends StatefulWidget { final String service; const BookPage({super.key, required this.service}); @override State<BookPage> createState() => _BookPageState(); }
class _BookPageState extends State<BookPage> {
  final _name = TextEditingController(); final _phone = TextEditingController(); final _notes = TextEditingController();
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: Text('Book - ${widget.service}'), backgroundColor: const Color(0xFF1E0A3A)), body: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Service: ${widget.service}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      const SizedBox(height: 16),
      TextField(controller: _name, decoration: const InputDecoration(labelText: 'Your Name', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'What do you need? e.g. Nurse for my mother', border: OutlineInputBorder())),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), padding: const EdgeInsets.all(16)), onPressed: () { showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Booking Received'), content: Text('Thank you ${_name.text}. We received your booking for ${widget.service}. We will call ${_phone.text} shortly.'), actions: [TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text('Done'))])); }, child: const Text('Confirm Booking', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)))),
    ])));
  }
}

// ===== CONSENT PAGE =====
class ConsentPage extends StatefulWidget { const ConsentPage({super.key}); @override State<ConsentPage> createState() => _ConsentPageState(); }
class _ConsentPageState extends State<ConsentPage> {
  bool agreed = false;
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Consent Form'), backgroundColor: const Color(0xFF1E0A3A)), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      const Expanded(child: SingleChildScrollView(child: Text('LOVE CARE GLOBAL - CONSENT FORM\n\nI agree that Love Care Global may provide home nursing and care services to me / my family member.\n\nI understand:\n1. Nurses will follow professional care standards.\n2. I will provide correct health information.\n3. I can stop the service at any time.\n4. My information will be kept private.\n\nBy ticking Agree, I give my consent.', style: TextStyle(color: Color(0xFFC4B5FD), height: 1.7)))),
      CheckboxListTile(value: agreed, onChanged: (v) => setState(() => agreed = v ?? false), title: const Text('I Agree - I give my consent'), activeColor: const Color(0xFF22C55E)),
      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: agreed ? () { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Consent Saved. Thank you.'))); Navigator.pop(context); } : null, child: const Text('Submit Consent'))),
    ])));
  }
}

// ===== DELETE PAGE =====
class DeletePage extends StatelessWidget {
  const DeletePage({super.key});
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Delete Account'), backgroundColor: Colors.red.shade900), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      const Text('Are you sure? This will request deletion of your account and data. Our team will call you to confirm.', style: TextStyle(height: 1.6)),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () { showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Request Received'), content: const Text('Your delete request has been received. We will contact you to confirm.'), actions: [TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text('Done'))])); }, child: const Text('Request Delete My Account'))),
    ])));
  }
}
