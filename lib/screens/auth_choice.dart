import 'package:flutter/material.dart';
import 'client_login.dart';
import 'nurse_login.dart';
import 'client_registration.dart';
import 'nurse_registration.dart';

// THIS FILE = 2 POPUPS
// Popup 1: REGISTER -> Nurse or Client?
// Popup 2: LOGIN -> Nurse or Client?

class AuthChoice {
  // ===== POPUP 1: REGISTER =====
  static void showRegisterPopup(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 16),
              const Text('Register As', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              const Text('Choose your account type', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),

              // CLIENT REGISTER
              _choiceCard(
                ctx: ctx,
                emoji: '🧑‍💼',
                title: 'Client',
                subtitle: 'Need care? Username + Password + SMS verification',
                color: const Color(0xFFFACC15),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientRegistrationPage()));
                },
              ),
              const SizedBox(height: 12),

              // NURSE REGISTER
              _choiceCard(
                ctx: ctx,
                emoji: '👩‍⚕️',
                title: 'Nurse',
                subtitle: 'Provide care? Email + Photo + Video + CEO Approval',
                color: const Color(0xFF7C3AED),
                textColor: Colors.white,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const NurseRegistrationPage()));
                },
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===== POPUP 2: LOGIN =====
  static void showLoginPopup(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 16),
              const Text('Login As', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              const Text('Choose your account type', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),

              // CLIENT LOGIN
              _choiceCard(
                ctx: ctx,
                emoji: '🧑‍💼',
                title: 'Client',
                subtitle: 'Username + Password ONLY - No SMS on login',
                color: const Color(0xFFFACC15),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientLoginPage()));
                },
              ),
              const SizedBox(height: 12),

              // NURSE LOGIN
              _choiceCard(
                ctx: ctx,
                emoji: '👩‍⚕️',
                title: 'Nurse',
                subtitle: 'Email + Password / Google - CEO Approval Required',
                color: const Color(0xFF7C3AED),
                textColor: Colors.white,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const NurseLoginPage()));
                },
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _choiceCard({
    required BuildContext ctx,
    required String emoji,
    required String title,
    required String subtitle,
    required Color color,
    Color textColor = Colors.black,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.8))),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: textColor),
          ],
        ),
      ),
    );
  }
}
