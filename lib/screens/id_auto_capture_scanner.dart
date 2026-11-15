import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// V9 - COMPLETE FILE. Force BACK camera, auto-retry if locked by other app. Auto-resume camera when you return to app. Light also restarts camera. Replace ALL of lib/screens/id_auto_capture_scanner.dart with this.
// Fixes: black preview (low res on web), build errors, missing getters.
// Camera stays INSIDE the app - it does NOT open phone Camera app.

enum ScanState { align, holding, ready, capturing }

class IdAutoCaptureScanner extends StatefulWidget {
  final String title;
  final bool isFront;
  const IdAutoCaptureScanner({super.key, required this.title, required this.isFront});
  @override
  State<IdAutoCaptureScanner> createState() => _IdAutoCaptureScannerState();
}

class _IdAutoCaptureScannerState extends State<IdAutoCaptureScanner> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  String _error = '';
  String _camStatus = 'Opening camera...';
  bool _flashOn = false;
  bool _lightOn = false;
  bool _isCapturing = false;
  ScanState _state = ScanState.align;
  String _hint = 'Put your ID inside the white box.\nFill the box. No glare.';
  int _countdown = 3;
  Timer? _countdownTimer;

  @override
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  // V8 FIX: When you leave the app and come back, Android kills the camera.
  // This auto-restarts it - you do NOT need to open phone Camera app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Small delay so Chrome / Android releases the camera first
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && (_controller == null || !_controller!.value.isInitialized)) {
          _initCamera();
        }
      });
    }
  }

  Future<void> _initCamera({int? useIndex}) async {
    _countdownTimer?.cancel();
    try { await _controller?.dispose(); } catch (_) {}
    if (!mounted) return;
    setState(() { _controller = null; _error = ''; _camStatus = 'Opening camera...'; _state = ScanState.align; });
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) { setState(() { _error = 'No camera found on this phone.\nClose Camera / WhatsApp app and try again.'; _camStatus = 'No camera found'; }); return; }
      // V9: ALWAYS try BACK camera first - FRONT is selfie, wrong for ID card.
      int idx;
      if (useIndex != null) {
        idx = useIndex;
      } else {
        idx = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        if (idx < 0) idx = 0;
      }
      if (idx < 0) idx = 0;
      _cameraIndex = idx;
      final controller = CameraController(_cameras[idx], kIsWeb ? ResolutionPreset.low : ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _camStatus = 'Camera ON - ${_cameras[idx].lensDirection == CameraLensDirection.back ? "Back camera" : "FRONT selfie camera - TAP SWITCH!"}';
        _hint = _cameras[idx].lensDirection == CameraLensDirection.back
            ? 'Camera is ON inside this box.\nDo NOT open phone Camera app.\n1. Put ID inside white box\n2. Tap CARD IN BOX\n3. Hold steady 3-2-1'
            : 'YOU ARE ON FRONT SELFIE CAMERA!\nThis is wrong for ID card.\nTap SWITCH CAMERA below to go to BACK camera.';
      });
    } catch (e) {
      if (mounted) setState(() { _error = 'Camera blocked: $e\n\nCAMERA IS STILL HELD BY ANOTHER APP.\n1. Close Phone Camera / WhatsApp / Facebook\n2. Restart phone (best fix)\n3. Come back and tap RETRY CAMERA'; _camStatus = 'Camera BLOCKED'; });
      // V9: if camera is locked by another app, wait 1.5s and try once more
      // in case the other app just released it.
      if ('$e'.contains('cameraNotReadable') || '$e'.contains('CameraException')) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted && (_controller == null || !_controller!.value.isInitialized)) _initCamera();
        });
      }
    }
  }

  void _onCardInBox() {
    if (_isCapturing) return;
    _countdownTimer?.cancel();
    setState(() { _state = ScanState.holding; _countdown = 3; _hint = 'Good! HOLD STEADY...\n3 - Do not move.'; });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _isCapturing) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown == 2) setState(() => _hint = 'Hold steady... 2\nKeep card in box.');
      if (_countdown == 1) setState(() => _hint = 'Hold steady... 1\nPerfect, stay still!');
      if (_countdown <= 0) { t.cancel(); _autoCapture(); }
    });
  }

  void _onReAlign() {
    _countdownTimer?.cancel();
    setState(() { _state = ScanState.align; _countdown = 3; _hint = 'OK, re-align.\n1. Put ID in white box\n2. Tap CARD IN BOX\n3. Hold steady 3-2-1'; });
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    final wantOn = !_flashOn;
    try {
      await _controller!.setFlashMode(wantOn ? FlashMode.torch : FlashMode.off);
      setState(() => _flashOn = wantOn);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(wantOn ? 'Flash ON - torch is on inside this screen' : 'Flash OFF')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Torch blocked by browser. Use LIGHT instead.')));
      setState(() => _lightOn = true);
    }
  }

  void _toggleLight() {
    // V8 FIX: If camera is OFF, Light alone cannot turn it on.
    // So Light now ALSO restarts the camera.
    if (_controller == null || !_controller!.value.isInitialized) {
      _initCamera();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Camera was OFF - restarting camera now... Do NOT open phone Camera app.')));
    }
    setState(() => _lightOn = !_lightOn);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lightOn ? 'Light ON - bright screen to light card' : 'Light OFF')));
  }

  void _switchCamera() {
    if (_cameras.length < 2) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only 1 camera found on this phone'))); return; }
    final next = (_cameraIndex + 1) % _cameras.length;
    _initCamera(useIndex: next);
  }

  Future<void> _autoCapture() async {
    if (_isCapturing || _controller == null || !_controller!.value.isInitialized) return;
    _countdownTimer?.cancel();
    setState(() { _isCapturing = true; _state = ScanState.capturing; _hint = 'Captured! Checking...'; });
    try {
      final XFile photo = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.pop(context, photo);
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not capture: $e'; _isCapturing = false; _state = ScanState.align; });
    }
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); _countdownTimer?.cancel(); _controller?.dispose(); super.dispose(); }

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
    final previewOk = _controller != null && _controller!.value.isInitialized && _error.isEmpty;
    final List<Widget> stackChildren = [];
    if (previewOk) {
      stackChildren.add(Positioned.fill(child: CameraPreview(_controller!)));
    } else {
      stackChildren.add(Positioned.fill(child: Container(color: Colors.black, padding: const EdgeInsets.all(24), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.videocam_off, color: Colors.white54, size: 64),
        const SizedBox(height: 12),
        Text(_error.isEmpty ? 'Camera is starting...\nIf it stays black, tap RETRY CAMERA below' : _error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15)),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: () => _initCamera(), icon: const Icon(Icons.refresh), label: const Text('RETRY CAMERA')),
        const SizedBox(height: 8),
        ElevatedButton.icon(onPressed: _switchCamera, icon: const Icon(Icons.switch_camera), label: const Text('SWITCH CAMERA - GO TO BACK'), style: ElevatedButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white)),
      ])))));
    }
    if (previewOk) {
      if (_lightOn) stackChildren.add(Positioned.fill(child: Container(color: Colors.white.withOpacity(0.12))));
      stackChildren.add(Positioned.fill(child: CustomPaint(painter: _BoxOverlayPainter(boxW: boxW, boxH: boxH, boxColor: _boxColor))));
    }
    stackChildren.add(Positioned(top: 8, left: 16, right: 16, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(99)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: previewOk ? Colors.green : Colors.red)),
      const SizedBox(width: 6),
      Flexible(child: Text(_camStatus, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
    ]))));
    stackChildren.add(Positioned(top: 44, left: 16, right: 16, child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: _state == ScanState.ready || _state == ScanState.holding ? Colors.green.withOpacity(0.9) : Colors.black87, borderRadius: BorderRadius.circular(12)), child: Text(_hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)))));
    if (previewOk && kIsWeb && _state == ScanState.align) {
      stackChildren.add(Positioned(bottom: 170, left: 32, right: 32, child: ElevatedButton.icon(onPressed: _onCardInBox, icon: const Icon(Icons.crop_free), label: const Text('CARD IN BOX - START 3 SEC', style: TextStyle(fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))));
    }
    if (previewOk && kIsWeb && _state == ScanState.holding) {
      stackChildren.add(Positioned(bottom: 170, left: 32, right: 32, child: Row(children: [
        Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text('HOLD STEADY... $_countdown', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))),
        const SizedBox(width: 8),
        Expanded(child: ElevatedButton(onPressed: _onReAlign, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text('RE-ALIGN'))),
      ])));
    }
    if (previewOk && (_state == ScanState.holding || _state == ScanState.ready)) {
      stackChildren.add(Positioned(bottom: 132, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (i) => Container(margin: const EdgeInsets.symmetric(horizontal: 4), width: 28, height: 8, decoration: BoxDecoration(color: (3 - _countdown) > i ? Colors.greenAccent : Colors.white30, borderRadius: BorderRadius.circular(99)))))));
    }
    stackChildren.add(Positioned(bottom: 18, left: 12, right: 12, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      GestureDetector(onTap: _toggleFlash, child: Column(children: [Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, color: _flashOn ? Colors.amber : Colors.white24), child: Icon(_flashOn ? Icons.flash_on : Icons.flash_off, color: Colors.white)), const SizedBox(height: 4), Text(_flashOn ? 'Flash ON' : 'Flash OFF', style: const TextStyle(color: Colors.white, fontSize: 11))])),
      GestureDetector(onTap: _toggleLight, child: Column(children: [Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, color: _lightOn ? Colors.amber : Colors.white24), child: Icon(_lightOn ? Icons.lightbulb : Icons.lightbulb_outline, color: Colors.white)), const SizedBox(height: 4), const Text('Light', style: TextStyle(color: Colors.white, fontSize: 11))])),
      GestureDetector(onTap: _autoCapture, child: Container(width: 68, height: 68, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: _isCapturing ? Colors.green : Colors.white), child: Icon(_isCapturing ? Icons.check : Icons.camera_alt, color: _isCapturing ? Colors.white : Colors.black, size: 30))),
      GestureDetector(onTap: () => Navigator.pop(context), child: Column(children: [Container(width: 52, height: 52, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24), child: const Icon(Icons.close, color: Colors.white)), const SizedBox(height: 4), const Text('Cancel', style: TextStyle(color: Colors.white, fontSize: 11))])),
    ])));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(widget.title), actions: [
        IconButton(onPressed: _toggleLight, icon: Icon(_lightOn ? Icons.lightbulb : Icons.lightbulb_outline, color: _lightOn ? Colors.amber : Colors.white)),
        IconButton(onPressed: _toggleFlash, icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off, color: _flashOn ? Colors.amber : Colors.white)),
        IconButton(onPressed: _switchCamera, icon: const Icon(Icons.switch_camera, color: Colors.white)),
      ]),
      body: Stack(children: stackChildren),
    );
  }
}

class _BoxOverlayPainter extends CustomPainter {
  final double boxW;
  final double boxH;
  final Color boxColor;
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
    void c(double x, double y, double dx, double dy) { final p = Path(); p.moveTo(x + dx * len, y); p.lineTo(x, y); p.lineTo(x, y + dy * len); canvas.drawPath(p, corner); }
    c(boxRect.left, boxRect.top, 1, 1);
    c(boxRect.right, boxRect.top, -1, 1);
    c(boxRect.left, boxRect.bottom, 1, -1);
    c(boxRect.right, boxRect.bottom, -1, -1);
  }
  @override
  bool shouldRepaint(covariant _BoxOverlayPainter old) => old.boxColor != boxColor;
}
