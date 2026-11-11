import 'package:flutter/material.dart';
import 'screens/auth_choice.dart';
import 'screens/ceo_control_page.dart';

void main() {
  runApp(const LoveCareApp());
}

class LoveCareApp extends StatelessWidget {
  const LoveCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Love Care Global',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.purple,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A1E),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // LOGO
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: const Center(
                    child: Text('L', style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'LOVE CARE GLOBAL',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Trusted Care, With Love',
                  style: TextStyle(color: Color(0xFFA78BFA), fontSize: 14),
                ),
                const SizedBox(height: 32),

                // ===== REGISTER BUTTON -> POPUP 1 =====
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => AuthChoice.showRegisterPopup(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFACC15),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Register', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 12),

                // ===== LOGIN BUTTON -> POPUP 2 =====
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => AuthChoice.showLoginPopup(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Login', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Register: Choose Nurse or Client\nLogin: Choose Nurse or Client',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFA78BFA), fontSize: 12),
                ),
                const SizedBox(height: 30),

                // CEO BUTTON - Hidden small link
                TextButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CeoControlPage()));
                  },
                  child: const Text('CEO Control', style: TextStyle(color: Colors.grey, fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
