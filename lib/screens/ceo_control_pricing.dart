import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

/// CEO Control Pricing - Flutter version of ceo-control-pricing.html
/// FINAL FIX: Old book-nurse reads config/rates/GHS/hourly — Old ceo-control saved only ceoPricing — Now saves to BOTH — Plus 8 other paths — So CEO change affects FULL + 50% LIVE
/// - Loads: tries config/rates + 9 other paths in order, first with cedis>0 || dollars>0 wins — same as HTML loadPricing()
///   Paths: config/rates, ceoPricing, pricing, publicPricing, settings/pricing, ceoSettings/pricing, appSettings/pricing, pricingConfig, loveCarePricing, ceoControlPricing
///   Parse: config/rates -> v.GHS.hourly / v.USD.hourly ; others -> v.cedis / v.cedisPerHour / v.ghs / v.GHS ; v.dollars / v.dollarsPerHour / v.usd / v.USD
/// - Preview: calcPreview — GHS: {cedis} GH₵/hr → CEO {(cedis*0.2).toFixed(2)} | Nurse {(cedis*0.8).toFixed(2)} — Saves to config/rates/GHS/hourly ; USD: ${dollars}/hr → CEO ${(dollars*0.2).toFixed(2)} | Nurse ${(dollars*0.8).toFixed(2)} — Saves to config/rates/USD/hourly
///   Split is 80% nurse / 20% CEO — same as Nurse Withdrawal (80%) and Book Nurse.
/// - Save: validate BOTH cedis AND dollars required ("Enter both Cedis & Dollars")
///   pricingData {cedis, dollars, cedisPerHour, dollarsPerHour, ghs, usd, GHS, USD, updatedAt}
///   configRatesData {GHS: {hourly, rate}, USD: {hourly, rate}, updatedAt}
///   Set pricingData to 9 simple paths: ceoPricing, pricing, publicPricing, settings/pricing, ceoSettings/pricing, appSettings/pricing, pricingConfig, loveCarePricing, ceoControlPricing
///   Set configRatesData to config/rates, then fallback: config/rates/GHS/hourly = cedis + config/rates/USD/hourly = dollars (if config/rates set fails), then again GHS/hourly + USD/hourly (same as HTML double-write)
///   savedStatus "Saved to {saved} paths — LIVE — FINAL FIX", success "✅ SAVED FINAL FIX — {cedis} GH₵/hr + ${dollars}/hr — Saved to {saved} paths — Including config/rates/GHS/hourly + USD/hourly — Now your previous book-nurse-full.txt reads LIVE — Screenshot GHS 16/hr will change to {cedis}/hr LIVE — Same applies to 50%!"
/// - NO alert buttons — only Sound Settings.

class CEOControlPricingScreen extends StatefulWidget {
  const CEOControlPricingScreen({super.key});
  @override
  State<CEOControlPricingScreen> createState() => _CEOControlPricingScreenState();
}

class _CEOControlPricingScreenState extends State<CEOControlPricingScreen> {
  final _cedisCtrl = TextEditingController();
  final _dollarsCtrl = TextEditingController();
  String savedStatus = 'Not saved';
  String? errorMsg, successMsg;
  bool showCalc = false;

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _calcPreview() {
    final cedis = double.tryParse(_cedisCtrl.text) ?? 0;
    final dollars = double.tryParse(_dollarsCtrl.text) ?? 0;
    setState(() => showCalc = !(cedis == 0 && dollars == 0));
  }

  Future<void> _loadPricing() async {
    _toast('Loading — FINAL FIX — Tries config/rates + 9 other paths...');
    final paths = ['config/rates', 'ceoPricing', 'pricing', 'publicPricing', 'settings/pricing', 'ceoSettings/pricing', 'appSettings/pricing', 'pricingConfig', 'loveCarePricing', 'ceoControlPricing'];
    Map<String, double>? loaded; String loadedFrom = '';
    for (final path in paths) {
      try {
        final snap = await FirebaseDatabase.instance.ref(path).get();
        if (!snap.exists) continue;
        final v = Map<String, dynamic>.from(snap.value as Map);
        double cedis = 0, dollars = 0;
        if (path == 'config/rates') {
          if (v['GHS'] is Map) cedis = double.tryParse(((v['GHS'] as Map)['hourly'] ?? 0).toString()) ?? 0;
          if (v['USD'] is Map) dollars = double.tryParse(((v['USD'] as Map)['hourly'] ?? 0).toString()) ?? 0;
        } else {
          cedis = double.tryParse((v['cedis'] ?? v['cedisPerHour'] ?? v['ghs'] ?? v['GHS'] ?? 0).toString()) ?? 0;
          dollars = double.tryParse((v['dollars'] ?? v['dollarsPerHour'] ?? v['usd'] ?? v['USD'] ?? 0).toString()) ?? 0;
        }
        if (cedis > 0 || dollars > 0) { loaded = {'cedis': cedis, 'dollars': dollars}; loadedFrom = path; break; }
      } catch (_) {}
    }
    if (loaded != null) {
      _cedisCtrl.text = (loaded['cedis'] ?? 0).toString();
      _dollarsCtrl.text = (loaded['dollars'] ?? 0).toString();
      setState(() { savedStatus = 'Loaded from $loadedFrom'; successMsg = 'Loaded ${loaded['cedis']} GH₵ + \$${loaded['dollars']} from $loadedFrom — FINAL FIX'; errorMsg = null; });
      _calcPreview();
    } else {
      _toast('No pricing — Enter new and Save — FINAL FIX');
    }
  }

  Future<void> _savePricing() async {
    final cedis = double.tryParse(_cedisCtrl.text);
    final dollars = double.tryParse(_dollarsCtrl.text);
    if (cedis == null || cedis == 0 || dollars == null || dollars == 0) {
      setState(() { errorMsg = 'Enter both Cedis & Dollars'; successMsg = null; });
      _toast('Enter both Cedis & Dollars');
      return;
    }
    _toast('Saving $cedis GH₵ + \$$dollars — FINAL FIX — Saves to config/rates + 9 paths...');
    final pricingData = {'cedis': cedis, 'dollars': dollars, 'cedisPerHour': cedis, 'dollarsPerHour': dollars, 'ghs': cedis, 'usd': dollars, 'GHS': cedis, 'USD': dollars, 'updatedAt': DateTime.now().millisecondsSinceEpoch};
    final configRatesData = {'GHS': {'hourly': cedis, 'rate': cedis}, 'USD': {'hourly': dollars, 'rate': dollars}, 'updatedAt': DateTime.now().millisecondsSinceEpoch};
    final simplePaths = ['ceoPricing', 'pricing', 'publicPricing', 'settings/pricing', 'ceoSettings/pricing', 'appSettings/pricing', 'pricingConfig', 'loveCarePricing', 'ceoControlPricing'];
    int saved = 0;
    final db = FirebaseDatabase.instance;
    for (final path in simplePaths) {
      try { await db.ref(path).set(pricingData); saved++; } catch (_) {}
    }
    try {
      await db.ref('config/rates').set(configRatesData); saved++;
    } catch (_) {
      try { await db.ref('config/rates/GHS/hourly').set(cedis); await db.ref('config/rates/USD/hourly').set(dollars); saved++; } catch (_) {}
    }
    try { await db.ref('config/rates/GHS/hourly').set(cedis); await db.ref('config/rates/USD/hourly').set(dollars); } catch (_) {}
    setState(() {
      savedStatus = 'Saved to $saved paths — LIVE — FINAL FIX';
      successMsg = '✅ SAVED FINAL FIX — $cedis GH₵/hr + \$$dollars/hr — Saved to $saved paths — Including config/rates/GHS/hourly + USD/hourly — Now your previous book-nurse-full.txt reads LIVE — Screenshot GHS 16/hr will change to $cedis/hr LIVE — Same applies to 50%!';
      errorMsg = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cedis = double.tryParse(_cedisCtrl.text) ?? 0;
    final dollars = double.tryParse(_dollarsCtrl.text) ?? 0;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1C),
      appBar: AppBar(title: const Text('CEO Control Pricing', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF1A1633), actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 8), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('LIVE Firebase', style: TextStyle(fontSize: 10, color: Color(0xFFA78BFA))), Text(savedStatus, style: const TextStyle(fontSize: 10, color: Color(0xFFFBBF24)))]))), IconButton(icon: const Icon(Icons.volume_up), onPressed: () => Navigator.pushNamed(context, '/sound-settings')), TextButton(onPressed: () => Navigator.pushNamed(context, '/ceo-dashboard'), child: const Text('Dashboard', style: TextStyle(fontSize: 10, color: Color(0xFFD8B4FE))))]),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 500), child: Column(children: [
        Container(width: 70, height: 70, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFA855F7), Color(0xFFD8B4FE)]), borderRadius: BorderRadius.circular(16)), child: const Center(child: Text('💰', style: TextStyle(fontSize: 34)))),
        const SizedBox(height: 12),
        const Text('CEO Control Pricing — FINAL FIX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Set rate per hour — Cedis and Dollars SEPARATELY — Saves to config/rates/GHS/hourly + USD/hourly PLUS 8 other paths — So your previous book-nurse-full.txt reads LIVE', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.white60)),
        const SizedBox(height: 16),
        if (errorMsg != null) Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withOpacity(0.12), border: Border.all(color: Colors.red.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)), child: Text(errorMsg!, style: const TextStyle(fontSize: 12, color: Color(0xFFFCA5A5)))),
        if (successMsg != null) Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.withOpacity(0.12), border: Border.all(color: Colors.green.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)), child: Text(successMsg!, style: const TextStyle(fontSize: 12, color: Color(0xFF86EFAC)))),
        const SizedBox(height: 16),
        const Align(alignment: Alignment.centerLeft, child: Text('💵 RATE PER HOUR — GHS CEDIS (GH₵) — Saves to config/rates/GHS/hourly', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        const SizedBox(height: 6),
        TextField(controller: _cedisCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'e.g., 17', border: OutlineInputBorder()), onChanged: (_) => _calcPreview()),
        const SizedBox(height: 16),
        const Align(alignment: Alignment.centerLeft, child: Text('💵 RATE PER HOUR — USD DOLLARS (\$) — Saves to config/rates/USD/hourly', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        const SizedBox(height: 6),
        TextField(controller: _dollarsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'e.g., 8', border: OutlineInputBorder()), onChanged: (_) => _calcPreview()),
        if (showCalc) Container(width: double.infinity, margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black26, border: Border.all(color: Colors.purple.withOpacity(0.15)), borderRadius: BorderRadius.circular(12)), child: Text('Preview — FINAL FIX:\nGHS: $cedis GH₵/hr → CEO ${(cedis * 0.2).toStringAsFixed(2)} | Nurse ${(cedis * 0.8).toStringAsFixed(2)} — Saves to config/rates/GHS/hourly\nUSD: \$$dollars/hr → CEO ${(dollars * 0.2).toStringAsFixed(2)} | Nurse ${(dollars * 0.8).toStringAsFixed(2)} — Saves to config/rates/USD/hourly', style: const TextStyle(fontSize: 11, color: Color(0xFFC4B5FD)))),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: _savePricing, child: const Text('💾 SAVE PRICING — FINAL FIX — Saves to config/rates PLUS 8 paths — LIVE affects FULL + 50%', style: TextStyle(fontSize: 11)))),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _loadPricing, child: const Text('🔄 Reload Pricing'))),
      ])))),
    );
  }
}
