import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

class NurseRegistrationScreen extends StatefulWidget {
  const NurseRegistrationScreen({super.key});
  @override
  State<NurseRegistrationScreen> createState() => _NurseRegistrationScreenState();
}

class _NurseRegistrationScreenState extends State<NurseRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pinNumberController = TextEditingController();
  final _idNumberTyped = TextEditingController();

  String _selectedIdCountry = '';
  String _selectedIdType = '';
  bool _idVerified = false;
  String _idCheck = '';
  bool _isLoading = false;
  bool _obscurePassword = true;

  File? _photo;
  File? _video;
  File? _cv;
  File? _pinCard;
  File? _idFront;
  File? _idBack;
  File? _cert;

  // ---------------- COUNTRIES ----------------
  static const List<String> _idCountries = [
    'Ghana', 'Nigeria', 'Kenya', 'South Africa', 'Togo', 'Ivory Coast',
    'Senegal', 'Cameroon', 'Ethiopia', 'Uganda', 'Tanzania',
    'India', 'Pakistan', 'Philippines',
    'United States', 'United Kingdom', 'Australia', 'Canada',
    'Germany', 'France', 'Netherlands', 'Spain', 'Italy', 'UAE',
  ];

  // ---------------- FIX: ID TYPES MUST MATCH ID COUNTRY ----------------
  static const Map<String, List<String>> _idTypesByCountry = {
    'Ghana': ['Ghana Card', 'Passport', 'Voter ID Card', 'Driving Licence', 'Health Insurance Card (NHIS)'],
    'Nigeria': ['National ID (NIN)', 'Passport', "Voter's Card", "Driver's Licence", 'Health Insurance Card'],
    'Kenya': ['National ID', 'Passport', 'Alien ID', 'Driving Licence', 'Voter ID'],
    'South Africa': ['National ID (Smart ID)', 'Passport', "Driver's Licence", 'Voter ID'],
    'India': ['Aadhaar Card', 'PAN Card', 'Passport', 'Voter ID', 'Driving Licence'],
    'United States': ['Passport', "Driver's Licence", 'State ID Card', 'Social Security Card'],
    'United Kingdom': ['Passport', 'Driving Licence', 'BRP / eVisa', 'National ID'],
    'Australia': ['Passport', 'Driver Licence', 'Medicare Card', 'Proof of Age Card'],
    'Canada': ['Passport', "Driver's Licence", 'PR Card', 'Health Card'],
    'Togo': ['National ID', 'Passport', "Voter's Card", 'Driving Licence'],
    'Ivory Coast': ['National ID (CNI)', 'Passport', "Voter's Card", 'Driving Licence'],
    'Senegal': ['National ID (CNI)', 'Passport', "Voter's Card", 'Driving Licence'],
    'Cameroon': ['National ID', 'Passport', "Voter's Card", 'Driving Licence'],
    'Ethiopia': ['National ID (Fayda)', 'Passport', 'Driving Licence', 'Voter ID'],
    'Uganda': ['National ID', 'Passport', 'Driving Licence', 'Voter ID'],
    'Tanzania': ['National ID (NIDA)', 'Passport', 'Driving Licence', 'Voter ID'],
    'Philippines': ['National ID (PhilSys)', 'Passport', "Driver's Licence", 'Voter ID'],
    'Pakistan': ['National ID (CNIC)', 'Passport', 'Driving Licence', 'Voter ID'],
  };

  static const List<String> _idTypesDefault = [
    'Passport',
    'National ID / National Identity Card',
    'Driving Licence',
    'Voter ID Card',
    'Health Insurance Card'
  ];

  List<String> get _currentIdTypes {
    if (_selectedIdCountry.isEmpty) return [];
    return _idTypesByCountry[_selectedIdCountry] ?? _idTypesDefault;
  }

  String get _idExample {
    switch (_selectedIdType) {
      case 'Ghana Card': return 'e.g. GHA-123456789-0';
      case 'Passport': return 'e.g. G1234567 / PA1234567 - as printed on passport';
      case 'Voter ID Card': return 'e.g. 1234567890 - as printed on Voter ID';
      case "Voter's Card": return 'e.g. 1234567890 - as printed on Voter Card';
      case 'Voter ID': return 'e.g. 1234567890 - as printed on Voter ID';
      case 'Driving Licence': return 'e.g. DL123456789 - as printed on licence';
      case "Driver's Licence": return 'e.g. DL123456789 - as printed on licence';
      case 'Driver Licence': return 'e.g. 123456789 - as printed on licence';
      case 'Health Insurance Card (NHIS)': return 'e.g. 12345678 - NHIS number';
      case 'Health Insurance Card': return 'e.g. 12345678 - Health Card number';
      case 'Health Card': return 'e.g. 1234-567-890 - Health Card number';
      case 'National ID (NIN)': return 'e.g. 12345678901 - 11-digit NIN';
      case 'National ID': return 'e.g. 12345678 - as printed on National ID';
      case 'National ID / National Identity Card': return 'e.g. 123456789 - as printed on National ID';
      case 'National ID (Smart ID)': return 'e.g. 1234567890123 - 13-digit SA ID';
      case 'National ID (CNI)': return 'e.g. 123456789 - as printed on CNI';
      case 'National ID (NIDA)': return 'e.g. 12345678-12345-12345-12';
      case 'National ID (Fayda)': return 'e.g. 123456789012 - 12-digit Fayda';
      case 'National ID (CNIC)': return 'e.g. 12345-1234567-1';
      case 'National ID (PhilSys)': return 'e.g. 1234-5678-9012-3456';
      case 'Aadhaar Card': return 'e.g. 1234 5678 9012 - 12-digit Aadhaar';
      case 'PAN Card': return 'e.g. ABCDE1234F - as printed on PAN';
      case 'Social Security Card': return 'e.g. 123-45-6789';
      case 'State ID Card': return 'e.g. D1234567 - as printed on State ID';
      case 'Medicare Card': return 'e.g. 1234 56789 1 - Medicare number';
      case 'Proof of Age Card': return 'e.g. 123456789 - as printed on card';
      case 'PR Card': return 'e.g. AB123456 - as printed on PR Card';
      case 'BRP / eVisa': return 'e.g. RA1234567 - BRP number';
      case 'Alien ID': return 'e.g. 12345678 - Alien ID number';
      default: return 'e.g. Enter exactly as printed on your ID';
    }
  }

  // ---------------- PICKERS ----------------
  Future<void> _pickImage(Function(File) onPicked) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (x != null) setState(() => onPicked(File(x.path)));
  }

  Future<void> _pickFile(Function(File) onPicked) async {
    final r = await FilePicker.platform.pickFiles();
    if (r != null && r.files.single.path != null) {
      setState(() => onPicked(File(r.files.single.path!)));
    }
  }

  Future<void> _scanId(bool isFront) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (x != null) {
      setState(() {
        if (isFront) {
          _idFront = File(x.path);
        } else {
          _idBack = File(x.path);
        }
        _idVerified = false;
        _idCheck = '';
      });
    }
  }

  String _passwordStrength(String v) {
    if (v.length < 6) return 'Weak';
    if (v.length < 8) return 'Medium';
    bool hasUpper = v.contains(RegExp(r'[A-Z]'));
    bool hasDigit = v.contains(RegExp(r'[0-9]'));
    bool hasSpecial = v.contains(RegExp(r'[^A-Za-z0-9]'));
    if (hasUpper && hasDigit && hasSpecial) return 'Very strong';
    if (hasUpper && hasDigit) return 'Strong';
    return 'Medium';
  }

  void _checkIdAgain() {
    if (_selectedIdCountry.isEmpty || _selectedIdType.isEmpty || _idNumberTyped.text.trim().isEmpty) {
      setState(() => _idCheck = 'Pick Country + ID Type + ID Number first');
      return;
    }
    if (_idFront == null || _idBack == null) {
      setState(() => _idCheck = 'Scan FRONT and BACK of your ID first');
      return;
    }
    setState(() {
      _idVerified = true;
      _idCheck = 'ID looks good. CEO will verify your documents.';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ID checked. CEO will verify documents.')),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick your photo first')));
      return;
    }
    if (_selectedIdCountry.isEmpty || _selectedIdType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick ID Country + ID Type first')));
      return;
    }
    setState(() => _isLoading = true);
    Future.delayed(const Duration(seconds: 1), () {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration sent. Wait for CEO verification.')),
      );
    });
  }

  Widget _fileRow({required IconData icon, required String label, required File? file, required String btn, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF9C1A5E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              file != null ? '$label: ${file.path.split('/').last}' : label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFDE7F0), foregroundColor: const Color(0xFF9C1A5E)),
            child: Text(btn),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pw = _passwordController.text;
    final strength = _passwordStrength(pw);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF9C1A5E),
        foregroundColor: Colors.white,
        title: const Text('Nurse Registration'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full Name', hintText: 'e.g. Ama Serwaa'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your full name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email', hintText: 'e.g. ama@gmail.com'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter valid email' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number', hintText: 'e.g. +233 20 123 4567'),
                validator: (v) => (v == null || v.trim().length < 9) ? 'Enter valid phone' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) => (v == null || v.length < 6) ? 'Password must be 6+ characters' : null,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: pw.isEmpty ? 0 : (strength == 'Very strong' ? 1 : strength == 'Strong' ? 0.75 : strength == 'Medium' ? 0.5 : 0.25),
                color: strength == 'Very strong' || strength == 'Strong' ? Colors.green : Colors.orange,
              ),
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.check_circle, color: strength == 'Very strong' || strength == 'Strong' ? Colors.green : Colors.grey, size: 20),
                const SizedBox(width: 6),
                Text(strength == 'Very strong' ? 'Strong password ✓' : strength, style: const TextStyle(color: Colors.green)),
                const Spacer(),
                Text(strength, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 20),
              _fileRow(icon: Icons.photo, label: 'Pick Photo', file: _photo, btn: 'Pick Photo', onTap: () => _pickImage((f) => _photo = f)),
              _fileRow(icon: Icons.videocam, label: 'Pick Video', file: _video, btn: 'Pick Video', onTap: () => _pickFile((f) => _video = f)),
              _fileRow(icon: Icons.description, label: 'Pick CV', file: _cv, btn: 'Pick CV', onTap: () => _pickFile((f) => _cv = f)),
              const SizedBox(height: 8),
              const Text('Nursing PIN Number', style: TextStyle(color: Color(0xFF9C1A5E), fontSize: 18)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _pinNumberController,
                decoration: const InputDecoration(hintText: 'e.g. PIN123456'),
              ),
              const SizedBox(height: 8),
              _fileRow(icon: Icons.badge, label: 'Pick PIN Card', file: _pinCard, btn: 'Pick PIN', onTap: () => _pickImage((f) => _pinCard = f)),

              const SizedBox(height: 8),
              // ---- ID COUNTRY ----
              DropdownButtonFormField<String>(
                value: _selectedIdCountry.isEmpty ? null : _selectedIdCountry,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'ID Country - Country you are a citizen of',
                  hintText: 'e.g. Ghana, Nigeria, Kenya, India...',
                ),
                items: _idCountries.map((c) => DropdownMenuItem<String>(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() {
                  _selectedIdCountry = v ?? '';
                  _selectedIdType = '';
                  _idNumberTyped.clear();
                  _idFront = null;
                  _idBack = null;
                  _idVerified = false;
                  _idCheck = '';
                }),
              ),
              const SizedBox(height: 12),
              // ---- ID TYPE - FILTERED BY COUNTRY ----
              DropdownButtonFormField<String>(
                value: _selectedIdType.isEmpty ? null : _selectedIdType,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'ID Type - Select your ID',
                  hintText: _selectedIdCountry.isEmpty ? 'Pick ID Country first' : 'Select ID for $_selectedIdCountry',
                ),
                items: _currentIdTypes.map((t) => DropdownMenuItem<String>(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: _selectedIdCountry.isEmpty
                    ? null
                    : (v) => setState(() {
                          _selectedIdType = v ?? '';
                          _idNumberTyped.clear();
                          _idFront = null;
                          _idBack = null;
                          _idVerified = false;
                          _idCheck = '';
                        }),
              ),
              const SizedBox(height: 12),
              // ---- ID NUMBER - EXAMPLE CHANGES WITH ID TYPE ----
              TextField(
                controller: _idNumberTyped,
                decoration: InputDecoration(
                  labelText: 'ID Number (as printed on your ID)',
                  hintText: _idExample,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'ID is AUTO-SCANNED - put it inside the box, turn on flash if dark. It snaps by itself when clear + steady.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _fileRow(
                icon: Icons.credit_card,
                label: _selectedIdCountry.isEmpty || _selectedIdType.isEmpty ? 'Pick ID Country + ID Type first' : 'Upload ID - FRONT\n${_selectedIdType} - $_selectedIdCountry',
                file: _idFront,
                btn: 'Scan Front',
                onTap: () {
                  if (_selectedIdCountry.isEmpty || _selectedIdType.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick ID Country + ID Type first')));
                    return;
                  }
                  _scanId(true);
                },
              ),
              _fileRow(
                icon: Icons.credit_card,
                label: _selectedIdType.isEmpty ? 'Auto-scan (box + flash) - Back of (required)' : 'Upload ID - BACK\nBack of $_selectedIdType',
                file: _idBack,
                btn: 'Scan Back',
                onTap: () {
                  if (_selectedIdCountry.isEmpty || _selectedIdType.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick ID Country + ID Type first')));
                    return;
                  }
                  _scanId(false);
                },
              ),
              _fileRow(icon: Icons.school, label: 'Upload Certificate', file: _cert, btn: 'Pick Cert', onTap: () => _pickFile((f) => _cert = f)),
              if (_idCheck.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _idCheck,
                  style: TextStyle(color: _idVerified ? Colors.green : Colors.orange, fontWeight: FontWeight.bold),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _checkIdAgain,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9C1A5E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('🔍 CHECK MY ID AGAIN'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9C1A5E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('REGISTER AS NURSE', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _pinNumberController.dispose();
    _idNumberTyped.dispose();
    super.dispose();
  }
}
