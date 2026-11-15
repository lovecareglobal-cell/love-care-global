
import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
// AUTO-CAPTURE ID SCANNER - V3 : REAL BOX CHECK
// How it should behave (what you asked for):
//  1. If NO card in box  -> "Move card into the box, fill the box"
//     + NO countdown, NO auto-capture, waits as long as needed.
//  2. If card PARTLY in box / blurry / too dark -> "Adjust: move closer / turn on flash / hold steady"
//  3. If card PROPERLY FIXED in box + clear + steady for 3 sec
//     -> Countdown 3-2-1 -> Auto-capture ONCE.
//
// How it detects the card WITHOUT ML Kit (so it still works on Web):
//  We use camera imageStream (NOT takePicture - that broke preview in V1).
//  Every ~400ms we check the frame inside the box:
//   - EDGE DENSITY: a card has lots of text/photo edges. A black screen /
//     empty hand / wall has almost no edges.
//   - BRIGHTNESS: too dark = flash needed.
//   - STABILITY: compare this frame to last frame. If user is moving,
//     frames change a lot -> reset countdown.
//  Only when: edges = HIGH + brightness = OK + stability = HIGH
//  for 3 seconds in a row -> capture.
// ─────────────────────────────────────────────────────────────

enum ScanState { noCard, adjusting, ready, capturing }

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
  bool _isCapturing = false;

  ScanState _state = ScanState.noCard;
  String _hint = 'Put your ID inside the box';
  int _steadyCount = 0; // 0..6 = 0..~3 sec (500ms per tick)
  double _lastEdgeScore = 0;
  double _lastBrightness = 0;
  bool _streamStarted = false;
  DateTime _lastCheck = DateTime.now();
  bool _guidanceShown = false;

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
      _startImageAnalysis();
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera error: $e\nAllow camera permission + use HTTPS.');
    }
  }

  void _startImageAnalysis() async {
    if (_controller == null || _streamStarted) return;
    _streamStarted = true;
    try {
      await _controller!.startImageStream((CameraImage image) {
        // Throttle: analyse at most every 500ms, otherwise phone lags
        final now = DateTime.now();
        if (now.difference(_lastCheck).inMilliseconds < 500) return;
        _lastCheck = now;
        if (!mounted || _isCapturing) return;
        _analyseFrame(image);
      });
    } catch (_) {
      // Some browsers don't support imageStream. Fallback: use timer + manual capture.
      // In that case we show "Tap Capture when card is in box" and don't auto-capture.
      if (mounted) setState(() {
        _state = ScanState.adjusting;
        _hint = 'Preview only on this browser.\nPut card in box, then tap the white button to capture.';
      });
    }
  }

  // ── FRAME ANALYSIS ───────────────────────────────
  // We only look at the CENTRE box region (where the card should be).
  // CameraImage planes[0] = Y (brightness) on Android/iOS, BGRA on Web.
  // We handle both by reading bytes as brightness.
  void _analyseFrame(CameraImage image) {
    try {
      final plane = image.planes[0];
      final bytes = plane.bytes;
      final w = image.width;
      final h = image.height;
      if (w == 0 || h == 0 || bytes.isEmpty) return;

      // Centre box: middle 70% width, middle 45% height (matches overlay box)
      final x0 = (w * 0.15).toInt();
      final x1 = (w * 0.85).toInt();
      final y0 = (h * 0.30).toInt();
      final y1 = (h * 0.70).toInt();
      final bytesPerPixel = (plane.bytesPerPixel ?? 1);
      final rowStride = plane.bytesPerRow;

      double sum = 0;
      double edgeSum = 0;
      int count = 0;
      int prev = -1;
      // Sample every 4th pixel for speed
      for (int y = y0; y < y1; y += 4) {
        for (int x = x0; x < x1; x += 4) {
          final idx = y * rowStride + x * bytesPerPixel;
          if (idx >= bytes.length) continue;
          final v = bytes[idx].toDouble();
          sum += v;
          if (prev >= 0) edgeSum += (v - prev).abs();
          prev = v.toInt();
          count++;
        }
      }
      if (count == 0) return;
      final brightness = sum / count; // 0-255
      final edgeScore = edgeSum / count; // higher = more text/edges

      // Stability: how much did edge/brightness change vs last frame?
      final edgeChange = (edgeScore - _lastEdgeScore).abs();
      final brightChange = (brightness - _lastBrightness).abs();
      _lastEdgeScore = edgeScore;
      _lastBrightness = brightness;
      final isStable = edgeChange < 4.0 && brightChange < 8.0;

      // ── DECISION ──
      ScanState newState;
      String newHint;
      int newSteady = _steadyCount;

      if (brightness < 35) {
        // Too dark - can't see card
        newState = ScanState.adjusting;
        newHint = 'Too dark! Tap FLASH ON, move to good light.';
        newSteady = 0;
      } else if (edgeScore < 6) {
        // Almost no edges = no card / black screen / wall / hand only
        newState = ScanState.noCard;
        newHint = 'No card in box.\nMove your ID into the white box. Fill the box.';
        newSteady = 0;
      } else if (!isStable) {
        // Card there but moving / shaky
        newState = ScanState.adjusting;
        newHint = 'Card found - now HOLD STEADY.\nDo not move your hand.';
        newSteady = 0;
      } else if (edgeScore < 10) {
        // Edges but weak = partly in box / blurry / too far
        newState = ScanState.adjusting;
        newHint = 'Almost! Move closer, fill the box, hold steady.';
        newSteady = 0;
      } else {
        // Card in box + clear + steady
        newState = ScanState.ready;
        newSteady = _steadyCount + 1;
        final secsLeft = ((6 - newSteady) / 2).ceil(); // 6 ticks * 500ms = 3 sec
        newHint = 'Perfect! Card fixed in box.\nHold steady... $secsLeft • Auto-capturing';
        if (newSteady >= 6) {
          _autoCapture();
          return;
        }
      }

      if (mounted) {
        setState(() {
          _state = newState;
          _hint = newHint;
          _steadyCount = newSteady;
        });
      }
    } catch (_) {
      // Ignore one bad frame
    }
  }

  Future<void> _autoCapture() async {
    if (_isCapturing || _controller == null || !_controller!.value.isInitialized) return;
    setState(() { _isCapturing = true; _state = ScanState.capturing; _hint = 'Captured! Checking...'; });
    try {
      // Stop stream before taking picture so it doesn't conflict
      await _controller!.stopImageStream();
    } catch (_) {}
    try {
      final XFile photo = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.pop(context, photo);
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not capture: $e'; _isCapturing = false; _steadyCount = 0; });
    }
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
    try { _controller?.stopImageStream(); } catch (_) {}
    _controller?.dispose();
    super.dispose();
  }

  Color get _boxColor {
    switch (_state) {
      case ScanState.noCard: return Colors.white;
      case ScanState.adjusting: return Colors.amber;
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
        actions: [IconButton(onPressed: _toggleFlash, icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off))]),
      body: _error.isNotEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center)))
          : _controller == null || !_controller!.value.isInitialized
              ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: Colors.white), SizedBox(height: 12), Text('Opening camera...', style: TextStyle(color: Colors.white))]))
              : Stack(children: [
                  Positioned.fill(child: CameraPreview(_controller!)),
                  Positioned.fill(child: CustomPaint(painter: _BoxOverlayPainter(boxW: boxW, boxH: boxH, boxColor: _boxColor))),
                  // Guidance banner - THIS is the "fix it" message
                  Positioned(top: 16, left: 16, right: 16, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: _state == ScanState.ready ? Colors.green.withOpacity(0.85) : Colors.black54, borderRadius: BorderRadius.circular(12)),
                    child: Text(_hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  )),
                  // Progress: 6 segments = 3 seconds steady
                  if (_state == ScanState.ready)
                    Positioned(bottom: 132, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(6, (i) => Container(margin: const EdgeInsets.symmetric(horizontal: 3), width: 22, height: 8, decoration: BoxDecoration(color: i < _steadyCount ? Colors.greenAccent : Colors.white30, borderRadius: BorderRadius.circular(99)))))),
                  // Bottom controls
                  Positioned(bottom: 24, left: 16, right: 16, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    GestureDetector(onTap: _toggleFlash, child: Column(children: [Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, color: _flashOn ? Colors.amber : Colors.white24), child: Icon(_flashOn ? Icons.flash_on : Icons.flash_off, color: Colors.white)), const SizedBox(height: 4), Text(_flashOn ? 'Flash ON' : 'Flash OFF', style: const TextStyle(color: Colors.white, fontSize: 11))])),
                    GestureDetector(onTap: _autoCapture, child: Container(width: 76, height: 76, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: _isCapturing ? Colors.green : Colors.white), child: Icon(_isCapturing ? Icons.check : Icons.camera_alt, color: _isCapturing ? Colors.white : Colors.black, size: 32))),
                    GestureDetector(onTap: () => Navigator.pop(context), child: Column(children: [Container(width: 56, height: 56, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24), child: const Icon(Icons.close, color: Colors.white)), const SizedBox(height: 4), const Text('Cancel', style: TextStyle(color: Colors.white, fontSize: 11))])),
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
