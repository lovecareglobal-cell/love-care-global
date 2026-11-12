
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

// Global sound helper - used by ALL other screens like ceo-bookings-progress.dart
// Keeps same localStorage keys as your HTML: lcg_sound_choice, lcg_custom_song
class SoundHelper {
  static bool enabled = false;
  static String choice = 'bell';
  static String customSongPath = '';
  static bool repeat = true;
  static bool vibrate = true;
  static bool keepRinging = false;
  static bool _isPlaying = false;
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    choice = prefs.getString('lcg_sound_choice') ?? 'bell';
    customSongPath = prefs.getString('lcg_custom_song') ?? '';
    repeat = prefs.getBool('lcg_sound_repeat') ?? true;
    vibrate = prefs.getBool('lcg_sound_vibrate') ?? true;
    keepRinging = prefs.getBool('lcg_sound_keep_ringing') ?? false;
  }

  static Future<void> saveChoice(String v) async {
    choice = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lcg_sound_choice', v);
  }

  static Future<void> saveCustom(String path) async {
    customSongPath = path;
    choice = 'custom';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lcg_custom_song', path);
    await prefs.setString('lcg_sound_choice', 'custom');
  }

  static Future<void> doVibrate() async {
    if (!vibrate) return;
    try {
      if (await Vibration.hasVibrator() ?? false) {
        await Vibration.vibrate(pattern: [300, 100, 300, 100, 300]);
      }
    } catch (_) {}
  }

  // Built-in sounds - same notes as your HTML beep() function
  // You need these files in assets/sounds/ : bell.mp3, chime.mp3, alarm.mp3, gospel.mp3, highlife.mp3, siren.mp3
  // If file missing, it falls back to bell.mp3
  static Future<void> playBuiltIn(String k) async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/$k.mp3'));
    } catch (_) {
      try { await _player.play(AssetSource('sounds/bell.mp3')); } catch (_) {}
    }
  }

  static Future<void> playOne() async {
    if (choice == 'custom' && customSongPath.isNotEmpty) {
      try {
        await _player.stop();
        if (customSongPath.startsWith('http')) {
          await _player.play(UrlSource(customSongPath));
        } else {
          await _player.play(DeviceFileSource(customSongPath));
        }
        await doVibrate();
        return;
      } catch (_) {
        await playBuiltIn('bell');
        await doVibrate();
        return;
      }
    }
    await playBuiltIn(choice);
    await doVibrate();
  }

  // Same as your HTML window.playCustomSound()
  static Future<void> playCustomSound([String reason = '']) async {
    if (!enabled) return;
    if (_isPlaying && !keepRinging) return;
    _isPlaying = true;
    int count = repeat ? 3 : 1;
    if (keepRinging) count = 99;

    for (int i = 0; i < count; i++) {
      if (!keepRinging && i > 0 && !enabled) break;
      if (keepRinging && !_isPlaying) break;
      await playOne();
      if (i < count - 1) await Future.delayed(const Duration(milliseconds: 1200));
      if (!keepRinging && i >= 2) break;
    }
    _isPlaying = false;
  }

  static Future<void> stop() async {
    _isPlaying = false;
    keepRinging = false;
    try { await _player.stop(); } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lcg_sound_keep_ringing', false);
  }
}

class SoundSettingsPage extends StatefulWidget {
  const SoundSettingsPage({super.key});
  @override
  State<SoundSettingsPage> createState() => _SoundSettingsPageState();
}

class _SoundSettingsPageState extends State<SoundSettingsPage> {
  String _log = '';
  String _saved = '';
  bool _repeat = true;
  bool _vibrate = true;
  bool _keepRinging = false;
  String _choice = 'bell';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await SoundHelper.load();
    setState(() {
      _choice = SoundHelper.choice;
      _repeat = SoundHelper.repeat;
      _vibrate = SoundHelper.vibrate;
      _keepRinging = SoundHelper.keepRinging;
      _saved = 'Saved: $_choice';
    });
  }

  void _logMsg(String m) => setState(() => _log = m);

  Future<void> _enableSound() async {
    SoundHelper.enabled = true;
    _logMsg('ON');
    await SoundHelper.playCustomSound('test');
    try {
      if (await Vibration.hasVibrator() ?? false) {
        await Vibration.vibrate(pattern: [200, 100, 200]);
      }
    } catch (_) {}
    setState(() {});
  }

  Future<void> _pickBuiltIn(String? v) async {
    if (v == null) return;
    await SoundHelper.saveChoice(v);
    setState(() { _choice = v; _saved = 'Saved: $v'; });
    _logMsg(v);
  }

  Future<void> _uploadCustomSong() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    // Same limit as HTML: 3MB
    if (file.size > 3 * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Too big - max 3MB')));
      return;
    }
    final path = file.path;
    if (path == null) return;
    await SoundHelper.saveCustom(path);
    setState(() { _choice = 'custom'; _saved = 'Saved: custom'; });
    _logMsg('Saved');
    await SoundHelper.playCustomSound('test');
  }

  Future<void> _testSound() async {
    if (!SoundHelper.enabled) { await _enableSound(); return; }
    await SoundHelper.playCustomSound('test');
  }

  Future<void> _stopSound() async {
    await SoundHelper.stop();
    setState(() => _keepRinging = false);
    _logMsg('Stopped');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: const Text('← Back', style: TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.w800, fontSize: 13)),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [const Color(0xFFEF4444).withOpacity(0.12), const Color(0xFFA855F7).withOpacity(0.15)]),
                    border: Border.all(color: const Color(0x59EF4444), width: 2),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      // ENABLE SOUND BUTTON - Same as HTML
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _enableSound,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SoundHelper.enabled ? const Color(0xFF16A34A) : const Color(0xFF22C55E),
                            padding: const EdgeInsets.all(18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          ),
                          child: Text(SoundHelper.enabled ? '✅ SOUND ON' : '🔊 TAP TO ENABLE SOUND', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                        ),
                      ),
                      if (_log.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_log, style: const TextStyle(fontSize: 11, color: Color(0xFF86EFAC)))),
                      const SizedBox(height: 12),
                      // DROPDOWN - Same options as HTML
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(color: const Color(0xFF1C1238), border: Border.all(color: const Color(0x66A855F7)), borderRadius: BorderRadius.circular(999)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _choice,
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1C1238),
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            items: const [
                              DropdownMenuItem(value: 'bell', child: Text('🔔 Bell')),
                              DropdownMenuItem(value: 'chime', child: Text('🎵 Chime')),
                              DropdownMenuItem(value: 'alarm', child: Text('⏰ Alarm')),
                              DropdownMenuItem(value: 'gospel', child: Text('🎶 Gospel')),
                              DropdownMenuItem(value: 'highlife', child: Text('🎶 Highlife')),
                              DropdownMenuItem(value: 'siren', child: Text('🚨 Siren')),
                              DropdownMenuItem(value: 'custom', child: Text('🎤 My Song')),
                            ],
                            onChanged: _pickBuiltIn,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: ElevatedButton(onPressed: _testSound, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))), child: const Text('▶ Test', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13)))),
                        const SizedBox(width: 8),
                        Expanded(child: ElevatedButton(onPressed: _stopSound, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))), child: const Text('⏹ Stop', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)))),
                      ]),
                      const SizedBox(height: 12),
                      // UPLOAD CUSTOM SONG - Same as HTML input type=file
                      InkWell(
                        onTap: _uploadCustomSong,
                        child: Container(
                          width: double.infinity, padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0x0FFFFFFF), borderRadius: BorderRadius.circular(12)),
                          child: Text(SoundHelper.customSongPath.isEmpty ? '🎤 Choose My Song (audio, max 3MB) - Tap to Upload' : '🎤 My Song: ${SoundHelper.customSongPath.split('/').last} - Tap to Change', style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                      ),
                      _chk('Ring 3 times', _repeat, (v) async { setState(() => _repeat = v); SoundHelper.repeat = v; final p = await SharedPreferences.getInstance(); await p.setBool('lcg_sound_repeat', v); }),
                      _chk('Vibrate', _vibrate, (v) async { setState(() => _vibrate = v); SoundHelper.vibrate = v; final p = await SharedPreferences.getInstance(); await p.setBool('lcg_sound_vibrate', v); }),
                      _chk('Keep ringing', _keepRinging, (v) async {
                        setState(() => _keepRinging = v);
                        SoundHelper.keepRinging = v;
                        final p = await SharedPreferences.getInstance();
                        await p.setBool('lcg_sound_keep_ringing', v);
                        if (v) await SoundHelper.playCustomSound('keep');
                        else await SoundHelper.stop();
                      }),
                      if (_log.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Log: $_log', style: const TextStyle(fontSize: 11, color: Color(0xFF86EFAC)))),
                      if (_saved.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_saved, style: const TextStyle(fontSize: 11, color: Color(0xFF86EFAC)))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chk(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        SizedBox(width: 20, height: 20, child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false), activeColor: const Color(0xFFFACC15))),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.white)),
      ]),
    );
  }
}
