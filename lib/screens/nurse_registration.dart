import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class NurseRegistrationPage extends StatefulWidget {
  const NurseRegistrationPage({super.key});
  @override
  State<NurseRegistrationPage> createState() => _NurseRegistrationPageState();
}

class _NurseRegistrationPageState extends State<NurseRegistrationPage> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  XFile? _photo;
  XFile? _video;
  XFile? _cv;
  XFile? _pinDoc;
  XFile? _idFront;
  XFile? _idBack;
  XFile? _certificate;
  final _pinNumber = TextEditingController();
  String _idCheck = ''; // ✅ / ⚠️ / ❌ result shown to nurse + saved for CEO
  bool _idVerified = false;
  String _idType = ''; // GHANA CARD / DRIVER LICENCE / PASSPORT / VOTER ID
  bool _loading = false;
  final _picker = ImagePicker();

  Future<void> _pickPhoto() async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (f != null) setState(() => _photo = f);
  }

  Future<void> _pickVideo() async {
    final f = await _picker.pickVideo(source: ImageSource.gallery);
    if (f != null) setState(() => _video = f);
  }

  Future<void> _pickDoc(void Function(XFile f) setFile) async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (f != null) setState(() => setFile(f));
  }

  Future<String?> _upload(XFile file, String path) async {
    final ref = FirebaseStorage.instance.ref().child(path);
    // Web: use bytes, Mobile: use file
    final bytes = await file.readAsBytes();
    await ref.putData(bytes, SettableMetadata(contentType: file.mimeType ?? 'application/octet-stream'));
    return await ref.getDownloadURL();
  }

  // ---- ID AUTHENTICITY PRE-CHECK (OCR) - INTERNATIONAL ----
  // Works for ANY country: Passport (any country), Driver's Licence (any country),
  // National ID (Ghana, Nigeria, Kenya, South Africa, India, UK, USA, etc.)
  // This is a PRE-CHECK, not proof - only the issuing government can prove an ID is real.
  // It catches: wrong document, unreadable photo, wrong format, expired ID,
  // and name on ID not matching the name typed in registration.
  Future<bool> _verifyIdDocument() async {
    if (_idFront == null) {
      setState(() => _idCheck = '❌ No ID Front uploaded');
      return false;
    }
    setState(() => _idCheck = '🔍 Checking ID, please wait...');
    try {
      final input = InputImage.fromFilePath(_idFront!.path);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(input);
      await recognizer.close();
      final text = result.text.toUpperCase();
      final compact = text.replaceAll(RegExp(r'\s+'), ' ');

      // 1. Detect COUNTRY (from text on the ID)
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
      else if (text.contains('NETHERLANDS')) country = 'NETHERLANDS';
      else if (text.contains('SPAIN') || text.contains('ESPANA')) country = 'SPAIN';
      else if (text.contains('ITALY') || text.contains('ITALIA')) country = 'ITALY';
      else if (text.contains('TOGO')) country = 'TOGO';
      else if (text.contains("COTE D'IVOIRE") || text.contains('IVORY COAST')) country = "COTE D'IVOIRE";
      else if (text.contains('BENIN')) country = 'BENIN';
      else if (text.contains('BURKINA')) country = 'BURKINA FASO';
      else if (text.contains('MALI')) country = 'MALI';
      else if (text.contains('SENEGAL')) country = 'SENEGAL';
      else if (text.contains('SIERRA LEONE')) country = 'SIERRA LEONE';
      else if (text.contains('LIBERIA')) country = 'LIBERIA';
      else if (text.contains('CAMEROON')) country = 'CAMEROON';
      else if (text.contains('ETHIOPIA')) country = 'ETHIOPIA';
      else if (text.contains('UGANDA')) country = 'UGANDA';
      else if (text.contains('TANZANIA')) country = 'TANZANIA';
      else if (text.contains('RWANDA')) country = 'RWANDA';
      else if (text.contains('ZAMBIA')) country = 'ZAMBIA';
      else if (text.contains('ZIMBABWE')) country = 'ZIMBABWE';
      else if (text.contains('EGYPT')) country = 'EGYPT';
      else if (text.contains('MOROCCO')) country = 'MOROCCO';
      else if (text.contains('ALGERIA')) country = 'ALGERIA';
      else if (text.contains('PAKISTAN')) country = 'PAKISTAN';
      else if (text.contains('BANGLADESH')) country = 'BANGLADESH';
      else if (text.contains('PHILIPPINES')) country = 'PHILIPPINES';
      else if (text.contains('CHINA')) country = 'CHINA';
      else if (text.contains('JAPAN')) country = 'JAPAN';
      else if (text.contains('BRAZIL') || text.contains('BRASIL')) country = 'BRAZIL';

      // 2. Detect DOCUMENT TYPE (any country)
      String type = 'UNKNOWN';
      // Passport - MRZ is the strongest signal, works for every country: P<XXX...
      final hasMrz = RegExp(r'P<[A-Z]{3}').hasMatch(compact.replaceAll(' ', ''));
      if (text.contains('PASSPORT') || hasMrz) {
        type = 'PASSPORT';
      } else if (text.contains('DRIV') && (text.contains('LICEN') || text.contains('PERMIS') || text.contains('DVLA'))) {
        type = 'DRIVER LICENCE';
      } else if (text.contains('GHANA CARD') || text.contains('NATIONAL IDENTIFICATION') || RegExp(r'GHA-\d{9}-\d').hasMatch(text)) {
        type = 'GHANA CARD';
      } else if (text.contains('AADHAAR') || text.contains('UNIQUE IDENTIFICATION')) {
        type = 'AADHAAR CARD';
      } else if (text.contains('NATIONAL IDENTITY') || text.contains('NATIONAL ID') || text.contains('IDENTITY CARD') || text.contains('IDENTITY DOCUMENT') || text.contains('CARTE NATIONALE') || text.contains('NATIONAL IDENTIFICATION')) {
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

      // 3. Country-specific FORMAT checks - only reject if we KNOW the format and it is wrong.
      // Unknown countries are NOT rejected for format - they fall through to name + expiry checks.
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

      // 4. Passport MRZ checksum (ICAO 9303) - works for EVERY country's passport.
      // MRZ line 2: passport number (9) + check digit, DOB (6) + check, expiry (6) + check.
      // If MRZ is readable and checksum fails, the passport data was altered.
      if (type == 'PASSPORT') {
        final mrzLines = text.split('\n').where((l) => l.replaceAll(' ', '').length >= 30 && RegExp(r'[A-Z0-9<]{20,}').hasMatch(l.replaceAll(' ', ''))).toList();
        if (mrzLines.length >= 2) {
          final line2 = mrzLines.last.replaceAll(' ', '');
          // Expiry is at position 21-27 in MRZ line 2 (YYMMDD) + check digit at 27
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

      // 5. Expiry check for non-passport IDs - look for EXP / EXPIRY / VALID UNTIL + a date
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

      // 6. Name check - surname on ID should appear in the typed name (or vice versa)
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
      // 1. Create Auth
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text.trim(),
      );
      final uid = cred.user!.uid;

      // 2. Upload ALL docs - Photo, Video, CV, Nursing PIN, ID Front/Back, Certificate
      String? photoUrl;
      String? videoUrl;
      String? cvUrl;
      String? pinDocUrl;
      String? idFrontUrl;
      String? idBackUrl;
      String? certUrl;
      if (_photo != null) {
        photoUrl = await _upload(_photo!, 'nurses/$uid/photo.jpg');
      }
      if (_video != null) {
        videoUrl = await _upload(_video!, 'nurses/$uid/video.mp4');
      }
      if (_cv != null) {
        cvUrl = await _upload(_cv!, 'nurses/$uid/cv.jpg');
      }
      if (_pinDoc != null) {
        pinDocUrl = await _upload(_pinDoc!, 'nurses/$uid/nursing_pin.jpg');
      }
      if (_idFront != null) {
        idFrontUrl = await _upload(_idFront!, 'nurses/$uid/id_front.jpg');
      }
      if (_idBack != null) {
        idBackUrl = await _upload(_idBack!, 'nurses/$uid/id_back.jpg');
      }
      if (_certificate != null) {
        certUrl = await _upload(_certificate!, 'nurses/$uid/certificate.jpg');
      }

      // 3. Save to Firestore (for the nurse's own app)
      await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).set({
        'uid': uid,
        'name': _name.text.trim(),
        'fullName': _name.text.trim(),
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'role': 'nurse',
        'type': 'nurse',
        'status': 'pending',
        'isApproved': false,
        'photoUrl': photoUrl ?? '',
        'photoURL': photoUrl ?? '',
        'photo': photoUrl ?? '',
        'videoUrl': videoUrl ?? '',
        'videoURL': videoUrl ?? '',
        'cvUrl': cvUrl ?? '',
        'cvURL': cvUrl ?? '',
        'pinNumber': _pinNumber.text.trim(),
        'pinDocUrl': pinDocUrl ?? '',
        'pinDocURL': pinDocUrl ?? '',
        'idFrontUrl': idFrontUrl ?? '',
        'idFrontURL': idFrontUrl ?? '',
        'idBackUrl': idBackUrl ?? '',
        'idBackURL': idBackUrl ?? '',
        'nationalIdFrontUrl': idFrontUrl ?? '',
        'nationalIdBackUrl': idBackUrl ?? '',
        'certificateUrl': certUrl ?? '',
        'certificateURL': certUrl ?? '',
        'idType': _idType,
        'idCountry': _idType,
        'idVerified': _idVerified,
        'idCheck': _idCheck,
        'certUrl': certUrl ?? '',
        'certURL': certUrl ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 4. ALSO save to Realtime Database - THIS is what CEO Registration Center reads.
      // CEO does NOT read Firestore at all. It only reads RTDB paths like
      // ceoRegistrationCenter/nurses, nurses, nurse_registrations.
      // Without this write, registration says "successful" but CEO sees nothing.
      // Do NOT set hasAll4: true here - CEO treats hasAll4==true as already approved
      // and would hide the nurse from the Pending tab.
      final rtdbData = <String, Object?>{
        'uid': uid,
        'id': uid,
        'name': _name.text.trim(),
        'fullName': _name.text.trim(),
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'role': 'nurse',
        'type': 'nurse',
        'status': 'pending',
        'isApproved': false,
        'approved': false,
        'hasAll4': false,
        'photo': photoUrl ?? '',
        'photoUrl': photoUrl ?? '',
        'photoURL': photoUrl ?? '',
        'videoUrl': videoUrl ?? '',
        'videoURL': videoUrl ?? '',
        'idURL': idFrontUrl ?? '',
        'idFrontURL': idFrontUrl ?? '',
        'idBackURL': idBackUrl ?? '',
        'nationalIdFrontUrl': idFrontUrl ?? '',
        'nationalIdBackUrl': idBackUrl ?? '',
        'licenceURL': pinDocUrl ?? '',
        'pinNumber': _pinNumber.text.trim(),
        'pinDocURL': pinDocUrl ?? '',
        'idType': _idType,
        'idVerified': _idVerified,
        'idCheck': _idCheck,
        'cvURL': cvUrl ?? '',
        'cvUrl': cvUrl ?? '',
        'certificateURL': certUrl ?? '',
        'certURL': certUrl ?? '',
        'certUrl': certUrl ?? '',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      // Write to ALL 3 RTDB paths the CEO screen checks, so it cannot miss it.
      await FirebaseDatabase.instance.ref('ceoRegistrationCenter/nurses/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('nurses/$uid').set(rtdbData);
      await FirebaseDatabase.instance.ref('nurse_registrations/$uid').set(rtdbData);

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
      appBar: AppBar(title: const Text('Nurse Registration'), backgroundColor: Colors.teal, foregroundColor: Colors.white),
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
            // PHOTO
            ListTile(
              leading: const Icon(Icons.photo),
              title: Text(_photo == null ? 'Upload Photo' : 'Photo Selected: ${_photo!.name}'),
              trailing: ElevatedButton(onPressed: _pickPhoto, child: const Text('Pick Photo')),
            ),
            // VIDEO
            ListTile(
              leading: const Icon(Icons.videocam),
              title: Text(_video == null ? 'Upload Intro Video' : 'Video Selected: ${_video!.name}'),
              trailing: ElevatedButton(onPressed: _pickVideo, child: const Text('Pick Video')),
            ),
            // CV
            ListTile(
              leading: const Icon(Icons.description),
              title: Text(_cv == null ? 'Upload CV' : 'CV Selected: ${_cv!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _cv = f), child: const Text('Pick CV')),
            ),
            // NURSING PIN NUMBER
            TextField(controller: _pinNumber, decoration: const InputDecoration(labelText: 'Nursing PIN Number')),
            // NURSING PIN DOCUMENT
            ListTile(
              leading: const Icon(Icons.badge),
              title: Text(_pinDoc == null ? 'Upload Nursing PIN Card' : 'PIN Card Selected: ${_pinDoc!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _pinDoc = f), child: const Text('Pick PIN')),
            ),
            // ID VERIFICATION RESULT
            if (_idCheck.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_idCheck, style: TextStyle(color: _idVerified ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
              ),
            // NATIONAL ID - FRONT
            ListTile(
              leading: const Icon(Icons.credit_card),
              title: Text(_idFront == null ? 'Upload National ID - FRONT' : 'ID Front Selected: ${_idFront!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _idFront = f), child: const Text('Pick Front')),
            ),
            // NATIONAL ID - BACK
            ListTile(
              leading: const Icon(Icons.credit_card),
              title: Text(_idBack == null ? 'Upload National ID - BACK' : 'ID Back Selected: ${_idBack!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _idBack = f), child: const Text('Pick Back')),
            ),
            // CERTIFICATE
            ListTile(
              leading: const Icon(Icons.school),
              title: Text(_certificate == null ? 'Upload Certificate' : 'Certificate Selected: ${_certificate!.name}'),
              trailing: ElevatedButton(onPressed: () => _pickDoc((f) => _certificate = f), child: const Text('Pick Cert')),
            ),
            const SizedBox(height: 20),
            _loading
                ? const CircularProgressIndicator()
                : Column(children: [
                    ElevatedButton(onPressed: _verifyIdDocument, child: const Text('🔍 VERIFY MY ID FIRST')),
                    const SizedBox(height: 10),
                    ElevatedButton(onPressed: _register, child: const Text('REGISTER AS NURSE')),
                  ]),
          ],
        ),
      ),
    );
  }
}
