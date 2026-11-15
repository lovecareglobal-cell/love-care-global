
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
    final boxW = size.width * 0.88;
    final boxH = boxW / 1.586;
    final previewOk = _controller != null && _controller!.value.isInitialized && _error.isEmpty;

    final List<Widget> stackChildren = [];

    if (previewOk) {
      stackChildren.add(Positioned.fill(child: CameraPreview(_controller!)));
    } else {
      stackChildren.add(Positioned.fill(
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam_off, color: Colors.white54, size: 64),
                const SizedBox(height: 12),
                Text(
                  _error.isEmpty ? 'Camera is starting...\nIf it stays black, tap RETRY CAMERA below' : _error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(onPressed: () => _initCamera(), icon: const Icon(Icons.refresh), label: const Text('RETRY CAMERA')),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _switchCamera,
                  icon: const Icon(Icons.switch_camera),
                  label: const Text('SWITCH CAMERA'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ));
    }

    if (previewOk) {
      if (_lightOn) {
        stackChildren.add(Positioned.fill(child: Container(color: Colors.white.withOpacity(0.12))));
      }
      stackChildren.add(Positioned.fill(child: CustomPaint(painter: _BoxOverlayPainter(boxW: boxW, boxH: boxH, boxColor: _boxColor))));
    }

    stackChildren.add(Positioned(
      top: 8,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(99)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: previewOk ? Colors.green : Colors.red)),
            const SizedBox(width: 6),
            Flexible(child: Text(_camStatus, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    ));

    stackChildren.add(Positioned(
      top: 44,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: _state == ScanState.ready || _state == ScanState.holding ? Colors.green.withOpacity(0.9) : Colors.black87, borderRadius: BorderRadius.circular(12)),
        child: Text(_hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    ));

    if (previewOk && kIsWeb && _state == ScanState.align) {
      stackChildren.add(Positioned(
        bottom: 170,
        left: 32,
        right: 32,
        child: ElevatedButton.icon(
          onPressed: _onCardInBox,
          icon: const Icon(Icons.crop_free),
          label: const Text('CARD IN BOX - START 3 SEC', style: TextStyle(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ));
    }

    if (previewOk && kIsWeb && _state == ScanState.holding) {
      stackChildren.add(Positioned(
        bottom: 170,
        left: 32,
        right: 32,
        child: Row(children: [
          Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text('HOLD STEADY... $_countdown', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton(onPressed: _onReAlign, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text('RE-ALIGN'))),
        ]),
      ));
    }

    if (previewOk && (_state == ScanState.holding || _state == ScanState.ready)) {
      stackChildren.add(Positioned(
        bottom: 132,
        left: 0,
        right: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) => Container(margin: const EdgeInsets.symmetric(horizontal: 4), width: 28, height: 8, decoration: BoxDecoration(color: (3 - _countdown) > i ? Colors.greenAccent : Colors.white30, borderRadius: BorderRadius.circular(99)))),
        ),
      ));
    }

    stackChildren.add(Positioned(
      bottom: 18,
      left: 12,
      right: 12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(onTap: _toggleFlash, child: Column(children: [Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, color: _flashOn ? Colors.amber : Colors.white24), child: Icon(_flashOn ? Icons.flash_on : Icons.flash_off, color: Colors.white)), const SizedBox(height: 4), Text(_flashOn ? 'Flash ON' : 'Flash OFF', style: const TextStyle(color: Colors.white, fontSize: 11))])),
          GestureDetector(onTap: _toggleLight, child: Column(children: [Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, color: _lightOn ? Colors.amber : Colors.white24), child: Icon(_lightOn ? Icons.lightbulb : Icons.lightbulb_outline, color: Colors.white)), const SizedBox(height: 4), const Text('Light', style: TextStyle(color: Colors.white, fontSize: 11))])),
          GestureDetector(onTap: _autoCapture, child: Container(width: 68, height: 68, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: _isCapturing ? Colors.green : Colors.white), child: Icon(_isCapturing ? Icons.check : Icons.camera_alt, color: _isCapturing ? Colors.white : Colors.black, size: 30))),
          GestureDetector(onTap: () => Navigator.pop(context), child: Column(children: [Container(width: 52, height: 52, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24), child: const Icon(Icons.close, color: Colors.white)), const SizedBox(height: 4), const Text('Cancel', style: TextStyle(color: Colors.white, fontSize: 11))])),
        ],
      ),
    ));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          IconButton(onPressed: _toggleLight, icon: Icon(_lightOn ? Icons.lightbulb : Icons.lightbulb_outline, color: _lightOn ? Colors.amber : Colors.white)),
          IconButton(onPressed: _toggleFlash, icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off, color: _flashOn ? Colors.amber : Colors.white)),
          IconButton(onPressed: _switchCamera, icon: const Icon(Icons.switch_camera, color: Colors.white)),
        ],
      ),
      body: Stack(children: stackChildren),
    );
  }
}

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
