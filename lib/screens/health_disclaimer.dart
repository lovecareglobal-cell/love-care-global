import 'package:flutter/material.dart';

class HealthDisclaimerPage extends StatelessWidget {
  const HealthDisclaimerPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCE4EC),
      appBar: AppBar(backgroundColor: const Color(0xFF880E4F), foregroundColor: Colors.white, title: const Text('Health Disclaimer')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _header('⚠️ Love Care Global - Health Disclaimer\nLast Updated: 23 Nov 2026'),
            _section('NOT Emergency Service'),
            _card('Love Care Global does NOT provide emergency medical services. We do NOT provide ambulance. We do NOT provide emergency hospital care.\nFor emergencies, call Ambulance / 112 or go to nearest hospital IMMEDIATELY. Do NOT wait for a Nurse in the app.'),
            _section('Non-Emergency Home Care Only'),
            _card('Nurses in this app provide non-emergency home care only: companionship, bathing, feeding, medication reminders, wound care support, elderly care, post-hospital home support, as agreed with Client.'),
            _section('No Diagnosis, No Prescription'),
            _card('Nurses in this app do NOT diagnose diseases and do NOT prescribe medicine. Always follow your doctor\'s advice. If Nurse advice conflicts with your doctor, follow your doctor. If you are unsure, ask your doctor or go to hospital.'),
            _section('No Guarantee'),
            _card('We do not guarantee cure, recovery, or any medical outcome. Every patient is different. Nurses are independent caregivers, not employees of Love Care Global.'),
            _section('If Condition Gets Worse'),
            _card('If patient condition gets worse - difficulty breathing, chest pain, heavy bleeding, unconscious, seizure - STOP home care, call 112 / Ambulance, go to hospital immediately.'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  static Widget _header(String t) => Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF880E4F))));
  static Widget _section(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Align(alignment: Alignment.centerLeft, child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF880E4F)))));
  static Widget _card(String t) => Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(t, style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF333333))));
}
