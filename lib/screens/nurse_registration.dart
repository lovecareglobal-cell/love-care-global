import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/id_catalog.dart';

class NurseRegistrationPage extends StatefulWidget {
  const NurseRegistrationPage({super.key});

  @override
  State<NurseRegistrationPage> createState() =>
      _NurseRegistrationPageState();
}

class _NurseRegistrationPageState extends State<NurseRegistrationPage> {
  final _formKey = GlobalKey<FormState>();

  // --- Colours ---
  static const primary = Color(0xFF880E4F);
  static const primaryLight = Color(0xFFFDE7F0);
  static const greenStrong = Color(0xFF2E9E4A);

  // --- Controllers ---
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pinNumberController = TextEditingController();
  final _idNumberController = TextEditingController();

  // --- Dropdowns ---
  String? _selectedCountry;
  IdTypeOption? _selectedIdType;
  String? _selectedSpecialty;
  String? _selectedExperience;
  bool _obscurePassword = true;

  // --- Files: name for UI + bytes for upload ---
  String? _photoName; Uint8List? _photoBytes;
  String? _videoName; Uint8List? _videoBytes;
  String? _cvName; Uint8List? _cvBytes;
  String? _pinCardName; Uint8List? _pinCardBytes;
  String? _idFrontName; Uint8List? _idFrontBytes;
  String? _idBackName; Uint8List? _idBackBytes;
  String? _certificateName; Uint8List? _certificateBytes;

  final ImagePicker _picker = ImagePicker();
  String? _uploadStatus;

  // --- ID Check ---
  bool _idCheckAttempted = false;
  bool _idCheckPassed = false;
  String? _idCheckMessage;
  List<String> _idCheckDetails = [];
  bool _isCheckingId = false;
  bool _isSubmitting = false;

  static const bool _visionApiConfigured = false;

  List<IdTypeOption> get _idTypesForCountry =>
      IdCatalog.forCountry(_selectedCountry);

  // --- Password strength ---
  int get _passwordStrength {
    final p = _passwordController.text;
    int score = 0;
    if (p.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(p)) score++;
    return score;
  }

  String get _passwordLabel {
    switch (_passwordStrength) {
      case 0:
      case 1:
        return 'Weak';
      case 2:
      case 3:
        return 'Medium';
      case 4:
        return 'Strong';
      default:
        return 'Very strong';
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _pinNumberController.dispose();
    _idNumberController.dispose();
    super.dispose();
  }

  // --- Country / ID Type logic ---
  void _onCountryChanged(String? country) {
    setState(() {
      _selectedCountry = country;
      _selectedIdType = null;
      _idNumberController.clear();
      _idFrontName = null; _idFrontBytes = null;
      _idBackName = null; _idBackBytes = null;
      _idCheckAttempted = false;
      _idCheckPassed = false;
      _idCheckMessage = null;
      _idCheckDetails = [];
    });
  }

  void _onIdTypeChanged(IdTypeOption? type) {
    setState(() {
      _selectedIdType = type;
      _idNumberController.clear();
      _idFrontName = null; _idFrontBytes = null;
      _idBackName = null; _idBackBytes = null;
      _idCheckAttempted = false;
      _idCheckPassed = false;
      _idCheckMessage = null;
      _idCheckDetails = [];
    });
  }

  Future<void> _pickFile(String kind) async {
    try {
      Uint8List? bytes;
      String? name;

      if (kind == 'photo' || kind == 'pin') {
        final XFile? picked = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );
        if (picked == null) return; // user cancelled
        bytes = await picked.readAsBytes();
        name = picked.name;
      } else if (kind == 'video') {
        final XFile? picked = await _picker.pickVideo(source: ImageSource.gallery);
        if (picked == null) return;
        bytes = await picked.readAsBytes();
        name = picked.name;
      } else {
        // cv / cert: PDF or image. withData:true is REQUIRED on Web,
        // otherwise file.bytes is null and upload silently fails.
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        final file = result.files.first;
        bytes = file.bytes;
        name = file.name;
      }

      if (bytes == null || bytes.isEmpty) {
        _showError('Could not read that file. Please try again.');
        return;
      }
      // Safety: keep uploads sane on mobile data (video can be huge).
      if (kind == 'video' && bytes.length > 100 * 1024 * 1024) {
        _showError('Video is too large. Please pick a video under 100 MB.');
        return;
      }

      setState(() {
        switch (kind) {
          case 'photo': _photoName = name; _photoBytes = bytes; break;
          case 'video': _videoName = name; _videoBytes = bytes; break;
          case 'cv': _cvName = name; _cvBytes = bytes; break;
          case 'pin': _pinCardName = name; _pinCardBytes = bytes; break;
          case 'cert': _certificateName = name; _certificateBytes = bytes; break;
        }
        _uploadStatus = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$kind selected: $name')),
        );
      }
    } catch (e) {
      _showError('Picker failed: $e');
    }
  }

  Future<void> _scanId(String side) async {
    if (_selectedCountry == null || _selectedIdType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick ID Country + ID Type first')),
      );
      return;
    }
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        if (side == 'front') {
          _idFrontName = picked.name; _idFrontBytes = bytes;
        } else {
          _idBackName = picked.name; _idBackBytes = bytes;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scanned $side of ${_selectedIdType!.label} ($_selectedCountry)')),
        );
      }
    } catch (e) {
      _showError('ID scan failed: $e');
    }
  }

  Future<void> _checkIdAgain() async {
    if (_selectedCountry == null || _selectedIdType == null) return;
    if (_idNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter ID Number first')),
      );
      return;
    }
    if (_idFrontName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan FRONT of ID first')),
      );
      return;
    }

    setState(() {
      _idCheckAttempted = true;
      _isCheckingId = true;
      _idCheckMessage = 'Checking ID... reading photo...';
      _idCheckDetails = [];
    });

    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isCheckingId = false);

    if (!_visionApiConfigured) {
      setState(() {
        _idCheckPassed = false;
        _idCheckMessage =
            'Auto ID check is not configured yet. Ask admin to add the Google Vision API key.';
        _idCheckDetails = ['❌ Vision API key missing'];
      });
      return;
    }

    final pattern = _selectedIdType!.pattern;
    final value = _idNumberController.text.trim();
    final ok = pattern == null || pattern.hasMatch(value);
    setState(() {
      _idCheckPassed = ok;
      _idCheckMessage = ok
          ? 'ID number format looks correct for ${_selectedIdType!.label}.'
          : _selectedIdType!.patternError ?? 'ID number format does not match.';
      _idCheckDetails = ok
          ? ['✅ Format matches ${_selectedIdType!.label} (${_selectedIdType!.example})']
          : ['❌ Format check failed', 'Expected: ${_selectedIdType!.example}'];
    });
  }

  String _contentTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4') || lower.endsWith('.mov')) return 'video/mp4';
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  String _safeFileName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<String> _uploadFile({
    required String folder,
    required String fileName,
    required Uint8List bytes,
    required String uid,
  }) async {
    final safe = _safeFileName(fileName);
    final ref = FirebaseStorage.instance.ref('nurses/$uid/$folder/$safe');
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: _contentTypeFor(safe)),
    );
    return task.ref.getDownloadURL();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_photoBytes == null) return _showError('Please pick a Photo');
    if (_cvBytes == null) return _showError('Please pick your CV');
    if (_pinCardBytes == null) return _showError('Please pick your PIN Card');
    if (_idFrontBytes == null || _idBackBytes == null) {
      return _showError('Please scan FRONT + BACK of your ID');
    }
    if (_certificateBytes == null) return _showError('Please pick your Certificate');

    setState(() {
      _isSubmitting = true;
      _uploadStatus = 'Creating account...';
    });

    try {
      // 1. Auth: reuse existing session if already signed in (e.g. retry
      // after a failed upload), otherwise create the account. Storage
      // rules use request.auth.uid, so this MUST happen before upload.
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email?.toLowerCase() != _emailController.text.trim().toLowerCase()) {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        user = cred.user;
      }
      final uid = user!.uid;

      // 2. Upload. Video is optional in the original form - only upload if picked.
      setState(() => _uploadStatus = 'Uploading documents... please keep the app open');
      final photoUrl = await _uploadFile(folder: 'photo', fileName: _photoName!, bytes: _photoBytes!, uid: uid);
      final cvUrl = await _uploadFile(folder: 'cv', fileName: _cvName!, bytes: _cvBytes!, uid: uid);
      final pinUrl = await _uploadFile(folder: 'pin', fileName: _pinCardName!, bytes: _pinCardBytes!, uid: uid);
      final idFrontUrl = await _uploadFile(folder: 'id_front', fileName: _idFrontName!, bytes: _idFrontBytes!, uid: uid);
      final idBackUrl = await _uploadFile(folder: 'id_back', fileName: _idBackName!, bytes: _idBackBytes!, uid: uid);
      final certUrl = await _uploadFile(folder: 'certificate', fileName: _certificateName!, bytes: _certificateBytes!, uid: uid);
      String videoUrl = '';
      if (_videoBytes != null && _videoName != null) {
        videoUrl = await _uploadFile(folder: 'video', fileName: _videoName!, bytes: _videoBytes!, uid: uid);
      }

      // 3. Save profile. Use Firestore (already in pubspec) - do NOT also
      // write to Realtime Database unless your CEO screen reads from there.
      setState(() => _uploadStatus = 'Saving registration...');
      await FirebaseFirestore.instance.collection('nurses').doc(uid).set({
        'fullName': _fullNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'pinNumber': _pinNumberController.text.trim(),
        'country': _selectedCountry,
        'idType': _selectedIdType?.label,
        'idNumber': _idNumberController.text.trim(),
        'specialty': _selectedSpecialty,
        'experience': _selectedExperience,
        'photoUrl': photoUrl,
        'videoUrl': videoUrl,
        'cvUrl': cvUrl,
        'pinCardUrl': pinUrl,
        'idFrontUrl': idFrontUrl,
        'idBackUrl': idBackUrl,
        'certificateUrl': certUrl,
        'idCheckPassed': _idCheckPassed,
        'status': 'pending_review',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _uploadStatus = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration submitted for review')),
      );
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Sign-up failed (${e.code})');
    } on FirebaseException catch (e) {
      // Storage errors land here: permission-denied = Storage Rules,
      // unauthenticated = user was not created/signed in first.
      _showError('Upload failed (${e.code}): ${e.message}');
      if (kIsWeb) debugPrint('Firebase upload error: $e');
    } catch (e) {
      _showError('Upload failed: $e');
    } finally {
      if (mounted) setState(() { _isSubmitting = false; _uploadStatus = null; });
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        title: const Text('Nurse Registration'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Personal Details'),
              _textField(
                controller: _fullNameController,
                label: 'Full Name',
                hint: 'e.g. Ama Mensah',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter full name' : null,
              ),
              _textField(
                controller: _emailController,
                label: 'Email',
                hint: 'e.g. ama@email.com',
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter email';
                  if (!v.contains('@')) return 'Enter valid email';
                  return null;
                },
              ),
              _textField(
                controller: _phoneController,
                label: 'Phone / WhatsApp',
                hint: 'e.g. +233 20 123 4567',
                keyboardType: TextInputType.phone,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter phone number' : null,
              ),

              _sectionTitle('Password'),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _passwordStrength / 5,
                      backgroundColor: Colors.grey.shade300,
                      color: _passwordStrength >= 4
                          ? greenStrong
                          : Colors.orange,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _passwordLabel,
                    style: TextStyle(
                      color: _passwordStrength >= 4
                          ? greenStrong
                          : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (_passwordStrength >= 4)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: greenStrong, size: 18),
                      SizedBox(width: 6),
                      Text('Strong password ✓',
                          style: TextStyle(color: greenStrong)),
                    ],
                  ),
                ),

              _sectionTitle('Documents'),
              _fileRow(
                icon: Icons.photo,
                label: 'Photo',
                fileName: _photoName,
                buttonText: 'Pick Photo',
                onPick: () => _pickFile('photo'),
              ),
              _fileRow(
                icon: Icons.videocam,
                label: 'Video',
                fileName: _videoName,
                buttonText: 'Pick Video',
                onPick: () => _pickFile('video'),
              ),
              _fileRow(
                icon: Icons.description,
                label: 'CV',
                fileName: _cvName,
                buttonText: 'Pick CV',
                onPick: () => _pickFile('cv'),
              ),

              _sectionTitle('Nursing PIN'),
              _textField(
                controller: _pinNumberController,
                label: 'Nursing PIN Number',
                hint: 'e.g. PIN123456',
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter PIN Number' : null,
              ),
              _fileRow(
                icon: Icons.badge,
                label: 'PIN Card',
                fileName: _pinCardName,
                buttonText: 'Pick PIN',
                onPick: () => _pickFile('pin'),
              ),

              _sectionTitle('ID Verification'),

              DropdownButtonFormField<String>(
                value: _selectedCountry,
                decoration: const InputDecoration(
                  labelText: 'ID Country - Country you are a citizen of',
                ),
                items: IdCatalog.countries
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: _onCountryChanged,
                validator: (v) => v == null ? 'Select ID Country' : null,
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<IdTypeOption>(
                value: _selectedIdType,
                decoration: InputDecoration(
                  labelText: 'ID Type - Select your ID',
                  hintText: _selectedCountry == null
                      ? 'Select ID Country first'
                      : 'Select your ID',
                ),
                items: _idTypesForCountry
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.label),
                        ))
                    .toList(),
                onChanged:
                    _selectedCountry == null ? null : _onIdTypeChanged,
                validator: (v) => v == null ? 'Select ID Type' : null,
              ),
              if (_selectedCountry != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Showing IDs for $_selectedCountry only • ${_idTypesForCountry.length} options',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _idNumberController,
                enabled: _selectedIdType != null,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'ID Number (as printed on your ID)',
                  hintText: _selectedIdType?.hint ??
                      'Select ID Country + ID Type first',
                  helperText: _selectedIdType != null
                      ? 'Example: ${_selectedIdType!.example}'
                      : null,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Enter ID Number';
                  }
                  final pattern = _selectedIdType?.pattern;
                  if (pattern != null && !pattern.hasMatch(v.trim())) {
                    return _selectedIdType?.patternError ??
                        'Invalid format. Example: ${_selectedIdType!.example}';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'ID is AUTO-SCANNED - put it inside the box, turn on flash if dark. It snaps by itself when clear + steady.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 16),

              _fileRow(
                icon: Icons.credit_card,
                label: 'Upload ID - FRONT',
                fileName: _idFrontName,
                subLabel: _selectedIdType == null
                    ? 'Pick ID Country + ID Type first'
                    : 'Front of ${_selectedIdType!.label}',
                buttonText: 'Scan Front',
                onPick: () => _scanId('front'),
                buttonEnabled: _selectedIdType != null,
              ),
              _fileRow(
                icon: Icons.credit_card,
                label: 'Upload ID - BACK',
                fileName: _idBackName,
                subLabel: _selectedIdType == null
                    ? 'Auto-scan (box + flash)'
                    : 'Back of ${_selectedIdType!.label} (required)',
                buttonText: 'Scan Back',
                onPick: () => _scanId('back'),
                buttonEnabled: _selectedIdType != null,
              ),
              _fileRow(
                icon: Icons.school,
                label: 'Upload Certificate',
                fileName: _certificateName,
                buttonText: 'Pick Cert',
                onPick: () => _pickFile('cert'),
              ),

              const SizedBox(height: 8),

              if (_idCheckAttempted && _idCheckMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _idCheckPassed
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _idCheckPassed
                                ? Icons.check_circle
                                : Icons.close,
                            color: _idCheckPassed
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _idCheckMessage!,
                              style: TextStyle(
                                color: _idCheckPassed
                                    ? Colors.green.shade900
                                    : Colors.orange.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_idCheckDetails.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ..._idCheckDetails.map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(c,
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: (_selectedCountry != null &&
                          _selectedIdType != null &&
                          !_isCheckingId)
                      ? _checkIdAgain
                      : null,
                  child: _isCheckingId
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          '🔍 CHECK MY ID AGAIN',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              _sectionTitle('Experience'),
              DropdownButtonFormField<String>(
                value: _selectedSpecialty,
                decoration: const InputDecoration(labelText: 'Specialty'),
                items: const [
                  'General Nursing',
                  'Midwifery',
                  'ICU / Critical Care',
                  'Paediatric Nursing',
                  'Mental Health',
                  'Community Health',
                  'Emergency / A&E',
                  'Theatre / Surgical',
                ]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedSpecialty = v),
                validator: (v) => v == null ? 'Select specialty' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedExperience,
                decoration:
                    const InputDecoration(labelText: 'Years of Experience'),
                items: const [
                  '0-1 years',
                  '1-3 years',
                  '3-5 years',
                  '5-10 years',
                  '10+ years',
                ]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedExperience = v),
                validator: (v) => v == null ? 'Select experience' : null,
              ),

              if (_uploadStatus != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_uploadStatus!, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'SUBMIT REGISTRATION',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: primary,
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
        ),
        validator: validator,
      ),
    );
  }

  Widget _fileRow({
    required IconData icon,
    required String label,
    required String buttonText,
    required VoidCallback onPick,
    String? fileName,
    String? subLabel,
    bool buttonEnabled = true,
  }) {
    final hasFile = fileName != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  hasFile ? fileName! : (subLabel ?? 'No file selected'),
                  style: TextStyle(
                    color: hasFile ? Colors.black87 : Colors.grey,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryLight,
              foregroundColor: primary,
              elevation: 0,
            ),
            onPressed: buttonEnabled ? onPick : null,
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }
}
