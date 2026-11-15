
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// ID Scanner with a box overlay.
/// - Shows live camera preview inside the app (not the phone camera app)
/// - White box in the middle - fit the ID inside it
/// - Capture button takes the photo, returns the file to the caller
/// Usage:
///   final file = await Navigator.push<XFile>(context,
///     MaterialPageRoute(builder: (_) => IdScannerScreen(
///       title: 'Scan Front of Ghana Card',
///       isPassport: false,
///     )));
class IdScannerScreen extends StatefulWidget {
  final String title;
  final bool isPassport; // true = tall box, false = wide card box
  const IdScannerScreen({super.key, required this.title, this.isPassport = false});

  @override
  State<IdScannerScreen> createState() => _IdScannerScreenState();
}

class _IdScannerScreenState extends State<IdScannerScreen> {
  CameraController? _controller;
  Future<void>? _initFuture;
  String _error = '';
  bool _takingPhoto = false;
  bool _flashOn = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      // Prefer back camera
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _initFuture = controller.initialize();
      setState(() => _controller = controller);
      await _initFuture;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open camera: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized || _takingPhoto) return;
    setState(() => _takingPhoto = true);
    try {
      final XFile photo = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.pop(context, photo);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Capture failed: $e')));
        setState(() => _takingPhoto = false);
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    try {
      _flashOn = !_flashOn;
      await _controller!.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const darkPink = Color(0xFF880E4F);
    const pink = Color(0xFFAD1457);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        backgroundColor: darkPink,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off),
            tooltip: 'Flash',
            onPressed: _toggleFlash,
          ),
        ],
      ),
      body: _error.isNotEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center)))
          : _controller == null
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : FutureBuilder(
                  future: _initFuture,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        // Box size: card = wide (85% width, 85/1.586 ratio), passport = taller
                        final boxWidth = constraints.maxWidth * 0.88;
                        final boxHeight = widget.isPassport ? boxWidth * 1.35 : boxWidth / 1.586;
                        return Stack(
                          children: [
                            // Camera preview - fills screen
                            Positioned.fill(child: CameraPreview(_controller!)),
                            // Dark dim outside the box
                            Positioned.fill(
                              child: CustomPaint(painter: _ScannerOverlayPainter(boxWidth: boxWidth, boxHeight: boxHeight)),
                            ),
                            // Instructions + box label
                            Positioned(
                              top: 16,
                              left: 16,
                              right: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(10)),
                                child: const Text(
                                  'Fit your ID INSIDE the white box.\nFill the box, hold steady, good light, no glare.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            // Corner markers are drawn by painter, this is just a label inside box
                            Center(
                              child: SizedBox(
                                width: boxWidth,
                                height: boxHeight,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(6)),
                                    child: Text(widget.isPassport ? 'PASSPORT' : 'ID CARD', style: const TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 2)),
                                  ),
                                ),
                              ),
                            ),
                            // Bottom capture bar
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                color: Colors.black.withOpacity(0.75),
                                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                                    ),
                                    GestureDetector(
                                      onTap: _capture,
                                      child: Container(
                                        width: 72,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 4),
                                          color: _takingPhoto ? Colors.grey : pink,
                                        ),
                                        child: _takingPhoto
                                            ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                                            : const Icon(Icons.camera_alt, color: Colors.white, size: 32),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _toggleFlash,
                                      child: Text(_flashOn ? 'Flash On' : 'Flash Off', style: const TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
    );
  }
}

/// Draws dark overlay everywhere EXCEPT the box, plus white corners.
class _ScannerOverlayPainter extends CustomPainter {
  final double boxWidth;
  final double boxHeight;
  _ScannerOverlayPainter({required this.boxWidth, required this.boxHeight});

  @override
  void paint(Canvas canvas, Size size) {
    final boxLeft = (size.width - boxWidth) / 2;
    final boxTop = (size.height - boxHeight) / 2 - 20;
    final boxRect = Rect.fromLTWH(boxLeft, boxTop, boxWidth, boxHeight);

    // Dark layer with hole
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()..addRect(boxRect);
    final cut = Path.combine(PathOperation.difference, path, hole);
    canvas.drawPath(cut, Paint()..color = Colors.black.withOpacity(0.55));

    // White border
    canvas.drawRect(boxRect, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5);

    // Corner accents
    final cornerLen = 28.0;
    final cornerPaint = Paint()..color = const Color(0xFFAD1457)..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.round;
    void corner(double x1, double y1, double x2, double y2, double x3, double y3) {
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), cornerPaint);
      canvas.drawLine(Offset(x2, y2), Offset(x3, y3), cornerPaint);
    }
    // top-left
    corner(boxRect.left, boxRect.top + cornerLen, boxRect.left, boxRect.top, boxRect.left + cornerLen, boxRect.top);
    // top-right
    corner(boxRect.right - cornerLen, boxRect.top, boxRect.right, boxRect.top, boxRect.right, boxRect.top + cornerLen);
    // bottom-left
    corner(boxRect.left, boxRect.bottom - cornerLen, boxRect.left, boxRect.bottom, boxRect.left + cornerLen, boxRect.bottom);
    // bottom-right
    corner(boxRect.right - cornerLen, boxRect.bottom, boxRect.right, boxRect.bottom, boxRect.right, boxRect.bottom - cornerLen);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter old) => old.boxWidth != boxWidth || old.boxHeight != boxHeight;
}
