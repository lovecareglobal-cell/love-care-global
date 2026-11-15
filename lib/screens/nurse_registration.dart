import 'package:flutter/material.dart';
import '../models/id_catalog.dart';

class NurseRegistrationScreen extends StatefulWidget {
  const NurseRegistrationScreen({super.key});

  @override
  State<NurseRegistrationScreen> createState() =>
      _NurseRegistrationScreenState();
}

class _NurseRegistrationScreenState extends State<NurseRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  // --- Colours (match your app) ---
  static const primary = Color(0xFF9C1452); // dark pink / maroon
  static const primaryLight = Color(0xFFFDE7F0);
  static const greenStrong = Color(0xFF2E9E4A);

  // --- Controllers ---
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pinNumberController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _yearsExpController = TextEditingController();

  // --- Dropdowns ---
  String? _selectedCountry;
  IdTypeOption? _selectedIdType;
  String? _selectedSpecialty;
  String? _selectedExperience;
  bool _obscurePassword = true;

  // --- Files (store file names / paths from image_picker) ---
  String? _photoName;
  String? _videoName;
  String? _cvName;
  String? _pinCardName;
  String? _idFrontName;
  String? _idBackName;
  String? _certificateName;

  // --- ID Check state ---
  bool _idCheckAttempted = false;
  bool _idCheckPassed = false;
  String? _idCheckMessage;
  bool _isSubmitting = false;

  // TODO: Replace with your real Vision API key check
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
    _yearsExpController.dispose();
    super.dispose();
  }

  // --- Country / ID Type logic (THE FIX) ---
  void _onCountryChanged(String? country) {
    setState(() {
      _selectedCountry = country;
      _selectedIdType = null; // clear old type
      _idNumberController.clear(); // clear old number
      _idFrontName = null;
      _idBackName = null;
      _idCheckAttempted = false;
      _idCheckPassed = false;
      _idCheckMessage = null;
    });
  }

  void _onIdTypeChanged(IdTypeOption? type) {
    setState(() {
      _selectedIdType = type;
      _idNumberController.clear(); // new type = new format
      _idFrontName = null;
      _idBackName = null;
      _idCheckAttempted = false;
      _idCheckPassed = false;
      _idCheckMessage = null;
    });
  }

  // --- Pickers - connect to image_picker / file_picker ---
  Future<void> _pickFile(String kind) async {
    // TODO: Implement with image_picker / file_picker
    // Example: final XFile? file = await ImagePicker().pickImage(...)
    // For now simulate selection so UI works
    final fakeName = switch (kind) {
      'photo' => 'scaled_1000011119.jpg',
      'video' => '1000024445.mp4',
      'cv' => 'scaled_IMG_20261108_163152_897.jpg',
      'pin' => 'scaled_1000028400.jpg',
      'cert' => 'certificate.pdf',
      _ => 'file.jpg',
    };
    setState(() {
      switch (kind) {
        case 'photo':
          _photoName = fakeName;
          break;
        case 'video':
          _videoName = fakeName;
          break;
        case 'cv':
          _cvName = fakeName;
          break;
        case 'pin':
          _pinCardName = fakeName;
          break;
        case 'cert':
          _certificateName = fakeName;
          break;
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$kind selected (connect picker)')),
      );
    }
  }

  Future<void> _scanId(String side) async {
    if (_selectedCountry == null || _selectedIdType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick ID Country + ID Type first'),
        ),
      );
      return;
    }
    // TODO: Open camera scanner here
    setState(() {
      if (side == 'front') {
        _idFrontName = 'id_front_scanned.jpg';
      } else {
        _idBackName = 'id_back_scanned.jpg';
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Scanned $side of ${_selectedIdType!.label} ($_selectedCountry)',
          ),
        ),
      );
    }
  }

  void _checkIdAgain() {
    setState(() => _idCheckAttempted = true);

    if (!_visionApiConfigured) {
      setState(() {
        _idCheckPassed = false;
        _idCheckMessage =
            'Auto ID check is not configured yet. Ask admin to add the Google Vision API key.';
      });
      return;
    }

    // TODO: Call Vision API, compare scanned number vs typed number
    // For now: basic local validation
    final pattern = _selectedIdType?.pattern;
    final value = _idNumberController.text.trim();
    final ok = pattern == null || pattern.hasMatch(value);
    setState(() {
      _idCheckPassed = ok;
      _idCheckMessage = ok
          ? 'ID number format looks correct for ${_selectedIdType!.label}.'
          : _selectedIdType?.patternError ?? 'ID number format does not match.';
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_photoName == null) {
      _showError('Please pick a Photo');
      return;
    }
    if (_cvName == null) {
      _showError('Please pick your CV');
      return;
    }
    if (_pinCardName == null) {
      _showError('Please pick your PIN Card');
      return;
    }
    if (_idFrontName == null || _idBackName == null) {
      _showError('Please scan FRONT + BACK of your ID');
      return;
    }
    if (_certificateName == null) {
      _showError('Please pick your Certificate');
      return;
    }

    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isSubmitting = false);

    // TODO: Upload to Firebase / API
    // Save these keys, NOT just labels:
    // country: _selectedCountry
    // idTypeId: _selectedIdType!.id  e.g. 'passport_au'
    // idTypeLabel: _selectedIdType!.label
    // idNumber: _idNumberController.text.trim()

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Registration submitted for review')),
    );
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

              // --- COUNTRY ---
              DropdownButtonFormField<String>(
                value: _selectedCountry,
                decoration: const InputDecoration(
                  labelText: 'ID Country - Country you are a citizen of',
                ),
                items: IdCatalog.countries
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: _onCountryChanged,
                validator: (v) =>
                    v == null ? 'Select ID Country' : null,
              ),
              const SizedBox(height: 16),

              // --- ID TYPE (FILTERED) ---
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
                onChanged: _selectedCountry == null
                    ? null
                    : _onIdTypeChanged,
                validator: (v) =>
                    v == null ? 'Select ID Type' : null,
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

              // --- ID NUMBER (DYNAMIC HINT) ---
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
                  if (pattern != null &&
                      !pattern.hasMatch(v.trim())) {
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

              // --- ID CHECK ---
              if (_idCheckAttempted && _idCheckMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _idCheckPassed
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _idCheckPassed ? Icons.check_circle : Icons.close,
                        color: _idCheckPassed ? Colors.green : Colors.orange,
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
                          _selectedIdType != null)
                      ? _checkIdAgain
                      : null,
                  child: const Text(
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
                decoration: const InputDecoration(
                  labelText: 'Specialty',
                ),
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
                decoration: const InputDecoration(
                  labelText: 'Years of Experience',
                ),
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

  // --- Helpers ---
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
                  hasFile
                      ? fileName!
                      : (subLabel ?? 'No file selected'),
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
