// LOVE CARE GLOBAL - Flutter port of Index-4-FIXED-VIDEO-SOUND.html
// SINGLE-FILE INDEX - paste this whole file as lib/main.dart
// Run: flutter pub get  |  flutterfire configure (web-care-618e8)  |  flutter run
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:just_audio/just_audio.dart';


// ================= MODELS =================

class CeoAnnouncement {
  final bool active;
  final String name, text, time, avatarUrl;
  final List<String> images, videos;
  final String? voice, videoUrl, displayType;
  CeoAnnouncement({
    this.active = false,
    this.name = '👑 CEO Announcement — Asabere Peter',
    this.text = 'Loading CEO announcement...',
    this.time = 'Just now • LoveCare Global',
    this.avatarUrl =
        'https://ui-avatars.com/api/?name=Asabere+Peter&background=facc15&color=000',
    this.images = const [],
    this.videos = const [],
    this.voice,
    this.videoUrl,
    this.displayType,
  });
  factory CeoAnnouncement.fromMap(Map m) => CeoAnnouncement(
        active: m['active'] == true,
        name: (m['name'] ?? '👑 CEO Announcement — Asabere Peter').toString(),
        text: (m['text'] ?? m['message'] ?? '').toString(),
        time: (m['time'] ?? 'Just now • LoveCare Global').toString(),
        avatarUrl: (m['avatar'] ?? m['avatarUrl'] ??
                'https://ui-avatars.com/api/?name=Asabere+Peter&background=facc15&color=000')
            .toString(),
        images: _strList(m['images']),
        videos: _strList(m['videos']),
        voice: m['voice']?.toString(),
        videoUrl: (m['videoURL'] ?? m['videoUrl'] ?? m['video'])?.toString(),
        displayType: m['displayType']?.toString(),
      );
  static List<String> _strList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => (e is Map ? (e['data'] ?? e['url'] ?? '') : e).toString())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (v is String && v.isNotEmpty) return [v];
    return [];
  }

  List<String> get allVideos =>
      [...videos, if (videoUrl != null && videoUrl!.isNotEmpty) videoUrl!];
}

class NurseRating {
  final String nurseName, initials, service, nurseId;
  final double avgRating;
  final int totalReviews;
  final bool verified;
  final Review topReview;
  NurseRating({
    required this.nurseName,
    required this.initials,
    required this.service,
    required this.avgRating,
    required this.totalReviews,
    required this.topReview,
    this.verified = true,
    this.nurseId = '',
  });
  factory NurseRating.mock(String n, double avg, int count, String text) =>
      NurseRating(
        nurseName: n,
        initials:
            n.split(' ').map((s) => s[0]).join('').substring(0, 2).toUpperCase(),
        service: 'Home Nursing',
        avgRating: avg,
        totalReviews: count,
        topReview: Review(
            client: 'Verified Client', loc: 'Ghana', text: text, rating: 5, date: ''),
      );
}

class Review {
  final String client, loc, text, date;
  final double rating;
  Review(
      {required this.client,
      required this.loc,
      required this.text,
      required this.rating,
      required this.date});
}

// ================= FIREBASE SERVICE =================


/// Same Firebase project as the HTML: web-care-618e8
/// HTML used firebasejs 9.22.0 compat + firebase.database().
/// In Flutter use firebase_core + firebase_database with the SAME
/// google-services.json / GoogleService-Info.plist from that project.
class FirebaseService {
  final _db = FirebaseDatabase.instance.ref();

  Stream<CeoAnnouncement> ceoStream() =>
      _db.child('ceoAnnouncement').onValue.map((e) {
        final v = e.snapshot.value;
        if (v is Map) return CeoAnnouncement.fromMap(v);
        return CeoAnnouncement(active: false);
      });

  /// Mirrors HTML loadLiveRatings(): ratings/{nurseId}/{ratingId}
  /// + allRatings + homepageReviews. Sorted high -> low.
  Stream<List<NurseRating>> ratingsStream() =>
      _db.child('ratings').onValue.map((e) {
        final v = e.snapshot.value;
        if (v is! Map) return <NurseRating>[];
        final out = <NurseRating>[];
        v.forEach((nurseId, ratings) {
          if (ratings is! Map) return;
          double total = 0;
          int count = 0;
          Map? latest;
          ratings.forEach((_, r) {
            if (r is Map) {
              total += double.tryParse('${r['stars'] ?? r['rating'] ?? 0}') ?? 0;
              count++;
              if (latest == null ||
                  ((r['time'] ?? 0) as num) > ((latest!['time'] ?? 0) as num)) {
                latest = r;
              }
            }
          });
          if (count == 0) return;
          final name = (latest?['nurseName'] ?? 'Nurse').toString();
          out.add(NurseRating(
            nurseName: name,
            initials: name
                .split(' ')
                .map((s) => s[0])
                .join('')
                .substring(0, 2)
                .toUpperCase(),
            service: (latest?['service'] ?? 'Home Nursing').toString(),
            avgRating: double.parse((total / count).toStringAsFixed(1)),
            totalReviews: count,
            nurseId: nurseId.toString(),
            topReview: Review(
              client: (latest?['clientName'] ?? latest?['client'] ?? 'Verified Client')
                  .toString(),
              loc: (latest?['loc'] ?? 'Ghana').toString(),
              text: (latest?['comment'] ?? latest?['text'] ?? latest?['ratingComment'] ??
                      'Excellent service')
                  .toString(),
              rating: double.tryParse(
                      '${latest?['stars'] ?? latest?['rating'] ?? 5}') ??
                  5,
              date: (latest?['timeStr'] ?? '').toString(),
            ),
          ));
        });
        out.sort((a, b) => b.avgRating != a.avgRating
            ? b.avgRating.compareTo(a.avgRating)
            : b.totalReviews.compareTo(a.totalReviews));
        return out;
      });
}

// ================= LAUNCHER =================


class LauncherService {
  static const phone = '+233544121814';
  static Future<void> call() async =>
      launchUrl(Uri.parse('tel:$phone'));
  static Future<void> whatsapp() async => launchUrl(
        Uri.parse(
            'https://wa.me/233544121814?text=Hello%20LOVE%20CARE%20GLOBAL%20%F0%9F%92%AC'),
        mode: LaunchMode.externalApplication,
      );
  static Future<void> open(String url) async =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

// ================= VIDEO WITH SOUND =================


/// Port of the HTML FIXED-VIDEO-SOUND logic:
/// video.muted=false; volume=1.0; onloadeddata/onplay -> unmute again.
/// Flutter has no autoplay-with-sound restriction like browsers, but we
/// still expose the same explicit "Play with Sound" button.
class VideoWithSound extends StatefulWidget {
  final String url;
  const VideoWithSound({super.key, required this.url});
  @override
  State<VideoWithSound> createState() => _S();
}

class _S extends State<VideoWithSound> {
  late final VideoPlayerController _c;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..setVolume(1.0)
      ..initialize().then((_) => setState(() {}));
    _c.addListener(() => setState(() => _playing = _c.value.isPlaying));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        AspectRatio(
          aspectRatio:
              _c.value.isInitialized ? _c.value.aspectRatio : 16 / 9,
          child: _c.value.isInitialized
              ? VideoPlayer(_c)
              : const Center(child: CircularProgressIndicator()),
        ),
        Container(
          color: Colors.black.withOpacity(.7),
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('🔊 Sound ON - Tap 🔊 if no sound',
                  style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF86EFAC),
                      fontWeight: FontWeight.w700)),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.black),
                onPressed: () async {
                  await _c.setVolume(1.0);
                  if (_playing) {
                    await _c.pause();
                  } else {
                    await _c.play();
                  }
                },
                child: Text(_playing ? '⏸ Pause' : '▶️ Play with Sound',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ]);
}

// ================= HOME SCREEN =================


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _H();
}

class _H extends State<HomeScreen> {
  final _fb = FirebaseService();
  final _scaffold = GlobalKey<ScaffoldState>();
  List<NurseRating> _ratings = [];
  bool _showAll = false;
  bool _bannerClosed = false;
  final _mock = [
    NurseRating.mock('Ama Serwaa', 5.0, 24, 'Very caring and professional.'),
    NurseRating.mock('Kwame Mensah', 4.9, 18, 'Arrived on time, excellent care.'),
    NurseRating.mock('Efua Asante', 4.8, 31, 'My mother loved her care.'),
  ];

  @override
  void initState() {
    super.initState();
    _fb.ratingsStream().listen((v) {
      if (v.isNotEmpty && mounted) setState(() => _ratings = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _ratings.isEmpty ? _mock : _ratings;
    final shown = _showAll ? list : list.take(3).toList();
    return Scaffold(
      key: _scaffold,
      backgroundColor: const Color(0xFF0E0A1C),
      drawer: _drawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0A1C),
        title: const Text('PROFESSIONAL ONLINE NURSE',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Text('SOS',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w900)),
            onPressed: () => LauncherService.open('sos.html'),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(children: [
          StreamBuilder<CeoAnnouncement>(
            stream: _fb.ceoStream(),
            builder: (c, s) {
              final a = s.data;
              if (a == null || !a.active || _bannerClosed) {
                return const SizedBox.shrink();
              }
              if (a.displayType == 'ticker') return _ticker(a);
              return _ceoBanner(a);
            },
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Welcome to',
                    style: TextStyle(color: Colors.white70, fontSize: 18)),
                const Text('LOVE CARE GLOBAL\nHOME NURSING',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text(
                    'Your health, our heart. We bring licensed nurses right to your doorstep — compassionate, professional care in 8 countries, 24/7. Now with live tracking, secure Paystack, and 2-step verified nurses.',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: _cta(
                          'Join as Nurse',
                          'Verified, earn with jobs — GPS + video profile',
                          ['Register (2 steps)', 'Login'],
                          ['nurses-registration.html', 'nurse-login.html'])),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _cta(
                          'Book a Nurse',
                          'See photo/video/rating before you pay',
                          ['Register', 'Login'],
                          ['client-registration.html', 'client-login.html'])),
                ]),
                const SizedBox(height: 18),
                _feature('📍', 'Live Tracking + GPS Verified',
                    'Track nurse in real time. All nurses GPS verified at registration.'),
                _feature('⚡', 'Secure Paystack + Pay on Delivery',
                    'Pay GHS/USD + new 50% online option. No double booking — availability lock.'),
                _feature('💜', '2-Step Verified Nurses',
                    'Photo, ID, Licence, Video checked by CEO. Only approved nurses show ONLINE.'),
                const SizedBox(height: 20),
                Row(children: [
                  const Text('👩‍⚕️ Client Ratings on Nurses — High Rank',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17)),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(99)),
                    child: Text('LIVE • ${list.length} nurses rated',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 12),
                ...shown.map(_ratingCard),
                TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(
                      _showAll ? 'Show less ↑' : 'Show more nurses ↓'),
                ),
                const Text(
                    '⭐ Ratings reflect live from client ratings in rating.html / client-dashboard — Verified bookings only',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ]),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
              heroTag: 'wa',
              backgroundColor: Colors.green,
              onPressed: LauncherService.whatsapp,
              child: const Text('💬')),
          const SizedBox(height: 8),
          FloatingActionButton.small(
              heroTag: 'call',
              onPressed: LauncherService.call,
              child: const Text('📞')),
        ],
      ),
    );
  }

  Widget _ticker(CeoAnnouncement a) => Container(
        color: Colors.amber,
        padding: const EdgeInsets.all(10),
        child: Text('CEO Announcement: ${a.text}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  Widget _ceoBanner(CeoAnnouncement a) => Card(
        margin: const EdgeInsets.all(12),
        color: const Color(0xFF1E1533),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Row(children: [
              CircleAvatar(backgroundImage: NetworkImage(a.avatarUrl)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(a.time,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ],
              )),
              IconButton(
                  onPressed: () => setState(() => _bannerClosed = true),
                  icon: const Icon(Icons.close, color: Colors.white)),
            ]),
            const SizedBox(height: 10),
            Text(a.text, style: const TextStyle(color: Colors.white)),
            ...a.images.map((u) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(u)))),
            ...a.allVideos.map((u) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: VideoWithSound(url: u))),
            if (a.voice != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _VoicePlayer(url: a.voice!)),
          ]),
        ),
      );

  Widget _cta(String title, String sub, List<String> labels,
          List<String> urls) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFF2A1B4A),
            borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
            Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 10),
            ...List.generate(
                labels.length,
                (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                            onPressed: () => LauncherService.open(urls[i]),
                            child: Text(labels[i]))))),
          ],
        ),
      );

  Widget _feature(String icon, String t, String s) => ListTile(
        leading: Text(icon, style: const TextStyle(fontSize: 26)),
        title: Text(t,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Text(s, style: const TextStyle(color: Colors.white70)),
      );

  Widget _ratingCard(NurseRating r) => Card(
        color: const Color(0xFF1E1533),
        child: ListTile(
          leading: CircleAvatar(child: Text(r.initials)),
          title: Text(r.nurseName,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: Text(
              '${r.service} • ⭐ ${r.avgRating} (${r.totalReviews} reviews)\n"${r.topReview.text}" — ${r.topReview.client}, ${r.topReview.loc}',
              style: const TextStyle(color: Colors.white70)),
          isThreeLine: true,
          trailing: const Icon(Icons.verified, color: Colors.green),
        ),
      );

  Widget _drawer() => Drawer(
        backgroundColor: const Color(0xFF140F24),
        child: ListView(children: [
          const DrawerHeader(
              child: Text('PROFESSIONAL\nONLINE NURSE',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 22))),
          const ListTile(
              title: Text('👋 Hi, Guest',
                  style: TextStyle(color: Colors.white70))),
          const ListTile(
              title: Text('Not logged in',
                  style: TextStyle(color: Colors.white54))),
          ...{
            'Home': 'index.html',
            'About': 'about.html',
            'Services': 'services.html',
            'How It Works': 'how-it-works.html',
            'Contact - +233544121814': 'contact.html',
            'Consent Form': 'consent-form.html',
            'Privacy': 'privacy.html',
            'Terms': 'terms.html',
            'Refund': 'refund.html',
            '🗑️ Delete Account': 'delete-account.html',
            'SOS Emergency': 'sos.html',
          }.entries.map((e) => ListTile(
                title: Text(e.key, style: const TextStyle(color: Colors.white)),
                onTap: () => LauncherService.open(e.value),
              )),
          ListTile(
              title: const Text('🚪 Logout',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context)),
        ]),
      );
}

class _VoicePlayer extends StatefulWidget {
  final String url;
  const _VoicePlayer({required this.url});
  @override
  State<_VoicePlayer> createState() => _V();
}

class _V extends State<_VoicePlayer> {
  final _p = AudioPlayer();
  bool _playing = false;
  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        IconButton(
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white),
            onPressed: () async {
              if (_playing) {
                await _p.pause();
              } else {
                await _p.setUrl(widget.url);
                await _p.play();
              }
              setState(() => _playing = !_playing);
            }),
        const Text('CEO voice note', style: TextStyle(color: Colors.white)),
      ]);
}

// ================= APP ENTRY (main.dart) =================


// TODO: run `flutterfire configure` (project web-care-618e8) to generate
// firebase_options.dart, then pass options: DefaultFirebaseOptions.currentPlatform
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase not configured yet: $e - app runs with mock ratings');
  }
  runApp(const LoveCareApp());
}

class LoveCareApp extends StatelessWidget {
  const LoveCareApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PROFESSIONAL ONLINE NURSE',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6D28D9),
            brightness: Brightness.dark,
          ),
        ),
        home: const HomeScreen(),
      );
}
