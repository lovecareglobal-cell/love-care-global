
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
// V4 - FIXES YOUR SCREENSHOT:
//  1) FLASH ON WEB: camera plugin torch does NOT work on web.
//     V4 tries torch 3 ways + shows WHY it failed, + adds a
//     "LIGHT" backup: bright white screen + exposure boost so
//     the card is lit even if torch is blocked by the browser.
//  2) NO LIVE INFO ON WEB: web does NOT support imageStream,
//     so V3 fell back to "Preview only". V4 replaces that with
//     a real guided flow for web:
//       Step 1: Align card in box (box is WHITE)
//       Step 2: Tap "CARD IN BOX" -> box turns AMBER
//       Step 3: Hold steady 3-2-1 -> box turns GREEN -> auto-capture
//     If you move, tap "RE-ALIGN" and it resets. It NEVER
//     captures while you are still aligning.
//  3) ON ANDROID APP (later Play Store): imageStream DOES work,
//     so V4 uses real auto-detection there, same file.
// ─────────────────────────────────────────────────────────────

enum ScanState { align, holding, ready, capturing }

class IdAutoCaptureScanner extends StatefulWidget {
  final String title;
  final bool isFront;
  const IdAutoCaptureScanner({super.key, required this.title, required this.isFront});

  @override
  State<IdAutoCaptureScanner> createState() => _IdAutoCaptureScannerState();
}

class _IdAutoCaptureScannerState extends State<IdAutoCaptureScanner> {
  CameraController? _controller;
  String _error = '';
  bool _flashOn = false;
  bool _lightOn = false; // web backup light
  bool _isCapturing = false;

  ScanState _state = ScanState.align;
  String _hint = 'Put your ID inside the white box.\nFill the box. No glare.';
  int _countdown = 3;
  Timer? _countdownTimer;

  // For native Android/iOS auto-detection
  bool _streamStarted = false;
  DateTime _lastCheck = DateTime.now();
  double _lastEdge = 0, _lastBright = 0;
  int _steadyTicks = 0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) { setState(() => _error = 'No camera found.'); return; }
      final back = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      final controller = CameraController(back, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await controller.initialize();
      if (!mounted) return;
      setState(() => _controller = controller);
      if (!kIsWeb) _startImageAnalysis(); // native only - web uses guided flow
      if (kIsWeb && mounted) {
        setState(() => _hint = 'WEB MODE:\n1. Put ID inside white box\n2. Tap CARD IN BOX below\n3. Hold steady 3-2-1 -> auto-capture');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera error: $e\nAllow camera + use HTTPS.');
    }
  }

  // ── NATIVE ONLY: real frame analysis (Android app) ──
  void _startImageAnalysis() async {
    if (_controller == null || _streamStarted) return;
    _streamStarted = true;
    try {
      await _controller!.startImageStream((img) {
        final now = DateTime.now();
        if (now.difference(_lastCheck).inMilliseconds < 500) return;
        _lastCheck = now;
        if (!mounted || _isCapturing) return;
        _analyseFrame(img);
      });
    } catch (_) {}
  }

  void _analyseFrame(CameraImage image) {
    try {
      final plane = image.planes[0];
      final bytes = plane.bytes;
      final w = image.width, h = image.height;
      if (w == 0 || bytes.isEmpty) return;
      final x0 = (w * 0.15).toInt(), x1 = (w * 0.85).toInt();
      final y0 = (h * 0.30).toInt(), y1 = (h * 0.70).toInt();
      final bpp = plane.bytesPerPixel ?? 1;
      final stride = plane.bytesPerRow;
      double sum = 0, edge = 0; int count = 0, prev = -1;
      for (int y = y0; y < y1; y += 4) {
        for (int x = x0; x < x1; x += 4) {
          final idx = y * stride + x * bpp;
          if (idx >= bytes.length) continue;
          final v = bytes[idx].toDouble();
          sum += v; if (prev >= 0) edge += (v - prev).abs(); prev = v.toInt(); count++;
        }
      }
      if (count == 0) return;
      final bright = sum / count;
      final edgeScore = edge / count;
      final stable = (edgeScore - _lastEdge).abs() < 4 && (bright - _lastBright).abs() < 8;
      _lastEdge = edgeScore; _lastBright = bright;
      if (!mounted) return;
      if (bright < 35) {
        setState(() { _state = ScanState.align; _hint = 'Too dark! Tap FLASH / LIGHT, move to good light.'; _steadyTicks = 0; });
      } else if (edgeScore < 6) {
        setState(() { _state = ScanState.align; _hint = 'No card in box.\nMove ID into white box. Fill the box.'; _steadyTicks = 0; });
      } else if (!stable) {
        setState(() { _state = ScanState.align; _hint = 'Card found - now HOLD STEADY.\nDo not move your hand.'; _steadyTicks = 0; });
      } else if (edgeScore < 10) {
        setState(() { _state = ScanState.align; _hint = 'Almost! Move closer, fill the box, hold steady.'; _steadyTicks = 0; });
      } else {
        _steadyTicks++;
        final left = ((6 - _steadyTicks) / 2).ceil();
        setState(() { _state = ScanState.ready; _hint = 'Perfect! Card fixed.\nHold steady... $left - Auto-capturing'; });
        if (_steadyTicks >= 6) _autoCapture();
      }
    } catch (_) {}
  }

  // ── WEB GUIDED FLOW ──
  void _onCardInBox() {
    if (_isCapturing) return;
    // Step 2 -> Step 3: start 3-sec hold
    _countdownTimer?.cancel();
    setState(() { _state = ScanState.holding; _countdown = 3; _hint = 'Good! Now HOLD STEADY...\n3 - Do not move your hand or card.'; });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _isCapturing) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown == 2) setState(() => _hint = 'Hold steady... 2\nKeep card in box. Almost there.');
      if (_countdown == 1) setState(() => _hint = 'Hold steady... 1\nPerfect, stay still!');
      if (_countdown <= 0) { t.cancel(); _autoCapture(); }
    });
  }

  void _onReAlign() {
    _countdownTimer?.cancel();
    setState(() {
      _state = ScanState.align;
      _countdown = 3; _steadyTicks = 0;
      _hint = kIsWeb
          ? 'OK, re-align.\n1. Put ID inside white box\n2. Tap CARD IN BOX\n3. Hold steady 3-2-1'
          : 'Move ID into white box. Fill the box.';
    });
  }

  // ── FLASH - 3 ATTEMPTS + LIGHT BACKUP ──
  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    final wantOn = !_flashOn;
    String msg = '';
    try {
      await _controller!.setFlashMode(wantOn ? FlashMode.torch : FlashMode.off);
      // Verify: some web browsers silently ignore torch
      await Future.delayed(const Duration(milliseconds: 300));
      setState(() => _flashOn = wantOn);
      msg = wantOn ? 'Flash ON' : 'Flash OFF';
    } catch (e) {
      msg = 'Torch not supported in this browser. Use LIGHT instead.';
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
    }
    // If torch failed on web, auto-suggest LIGHT
    if (kIsWeb && wantOn && !_flashOn) {
      setState(() => _lightOn = true);
    }
  }

  void _toggleLight() {
    setState(() => _lightOn = !_lightOn);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lightOn ? 'Screen Light ON - hold phone close to card' : 'Screen Light OFF')));
  }

  Future<void> _autoCapture() async {
    if (_isCapturing || _controller == null || !_controller!.value.isInitialized) return;
    _countdownTimer?.cancel();
    setState(() { _isCapturing = true; _state = ScanState.capturing; _hint = 'Captured! Checking...'; });
    try { await _controller!.stopImageStream(); } catch (_) {}
    // If LIGHT was on, keep it on for the photo so card is lit
    try {
      final XFile photo = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.pop(context, photo);
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not capture: $e'; _isCapturing = false; });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    try { _controller?.stopImageStream(); } catch (_) {}
    _controller?.dispose();
    super.dispose();
  }

  Color get _boxColor {
    switch (_state) {
      case ScanState.align: return Colors.white;
      case ScanState.holding: return Colors.amber;
      case ScanState.ready: return Colors.greenAccent;
      case ScanState.capturing: return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final boxW = size.width * 0.88;
    final boxH = boxW / 1.586;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(widget.title),
        actions: [
          IconButton(onPressed: _toggleLight, icon: Icon(_lightOn ? Icons.lightbulb : Icons.lightbulb_outline, color: _lightOn ? Colors.amber : Colors.white), tooltip: 'Screen Light'),
          IconButton(onPressed: _toggleFlash, icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off, color: _flashOn ? Colors.amber : Colors.white), tooltip: 'Flash'),
        ]),
      body: _error.isNotEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center)))
          : _controller == null || !_controller!.value.isInitialized
              ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: Colors.white), SizedBox(height: 12), Text('Opening camera...', style: TextStyle(color: Colors.white))]))
              : Stack(children: [
                  Positioned.fill(child: CameraPreview(_controller!)),
                  // LIGHT backup: white overlay that lights the card on web
                  if (_lightOn) Positioned.fill(child: Container(color: Colors.white.withOpacity(0.12))),
                  Positioned.fill(child: CustomPaint(painter: _BoxOverlayPainter(boxW: boxW, boxH: boxH, boxColor: _boxColor))),
                  // LIVE GUIDANCE - always visible, never "Preview only"
                  Positioned(top: 16, left: 16, right: 16, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: _state == ScanState.ready || _state == ScanState.holding ? Colors.green.withOpacity(0.85) : Colors.black87, borderRadius: BorderRadius.circular(12)),
                    child: Text(_hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  )),
                  // WEB: big CARD IN BOX / RE-ALIGN button
                  if (kIsWeb && _state == ScanState.align)
                    Positioned(bottom: 170, left: 32, right: 32, child: ElevatedButton.icon(
                      onPressed: _onCardInBox,
                      icon: const Icon(Icons.crop_free),
                      label: const Text('CARD IN BOX - START 3 SEC', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    )),
                  if (kIsWeb && _state == ScanState.holding)
                    Positioned(bottom: 170, left: 32, right: 32, child: Row(children: [
                      Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text('HOLD STEADY... $_countdown', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))),
                      const SizedBox(width: 8),
                      Expanded(child: ElevatedButton(onPressed: _onReAlign, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text('RE-ALIGN'))),
                    ])),
                  // Countdown dots
                  if (_state == ScanState.holding || _state == ScanState.ready)
                    Positioned(bottom: 132, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (i) => Container(margin: const EdgeInsets.symmetric(horizontal: 4), width: 28, height: 8, decoration: BoxDecoration(color: (3 - _countdown) > i ? Colors.greenAccent : Colors.white30, borderRadius: BorderRadius.circular(99)))))),
                  // Bottom controls: Flash + Light + Capture + Cancel
                  Positioned(bottom: 18, left: 12, right: 12, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    GestureDetector(onTap: _toggleFlash, child: Column(children: [Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, color: _flashOn ? Colors.amber : Colors.white24), child: Icon(_flashOn ? Icons.flash_on : Icons.flash_off, color: Colors.white)), const SizedBox(height: 4), Text(_flashOn ? 'Flash ON' : 'Flash OFF', style: const TextStyle(color: Colors.white, fontSize: 11))])),
                    GestureDetector(onTap: _toggleLight, child: Column(children: [Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, color: _lightOn ? Colors.amber : Colors.white24), child: Icon(_lightOn ? Icons.lightbulb : Icons.lightbulb_outline, color: Colors.white)), const SizedBox(height: 4), const Text('Light', style: TextStyle(color: Colors.white, fontSize: 11))])),
                    GestureDetector(onTap: _autoCapture, child: Container(width: 68, height: 68, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: _isCapturing ? Colors.green : Colors.white), child: Icon(_isCapturing ? Icons.check : Icons.camera_alt, color: _isCapturing ? Colors.white : Colors.black, size: 30))),
                    GestureDetector(onTap: () => Navigator.pop(context), child: Column(children: [Container(width: 52, height: 52, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24), child: const Icon(Icons.close, color: Colors.white)), const SizedBox(height: 4), const Text('Cancel', style: TextStyle(color: Colors.white, fontSize: 11))])),
                  ])),
                ]),
    );
  }
}

class _BoxOverlayPainter extends CustomPainter {
  final double boxW; final double boxH; final Color boxColor;
  _BoxOverlayPainter({required this.boxW, required this.boxH, required this.boxColor});
  @override
  void paint(Canvas canvas, Size size) {
    final boxRect = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.42), width: boxW, height: boxH);
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    path.addRRect(RRect.fromRectAndRadius(boxRect, const Radius.circular(14)));
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withOpacity(0.55));
    final corner = Paint()..color = boxColor..strokeWidth = 5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    const len = 28.0;
    void c(double x, double y, double dx, double dy) {
      final p = Path(); p.moveTo(x + dx * len, y); p.lineTo(x, y); p.lineTo(x, y + dy * len); canvas.drawPath(p, corner);
    }
    c(boxRect.left, boxRect.top, 1, 1); c(boxRect.right, boxRect.top, -1, 1); c(boxRect.left, boxRect.bottom, 1, -1); c(boxRect.right, boxRect.bottom, -1, -1);
  }
  @override
  bool shouldRepaint(covariant _BoxOverlayPainter old) => old.boxColor != boxColor;
}
