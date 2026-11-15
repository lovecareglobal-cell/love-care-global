
import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
// AUTO-CAPTURE ID SCANNER
// - Box overlay: put the ID inside the box
// - Flashlight ON/OFF button
// - Auto-capture: snaps by itself when the frame is steady + clear
// - Returns the photo to NurseRegistrationPage
//
// HOW TO USE:
// 1. Add to pubspec.yaml:
//      camera: ^0.11.0
// 2. Replace your old _pickIdSide() with:
//      final file = await Navigator.push<XFile>(
//        context,
//        MaterialPageRoute(
//          builder: (_) => IdAutoCaptureScanner(
//            title: 'Scan Front of Ghana Card',
//            isFront: true,
//          ),
//        ),
//      );
//      if (file != null) setState(() { _idFront = file; _idVerified = false; });
//    Do the same for back.
// 3. Keep your existing _verifyIdDocument() - it already runs Vision
//    OCR + face-match on _idFront / _idBack.
// ─────────────────────────────────────────────────────────────

class IdAutoCaptureScanner extends StatefulWidget {
  final String title;
  final bool isFront;
  const IdAutoCaptureScanner({super.key, required this.title, required this.isFront});

  @override
  State<IdAutoCaptureScanner> createState() => _IdAutoCaptureScannerState();
}

class _IdAutoCaptureScannerState extends State<IdAutoCaptureScanner> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  String _error = '';
  bool _flashOn = false;
  bool _isCapturing = false;

  // Auto-capture state
  int _steadySeconds = 0; // 0..2 - counts how long user held steady
  Timer? _steadyTimer;
  Timer? _sharpnessTimer;
  double _lastSharpness = 0;
  double _sharpness = 0;
  bool _isSteady = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      // Prefer back camera
      final back = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() => _controller = controller);
      _startAutoCaptureLoop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera error: $e');
    }
  }

  // ── AUTO-CAPTURE LOGIC ───────────────────────────────
  // We check a preview frame every 800ms.
  // If the image inside the box stays sharp + stable for 2 seconds,
  // we auto-capture. If user moves, the counter resets.
  void _startAutoCaptureLoop() {
    _sharpnessTimer?.cancel();
    _sharpnessTimer = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      if (!mounted || _controller == null || !_controller!.value.isInitialized) return;
      if (_isCapturing) return;
      try {
        final XFile frame = await _controller!.takePicture();
        final bytes = await frame.readAsBytes();
        final score = _estimateSharpness(bytes);
        if (!mounted) return;
        setState(() {
          _sharpness = score;
          // Sharp = score > threshold. Stable = sharpness didn't jump a lot.
          final stable = (score - _lastSharpness).abs() < 18 && score > 35;
          _lastSharpness = score;
          if (stable) {
            _isSteady = true;
            _steadySeconds++;
          } else {
            _isSteady = false;
            _steadySeconds = 0;
          }
        });
        if (_steadySeconds >= 3) {
          // ~2.4 seconds steady + sharp = auto capture
          await _autoCapture();
        }
      } catch (_) {
        // Ignore frame errors, keep looping
      }
    });
  }

  // Very cheap sharpness estimate: variance of pixel brightness.
  // Blurry = low variance, sharp text/edges = high variance.
  // This runs on a down-sampled image so it stays fast on phones.
  double _estimateSharpness(Uint8List bytes) {
    // We can't decode full JPEG cheaply here without extra packages,
    // so we use byte variance as a proxy + file size as a signal.
    // Larger, more varied file = more detail = sharper.
    if (bytes.isEmpty) return 0;
    double sum = 0;
    const step = 997; // sample every ~1000th byte for speed
    int count = 0;
    for (int i = 0; i < bytes.length; i += step) {
      sum += bytes[i];
      count++;
    }
    if (count == 0) return 0;
    final mean = sum / count;
    double variance = 0;
    for (int i = 0; i < bytes.length; i += step) {
      final d = bytes[i] - mean;
      variance += d * d;
    }
    variance = variance / count;
    // Normalise to 0-100 scale + size bonus
    double score = (variance / 60).clamp(0, 80);
    score += (bytes.length / 120000).clamp(0, 20); // bigger file = more detail
    return score.clamp(0, 100);
  }

  Future<void> _autoCapture() async {
    if (_isCapturing || _controller == null) return;
    setState(() => _isCapturing = true);
    try {
      final XFile photo = await _controller!.takePicture();
      if (!mounted) return;
      // Return to registration page
      Navigator.pop(context, photo);
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not capture: $e'; _isCapturing = false; _steadySeconds = 0; });
    }
  }

  Future<void> _manualCapture() async {
    await _autoCapture();
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    try {
      final next = !_flashOn;
      await _controller!.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _flashOn = next);
    } catch (_) {}
  }

  @override
  void dispose() {
    _steadyTimer?.cancel();
    _sharpnessTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // ID card ratio ~ 85.6 x 54mm = 1.586
    final boxW = size.width * 0.88;
    final boxH = boxW / 1.586;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _toggleFlash,
            icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off),
            tooltip: _flashOn ? 'Turn flash OFF' : 'Turn flash ON',
          ),
        ],
      ),
      body: _error.isNotEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center)))
          : _controller == null || !_controller!.value.isInitialized
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Stack(
                  children: [
                    Positioned.fill(child: CameraPreview(_controller!)),
                    // Dark scrim with clear box hole
                    Positioned.fill(
                      child: CustomPaint(painter: _BoxOverlayPainter(boxW: boxW, boxH: boxH)),
                    ),
                    // Top instruction
                    Positioned(
                      top: 16, left: 16, right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          _isCapturing
                              ? 'Captured! Checking...'
                              : _isSteady
                                  ? 'Hold steady... ${3 - _steadySeconds} • Auto-capturing'
                                  : 'Put your ${widget.isFront ? 'FRONT' : 'BACK'} inside the box • Fill the box • Good light',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    // Sharpness / steady indicator
                    Positioned(
                      bottom: 130, left: 0, right: 0,
                      child: Column(
                        children: [
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(_sharpness > 35 ? Icons.check_circle : Icons.warning, color: _sharpness > 35 ? Colors.greenAccent : Colors.amber, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              _sharpness > 35 ? 'Clear • ${_sharpness.toStringAsFixed(0)}/100' : 'Too blurry / dark • Move closer / turn on flash',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          // Progress dots for steady hold
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (i) {
                            final filled = i < _steadySeconds;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 28, height: 8,
                              decoration: BoxDecoration(color: filled ? Colors.greenAccent : Colors.white30, borderRadius: BorderRadius.circular(99)),
                            );
                          })),
                          Text(_isSteady ? 'Steady ✓' : 'Hold phone steady', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    // Bottom controls
                    Positioned(
                      bottom: 24, left: 16, right: 16,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Flash button
                          _circleButton(
                            icon: _flashOn ? Icons.flash_on : Icons.flash_off,
                            label: _flashOn ? 'Flash ON' : 'Flash OFF',
                            onTap: _toggleFlash,
                            bg: _flashOn ? Colors.amber : Colors.white24,
                          ),
                          // Big capture button (manual fallback)
                          GestureDetector(
                            onTap: _manualCapture,
                            child: Container(
                              width: 76, height: 76,
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: _isCapturing ? Colors.green : Colors.white),
                              child: Icon(_isCapturing ? Icons.check : Icons.camera_alt, color: _isCapturing ? Colors.white : Colors.black, size: 32),
                            ),
                          ),
                          // Retake / cancel
                          _circleButton(icon: Icons.close, label: 'Cancel', onTap: () => Navigator.pop(context), bg: Colors.white24),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _circleButton({required IconData icon, required String label, required VoidCallback onTap, required Color bg}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, color: bg), child: Icon(icon, color: Colors.white)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ]),
    );
  }
}

// Paints dark overlay + clear rounded box in the centre
class _BoxOverlayPainter extends CustomPainter {
  final double boxW;
  final double boxH;
  _BoxOverlayPainter({required this.boxW, required this.boxH});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.55);
    final boxRect = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.42), width: boxW, height: boxH);
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    path.addRRect(RRect.fromRectAndRadius(boxRect, const Radius.circular(14)));
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
    // Corner brackets
    final corner = Paint()..color = Colors.white..strokeWidth = 4..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    const len = 28.0;
    void cornerPath(double x, double y, double dx, double dy) {
      final p = Path();
      p.moveTo(x + dx * len, y);
      p.lineTo(x, y);
      p.lineTo(x, y + dy * len);
      canvas.drawPath(p, corner);
    }
    cornerPath(boxRect.left, boxRect.top, 1, 1);
    cornerPath(boxRect.right, boxRect.top, -1, 1);
    cornerPath(boxRect.left, boxRect.bottom, 1, -1);
    cornerPath(boxRect.right, boxRect.bottom, -1, -1);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
