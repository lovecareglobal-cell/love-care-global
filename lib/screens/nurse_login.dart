import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'nurse_dashboard.dart';

class NurseLoginPage extends StatefulWidget {
  const NurseLoginPage({super.key});
  @override
  State<NurseLoginPage> createState() => _NurseLoginPageState();
}

class _NurseLoginPageState extends State<NurseLoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _msg = '';
  bool _loading = false;
  bool _showPass = false; // For show/hide password eye

  // Helper - checks if a field actually has value, no matter the name
  bool _hasVal(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v == true;
    final s = v.toString().trim();
    return s.isNotEmpty && s.toLowerCase() != 'false' && s.toLowerCase() != 'null';
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) { setState(() => _msg = 'Enter email + password'); return; }
    setState(() { _loading = true; _msg = 'Checking...'; });
    try {
      // GUARD: If this email is a CLIENT, BLOCK immediately - before sign in.
      // Check BOTH lowercased and original-case, in case the client doc was saved before lowercasing.
      final clientCheck = await FirebaseFirestore.instance.collection('clients').where('email', isEqualTo: email).limit(1).get();
      final clientCheckRaw = await FirebaseFirestore.instance.collection('clients').where('email', isEqualTo: _emailCtrl.text.trim()).limit(1).get();
      if (clientCheck.docs.isNotEmpty || clientCheckRaw.docs.isNotEmpty) {
        setState(() { _loading = false; _msg = 'BLOCKED: This is a CLIENT account. Use Client Login. One email cannot be both.'; });
        return;
      }
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
      final uid = cred.user!.uid;

      // GUARD 2: Must exist in nurses/pending + be approved + complete.
      // BYPASS FIX: Before deleting, check EVERYWHERE. If this UID is a real Client,
      // sign out ONLY and NEVER delete - deleting would erase their Client account.
      // This is the bug where a Client trying Nurse Login got deleted.
      final clientByUid = await FirebaseFirestore.instance.collection('clients').doc(uid).get();
      if (clientByUid.exists) {
        await FirebaseAuth.instance.signOut();
        setState(() { _loading = false; _msg = 'BLOCKED: This is a CLIENT account. Use Client Login. One email cannot be both.'; });
        return;
      }
      // Nurse can be in any of these (old registrations wrote to different ones).
      // Check all before declaring NOT REGISTERED.
      var doc = await FirebaseFirestore.instance.collection('nurses').doc(uid).get();
      DocumentSnapshot<Map<String, dynamic>>? pendingDoc;
      if (!doc.exists) {
        pendingDoc = await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).get();
        if (pendingDoc.exists) doc = pendingDoc;
      } else {
        pendingDoc = await FirebaseFirestore.instance.collection('pending_nurses').doc(uid).get();
      }
      if (!doc.exists) {
        final inRegs = await FirebaseFirestore.instance.collection('nurse_registrations').doc(uid).get();
        if (inRegs.exists) doc = inRegs;
      }
      if (!doc.exists) {
        final inCeo = await FirebaseFirestore.instance.collection('ceo_registration').doc(uid).get();
        if (inCeo.exists) doc = inCeo;
      }
      // If nurses doc is pending but pending_nurses doc is approved, CEO approved in the
      // pending list - use the approved one.
      if (doc.exists && pendingDoc != null && pendingDoc.exists) {
        final pData = pendingDoc.data()!;
        final pApproved = pData['isApproved'] == true || pData['approved'] == true || pData['status'] == 'approved';
        final nData = doc.data()!;
        final nApproved = nData['isApproved'] == true || nData['approved'] == true || nData['status'] == 'approved';
        if (pApproved && !nApproved) doc = pendingDoc;
      }
      if (!doc.exists) {
        // No profile in ANY role: leftover from failed / bypassed registration.
        // Sign-out alone leaves it in Auth, so 2nd login slips through. DELETE it.
        // (Client case already returned above, so this delete is safe.)
        try { await cred.user!.delete(); } catch (_) { await FirebaseAuth.instance.signOut(); }
        setState(() { _loading = false; _msg = 'BLOCKED: NOT A REGISTERED NURSE. Go Register first. Leftover account deleted.'; });
        return;
      }
      // NURSE GATE: CEO approval is the gate, NOT email verification.
      // Email verification is for CLIENT only. Do NOT block nurses on emailVerified here.
      final data = doc.data()!;
      final approved = data['isApproved'] == true || data['approved'] == true || data['status'] == 'approved';

      // Complete check - accept ANY field name Registration used
      final hasPhoto = _hasVal(data['hasPhoto']) ||
          _hasVal(data['photoUrl']) ||
          _hasVal(data['photo']) ||
          _hasVal(data['profilePhoto']) ||
          _hasVal(data['profileImage']) ||
          _hasVal(data['image']) ||
          _hasVal(data['imageUrl']) ||
          _hasVal(data['photoURL']);
      final hasPhone = _hasVal(data['hasPhone']) ||
          _hasVal(data['phone']) ||
          _hasVal(data['phoneNumber']) ||
          _hasVal(data['mobile']) ||
          _hasVal(data['phoneNo']);
      final hasVideo = _hasVal(data['hasVideo']) ||
          _hasVal(data['videoUrl']) ||
          _hasVal(data['video']) ||
          _hasVal(data['videoURL']);
      final isCompleteFlag = data['isComplete'] == true || data['complete'] == true || data['isCompleted'] == true;

      // CEO approved = CEO don check documents. If Photo + Phone dey, allow.
      final complete = isCompleteFlag || (hasPhoto && hasPhone) || (hasPhoto && hasPhone && hasVideo);

      if (!approved) {
        await FirebaseAuth.instance.signOut();
        setState(() { _loading = false; _msg = 'WAITING FOR CEO APPROVAL. You cannot login yet.'; });
        return;
      }
      if (!complete) {
        await FirebaseAuth.instance.signOut();
        setState(() { _loading = false; _msg = 'BLOCKED: Approved but missing Photo/Video/Phone. Contact CEO.'; });
        return;
      }

      // SUCCESS - GO TO DASHBOARD
      setState(() { _loading = false; _msg = '✅ Welcome Nurse! Redirecting to dashboard...'; });
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const NurseDashboardScreen()),
      );
    } on FirebaseAuthException catch (e) {
      String m;
      if (e.code == 'user-not-found' || e.code == 'invalid-credential' || e.code == 'wrong-password') {
        m = 'Login failed: Wrong email or password. If you never completed registration, register again - a failed registration does not create a login.';
      } else if (e.code == 'invalid-email') {
        m = 'Login failed: Enter a valid email.';
      } else if (e.code == 'too-many-requests') {
        m = 'Too many tries. Wait a few minutes and try again.';
      } else if (e.code == 'user-disabled') {
        m = 'This account is disabled. Contact CEO.';
      } else {
        m = 'Login failed: ${e.message ?? e.code}';
      }
      setState(() { _loading = false; _msg = m; });
    } catch (e) {
      setState(() { _loading = false; _msg = 'Login failed: $e'; });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nurse Login')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nurse Login', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(hintText: 'Email', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: !_showPass,
              decoration: InputDecoration(
                hintText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_msg.isNotEmpty) Text(_msg, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loading ? null : _login, child: Text(_loading ? 'Checking...' : 'Login as Nurse')),
          ],
        ),
      ),
    );
  }
}
