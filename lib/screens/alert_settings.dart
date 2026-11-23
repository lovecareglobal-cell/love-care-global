// alert_settings.dart - PATCHED WITH RULE - CEO ENGLISH ONLY
// RULE: CEO = English ONLY. Nurse + Client = 22 languages from main.dart
// Works with: alert_translations.dart (same folder)

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'alert_translations.dart';

class AlertSettingsScreen extends StatefulWidget {
  final String userId;
  final String role; // Nurse, Client, CEO
  const AlertSettingsScreen({super.key, required this.userId, required this.role});

  @override
  State<AlertSettingsScreen> createState() => _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends State<AlertSettingsScreen> {
  // ---------- LANGUAGE - THE RULE ----------
  // savedLang = wetin user pick for main.dart (fr, tw, ga, etc)
  // lang = wetin screen go actually show
  // CEO -> lang is ALWAYS 'en', no matter wetin user pick
  String lang = 'en';
  String savedLang = 'en';

  // ---------- STATE - must be above t() because t() checks isCEO ----------
  String selectedRole = 'Nurse';
  bool soundOn = true;
  String selectedSong = 'default'; // default, song1, song2, custom
  Uint8List? customSongBytes;
  String? customSongName;
  List<Map<String, dynamic>> alerts = [];
  final AudioPlayer _player = AudioPlayer();

  bool get isCEO => selectedRole == 'CEO';
  bool get isNurse => selectedRole == 'Nurse';
  bool get isClient => selectedRole == 'Client';

  String get roleKey => selectedRole.toLowerCase();

  // THE RULE - single place, every Text() uses this
  String t(String key) {
    if (isCEO) return AlertTranslations.get('en', key);
    return AlertTranslations.get(lang, key);
  }

  // Apply rule after role changes or lang loads
  void _applyLangForRole() {
    if (isCEO) {
      lang = 'en';
    } else {
      lang = savedLang;
    }
  }

  Future<void> _loadLang() async {
    final prefs = await SharedPreferences.getInstance();
    String raw = prefs.getString('app_lang') ??
        prefs.getString('language') ??
        prefs.getString('lang') ??
        prefs.getString('locale') ??
        'en';
    raw = raw.toLowerCase().split('_').first.split('-').first;
    if (raw == 'french') raw = 'fr';
    if (raw == 'twi') raw = 'tw';
    if (raw == 'english') raw = 'en';
    if (raw == 'ga') raw = 'ga';
    if (raw == 'ewe') raw = 'ee';
    if (raw == 'yoruba') raw = 'yo';
    if (raw == 'igbo') raw = 'ig';
    if (raw == 'hausa') raw = 'ha';
    if (AlertTranslations.all.containsKey(raw)) savedLang = raw;
    _applyLangForRole(); // CEO -> en, Nurse/Client -> savedLang
    if (mounted) setState(() {});
  }

  Future<void> _switchRole(String newRole) async {
    selectedRole = newRole;
    _applyLangForRole(); // <-- RULE applied instantly on pill tap
    await _loadSettings();
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Role FIRST, before lang - because t() needs to know if na CEO
    selectedRole = widget.role;
    if (selectedRole != 'Nurse' && selectedRole != 'Client' && selectedRole != 'CEO') {
      selectedRole = 'Client';
    }
    await _loadLang();
    await _loadSettings();
    await _loadAlerts();
    if (mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    soundOn = prefs.getBool('alert_sound_on_$selectedRole') ?? true;
    selectedSong = prefs.getString('alert_song_$selectedRole') ?? 'default';
    final custom = prefs.getString('alert_custom_song_$selectedRole');
    if (custom != null) {
      try {
        customSongBytes = base64Decode(custom);
        customSongName = prefs.getString('alert_custom_name_$selectedRole');
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alert_sound_on_$selectedRole', soundOn);
    await prefs.setString('alert_song_$selectedRole', selectedSong);
    if (customSongBytes != null) {
      await prefs.setString('alert_custom_song_$selectedRole', base64Encode(customSongBytes!));
      if (customSongName != null) {
        await prefs.setString('alert_custom_name_$selectedRole', customSongName!);
      }
    }
  }

  Future<void> _loadAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('alerts_${widget.userId}') ?? [];
    alerts = raw.map((e) => Map<String, dynamic>.from(jsonDecode(e))).toList();
    if (mounted) setState(() {});
  }

  Future<void> _saveAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'alerts_${widget.userId}', alerts.map((e) => jsonEncode(e)).toList());
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickSong() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.size > 8 * 1024 * 1024) {
      _toast(t('pickSong'));
      return;
    }
    customSongBytes = file.bytes;
    customSongName = file.name;
    selectedSong = 'custom';
    await _saveSettings();
    setState(() {});
    _toast(t('mySongFromPhone'));
  }

  Future<void> _playTest(String type) async {
    if (customSongBytes != null && selectedSong == 'custom') {
      await _player.play(BytesSource(customSongBytes!));
      return;
    }
    try {
      if (selectedSong == 'song1') {
        await _player.play(AssetSource('sounds/church_bell.mp3'));
      } else if (selectedSong == 'song2') {
        await _player.play(AssetSource('sounds/afrobeat.mp3'));
      } else {
        await _player.play(AssetSource('sounds/default_beep.mp3'));
      }
    } catch (_) {
      _toast(type);
    }
  }

  String _loudDesc() {
    if (isCEO) return t('loudDescCEO');
    if (isNurse) return t('loudDescNurse');
    return t('loudDescClient');
  }

  String _noAlertsText() {
    if (isCEO) return t('noAlertsCEO');
    if (isNurse) return t('noAlertsNurse');
    return t('noAlertsClient');
  }

  String _alertsListText() {
    if (isCEO) return t('alertsListCEO');
    if (isNurse) return t('alertsListNurse');
    return t('alertsListClient');
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(t('alertSettings'))),
        body: Center(child: Text(t('noUserId'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${t('alertSettings')} — ${t(roleKey)}'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {});
            },
            child: Text(t('newAlerts'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // WHO IS USING
            Text(t('whoUsingPhone'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: Text(t('nurse')),
                  selected: selectedRole == 'Nurse',
                  onSelected: (_) => _switchRole('Nurse'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(t('client')),
                  selected: selectedRole == 'Client',
                  onSelected: (_) => _switchRole('Client'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(t('ceo')),
                  selected: selectedRole == 'CEO',
                  onSelected: (_) => _switchRole('CEO'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${t('sameSettings')} ID: ${widget.userId}'),
            const Divider(height: 28),

            // LOUD SOUND
            Text(t('loudSound'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(_loudDesc()),
            SwitchListTile(
              title: Text(soundOn ? t('onLoud') : t('off')),
              value: soundOn,
              onChanged: (v) async {
                soundOn = v;
                await _saveSettings();
                setState(() {});
              },
            ),
            const Divider(height: 28),

            // SONG CHOICE
            Text('${t('songChoiceTitle')} — ${t(roleKey)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            RadioListTile<String>(
              title: Text(t('defaultBeep')),
              value: 'default',
              groupValue: selectedSong,
              onChanged: (v) async {
                selectedSong = v!;
                await _saveSettings();
                setState(() {});
              },
            ),
            RadioListTile<String>(
              title: Text(t('mySongFromPhone')),
              value: 'custom',
              groupValue: selectedSong,
              onChanged: (v) async {
                if (customSongBytes == null) {
                  await _pickSong();
                } else {
                  selectedSong = v!;
                  await _saveSettings();
                  setState(() {});
                }
              },
            ),
            RadioListTile<String>(
              title: Text(t('song1')),
              value: 'song1',
              groupValue: selectedSong,
              onChanged: (v) async {
                selectedSong = v!;
                await _saveSettings();
                setState(() {});
              },
            ),
            RadioListTile<String>(
              title: Text(t('song2')),
              value: 'song2',
              groupValue: selectedSong,
              onChanged: (v) async {
                selectedSong = v!;
                await _saveSettings();
                setState(() {});
              },
            ),
            Text('${t('currentDefault')} ${customSongName ?? ''}'),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _pickSong,
                  child: Text(t('pickSong')),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _playTest(t('testMySong')),
                  child: Text(t('testMySong')),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    customSongBytes = null;
                    customSongName = null;
                    selectedSong = 'default';
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('alert_custom_song_$selectedRole');
                    await _saveSettings();
                    setState(() {});
                  },
                  child: Text(t('remove')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () => _playTest(t('testNewBooking')),
                  child: Text(t('testNewBooking')),
                ),
                ElevatedButton(
                  onPressed: () => _playTest(t('testAccepted')),
                  child: Text(t('testAccepted')),
                ),
                ElevatedButton(
                  onPressed: () => _playTest(t('testArrived')),
                  child: Text(t('testArrived')),
                ),
                ElevatedButton(
                  onPressed: () => _playTest(t('testCompleted')),
                  child: Text(t('testCompleted')),
                ),
              ],
            ),
            const Divider(height: 28),

            // ALERTS LIST
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(_alertsListText())),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        for (var a in alerts) a['read'] = true;
                        await _saveAlerts();
                        setState(() {});
                      },
                      child: Text(t('markAllRead')),
                    ),
                    TextButton(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text(t('deleteQ')),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: Text(t('no'))),
                              TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(t('yes'))),
                            ],
                          ),
                        );
                        if (ok == true) {
                          alerts.clear();
                          await _saveAlerts();
                          setState(() {});
                        }
                      },
                      child: Text(t('deleteAll')),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (alerts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(_noAlertsText(), textAlign: TextAlign.center),
              )
            else
              ...alerts.map((n) {
                final isRead = n['read'] == true;
                return Card(
                  child: ListTile(
                    title: Text(n['title']?.toString() ?? ''),
                    subtitle: Text(
                        '${t('bookingId')} ${n['bookingId'] ?? 'N/A'} • ${n['body']?.toString() ?? ''}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'read') {
                          n['read'] = true;
                          await _saveAlerts();
                          setState(() {});
                        } else if (v == 'delete') {
                          alerts.remove(n);
                          await _saveAlerts();
                          setState(() {});
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'read', child: Text(t('markRead'))),
                        PopupMenuItem(value: 'delete', child: Text(t('delete'))),
                      ],
                    ),
                    tileColor: isRead ? null : Colors.yellow.shade50,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
