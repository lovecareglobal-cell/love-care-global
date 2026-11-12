import 'package:flutter/material.dart';

class ClientRegistrationPage extends StatefulWidget {
  const ClientRegistrationPage({super.key});
  @override
  State<ClientRegistrationPage> createState() => _ClientRegistrationPageState();
}

class _ClientRegistrationPageState extends State<ClientRegistrationPage> {
  final _userCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _showOtp = false;
  bool _showPass = false;
  String _msg = '';

  void _sendOtp() {
    if (_userCtrl.text.isEmpty || _phoneCtrl.text.isEmpty) {
      setState(() => _msg = 'Enter username and phone');
      return;
    }
    setState(() { _showOtp = true; _msg = 'OTP sent to ${_phoneCtrl.text} (Demo: 123456)'; });
  }

  void _register() {
    if (_otpCtrl.text != '123456' && _showOtp) {
      setState(() => _msg = 'Wrong OTP - use 123456 for demo');
      return;
    }
    setState(() => _msg = '✅ Registered! Go to Login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(backgroundColor: const Color(0xFF0C0A1E), title: const Text('Client Registration', style: TextStyle(color: Colors.white)), iconTheme: const IconThemeData(color: Colors.white)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Client Registration', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Username + Phone + SMS Verification', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFA78BFA), fontSize: 12)),
            const SizedBox(height: 16),
            _field(_userCtrl, 'Username (e.g. kusipeter)'),
            const SizedBox(height: 12),
            _field(_phoneCtrl, 'Phone e.g. +233...', isPhone: true),
            const SizedBox(height: 12),
            _field(_passCtrl, 'Password', isPass: true),
            const SizedBox(height: 12),
            if (_showOtp) ...[
              _field(_otpCtrl, 'Enter OTP - 123456'),
              const SizedBox(height: 12),
            ],
            if (_msg.isNotEmpty) ...[
              Text(_msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.yellow, fontSize: 12)),
              const SizedBox(height: 12),
            ],
            ElevatedButton(
              onPressed: _showOtp ? _register : _sendOtp,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFACC15), padding: const EdgeInsets.all(14)),
              child: Text(_showOtp ? 'Verify OTP & Register' : 'Send OTP', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, {bool isPhone = false, bool isPass = false}) {
    return TextField(
      controller: c,
      obscureText: isPass ? !_showPass : false,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFA78BFA)),
        filled: true,
        fillColor: const Color(0xFF1E1A3A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: isPass ? IconButton(icon: Text(_showPass ? '🙈' : '👁️'), onPressed: () => setState(() => _showPass = !_showPass)) : null,
      ),
    );
  }
}
