import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';

/// Nurse Settings - Flutter version of nurse-settings.html
/// - Photo upload -> Storage nurses/{uid}/photo_... + nurses/{uid} + syncToCEO
/// - Docs: CV 10MB, Video 50MB, Certificate 10MB, License 10MB -> Storage nurses/{uid}/{type}_...
/// - Email change (reauth), Phone+Name, Nurse Info (specialty, country, bio, prices, hours, availability)
/// - GPS Location save, Password change (reauth), Delete Account (deletedNurses)
/// - syncToCEO: nurses, nurse_registrations, pendingNurseRegistrations, nurseUsers, nurseProfiles, ceoNurseUpdates, ceoRegistrationCenter/nurses, ceoBookingReceiverNurses

class NurseSettingsScreen extends StatefulWidget {
  const NurseSettingsScreen({super.key});
  @override
  State<NurseSettingsScreen> createState() => _NurseSettingsScreenState();
}

class _NurseSettingsScreenState extends State<NurseSettingsScreen> {
  User? currentUser;
  Map? nurseData;
  // Controllers
  final _newEmailCtrl = TextEditingController();
  final _emailPassCtrl = TextEditingController();
  final _newPhoneCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _specialtyCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _priceShortCtrl = TextEditingController();
  final _priceLongCtrl = TextEditingController();
  final _workHoursCtrl = TextEditingController();
  String availability = 'Available';
  final _gpsNameCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _curPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _deletePassCtrl = TextEditingController();
  final _deleteDetailsCtrl = TextEditingController();
  String deleteReason = '';
  bool confirmCheck = false, confirmData = false;
  Map<String, String> docUrls = {}; // cv, video, certificate, license
  Map<String, double> uploadProgress = {};
  String? photoUrl;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    setState(() => currentUser = user);
    if (user == null) return;
    final snap = await FirebaseDatabase.instance.ref('nurses/${user.uid}').get();
    if (snap.exists) {
      final d = Map<String, dynamic>.from(snap.value as Map);
      setState(() {
        nurseData = d;
        photoUrl = d['photo'] ?? d['photoURL'];
        _displayNameCtrl.text = d['name'] ?? user.displayName ?? '';
        _newPhoneCtrl.text = d['phone'] ?? '';
        _specialtyCtrl.text = d['specialty'] ?? '';
        _countryCtrl.text = d['country'] ?? 'Ghana';
        _bioCtrl.text = d['bio'] ?? '';
        _priceShortCtrl.text = d['priceShort']?.toString() ?? '';
        _priceLongCtrl.text = d['priceLong']?.toString() ?? '';
        _workHoursCtrl.text = d['workHours']?.toString() ?? '';
        availability = d['availability'] ?? 'Available';
        _latCtrl.text = d['lat']?.toString() ?? '';
        _lngCtrl.text = d['lng']?.toString() ?? '';
        _gpsNameCtrl.text = d['gpsActualName'] ?? '';
        docUrls = {
          'cv': d['cvUrl'] ?? '', 'video': d['videoUrl'] ?? '',
          'certificate': d['certificateUrl'] ?? '', 'license': d['licenseUrl'] ?? '',
        };
      });
    }
  }

  Future<void> _syncToCEO(String uid, Map<String, dynamic> data) async {
    try {
      final base = {...data, 'updatedAt': DateTime.now().millisecondsSinceEpoch, 'settingsUpdatedAt': DateTime.now().millisecondsSinceEpoch, 'lastUpdate': DateTime.now().millisecondsSinceEpoch, 'profileUpdatedAt': DateTime.now().millisecondsSinceEpoch};
      final db = FirebaseDatabase.instance;
      await db.ref('nurses/$uid').update(base);
      await db.ref('nurse_registrations/$uid').update(base);
      await db.ref('pendingNurseRegistrations/$uid').update(base);
      await db.ref('nurseUsers/$uid').update(base).catchError((_) {});
      await db.ref('nurseProfiles/$uid').update(base).catchError((_) {});
      await db.ref('ceoNurseUpdates/$uid').set({...base, 'updatedBy': 'nurse-settings.dart', 'uid': uid});
      await db.ref('ceoRegistrationCenter/nurses/$uid').set(base);
      await db.ref('ceoBookingReceiverNurses/$uid').set(base);
    } catch (e) { debugPrint('CEO sync failed: $e'); }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _uploadPhoto() async {
    if (currentUser == null) { _toast('Login required to upload'); return; }
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res == null || res.files.single.path == null) { _toast('Select a photo first'); return; }
    _toast('Uploading photo...');
    try {
      final file = File(res.files.single.path!);
      final ref = FirebaseStorage.instance.ref('nurses/${currentUser!.uid}/photo_${DateTime.now().millisecondsSinceEpoch}_${res.files.single.name}');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      await currentUser!.updatePhotoURL(url);
      await FirebaseDatabase.instance.ref('nurses/${currentUser!.uid}').update({'photo': url, 'photoUpdatedAt': DateTime.now().millisecondsSinceEpoch});
      await _syncToCEO(currentUser!.uid, {'photo': url, 'photoURL': url, 'photoUpdatedAt': DateTime.now().millisecondsSinceEpoch});
      setState(() => photoUrl = url);
      _toast('Photo updated ✅ — CEO Center live');
    } catch (e) { _toast('Upload failed: $e'); }
  }

  Future<void> _uploadDoc(String type) async {
    if (currentUser == null) { _toast('Login required'); return; }
    final maxMB = type == 'video' ? 50 : 10;
    final fieldUrl = type == 'cv' ? 'cvUrl' : type == 'video' ? 'videoUrl' : type == 'certificate' ? 'certificateUrl' : 'licenseUrl';
    final fieldName = type == 'cv' ? 'cvName' : type == 'video' ? 'videoName' : type == 'certificate' ? 'certificateName' : 'licenseName';
    final res = await FilePicker.platform.pickFiles();
    if (res == null || res.files.single.path == null) { _toast('Select a file for $type'); return; }
    final file = File(res.files.single.path!);
    if (await file.length() > maxMB * 1024 * 1024) { _toast('File too large >$maxMB MB'); return; }
    try {
      final ref = FirebaseStorage.instance.ref('nurses/${currentUser!.uid}/${type}_${DateTime.now().millisecondsSinceEpoch}_${res.files.single.name}');
      final task = ref.putFile(file);
      task.snapshotEvents.listen((s) {
        final pct = s.totalBytes > 0 ? s.bytesTransferred / s.totalBytes : 0;
        setState(() => uploadProgress[type] = pct);
      });
      await task;
      final url = await ref.getDownloadURL();
      final updates = {fieldUrl: url, fieldName: res.files.single.name, '${fieldUrl}UpdatedAt': DateTime.now().millisecondsSinceEpoch};
      await FirebaseDatabase.instance.ref('nurses/${currentUser!.uid}').update(updates);
      await _syncToCEO(currentUser!.uid, updates);
      setState(() => docUrls[type] = url);
      _toast('${type.toUpperCase()} uploaded ✅ — CEO Center live');
    } catch (e) { _toast('Upload failed: $e'); }
  }

  Future<void> _changeEmail() async {
    final newEmail = _newEmailCtrl.text.trim();
    final pass = _emailPassCtrl.text.trim();
    if (newEmail.isEmpty) { _toast('Enter new email'); return; }
    if (currentUser == null) { _toast('Login required'); return; }
    if (pass.isEmpty) { _toast('Enter current password to confirm'); return; }
    try {
      final cred = EmailAuthProvider.credential(email: currentUser!.email!, password: pass);
      await currentUser!.reauthenticateWithCredential(cred);
      await currentUser!.verifyBeforeUpdateEmail(newEmail);
      await FirebaseDatabase.instance.ref('nurses/${currentUser!.uid}').update({'email': newEmail});
      await _syncToCEO(currentUser!.uid, {'email': newEmail, 'emailUpdatedAt': DateTime.now().millisecondsSinceEpoch});
      _toast('Email updated — please re-login — CEO Center live');
    } catch (e) { _toast('Email change failed: $e'); }
  }

  Future<void> _changePhone() async {
    final newPhone = _newPhoneCtrl.text.trim();
    final name = _displayNameCtrl.text.trim();
    if (currentUser == null) { _toast('Login required'); return; }
    if (newPhone.isEmpty && name.isEmpty) { _toast('Enter phone or name'); return; }
    try {
      final updates = <String, dynamic>{'updatedAt': DateTime.now().millisecondsSinceEpoch};
      if (newPhone.isNotEmpty) updates['phone'] = newPhone;
      if (name.isNotEmpty) updates['name'] = name;
      await FirebaseDatabase.instance.ref('nurses/${currentUser!.uid}').update(updates);
      await _syncToCEO(currentUser!.uid, updates);
      if (name.isNotEmpty) await currentUser!.updateDisplayName(name);
      _toast('Phone & name updated ✅ — CEO Center live');
    } catch (e) { _toast('Update failed: $e'); }
  }

  Future<void> _saveNurseInfo() async {
    if (currentUser == null) { _toast('Login required'); return; }
    final data = {'specialty': _specialtyCtrl.text.trim(), 'country': _countryCtrl.text, 'bio': _bioCtrl.text.trim(), 'priceShort': _priceShortCtrl.text.trim(), 'priceLong': _priceLongCtrl.text.trim(), 'workHours': _workHoursCtrl.text.trim(), 'availability': availability, 'updatedAt': DateTime.now().millisecondsSinceEpoch};
    try {
      await FirebaseDatabase.instance.ref('nurses/${currentUser!.uid}').update(data);
      await _syncToCEO(currentUser!.uid, data);
      _toast('Nurse info saved ✅ — CEO Center live');
    } catch (e) { _toast('Save failed: $e'); }
  }

  Future<void> _getGPS() async {
    _gpsNameCtrl.text = 'Locating...';
    try {
      final perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) { _gpsNameCtrl.text = 'Enable GPS'; return; }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() { _latCtrl.text = pos.latitude.toStringAsFixed(6); _lngCtrl.text = pos.longitude.toStringAsFixed(6); _gpsNameCtrl.text = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}'; });
    } catch (_) { _gpsNameCtrl.text = 'Enable GPS'; }
  }

  Future<void> _saveLocation() async {
    if (currentUser == null) { _toast('Login required'); return; }
    final lat = double.tryParse(_latCtrl.text);
    final lng = double.tryParse(_lngCtrl.text);
    if (lat == null || lng == null) { _toast('Get GPS first'); return; }
    try {
      final data = {'lat': lat, 'lng': lng, 'gpsActualName': _gpsNameCtrl.text, 'updatedAt': DateTime.now().millisecondsSinceEpoch};
      await FirebaseDatabase.instance.ref('nurses/${currentUser!.uid}').update(data);
      await _syncToCEO(currentUser!.uid, data);
      _toast('Location saved ✅ — CEO Center live');
    } catch (e) { _toast('Save failed: $e'); }
  }

  Future<void> _changePassword() async {
    final cur = _curPassCtrl.text.trim(), np = _newPassCtrl.text.trim(), cp = _confirmPassCtrl.text.trim();
    if (cur.isEmpty || np.isEmpty || cp.isEmpty) { _toast('Fill all password fields'); return; }
    if (np.length < 6) { _toast('New password min 6 chars'); return; }
    if (np != cp) { _toast('Passwords do not match'); return; }
    if (currentUser == null) { _toast('Login required'); return; }
    try {
      final cred = EmailAuthProvider.credential(email: currentUser!.email!, password: cur);
      await currentUser!.reauthenticateWithCredential(cred);
      await currentUser!.updatePassword(np);
      _toast('Password updated ✅');
    } catch (e) { _toast('Password change failed: $e'); }
  }

  Future<void> _deleteAccount() async {
    final reason = deleteReason, pass = _deletePassCtrl.text.trim();
    if (reason.isEmpty) { _toast('Select a reason'); return; }
    if (!confirmCheck || !confirmData) { _toast('Check both boxes'); return; }
    if (pass.isEmpty) { _toast('Enter password'); return; }
    if (currentUser == null) { _toast('Login required'); return; }
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Delete account for reason: $reason?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
    if (confirm != true) return;
    try {
      final cred = EmailAuthProvider.credential(email: currentUser!.email!, password: pass);
      await currentUser!.reauthenticateWithCredential(cred);
      await FirebaseDatabase.instance.ref('deletedNurses/${currentUser!.uid}').set({'email': currentUser!.email, 'reason': reason, 'details': _deleteDetailsCtrl.text, 'deletedAt': DateTime.now().millisecondsSinceEpoch});
      await FirebaseDatabase.instance.ref('nurses/${currentUser!.uid}').remove().catchError((_) {});
      await currentUser!.delete();
      _toast('Account deleted — Redirecting...');
      Future.delayed(const Duration(seconds: 2), () { if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false); });
    } catch (e) { _toast('Delete failed: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('Nurse Settings', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [TextButton(onPressed: () {}, child: const Text('SOS', style: TextStyle(color: Colors.white)))]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          // Photo
          _card('📸 Profile Photo', Column(children: [
            CircleAvatar(radius: 40, backgroundImage: photoUrl != null && photoUrl!.isNotEmpty ? NetworkImage(photoUrl!) : null, child: photoUrl == null || photoUrl!.isEmpty ? const Icon(Icons.person, size: 40) : null),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _uploadPhoto, child: const Text('Upload New Photo')),
            Text(currentUser == null ? '● Not logged in' : '● Logged in as ${currentUser!.email}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ])),
          // Docs
          _card('📄 Documents — CV / Video / Certificate / License', Column(children: [
            for (final type in ['cv','video','certificate','license']) ...[
              ListTile(title: Text(type.toUpperCase()), subtitle: Text(docUrls[type]?.isNotEmpty == true ? '✅ Uploaded' : 'Not uploaded yet')),
              if (uploadProgress[type] != null) LinearProgressIndicator(value: uploadProgress[type]),
              ElevatedButton(onPressed: () => _uploadDoc(type), child: Text('Upload ${type.toUpperCase()} ${type == 'video' ? '(max 50MB)' : '(max 10MB)'}')),
              const SizedBox(height: 8),
            ],
          ])),
          // Email
          _card('📧 Change Email', Column(children: [
            Text('Current: ${currentUser?.email ?? ''}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            TextField(controller: _newEmailCtrl, decoration: const InputDecoration(labelText: 'New Email', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _emailPassCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Current Password to Confirm', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _changeEmail, child: const Text('Change Email'))),
          ])),
          // Phone + Name
          _card('📱 Phone & Name', Column(children: [
            TextField(controller: _displayNameCtrl, decoration: const InputDecoration(labelText: 'Display Name', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _newPhoneCtrl, decoration: const InputDecoration(labelText: 'New Phone', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _changePhone, child: const Text('Update Phone & Name'))),
          ])),
          // Nurse Info
          _card('🩺 Nurse Info', Column(children: [
            TextField(controller: _specialtyCtrl, decoration: const InputDecoration(labelText: 'Specialty', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(value: _countryCtrl.text.isEmpty ? 'Ghana' : _countryCtrl.text, decoration: const InputDecoration(labelText: 'Country', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'Ghana', child: Text('Ghana')), DropdownMenuItem(value: 'USA', child: Text('USA')), DropdownMenuItem(value: 'UK', child: Text('UK')), DropdownMenuItem(value: 'Other', child: Text('Other'))], onChanged: (v) => setState(() => _countryCtrl.text = v ?? 'Ghana')),
            const SizedBox(height: 8),
            TextField(controller: _bioCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Bio', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            Row(children: [Expanded(child: TextField(controller: _priceShortCtrl, decoration: const InputDecoration(labelText: 'Price Short', border: OutlineInputBorder()))), const SizedBox(width: 8), Expanded(child: TextField(controller: _priceLongCtrl, decoration: const InputDecoration(labelText: 'Price Long', border: OutlineInputBorder())))]),
            const SizedBox(height: 8),
            TextField(controller: _workHoursCtrl, decoration: const InputDecoration(labelText: 'Work Hours', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(value: availability, decoration: const InputDecoration(labelText: 'Availability', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'Available', child: Text('Available')), DropdownMenuItem(value: 'Busy', child: Text('Busy')), DropdownMenuItem(value: 'Offline', child: Text('Offline'))], onChanged: (v) => setState(() => availability = v ?? 'Available')),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saveNurseInfo, child: const Text('Save Nurse Info'))),
          ])),
          // Location
          _card('📍 GPS Location', Column(children: [
            TextField(controller: _gpsNameCtrl, decoration: const InputDecoration(labelText: 'GPS Location Name', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            Row(children: [Expanded(child: TextField(controller: _latCtrl, decoration: const InputDecoration(labelText: 'Lat', border: OutlineInputBorder()))), const SizedBox(width: 8), Expanded(child: TextField(controller: _lngCtrl, decoration: const InputDecoration(labelText: 'Lng', border: OutlineInputBorder())))]),
            const SizedBox(height: 8),
            Row(children: [Expanded(child: ElevatedButton(onPressed: _getGPS, child: const Text('Get GPS'))), const SizedBox(width: 8), Expanded(child: ElevatedButton(onPressed: _saveLocation, child: const Text('Save Location')))]),
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
          // Delete
          _card('🗑️ Delete Account', Column(children: [
            DropdownButtonFormField<String>(value: deleteReason.isEmpty ? null : deleteReason, decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'Leaving', child: Text('Leaving')), DropdownMenuItem(value: 'Not getting bookings', child: Text('Not getting bookings')), DropdownMenuItem(value: 'Privacy', child: Text('Privacy')), DropdownMenuItem(value: 'Other', child: Text('Other'))], onChanged: (v) => setState(() => deleteReason = v ?? '')),
            const SizedBox(height: 8),
            TextField(controller: _deleteDetailsCtrl, decoration: const InputDecoration(labelText: 'Details (optional)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _deletePassCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password to Confirm', border: OutlineInputBorder())),
            CheckboxListTile(title: const Text('I understand my account will be deleted', style: TextStyle(fontSize: 12)), value: confirmCheck, onChanged: (v) => setState(() => confirmCheck = v ?? false)),
            CheckboxListTile(title: const Text('I understand my data will be removed', style: TextStyle(fontSize: 12)), value: confirmData, onChanged: (v) => setState(() => confirmData = v ?? false)),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _deleteAccount, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete Account'))),
          ])),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _card(String title, Widget child) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1C1238), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.15))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), const SizedBox(height: 10), child]));
}
