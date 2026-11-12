import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

/// Client Settings - Flutter version of client-settings.html
/// USERNAME SYSTEM — NO EMAIL NEEDED (same as HTML)
/// - Photo: max 5MB -> Storage clients/{uid}/photo_... + clients/{uid} + syncToCEO
/// - Change Username: no spaces, min 3, check clientUsernames/{clean} availability, remove old keys
/// - Update Profile: fullName, username, phone (+233), photo
/// - Change Password: fake email username@lovecare.local reauth, fallback DB-only passwordUpdatedAt
/// - Delete Account: SAME AS HTML -> toast 'Contact CEO to delete — Safety' (does NOT delete)
/// - syncToCEO: clients, allowedClients/{usernameKey} + allowedClients/{emailKey}, client_registrations, ceoRegistrationCenter/clients, clientUsernames/{usernameKey}
/// - saveToLocalStorage: clientName, clientUsername, clientPhone, clientPhotoUrl, clientUid, clientEmail

class ClientSettingsScreen extends StatefulWidget {
  const ClientSettingsScreen({super.key});
  @override
  State<ClientSettingsScreen> createState() => _ClientSettingsScreenState();
}

class _ClientSettingsScreenState extends State<ClientSettingsScreen> {
  User? currentUser;
  String currentUid = '';
  String photoUrl = '';
  final _currentUsernameCtrl = TextEditingController();
  final _newUsernameCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _curPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _deleteReasonCtrl = TextEditingController();
  final _deleteDetailsCtrl = TextEditingController();

  String sanitizeUsername(String s) => s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9_]'), '_').replaceAll(RegExp(r'_+'), '_');
  String sanitizeEmail(String s) => s.toLowerCase().trim().replaceAll(RegExp(r'[.#\$\[\]]'), '_').replaceAll('@', '_at_');

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    setState(() {
      currentUser = user;
      currentUid = prefs.getString('clientUid') ?? user?.uid ?? '';
      _fullNameCtrl.text = prefs.getString('clientName') ?? prefs.getString('fullName') ?? '';
      _currentUsernameCtrl.text = prefs.getString('clientUsername') ?? prefs.getString('username') ?? '';
      final phone = prefs.getString('clientPhone') ?? prefs.getString('phone') ?? '';
      _phoneCtrl.text = phone.startsWith('+233 ') ? phone.substring(5) : phone.replaceAll('+233', '').trim();
      photoUrl = prefs.getString('clientPhotoUrl') ?? prefs.getString('photoUrl') ?? '';
    });
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _saveToLocalStorage(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    if (data['fullName'] != null || data['name'] != null) {
      await prefs.setString('clientName', (data['fullName'] ?? data['name']).toString());
      await prefs.setString('fullName', (data['fullName'] ?? data['name']).toString());
    }
    if (data['username'] != null || data['userName'] != null) {
      await prefs.setString('clientUsername', (data['username'] ?? data['userName']).toString());
      await prefs.setString('username', (data['username'] ?? data['userName']).toString());
      await prefs.setString('clientUserName', (data['username'] ?? data['userName']).toString());
    }
    if (data['phone'] != null || data['phoneNumber'] != null) {
      await prefs.setString('clientPhone', (data['phone'] ?? data['phoneNumber']).toString());
      await prefs.setString('phone', (data['phone'] ?? data['phoneNumber']).toString());
    }
    if (data['photoURL'] != null || data['photo'] != null || data['photoUrl'] != null) {
      final ph = (data['photoURL'] ?? data['photo'] ?? data['photoUrl']).toString();
      await prefs.setString('clientPhotoUrl', ph);
      await prefs.setString('clientPhoto', ph);
      await prefs.setString('photoUrl', ph);
      await prefs.setString('photo', ph);
    }
    if (data['uid'] != null) await prefs.setString('clientUid', data['uid'].toString());
    if (data['email'] != null) await prefs.setString('clientEmail', data['email'].toString());
  }

  Future<void> _syncToCEO(String uid, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final base = {
        ...data,
        'uid': uid,
        'username': data['username'] ?? data['userName'] ?? prefs.getString('clientUsername') ?? '',
        'userName': data['username'] ?? data['userName'] ?? prefs.getString('clientUsername') ?? '',
        'fullName': data['fullName'] ?? data['name'] ?? prefs.getString('clientName') ?? '',
        'name': data['fullName'] ?? data['name'] ?? prefs.getString('clientName') ?? '',
        'phone': data['phone'] ?? data['phoneNumber'] ?? prefs.getString('clientPhone') ?? '',
        'phoneNumber': data['phone'] ?? data['phoneNumber'] ?? prefs.getString('clientPhone') ?? '',
        'photoURL': data['photoURL'] ?? data['photo'] ?? prefs.getString('clientPhotoUrl') ?? '',
        'photo': data['photoURL'] ?? data['photo'] ?? prefs.getString('clientPhotoUrl') ?? '',
        'lastUpdate': DateTime.now().millisecondsSinceEpoch,
        'clientSettingsUpdatedAt': DateTime.now().millisecondsSinceEpoch,
        'loginType': 'username',
      };
      final usernameKey = sanitizeUsername((base['username'] ?? base['fullName'] ?? uid).toString());
      final emailKey = (base['email'] != null && (base['email'] as String).isNotEmpty) ? sanitizeEmail(base['email'].toString()) : usernameKey;
      final db = FirebaseDatabase.instance;
      await db.ref('clients/$uid').update(base);
      await db.ref('allowedClients/$usernameKey').update(base);
      if (emailKey != usernameKey) await db.ref('allowedClients/$emailKey').update(base).catchError((_) {});
      await db.ref('client_registrations/$uid').update(base);
      await db.ref('ceoRegistrationCenter/clients/$uid').update(base);
      await db.ref('clientUsernames/$usernameKey').set({'uid': uid, 'username': base['username'], 'fullName': base['fullName'], 'phone': base['phone'], 'photoURL': base['photoURL'], 'updatedAt': DateTime.now().millisecondsSinceEpoch});
      await _saveToLocalStorage(base);
    } catch (e) { debugPrint('CEO sync failed: $e'); }
  }

  Future<void> _updatePhoto() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res == null || res.files.single.path == null) { _toast('Select photo first'); return; }
    final file = File(res.files.single.path!);
    if (await file.length() > 5 * 1024 * 1024) { _toast('Max 5MB'); return; }
    _toast('Uploading photo... (username system)');
    try {
      final safeName = res.files.single.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final uid = currentUser?.uid ?? (await SharedPreferences.getInstance()).getString('clientUid') ?? 'unknown';
      final ref = FirebaseStorage.instance.ref('clients/$uid/photo_${DateTime.now().millisecondsSinceEpoch}_$safeName');
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      final username = _currentUsernameCtrl.text.isNotEmpty ? _currentUsernameCtrl.text : (await SharedPreferences.getInstance()).getString('clientUsername') ?? '';
      final data = {'photoURL': url, 'photo': url, 'photoUrl': url, 'username': username, 'userName': username, 'uid': uid, 'fullName': _fullNameCtrl.text, 'name': _fullNameCtrl.text, 'phone': '+233 ${_phoneCtrl.text.trim()}'};
      await FirebaseDatabase.instance.ref('clients/$uid').update(data);
      await _syncToCEO(uid, data);
      await _saveToLocalStorage(data);
      setState(() => photoUrl = url);
      _toast('📸 Photo updated ✅ — Username system — Saved!');
    } catch (e) { _toast('Failed: $e'); }
  }

  Future<void> _changeUsername() async {
    final newU = _newUsernameCtrl.text.trim();
    if (newU.isEmpty) { _toast('Enter new username'); return; }
    if (newU.contains(' ')) { _toast('No spaces, use _'); return; }
    final cleanU = sanitizeUsername(newU);
    if (cleanU.length < 3) { _toast('Username min 3 chars'); return; }
    try {
      _toast('Checking username availability...');
      final check = await FirebaseDatabase.instance.ref('clientUsernames/$cleanU').get();
      if (check.exists && (check.value as Map)['uid'] != currentUser?.uid) { _toast('❌ Username taken: $cleanU'); return; }
      _toast('Updating username...');
      final prefs = await SharedPreferences.getInstance();
      final uid = currentUser?.uid ?? prefs.getString('clientUid') ?? 'username-$cleanU';
      final data = {'username': cleanU, 'userName': cleanU, 'usernameUpdatedAt': DateTime.now().millisecondsSinceEpoch, 'uid': uid, 'name': _fullNameCtrl.text, 'fullName': _fullNameCtrl.text, 'phone': '+233 ${_phoneCtrl.text.trim()}'};
      await FirebaseDatabase.instance.ref('clients/$uid').update(data);
      setState(() => _currentUsernameCtrl.text = cleanU);
      await _syncToCEO(uid, data);
      final oldU = prefs.getString('clientUsername');
      if (oldU != null && sanitizeUsername(oldU) != cleanU) {
        await FirebaseDatabase.instance.ref('clientUsernames/${sanitizeUsername(oldU)}').remove().catchError((_) {});
        await FirebaseDatabase.instance.ref('allowedClients/${sanitizeUsername(oldU)}').remove().catchError((_) {});
      }
      await _saveToLocalStorage(data);
      _toast('🔑 Username updated ✅ to: $cleanU');
    } catch (e) { _toast(e.toString()); }
  }

  Future<void> _updateProfile() async {
    final name = _fullNameCtrl.text.trim();
    final username = _currentUsernameCtrl.text.trim();
    final phoneRaw = _phoneCtrl.text.trim();
    if (name.isEmpty) { _toast('Enter full name'); return; }
    if (username.isEmpty) { _toast('Username required - set it above'); return; }
    if (phoneRaw.isEmpty) { _toast('Enter phone'); return; }
    final fullPhone = '+233 $phoneRaw';
    try {
      _toast('Saving profile... (username system)');
      final prefs = await SharedPreferences.getInstance();
      final uid = currentUser?.uid ?? prefs.getString('clientUid') ?? 'username-${sanitizeUsername(username)}';
      final data = {'name': name, 'fullName': name, 'clientName': name, 'displayName': name, 'username': username, 'userName': username, 'clientUsername': username, 'clientUserName': username, 'phone': fullPhone, 'phoneNumber': fullPhone, 'clientPhone': fullPhone, 'uid': uid, 'clientUid': uid, 'nameUpdatedAt': DateTime.now().millisecondsSinceEpoch, 'phoneUpdatedAt': DateTime.now().millisecondsSinceEpoch, 'profileUpdatedAt': DateTime.now().millisecondsSinceEpoch, 'clientSettingsUpdatedAt': DateTime.now().millisecondsSinceEpoch, 'lastUpdate': DateTime.now().millisecondsSinceEpoch, 'loginType': 'username'};
      if (photoUrl.isNotEmpty && !photoUrl.contains('via.placeholder')) { data['photoURL'] = photoUrl; data['photo'] = photoUrl; data['photoUrl'] = photoUrl; data['clientPhotoUrl'] = photoUrl; }
      await FirebaseDatabase.instance.ref('clients/$uid').update(data);
      await _syncToCEO(uid, data);
      await _saveToLocalStorage(data);
      _toast('✅ Saved! Name: $name • Username: $username • Phone: $fullPhone');
    } catch (e) { _toast(e.toString()); }
  }

  Future<void> _changePassword() async {
    final cur = _curPassCtrl.text, nw = _newPassCtrl.text, cf = _confirmPassCtrl.text;
    if (nw.length < 6) { _toast('Min 6 chars'); return; }
    if (nw != cf) { _toast('Mismatch'); return; }
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = _currentUsernameCtrl.text.isNotEmpty ? _currentUsernameCtrl.text : prefs.getString('clientUsername') ?? '';
      final fakeEmail = currentUser?.email ?? (username.isNotEmpty ? '$username@lovecare.local' : '');
      final uid = currentUser?.uid ?? prefs.getString('clientUid') ?? '';
      if (cur.isNotEmpty && fakeEmail.isNotEmpty && currentUser != null && !uid.startsWith('username-')) {
        try {
          final cred = EmailAuthProvider.credential(email: fakeEmail, password: cur);
          await currentUser!.reauthenticateWithCredential(cred);
          await currentUser!.updatePassword(nw);
        } catch (_) {
          await FirebaseDatabase.instance.ref('clients/$uid').update({'passwordUpdatedAt': DateTime.now().millisecondsSinceEpoch, 'passwordHash': 'updated_${DateTime.now().millisecondsSinceEpoch}'});
          _toast('Password updated in DB (custom username system) ✅');
          return;
        }
      } else {
        await FirebaseDatabase.instance.ref('clients/$uid').update({'passwordUpdatedAt': DateTime.now().millisecondsSinceEpoch, 'passwordChangedAt': DateTime.now().millisecondsSinceEpoch});
        await _syncToCEO(uid, {'passwordUpdatedAt': DateTime.now().millisecondsSinceEpoch});
      }
      _toast('Password changed ✅');
      setState(() { _curPassCtrl.clear(); _newPassCtrl.clear(); _confirmPassCtrl.clear(); });
    } catch (e) { _toast(e.toString()); }
  }

  void _deleteAccount() {
    // SAME AS HTML — do NOT delete, CEO must do it for safety
    _toast('Contact CEO to delete — Safety');
    showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Delete Account'), content: Text('For safety, please contact CEO to delete your account.\nReason: ${_deleteReasonCtrl.text}\nDetails: ${_deleteDetailsCtrl.text}'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('Client Settings', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          // Current Info
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Current Info', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [Chip(label: Text('👤 Name: ${_fullNameCtrl.text.isEmpty ? 'Not set' : _fullNameCtrl.text}', style: const TextStyle(fontSize: 11))), Chip(label: Text('🔑 Username: ${_currentUsernameCtrl.text.isEmpty ? 'Not set' : _currentUsernameCtrl.text}', style: const TextStyle(fontSize: 11))), Chip(label: Text('📞 Phone: ${_phoneCtrl.text.isEmpty ? 'Not set' : '+233 ${_phoneCtrl.text}'}', style: const TextStyle(fontSize: 11))), Chip(label: Text(photoUrl.isNotEmpty ? '📸 Photo: Yes' : '📸 Photo: No', style: const TextStyle(fontSize: 11)))]),
            const SizedBox(height: 6),
            const Text('Saved in: SharedPreferences + clients/ + allowedClients/ + ceoRegistrationCenter', style: TextStyle(color: Colors.white60, fontSize: 10)),
          ])),
          const SizedBox(height: 12),
          // Photo
          _card('📸 Profile Photo', Column(children: [
            CircleAvatar(radius: 40, backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null, child: photoUrl.isEmpty ? const Icon(Icons.person, size: 40) : null),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _updatePhoto, child: const Text('Upload New Photo (max 5MB)')),
          ])),
          // Username
          _card('🔑 Change Username', Column(children: [
            TextField(controller: _currentUsernameCtrl, decoration: const InputDecoration(labelText: 'Current Username', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _newUsernameCtrl, decoration: const InputDecoration(labelText: 'New Username (no spaces, use _)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _changeUsername, child: const Text('Change Username'))),
          ])),
          // Profile
          _card('👤 Profile — Full Name + Phone', Column(children: [
            TextField(controller: _fullNameCtrl, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (without +233)', prefixText: '+233 ', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _updateProfile, child: const Text('Save Profile'))),
          ])),
          // Password
          _card('🔒 Change Password', Column(children: [
            TextField(controller: _curPassCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Current Password', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _newPassCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'New Password (min 6)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _confirmPassCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm New Password', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _changePassword, child: const Text('Change Password'))),
          ])),
          // Delete (CEO only)
          _card('🗑️ Delete Account', Column(children: [
            DropdownButtonFormField<String>(value: null, decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'Leaving', child: Text('Leaving')), DropdownMenuItem(value: 'Privacy', child: Text('Privacy')), DropdownMenuItem(value: 'Other', child: Text('Other'))], onChanged: (v) => _deleteReasonCtrl.text = v ?? ''),
            const SizedBox(height: 8),
            TextField(controller: _deleteDetailsCtrl, decoration: const InputDecoration(labelText: 'Details', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _deleteAccount, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Request Delete — Contact CEO'))),
            const Text('For safety, account deletion is done by CEO only.', style: TextStyle(color: Colors.white60, fontSize: 11)),
          ])),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _card(String title, Widget child) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), const SizedBox(height: 10), child]));
}
