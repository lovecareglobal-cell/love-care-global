import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ClientRegistrationPage extends StatefulWidget {
  const ClientRegistrationPage({super.key});
  @override
  State<ClientRegistrationPage> createState() => _ClientRegistrationPageState();
}

class _ClientRegistrationPageState extends State<ClientRegistrationPage> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  XFile? _photo;
  XFile? _idFront;
  XFile? _idBack;
  String _idCheck = '';
  bool _idVerified = false;
  String _idType = '';
  bool _loading = false;
  final _picker = ImagePicker();

  Future<void> _pickPhoto() async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (f != null) setState(() => _photo = f);
  }

  Future<void> _pickDoc(void Function(XFile f) setFile) async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (f != null) setState(() => setFile(f));
  }

  Future<String?> _upload(XFile file, String path) async {
    final ref = FirebaseStorage.instance.ref().child(path);
    final bytes = await file.readAsBytes();
    await ref.putData(bytes, SettableMetadata(contentType: file.mimeType ?? 'application/octet-stream'));
    return await ref.getDownloadURL();
  }


  // ---- ID AUTHENTICITY PRE-CHECK (OCR) - INTERNATIONAL, WEB-COMPATIBLE ----
  // Uses Google Cloud Vision API over HTTP - works on Web, Android and iOS.
  // ML Kit does NOT work on Web, so we do NOT use it here.
  // To turn on auto-check: paste a Google Cloud Vision API key below
  // (Google Cloud Console -> APIs -> Cloud Vision API -> Create API key).
  // If no key is set, registration is NOT blocked - it is marked for CEO manual check.
  static const String _visionApiKey = 'PASTE_YOUR_GOOGLE_VISION_API_KEY_HERE';

  Future<String?> _ocrWithVision(Uint8List bytes) async {
    if (_visionApiKey == 'PASTE_YOUR_GOOGLE_VISION_API_KEY_HERE' || _visionApiKey.isEmpty) return null;
    try {
      final res = await http.post(
        Uri.parse('https://vision.googleapis.com/v1/images:annotate?key=$_visionApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requests': [
            {
              'image': {'content': base64Encode(bytes)},
              'features': [
                {'type': 'TEXT_DETECTION'}
              ]
            }
          ]
        }),
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final responses = data['responses'] as List?;
      if (responses == null || responses.isEmpty) return '';
      final annotations = responses[0]['textAnnotations'] as List?;
      if (annotations == null || annotations.isEmpty) return '';
      return (annotations[0]['description'] as String?) ?? '';
    } catch (_) {
      return null;
    }
  }

  Future<bool> _verifyIdDocument() async {
    if (_idFront == null) {
      setState(() => _idCheck = '❌ No ID Front uploaded');
      return false;
    }
    setState(() => _idCheck = '🔍 Checking ID, please wait...');
    // No Vision key configured -> do NOT block, mark for CEO manual check.
    if (_visionApiKey == 'PASTE_YOUR_GOOGLE_VISION_API_KEY_HERE' || _visionApiKey.isEmpty) {
      setState(() {
        _idType = 'ID (manual check)';
        _idVerified = false;
        _idCheck = '⚠️ Auto-check not configured yet. Your ID was sent to CEO for manual check.';
      });
      return true;
    }
    try {
      final bytes = await _idFront!.readAsBytes();
      final ocrText = await _ocrWithVision(bytes);
      if (ocrText == null) {
        setState(() {
          _idType = 'ID (manual check)';
          _idVerified = false;
          _idCheck = '⚠️ Could not reach ID check service. Your ID was sent to CEO for manual check.';
        });
        return true;
      }
      final text = ocrText.toUpperCase();
      final compact = text.replaceAll(RegExp(r'\s+'), ' ');

      String country = 'UNKNOWN';
      if (text.contains('GHANA')) country = 'GHANA';
      else if (text.contains('NIGERIA')) country = 'NIGERIA';
      else if (text.contains('KENYA')) country = 'KENYA';
      else if (text.contains('SOUTH AFRICA')) country = 'SOUTH AFRICA';
      else if (text.contains('INDIA') || text.contains('AADHAAR')) country = 'INDIA';
      else if (text.contains('UNITED KINGDOM') || text.contains('GREAT BRITAIN')) country = 'UNITED KINGDOM';
      else if (text.contains('UNITED STATES') || text.contains('USA') || text.contains('AMERICA')) country = 'USA';
      else if (text.contains('CANADA')) country = 'CANADA';
      else if (text.contains('AUSTRALIA')) country = 'AUSTRALIA';
      else if (text.contains('FRANCE')) country = 'FRANCE';
      else if (text.contains('GERMANY') || text.contains('BUNDESREPUBLIK')) country = 'GERMANY';
      else if (text.contains('TOGO')) country = 'TOGO';
      else if (text.contains("COTE D'IVOIRE") || text.contains('IVORY COAST')) country = "COTE D'IVOIRE";
      else if (text.contains('BENIN')) country = 'BENIN';
      else if (text.contains('BURKINA')) country = 'BURKINA FASO';
      else if (text.contains('SENEGAL')) country = 'SENEGAL';
      else if (text.contains('SIERRA LEONE')) country = 'SIERRA LEONE';
      else if (text.contains('LIBERIA')) country = 'LIBERIA';
      else if (text.contains('CAMEROON')) country = 'CAMEROON';
      else if (text.contains('ETHIOPIA')) country = 'ETHIOPIA';
      else if (text.contains('UGANDA')) country = 'UGANDA';
      else if (text.contains('TANZANIA')) country = 'TANZANIA';
      else if (text.contains('EGYPT')) country = 'EGYPT';
      else if (text.contains('PAKISTAN')) country = 'PAKISTAN';
      else if (text.contains('PHILIPPINES')) country = 'PHILIPPINES';
      else if (text.contains('BRAZIL') || text.contains('BRASIL')) country = 'BRAZIL';

      String type = 'UNKNOWN';
      final hasMrz = RegExp(r'P<[A-Z]{3}').hasMatch(compact.replaceAll(' ', ''));
      if (text.contains('PASSPORT') || hasMrz) {
        type = 'PASSPORT';
      } else if (text.contains('DRIV') && (text.contains('LICEN') || text.contains('PERMIS') || text.contains('DVLA'))) {
        type = 'DRIVER LICENCE';
      } else if (text.contains('GHANA CARD') || text.contains('NATIONAL IDENTIFICATION') || RegExp(r'GHA-\d{9}-\d').hasMatch(text)) {
        type = 'GHANA CARD';
      } else if (text.contains('AADHAAR') || text.contains('UNIQUE IDENTIFICATION')) {
        type = 'AADHAAR CARD';
      } else if (text.contains('NATIONAL IDENTITY') || text.contains('NATIONAL ID') || text.contains('IDENTITY CARD') || text.contains('IDENTITY DOCUMENT') || text.contains('CARTE NATIONALE')) {
        type = 'NATIONAL ID';
      } else if (text.contains('VOTER') || text.contains('ELECTORAL')) {
        type = 'VOTER ID';
      } else if (text.contains('NHIS') || text.contains('HEALTH INSURANCE')) {
        type = 'HEALTH INSURANCE CARD';
      } else if (text.contains('RESIDENCE') || text.contains('PERMIT')) {
        type = 'RESIDENCE PERMIT';
      }

      if (type == 'UNKNOWN') {
        setState(() {
          _idCheck = '❌ Could not read this as an ID. Take a clearer photo of your Passport, Driver Licence, or National ID (any country).';
          _idVerified = false;
        });
        return false;
      }

      String formatError = '';
      if (type == 'GHANA CARD' && country == 'GHANA' && !RegExp(r'GHA-\d{9}-\d').hasMatch(text)) {
        formatError = 'Ghana Card number should look like GHA-XXXXXXXXX-X.';
      } else if (type == 'AADHAAR CARD' && !RegExp(r'\d{4}\s?\d{4}\s?\d{4}').hasMatch(text)) {
        formatError = 'Aadhaar number should be 12 digits.';
      } else if (type == 'NATIONAL ID' && country == 'NIGERIA' && !RegExp(r'\d{11}').hasMatch(text.replaceAll(' ', ''))) {
        formatError = 'Nigeria NIN should be 11 digits.';
      } else if (type == 'NATIONAL ID' && country == 'SOUTH AFRICA' && !RegExp(r'\d{13}').hasMatch(text.replaceAll(' ', ''))) {
        formatError = 'South Africa ID number should be 13 digits.';
      }
      if (formatError.isNotEmpty) {
        setState(() {
          _idCheck = '⚠️ $type ($country) found, but $formatError CEO must check manually.';
          _idType = '$type ($country)';
          _idVerified = false;
        });
        return false;
      }

      if (type == 'PASSPORT') {
        final mrzLines = text.split('\n').where((l) => l.replaceAll(' ', '').length >= 30 && RegExp(r'[A-Z0-9<]{20,}').hasMatch(l.replaceAll(' ', ''))).toList();
        if (mrzLines.length >= 2) {
          final line2 = mrzLines.last.replaceAll(' ', '');
          if (line2.length >= 28) {
            final yy = int.tryParse(line2.substring(21, 23)) ?? 0;
            final mm = int.tryParse(line2.substring(23, 25)) ?? 0;
            final dd = int.tryParse(line2.substring(25, 27)) ?? 0;
            if (yy > 0 && mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31) {
              final expiry = DateTime(2000 + yy, mm, dd);
              if (expiry.isBefore(DateTime.now())) {
                setState(() {
                  _idCheck = '❌ This PASSPORT ($country) is EXPIRED ($dd/$mm/${2000 + yy}). Upload a valid, unexpired passport.';
                  _idType = 'PASSPORT ($country)';
                  _idVerified = false;
                });
                return false;
              }
            }
          }
        }
      }

      if (type != 'PASSPORT') {
        final expMatch = RegExp(r'(EXP|EXPIRY|VALID UNTIL|VALID THRU|DATE OF EXPIRY)[^\d]{0,10}(\d{1,2}[-/\.]\d{1,2}[-/\.]\d{2,4})').firstMatch(text);
        if (expMatch != null) {
          final parts = expMatch.group(2)!.split(RegExp(r'[-/.]'));
          int year = int.tryParse(parts[2]) ?? 0;
          if (year < 100) year += 2000;
          final month = int.tryParse(parts[1]) ?? 1;
          final day = int.tryParse(parts[0]) ?? 1;
          if (year > 1900 && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
            final expiry = DateTime(year, month, day);
            if (expiry.isBefore(DateTime.now())) {
              setState(() {
                _idCheck = '❌ This $type ($country) is EXPIRED ($day/$month/$year). Upload a valid, unexpired ID.';
                _idType = '$type ($country)';
                _idVerified = false;
              });
              return false;
            }
          }
        }
      }

      final typedName = _name.text.trim().toUpperCase();
      bool nameMatches = false;
      if (typedName.isNotEmpty) {
        for (final word in typedName.split(' ')) {
          if (word.length >= 3 && text.contains(word)) { nameMatches = true; break; }
        }
      }
      if (!nameMatches) {
        setState(() {
          _idCheck = '⚠️ Name on ID does not match "$typedName". CEO must check manually - could be a different person\'s ID.';
          _idType = '$type ($country)';
          _idVerified = false;
        });
        return false;
      }

      setState(() {
        _idType = country == 'UNKNOWN' ? type : '$type ($country)';
        _idVerified = true;
        _idCheck = '✅ $_idType detected. Format OK. Name matches. Not expired (where expiry was readable). Sent to CEO for final approval.';
      });
      return true;
    } catch (e) {
      setState(() => _idCheck = '⚠️ Could not check ID automatically ($e). CEO will check manually.');
      return false;
    }
  }

  Future<void> _register() async {
    if (_name.text.isEmpty || _email.text.isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill all fields')));
      return;
    }
    // ID must be verified BEFORE registration is sent to CEO
    final idOk = await _verifyIdDocument();
    if (!idOk) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_idCheck)));
      return;
    }
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text.trim(),
      );
      final uid = cred.user!.uid;

      String? photoUrl;
      String? idFrontUrl;
      String? idBackUrl;
      if (_photo != null) photoUrl = await _upload(_photo!, 'clients/$uid/photo.jpg');
      if (_idFront != null) idFrontUrl = await _upload(_idFront!, 'clients/$uid/id_front.jpg');
      if (_idBack != null) idBackUrl = await _upload(_idBack!, 'clients/$uid/id_back.jpg');

      // Firestore (for the client's own app)
      await FirebaseFirestore.instance.collection('pending_clients').doc(uid).set({
        'uid': uid,
        'name': _name.text.trim(),
        'fullName': _name.text.trim(),
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'role': 'client',
        'type': 'client',
        'status': 'pending',
        'isApproved': false,
        'photoUrl': photoUrl ?? '',
        'photoURL': photoUrl ?? '',
        'photo': photoUrl ?? '',
        'idFrontUrl': idFrontUrl ?? '',
        'idFrontURL': idFrontUrl ?? '',
        'idBackUrl': idBackUrl ?? '',
        'idBackURL': idBackUrl ?? '',
        'idType': _idType,
        'idVerified': _idVerified,
        'idCheck': _idCheck,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // RTDB dual-write - THIS is what CEO Registration Center reads.
      // CEO does NOT read Firestore. Without this, CEO sees nothing.
      final rtdbData = <String, Object?>{
        'uid': uid,
        'id': uid,
        'name': _name.text.trim(),
        'fullName': _name.text.trim(),
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'role': 'client',
        'type': 'client',
        'status': 'pending',
        'isApproved': false,
        'approved': false,
        'hasAll4': false,
        'photo': photoUrl ?? '',
        'photoUrl': photoUrl ?? '',
        'photoURL': photoUrl ?? '',
        'idURL': idFrontUrl ?? '',
        'idFrontURL': idFrontUrl ?? '',
        'idBackURL': idBackUrl ?? '',
        'idType': _idType,
        'idVerified': _idVerified,
        'idCheck': _idCheck,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      await FirebaseDatabase.instance.ref('ceoRegistrationCenter/clients/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('clients/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('client_registrations/$uid').set(rtdbData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registered! Wait for CEO approval')));
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Client Registration'), backgroundColor: Colors.purple, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name')),
            TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username')),
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo),
              title: Text(_photo == null ? 'Upload Photo' : 'Photo Selected: ${_photo!.name}'),
              trailing: ElevatedButton(onPressed: _pickPhoto, child: const Text('Pick Photo')),
            ),
            if (_idCheck.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_idCheck, style: TextStyle(color: _idVerified ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
              ),
            ListTile(
              leading: const Icon(Icons.credit_card),
              title: Text(_idFront == null ? 'Upload ID - FRONT (Passport / Licence / National ID, any country)' : 'ID Front Selected: ${_idFront!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _idFront = f), child: const Text('Pick Front')),
            ),
            ListTile(
              leading: const Icon(Icons.credit_card),
              title: Text(_idBack == null ? 'Upload ID - BACK' : 'ID Back Selected: ${_idBack!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _idBack = f), child: const Text('Pick Back')),
            ),
            const SizedBox(height: 20),
            _loading
                ? const CircularProgressIndicator()
                : Column(children: [
                    ElevatedButton(onPressed: _verifyIdDocument, child: const Text('🔍 VERIFY MY ID FIRST')),
                    const SizedBox(height: 10),
                    ElevatedButton(onPressed: _register, child: const Text('REGISTER AS CLIENT')),
                  ]),
          ],
        ),
      ),
    );
  }
}
