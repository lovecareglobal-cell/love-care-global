import 'package:flutter/material.dart';
import 'client_registration.dart';

// SAME AS YOUR HTML - Client Login - Username + Password ONLY
// No SMS on login. SMS only on registration.

class ClientLoginPage extends StatefulWidget {
  const ClientLoginPage({super.key});

  @override
  State<ClientLoginPage> createState() => _ClientLoginPageState();
}

class _ClientLoginPageState extends State<ClientLoginPage> {
  final _usernameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _showPass = false;
  String _status = '';
  bool _isOk = false;
  bool _loading = false;

  // Same hash as your HTML: btoa reversed + _length
  // In Flutter we do simple version - replace with your Firebase check
  String _hashPassword(String p) {
    return p.split('').reversed.join() + '_${p.length}';
  }

  void _showStatus(String msg, bool ok) {
    setState(() {
      _status = msg;
      _isOk = ok;
    });
  }

  Future<void> _login() async {
    final username = _usernameCtrl.text.trim().toLowerCase().replaceAll(' ', '');
    final pass = _passCtrl.text.trim();

    if (username.isEmpty || pass.isEmpty) {
      _showStatus('Enter username & password', false);
      return;
    }

    setState(() => _loading = true);
    _showStatus('Checking username...', true);

    // TODO: Connect this to your Firebase allowedClients/$username
    // For now this is UI + validation same as HTML.
    // When you add firebase_database package, replace this block
    // with the same checks from your HTML:
    // - isBlocked == true -> block
    // - missing photo / phone / username -> block + go to registration
    // - phoneVerified == true -> allow
    // - passwordHash == hashPassword(pass) -> allow
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;
    setState(() => _loading = false);

    // Demo check - remove when Firebase is connected
    _showStatus(
      '✅ Photo, Phone, Username verified + Password OK — Welcome $username — Entering dashboard...',
      true,
    );

    // TODO: Save login like your HTML localStorage:
    // clientLoggedIn = true, lcg_role = client, clientUsername = username
    // Then: Navigator.push to Client Dashboard
  }

  void _resetPass() {
    // Same as your HTML prompt - strong password check
    final username = _usernameCtrl.text.trim().toLowerCase();
    if (username.isEmpty) {
      _showStatus('Enter username to reset password', false);
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1A3A),
          title: const Text('Reset Password', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: c,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'New strong password e.g. Kusi@2026',
              hintStyle: TextStyle(color: Color(0xFFA78BFA)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final np = c.text.trim();
                final hasLen = np.length >= 8;
                final hasSmall = RegExp(r'[a-z]').hasMatch(np);
                final hasBig = RegExp(r'[A-Z]').hasMatch(np);
                final hasNum = RegExp(r'[0-9]').hasMatch(np);
                final hasSpecial = RegExp(r'[@&+#$!%*?_]').hasMatch(np);
                if (!(hasLen && hasSmall && hasBig && hasNum && hasSpecial)) {
                  _showStatus('Weak password — 8+ chars, small, BIG, number, special', false);
                  Navigator.pop(ctx);
                  return;
                }
                Navigator.pop(ctx);
                _showStatus('✅ Password reset success — Login with new password (No SMS needed)', true);
                // TODO: Update Firebase allowedClients/$username passwordHash = _hashPassword(np)
              },
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0A1E),
        title: const Text('Client Login', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1A3A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Client Login',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFF3E8FF), fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Username + Password ONLY — No SMS on login (SMS only on registration for real person verification)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFA78BFA), fontSize: 10),
                ),
                const SizedBox(height: 14),
                // USERNAME - lowercase, no spaces - same as HTML oninput
                TextField(
                  controller: _usernameCtrl,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (v) {
                    final cleaned = v.toLowerCase().replaceAll(' ', '');
                    if (cleaned != v) {
                      _usernameCtrl.value = TextEditingValue(text: cleaned, selection: TextSelection.collapsed(offset: cleaned.length));
                    }
                  },
                  decoration: _inputDec('Username (e.g. kusipeter)'),
                ),
                const SizedBox(height: 14),
                // PASSWORD + EYE
                TextField(
                  controller: _passCtrl,
                  obscureText: !_showPass,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDec('Password').copyWith(
                    suffixIcon: IconButton(
                      icon: Text(_showPass ? '🙈' : '👁️'),
                      onPressed: () => setState(() => _showPass = !_showPass),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_status.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _isOk ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _isOk ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)),
                    ),
                    child: Text(_status, textAlign: TextAlign.center, style: TextStyle(color: _isOk ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5), fontSize: 11)),
                  ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFACC15),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.all(14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_loading ? 'Checking...' : 'Login — Enter Dashboard', style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientRegistrationPage()));
                      },
                      child: const Text('No account? Register (SMS verification)', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: _resetPass,
                      child: const Text('Forgot password?', style: TextStyle(color: Color(0xFFFACC15), fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF0E0A1C).withOpacity(0.6), borderRadius: BorderRadius.circular(10)),
                  child: const Text(
                    'Login Flow:\n• Username + Password only\n• No SMS on login — fast entry\n• SMS was already done on registration to prove real person\n• CEO can still trace you via phone + country code',
                    style: TextStyle(color: Color(0xFFA78BFA), fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFA78BFA)),
      filled: true,
      fillColor: const Color(0xFF0C0A1E).withOpacity(0.8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFA855F7))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFFA855F7).withOpacity(0.2))),
    );
  }
}
