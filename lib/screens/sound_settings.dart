import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

// ===== GLOBAL SOUND SERVICE - Use from ANY screen =====
// Same keys as HTML: lcg_sound_choice + lcg_custom_song
// Usage: await SoundService.playCustomSound();
//        await SoundService.enableSound();
class SoundService {
  static final AudioPlayer _player = AudioPlayer();
  static bool soundEnabled = false;
  static bool keepRinging = false;
  static String choice = 'bell';
  static String customSong = ''; // data:audio/...;base64,...
  static bool repeat3 = true;
  static bool vibrateOn = true;
  static bool keepRingingOpt = false;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    choice = prefs.getString('lcg_sound_choice') ?? 'bell';
    customSong = prefs.getString('lcg_custom_song') ?? '';
    repeat3 = prefs.getBool('lcg_sound_repeat') ?? true;
    vibrateOn = prefs.getBool('lcg_sound_vibrate') ?? true;
    keepRingingOpt = prefs.getBool('lcg_sound_keep') ?? false;
  }

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lcg_sound_choice', choice);
    if (customSong.isNotEmpty) await prefs.setString('lcg_custom_song', customSong);
    await prefs.setBool('lcg_sound_repeat', repeat3);
    await prefs.setBool('lcg_sound_vibrate', vibrateOn);
    await prefs.setBool('lcg_sound_keep', keepRingingOpt);
  }

  static Future<void> enableSound() async {
    soundEnabled = true;
    await load();
    await playCustomSound();
    await _vibrate([200, 100, 200]);
  }

  static Future<void> stopSound() async {
    keepRinging = false;
    keepRingingOpt = false;
    try { await _player.stop(); } catch (_) {}
  }

  static Future<void> _vibrate(List<int> pattern) async {
    if (!vibrateOn) return;
    try {
      final has = await Vibration.hasVibrator() ?? false;
      if (has) await Vibration.vibrate(pattern: pattern);
    } catch (_) {}
  }

  // Generate WAV tone - same frequencies as HTML beep()
  static Uint8List _wavTone(double freq, double durationSec, String type) {
    const sampleRate = 22050;
    final total = (sampleRate * durationSec).toInt();
    final bytes = <int>[];
    // WAV header - 44 bytes
    void addStr(String s) => bytes.addAll(s.codeUnits);
    void add32(int v) => bytes.addAll([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    void add16(int v) => bytes.addAll([v & 0xFF, (v >> 8) & 0xFF]);
    final dataSize = total * 2;
    addStr('RIFF'); add32(36 + dataSize); addStr('WAVE');
    addStr('fmt '); add32(16); add16(1); add16(1); add32(sampleRate); add32(sampleRate * 2); add16(2); add16(16);
    addStr('data'); add32(dataSize);
    for (var i = 0; i < total; i++) {
      final t = i / sampleRate;
      double v = 0;
      if (type == 'sine') v = sin(2 * pi * freq * t);
      if (type == 'square') v = sin(2 * pi * freq * t) >= 0 ? 1 : -1;
      if (type == 'triangle') v = (2 / pi) * asin(sin(2 * pi * freq * t));
      if (type == 'sawtooth') v = 2 * ((freq * t) % 1) - 1;
      // Fade in/out
      final fade = min(1.0, min(i / 200, (total - i) / 200));
      final sample = (v * 0.5 * fade * 32767).toInt().clamp(-32767, 32767);
      add16(sample);
    }
    return Uint8List.fromList(bytes);
  }

  static Future<void> _beep(double freq, double dur, String type) async {
    try {
      final wav = _wavTone(freq, dur, type);
      await _player.play(BytesSource(wav));
      await Future.delayed(Duration(milliseconds: (dur * 1000).toInt() + 30));
    } catch (_) {}
  }

  // Same as HTML playBuiltIn(k)
  static Future<void> _playBuiltIn(String k) async {
    if (k == 'bell') {
      await _beep(880, 0.4, 'sine');
      await Future.delayed(const Duration(milliseconds: 250));
      await _beep(1174, 0.5, 'sine');
      await Future.delayed(const Duration(milliseconds: 250));
      await _beep(1568, 0.6, 'sine');
    } else if (k == 'chime') {
      for (final f in [523.0, 659.0, 784.0, 1046.0]) {
        await _beep(f, 0.5, 'sine');
        await Future.delayed(const Duration(milliseconds: 200));
      }
    } else if (k == 'alarm') {
      for (var i = 0; i < 6; i++) {
        await _beep(1000, 0.2, 'square');
        await Future.delayed(const Duration(milliseconds: 150));
        await _beep(700, 0.2, 'square');
        await Future.delayed(const Duration(milliseconds: 150));
      }
    } else if (k == 'gospel') {
      for (final f in [392.0, 523.0, 659.0, 784.0]) {
        await _beep(f, 0.6, 'triangle');
        await Future.delayed(const Duration(milliseconds: 250));
      }
      await _beep(1046, 0.9, 'triangle');
    } else if (k == 'highlife') {
      for (final f in [440.0, 554.0, 659.0, 880.0, 659.0, 554.0]) {
        await _beep(f, 0.3, 'triangle');
        await Future.delayed(const Duration(milliseconds: 180));
      }
    } else if (k == 'siren') {
      for (var i = 0; i < 4; i++) {
        await _beep(600, 0.3, 'sawtooth');
        await Future.delayed(const Duration(milliseconds: 200));
        await _beep(1200, 0.3, 'sawtooth');
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  // Same as HTML playCustomSound(reason)
  static Future<void> playCustomSound([String reason = 'test']) async {
    if (!soundEnabled) return;
    await load();
    final repeat = repeat3;
    final keep = keepRingingOpt;
    int count = repeat ? 3 : 1;
    if (keep) { keepRinging = true; count = 99; }
    for (var i = 0; i < count; i++) {
      if (keep && !keepRinging) break;
      if (i > 0) await Future.delayed(const Duration(milliseconds: 1200));
      if (choice == 'custom' && customSong.isNotEmpty) {
        try {
          final base64Part = customSong.contains(',') ? customSong.split(',').last : customSong;
          final bytes = base64Decode(base64Part);
          await _player.play(BytesSource(bytes));
          // If keep ringing, loop on complete
          if (keep) {
            await Future.delayed(const Duration(milliseconds: 300));
            continue;
          }
        } catch (_) {
          await _playBuiltIn('bell');
        }
      } else {
        await _playBuiltIn(choice);
      }
      await _vibrate([300, 100, 300, 100, 300]);
      if (!keep) break;
      if (i >= 2 && !keep) break;
      if (keep && i >= 2) {
        // Keep ringing - continue loop, stop button will set keepRinging=false
        if (!keepRinging) break;
      }
    }
  }
}

class SoundSettingsScreen extends StatefulWidget {
  const SoundSettingsScreen({super.key});
  @override
  State<SoundSettingsScreen> createState() => _SoundSettingsScreenState();
}

// Aliases
class SoundSettingsPage extends SoundSettingsScreen {
  const SoundSettingsPage({super.key});
}

class _SoundSettingsScreenState extends State<SoundSettingsScreen> {
  String choice = 'bell';
  bool soundEnabled = false;
  bool repeat3 = true;
  bool vibrateOn = true;
  bool keepRinging = false;
  String logText = '';
  String customName = '';

  final List<Map<String, String>> options = [
    {'value': 'bell', 'label': '🔔 Bell'},
    {'value': 'chime', 'label': '🎵 Chime'},
    {'value': 'alarm', 'label': '⏰ Alarm'},
    {'value': 'gospel', 'label': '🎶 Gospel'},
    {'value': 'highlife', 'label': '🎶 Highlife'},
    {'value': 'siren', 'label': '🚨 Siren'},
    {'value': 'custom', 'label': '🎤 My Song'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await SoundService.load();
    setState(() {
      choice = SoundService.choice;
      soundEnabled = SoundService.soundEnabled;
      repeat3 = SoundService.repeat3;
      vibrateOn = SoundService.vibrateOn;
      keepRinging = SoundService.keepRingingOpt;
      if (SoundService.customSong.isNotEmpty) customName = 'Custom song saved';
    });
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _saveAll() async {
    SoundService.choice = choice;
    SoundService.repeat3 = repeat3;
    SoundService.vibrateOn = vibrateOn;
    SoundService.keepRingingOpt = keepRinging;
    await SoundService.save();
    setState(() => logText = 'Saved: $choice');
  }

  Future<void> _enable() async {
    await SoundService.enableSound();
    setState(() {
      soundEnabled = true;
      logText = 'ON';
    });
    await _saveAll();
    _toast('✅ SOUND ON');
  }

  Future<void> _pickBuiltIn(String? v) async {
    if (v == null) return;
    setState(() => choice = v);
    SoundService.choice = v;
    await _saveAll();
  }

  Future<void> _uploadCustom() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;
    final f = res.files.first;
    if (f.bytes!.length > 3 * 1024 * 1024) {
      _toast('Too big - max 3MB');
      return;
    }
    final base64 = base64Encode(f.bytes!);
    SoundService.customSong = 'data:audio/mpeg;base64,$base64';
    SoundService.choice = 'custom';
    setState(() {
      choice = 'custom';
      customName = f.name;
      logText = 'Saved';
    });
    await _saveAll();
    _toast('✅ Custom song saved: ${f.name}');
    await SoundService.playCustomSound('test');
  }

  Future<void> _test() async {
    if (!soundEnabled) { await _enable(); return; }
    await _saveAll();
    await SoundService.playCustomSound('test');
    setState(() => logText = 'Ringing: $choice');
  }

  Future<void> _stop() async {
    SoundService.keepRinging = false;
    setState(() => keepRinging = false);
    SoundService.keepRingingOpt = false;
    await SoundService.stopSound();
    await _saveAll();
    setState(() => logText = 'Stopped');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0A1C),
        title: const Text('🔔 Sound Settings', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 640),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.red.withOpacity(0.12), Colors.purple.withOpacity(0.15)]),
              border: Border.all(color: Colors.red.withOpacity(0.35), width: 2),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed: _enable,
                  style: ElevatedButton.styleFrom(backgroundColor: soundEnabled ? const Color(0xFF16A34A) : const Color(0xFF22C55E), foregroundColor: Colors.white, padding: const EdgeInsets.all(18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                  child: Text(soundEnabled ? '✅ SOUND ON' : '🔊 TAP TO ENABLE SOUND', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: choice,
                  dropdownColor: const Color(0xFF1C1238),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(filled: true, fillColor: const Color(0xFF1C1238), border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: Colors.purple.withOpacity(0.4))), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                  items: options.map((o) => DropdownMenuItem(value: o['value'], child: Text(o['label']!))).toList(),
                  onChanged: _pickBuiltIn,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: ElevatedButton(onPressed: _test, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), foregroundColor: Colors.black, padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))), child: const Text('▶ Test', style: TextStyle(fontWeight: FontWeight.w900)))),
                    const SizedBox(width: 8),
                    Expanded(child: ElevatedButton(onPressed: _stop, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white, padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))), child: const Text('⏹ Stop', style: TextStyle(fontWeight: FontWeight.w900)))),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _uploadCustom,
                  icon: const Icon(Icons.upload, size: 18),
                  label: Text(customName.isEmpty ? '🎤 Upload My Song (max 3MB)' : '🎤 $customName — Tap to change'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.06), foregroundColor: Colors.white, padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
                const SizedBox(height: 8),
                const Text('Pick audio file from phone — will play as your notification sound', style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 10),
                CheckboxListTile(value: repeat3, onChanged: (v) async { setState(() => repeat3 = v ?? true); await _saveAll(); }, title: const Text('Ring 3 times', style: TextStyle(color: Colors.white, fontSize: 13)), activeColor: const Color(0xFF22C55E), controlAffinity: ListTileControlAffinity.leading),
                CheckboxListTile(value: vibrateOn, onChanged: (v) async { setState(() => vibrateOn = v ?? true); await _saveAll(); }, title: const Text('Vibrate', style: TextStyle(color: Colors.white, fontSize: 13)), activeColor: const Color(0xFF22C55E), controlAffinity: ListTileControlAffinity.leading),
                CheckboxListTile(value: keepRinging, onChanged: (v) async { setState(() => keepRinging = v ?? false); await _saveAll(); }, title: const Text('Keep ringing', style: TextStyle(color: Colors.white, fontSize: 13)), activeColor: const Color(0xFFEF4444), controlAffinity: ListTileControlAffinity.leading),
                if (logText.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(logText, style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11))),
                Padding(padding: const EdgeInsets.only(top: 8), child: Text('Saved: $choice', style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11))),
                const SizedBox(height: 10),
                const Text('Tip: Tap ENABLE first — phone browsers block sound until you tap. This choice is used by Bookings + Refunds + CEO screens when new booking / refund arrives.', style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
