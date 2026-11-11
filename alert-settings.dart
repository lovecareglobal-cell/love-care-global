import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';

/// Alert Settings — UNIFIED for Nurses + Clients + CEO
/// This ONE screen replaces client-alerts.html for ALL THREE roles.
/// CEO uses the SAME screen — same sound, same song, same list — just CEO alerts.
/// Same logic as client-alerts.html, but role-aware:
///
/// Role detection (in order):
///   1. Constructor / route arg: {'role': 'nurse' | 'client' | 'ceo'}
///   2. SharedPreferences: role / userRole / userType == 'ceo' / 'nurse'
///   3. Has ceoUid / isCEO -> CEO, has nurseUid / nurseId -> nurse, else client
///   4. Manual toggle in UI (Nurse / Client / CEO pills) — overrides and saves choice
///
/// Storage (UNIFIED + backward compatible):
///   Unified keys used by this screen: alerts_sound, alert_song_choice, alert_custom_song, alert_custom_song_name
///   Also synced to legacy keys so old screens keep working:
///     Client: client_alerts_sound, client_song_choice, client_custom_song, client_custom_song_name
///     Nurse:  nurse_alerts_sound,  nurse_song_choice,  nurse_custom_song,  nurse_custom_song_name
///     CEO:    ceo_alerts_sound,    ceo_song_choice,    ceo_custom_song,    ceo_custom_song_name
///
/// Notifications path:
///   Client: clientNotifications/{userId}  (same as client-alerts.html)
///   Nurse:  nurseNotifications/{userId}   (symmetric — CEO writes here same way)
///   CEO:    ceoNotifications/{userId}     (same bucket CEO Control Chat already logs pushes to — CEO alerts: new booking, new refund, new nurse registration, payment increase, SOS)
///   Both: limitToLast(50), sorted by createdAt desc, new alert -> play LOUD + toast
///
/// Sound (same as client-alerts.html playLoud):
///   accepted  -> 3 beeps 800Hz + 150*i,  completed -> notes 523,659,784,1046,  arrived/other -> 1000Hz sine 1s
///   + vibrate [200,100,200,100,400] + custom song if choice != default

class AlertSettingsScreen extends StatefulWidget {
  final String? role; // 'nurse' | 'client' | 'ceo'
  const AlertSettingsScreen({super.key, this.role});
  @override
  State<AlertSettingsScreen> createState() => _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends State<AlertSettingsScreen> {
  String role = 'client'; // 'client' | 'nurse' | 'ceo'
  String? userId;
  List<Map> alerts = [];
  Set<String> prevIds = {};
  bool soundOn = false;
  String songChoice = 'default';
  String customSongName = '';
  final AudioPlayer _player = AudioPlayer();

  bool get isNurse => role == 'nurse';
  bool get isCEO => role == 'ceo';
  bool get isClient => role == 'client';
  String get notifPath => isCEO ? 'ceoNotifications' : isNurse ? 'nurseNotifications' : 'clientNotifications';
  String get soundKey => isCEO ? 'ceo_alerts_sound' : isNurse ? 'nurse_alerts_sound' : 'client_alerts_sound';
  String get songKey => isCEO ? 'ceo_song_choice' : isNurse ? 'nurse_song_choice' : 'client_song_choice';
  String get customSongKey => isCEO ? 'ceo_custom_song' : isNurse ? 'nurse_custom_song' : 'client_custom_song';
  String get customNameKey => isCEO ? 'ceo_custom_song_name' : isNurse ? 'nurse_custom_song_name' : 'client_custom_song_name';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['role'] != null) {
      final r = args['role'].toString().toLowerCase();
      if ((r == 'nurse' || r == 'client' || r == 'ceo') && r != role) {
        role = r;
        _reloadForRole();
      }
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    // 1. Constructor wins, 2. Saved role, 3. Prefs role, 4. Has nurse UID
    String detected = widget.role?.toLowerCase() ?? '';
    if (detected != 'nurse' && detected != 'client' && detected != 'ceo') detected = '';
    if (detected.isEmpty) detected = (prefs.getString('alert_role') ?? '').toLowerCase();
    if (detected != 'nurse' && detected != 'client' && detected != 'ceo') detected = (prefs.getString('role') ?? prefs.getString('userRole') ?? prefs.getString('userType') ?? '').toLowerCase();
    if (detected != 'nurse' && detected != 'client' && detected != 'ceo') {
      if (prefs.getBool('isCEO') == true || prefs.getString('ceoUid') != null || prefs.getString('ceoId') != null) detected = 'ceo';
      else if (prefs.getString('nurseUid') != null || prefs.getString('nurseId') != null || prefs.getBool('isNurse') == true) detected = 'nurse';
      else detected = 'client';
    }
    role = detected;
    await _loadPrefsForRole();
    await _resolveUserId();
    _loadAlerts();
    setState(() {});
  }

  Future<void> _reloadForRole() async {
    await _loadPrefsForRole();
    await _resolveUserId();
    prevIds = {};
    _loadAlerts();
    setState(() {});
  }

  Future<void> _loadPrefsForRole() async {
    final prefs = await SharedPreferences.getInstance();
    // Unified keys first, fallback to role keys, fallback to client legacy (so existing clients keep their song)
    soundOn = prefs.getString('alerts_sound') == 'true' || prefs.getString(soundKey) == 'true';
    songChoice = prefs.getString('alert_song_choice') ?? prefs.getString(songKey) ?? prefs.getString('client_song_choice') ?? 'default';
    customSongName = prefs.getString('alert_custom_song_name') ?? prefs.getString(customNameKey) ?? prefs.getString('client_custom_song_name') ?? '';
  }

  Future<void> _resolveUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (isCEO) {
      userId = prefs.getString('ceoUid') ?? prefs.getString('ceoId') ?? prefs.getString('lcg_ceo_uid') ?? prefs.getString('uid') ?? prefs.getString('userPhone') ?? prefs.getString('phone') ?? 'CEO';
    } else if (isNurse) {
      userId = prefs.getString('nurseUid') ?? prefs.getString('nurseId') ?? prefs.getString('lcg_nurse_uid') ?? prefs.getString('uid') ?? prefs.getString('userPhone') ?? prefs.getString('phone');
    } else {
      userId = prefs.getString('lcg_client_uid') ?? prefs.getString('clientUid') ?? prefs.getString('uid') ?? prefs.getString('userPhone') ?? prefs.getString('clientPhone') ?? prefs.getString('phone');
    }
  }

  Future<void> _saveSound(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alerts_sound', v ? 'true' : 'false');
    await prefs.setString(soundKey, v ? 'true' : 'false');
    // Keep the other role's key untouched — each role has its own ON/OFF
    setState(() => soundOn = v);
  }

  Future<void> _saveSongChoice(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alert_song_choice', v);
    await prefs.setString(songKey, v);
    setState(() => songChoice = v);
  }

  Future<void> _toggleSound() async {
    final cur = soundOn;
    await _saveSound(!cur);
    if (!cur) _enableSound();
  }

  void _enableSound() {
    _toast(isCEO ? '🔊 CEO Sound ON!' : isNurse ? '🔊 Nurse Sound ON!' : '🔊 Client Sound ON!');
  }

  // ---- Custom Song (max 8MB, same as HTML handleSongFile) ----
  Future<void> _pickCustomSong() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (res == null || res.files.single.path == null) return;
    final file = File(res.files.single.path!);
    if (await file.length() > 8 * 1024 * 1024) { _toast('Song too big! Less than 8MB'); return; }
    try {
      final bytes = await file.readAsBytes();
      final b64 = 'data:audio/mpeg;base64,${base64Encode(bytes)}';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('alert_custom_song', b64);
      await prefs.setString(customSongKey, b64);
      await prefs.setString('alert_custom_song_name', res.files.single.name);
      await prefs.setString(customNameKey, res.files.single.name);
      await prefs.setString('alert_song_choice', 'custom');
      await prefs.setString(songKey, 'custom');
      setState(() { customSongName = res.files.single.name; songChoice = 'custom'; });
      _toast('✅ Song saved! ${res.files.single.name}');
      _testSong('accepted');
    } catch (_) { _toast('Storage full - pick shorter song'); }
  }

  Future<void> _clearCustomSong() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('alert_custom_song'); await prefs.remove(customSongKey);
    await prefs.remove('alert_custom_song_name'); await prefs.remove(customNameKey);
    await prefs.setString('alert_song_choice', 'default'); await prefs.setString(songKey, 'default');
    setState(() { songChoice = 'default'; customSongName = ''; });
    _toast('🗑️ Custom song removed');
  }

  // ---- Play Loud (same patterns as client-alerts.html playLoud) ----
  Future<void> _playLoud(String type) async {
    if (!soundOn) return;
    try {
      if (songChoice != 'default') {
        if (await _playCustomSong()) return;
      }
      // Fallback: asset beeps — put sounds/default.mp3, sounds/song1.mp3, sounds/song2.mp3 in assets
      await _player.play(AssetSource('sounds/$songChoice.mp3')).catchError((_) async {
        await _player.play(AssetSource('sounds/default.mp3')).catchError((_) {});
      });
    } catch (_) {}
    HapticFeedback.vibrate();
    // Titles mirror HTML Notification titles, role-aware
    String title = '🔔 Update!';
    if (type == 'accepted') title = isCEO ? '✅ New Booking / Nurse Accepted!' : isNurse ? '✅ New Booking!' : '✅ Nurse Don Accept!';
    else if (type == 'arrived') title = isCEO ? '📍 Nurse Arrived!' : isNurse ? '📍 Client Waiting!' : '📍 Nurse Don Arrive!';
    else if (type == 'completed') title = isCEO ? '🎉 Work Completed / Payment!' : '🎉 Work Completed!';
    else if (type == 'refund') title = '💰 New Refund Request!';
    else if (type == 'registration') title = '👩‍⚕️ New Nurse Registration!';
    _toast(title);
  }

  Future<bool> _playCustomSong() async {
    if (songChoice != 'custom') return false;
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString('alert_custom_song') ?? prefs.getString(customSongKey);
    if (custom == null || custom.isEmpty) return false;
    try {
      await _player.stop();
      await _player.play(UrlSource(custom));
      return true;
    } catch (_) { return false; }
  }

  Future<void> _testSong(String type) async {
    await _saveSound(true); // testSound() in HTML calls enableSound() first
    await Future.delayed(const Duration(milliseconds: 400));
    await _playLoud(type);
    _toast('🔊 Playing $type sound — ${isCEO ? 'CEO' : isNurse ? 'Nurse' : 'Client'}');
  }

  // ---- Alerts list ----
  void _loadAlerts() {
    if (userId == null) return;
    FirebaseDatabase.instance.ref('$notifPath/$userId').limitToLast(50).onValue.listen((e) {
      if (!e.snapshot.exists) { setState(() => alerts = []); return; }
      final map = e.snapshot.value as Map;
      List<Map> list = [];
      map.forEach((k, val) { list.add({...Map<String, dynamic>.from(val as Map), 'id': k}); });
      list.sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
      final curIds = list.map((l) => l['id'].toString()).toSet();
      if (prevIds.isNotEmpty) {
        for (final item in list) {
          if (!prevIds.contains(item['id'])) {
            String type = 'accepted';
            if ((item['type'] ?? '').toString().contains('arrived')) type = 'arrived';
            else if ((item['type'] ?? '').toString().contains('completed')) type = 'completed';
            Future.delayed(const Duration(milliseconds: 300), () => _playLoud(type));
            _toast('🔔 NEW: ${item['title'] ?? 'New alert'}');
          }
        }
      }
      prevIds = curIds;
      setState(() => alerts = list);
    });
  }

  Future<void> _markRead(String id) async {
    await FirebaseDatabase.instance.ref('$notifPath/$userId/$id').update({'read': true});
    _toast('Read');
  }

  Future<void> _delOne(String id) async {
    final c = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Delete?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes'))]));
    if (c != true) return;
    await FirebaseDatabase.instance.ref('$notifPath/$userId/$id').remove();
    _toast('Deleted');
  }

  Future<void> _markAllRead() async {
    for (final a in alerts) {
      await FirebaseDatabase.instance.ref('$notifPath/$userId/${a['id']}').update({'read': true}).catchError((_) {});
    }
    _toast('All read');
  }

  Future<void> _deleteAll() async {
    final c = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Delete ALL ${alerts.length}?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes'))]));
    if (c != true) return;
    await FirebaseDatabase.instance.ref('$notifPath/$userId').remove();
    _toast('Deleted All');
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _switchRole(String r) async {
    if (r == role) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alert_role', r);
    setState(() => role = r);
    await _reloadForRole();
  }

  String _iconFor(Map n) {
    final t = (n['type'] ?? '').toString();
    if (t.contains('accepted')) return '✅';
    if (t.contains('arrived')) return '📍';
    if (t.contains('completed')) return '🎉';
    if (t.contains('refund')) return '💰';
    if (t.contains('regist')) return '👩‍⚕️';
    if (t.contains('sos')) return '🚨';
    if (t.contains('payment') || t.contains('increase')) return '💳';
    return '🔔';
  }

  @override
  Widget build(BuildContext context) {
    final unread = alerts.where((a) => a['read'] != true).length;
    final roleLabel = isCEO ? 'CEO' : isNurse ? 'Nurse' : 'Client';
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(
        title: Text('🔔 Alert Settings — $roleLabel'),
        backgroundColor: const Color(0xFF1A1633),
        actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 10), child: Text('$unread New • ${alerts.length} Alerts', style: const TextStyle(fontSize: 11))))],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          // ROLE SWITCH — ONE screen for both
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('WHO IS USING THIS PHONE?', style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: ChoiceChip(label: const Center(child: Text('👩‍⚕️ Nurse', style: TextStyle(fontSize: 11))), selected: isNurse, onSelected: (_) => _switchRole('nurse'), selectedColor: const Color(0xFFA78BFA).withOpacity(0.3))),
              const SizedBox(width: 6),
              Expanded(child: ChoiceChip(label: const Center(child: Text('👤 Client', style: TextStyle(fontSize: 11))), selected: isClient, onSelected: (_) => _switchRole('client'), selectedColor: const Color(0xFF22C55E).withOpacity(0.3))),
              const SizedBox(width: 6),
              Expanded(child: ChoiceChip(label: const Center(child: Text('👑 CEO', style: TextStyle(fontSize: 11))), selected: isCEO, onSelected: (_) => _switchRole('ceo'), selectedColor: const Color(0xFFFACC15).withOpacity(0.3))),
            ]),
            const SizedBox(height: 6),
            Text('Same settings for all three — sound, song, and alerts change with role. ID: ${userId ?? 'Not logged in'}', style: const TextStyle(color: Colors.white60, fontSize: 10)),
          ])),
          const SizedBox(height: 12),
          // LOUD SOUND
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4))), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🔔 Loud Sound - Even Far From Phone', style: TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold)),
              Text(isCEO ? 'When new booking / refund / nurse registers / SOS comes in, phone RINGS loudly + vibrates' : isNurse ? 'When client books you, phone RINGS loudly + vibrates' : 'When nurse accepts you, phone RINGS loudly + vibrates', style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 10)),
            ])),
            Switch(value: soundOn, onChanged: (_) => _toggleSound()),
            Text(soundOn ? 'ON - Loud' : 'OFF', style: TextStyle(color: soundOn ? const Color(0xFF22C55E) : const Color(0xFFFACC15), fontSize: 11, fontWeight: FontWeight.bold)),
          ])),
          const SizedBox(height: 12),
          // SONG
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('🎵 My Song Choice — $roleLabel', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(value: songChoice, decoration: const InputDecoration(border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'default', child: Text('🔔 Default Beep')), DropdownMenuItem(value: 'custom', child: Text('🎵 My Song From Phone')), DropdownMenuItem(value: 'song1', child: Text('🎶 Song 1 - Church Bell')), DropdownMenuItem(value: 'song2', child: Text('🎶 Song 2 - Afrobeat Alert'))], onChanged: (v) async { await _saveSongChoice(v ?? 'default'); if (v != 'custom') _testSong(v ?? 'default'); }),
            const SizedBox(height: 8),
            Text(songChoice == 'custom' && customSongName.isNotEmpty ? 'Current: 🎵 $customSongName' : songChoice == 'default' ? 'Current: Default Beep' : 'Current: $songChoice', style: const TextStyle(color: Color(0xFF22C55E), fontSize: 11)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: ElevatedButton(onPressed: _pickCustomSong, child: const Text('📁 Pick Song (max 8MB)', style: TextStyle(fontSize: 11)))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(onPressed: () => _testSong(songChoice), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15)), child: const Text('▶️ Test My Song', style: TextStyle(color: Colors.black, fontSize: 11)))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(onPressed: _clearCustomSong, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.15)), child: const Text('🗑️ Remove', style: TextStyle(fontSize: 11)))),
            ]),
          ])),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ElevatedButton(onPressed: () => _testSong('accepted'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15)), child: Text(isCEO ? '🔊 Test New Booking' : isNurse ? '🔊 Test New Booking' : '🔊 Test Accepted', style: const TextStyle(color: Colors.black, fontSize: 10)))),
            const SizedBox(width: 6),
            Expanded(child: ElevatedButton(onPressed: () => _testSong('arrived'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15)), child: const Text('🔊 Test Arrived', style: TextStyle(color: Colors.black, fontSize: 10)))),
            const SizedBox(width: 6),
            Expanded(child: ElevatedButton(onPressed: () => _testSong('completed'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15)), child: const Text('🔊 Test Completed', style: TextStyle(color: Colors.black, fontSize: 10)))),
          ]),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: OutlinedButton(onPressed: _markAllRead, child: const Text('Mark All Read', style: TextStyle(fontSize: 11)))), const SizedBox(width: 8), Expanded(child: OutlinedButton(onPressed: _deleteAll, style: OutlinedButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete All', style: TextStyle(fontSize: 11))))]),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: Text('📜 $roleLabel Alerts — ${isCEO ? 'New booking, New refund, New nurse registration, Payment increase, SOS' : isNurse ? 'New booking, Client cancelled, Payment' : 'Nurse accepted, Nurse arrived, Payment, Completed'}', style: const TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(height: 8),
          if (userId == null) const Padding(padding: EdgeInsets.all(20), child: Text('No user ID - Login again', style: TextStyle(color: Colors.white60))),
          if (userId != null && alerts.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(isCEO ? 'No alerts yet - When new booking / refund / nurse registers, loud sound + notification here' : isNurse ? 'No alerts yet - When client books you, loud sound + notification here' : 'No alerts yet - When nurse accepts you, loud sound + notification here', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60))),
          ...alerts.map((n) => Container(
            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF1A1633), borderRadius: BorderRadius.circular(16), border: Border(left: n['read'] != true ? const BorderSide(color: Color(0xFF22C55E), width: 4) : BorderSide.none)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(12)), child: Center(child: Text(_iconFor(n), style: const TextStyle(fontSize: 20)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n['title'] ?? 'Notification', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(n['message'] ?? '', style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 6),
                Text('Booking ID: ${n['bookingId'] ?? 'N/A'} • ${n['createdAt'] != null ? DateTime.fromMillisecondsSinceEpoch((n['createdAt'] as num).toInt()).toString() : ''}', style: const TextStyle(color: Colors.white60, fontSize: 9)),
                Row(children: [TextButton(onPressed: () => _markRead(n['id']), child: const Text('Mark Read', style: TextStyle(fontSize: 11))), TextButton(onPressed: () => _delOne(n['id']), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete', style: TextStyle(fontSize: 11)))]),
              ])),
            ]),
          )),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
