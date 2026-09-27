import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../catalog/application/catalog_search_controller.dart';
import '../../order/application/order_controller.dart';
import '../application/barcode_scan_controller.dart';

Rect barcodeScanWindowForSize(Size size) {
  if (size.isEmpty) {
    return Rect.zero;
  }

  const horizontalPadding = 24.0;
  final availableWidth = math.max(0.0, size.width - (horizontalPadding * 2));
  final width = math.min(420.0, availableWidth);
  final preferredHeight = math.max(96.0, width * 0.32);
  final height = math.min(preferredHeight, size.height * 0.32);

  return Rect.fromCenter(
    center: size.center(Offset.zero),
    width: width,
    height: height,
  );
}

class AndroidBarcodeScannerScreen extends ConsumerStatefulWidget {
  const AndroidBarcodeScannerScreen({super.key});

  @override
  ConsumerState<AndroidBarcodeScannerScreen> createState() =>
      _AndroidBarcodeScannerScreenState();
}

class _AndroidBarcodeScannerScreenState
    extends ConsumerState<AndroidBarcodeScannerScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _camera;
  late final BarcodeScanController _scan;
  bool _accepting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 100,
      autoZoom: true,
    );
    _scan = BarcodeScanController(
      catalog: ref.read(catalogRepositoryProvider),
      order: ref.read(orderControllerProvider.notifier),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_camera.value.hasCameraPermission) {
      return;
    }
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _camera.stop();
        break;
      case AppLifecycleState.resumed:
        if (!_accepting) {
          _camera.start();
        }
        break;
    }
  }

  Future<void> _detected(BarcodeCapture capture) async {
    if (_accepting) return;

    String? code;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        code = value;
        break;
      }
    }
    if (code == null) return;

    setState(() {
      _accepting = true;
      _message = 'Checking barcode...';
    });
    await _camera.pause();
    final result = await _scan.accept(code);
    if (!mounted) return;

    if (result == null) {
      await _rearm();
      return;
    }

    switch (result.status) {
      case BarcodeScanStatus.added:
      case BarcodeScanStatus.incremented:
        Navigator.of(context).pop(result);
        return;
      case BarcodeScanStatus.unknown:
        _message = 'Barcode not found.';
        break;
      case BarcodeScanStatus.ambiguous:
        _message = 'Barcode matches more than one product.';
        break;
      case BarcodeScanStatus.invalidPrice:
        _message = 'Product price is not valid for an order.';
        break;
      case BarcodeScanStatus.overflow:
        _message = 'Order amount is too large to calculate safely.';
        break;
      case BarcodeScanStatus.failed:
        _message =
            'Could not verify this barcode. Check the connection and try again.';
        break;
    }
    setState(() {});
  }

  Future<void> _rearm() async {
    if (!mounted) return;
    setState(() {
      _accepting = false;
      _message = null;
    });
    await _camera.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan barcode')),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scanWindow = barcodeScanWindowForSize(
                  Size(constraints.maxWidth, constraints.maxHeight),
                );

                return MobileScanner(
                  key: const Key('android-barcode-camera'),
                  controller: _camera,
                  onDetect: _detected,
                  scanWindow: scanWindow,
                  scanWindowUpdateThreshold: 0.01,
                  tapToFocus: true,
                  overlayBuilder: (context, constraints) =>
                      _BarcodeScannerOverlay(scanWindow: scanWindow),
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        error.errorCode ==
                                MobileScannerErrorCode.permissionDenied
                            ? 'Camera permission is required to scan barcodes.'
                            : 'Camera is unavailable. Close other camera apps and try again.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(_message!, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  if (_accepting)
                    OutlinedButton(
                      key: const Key('scanner-try-again'),
                      onPressed: _rearm,
                      child: const Text('Try again'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BarcodeScannerOverlay extends StatelessWidget {
  const _BarcodeScannerOverlay({required this.scanWindow});

  final Rect scanWindow;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _BarcodeScannerOverlayPainter(scanWindow: scanWindow),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 24,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(
                  'Align the barcode inside the frame. Tap the screen to focus.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BarcodeScannerOverlayPainter extends CustomPainter {
  const _BarcodeScannerOverlayPainter({required this.scanWindow});

  final Rect scanWindow;

  @override
  void paint(Canvas canvas, Size size) {
    final cutout = RRect.fromRectAndRadius(
      scanWindow,
      const Radius.circular(16),
    );

    final shadePath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(cutout);
    canvas.drawPath(
      shadePath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.black54,
    );

    canvas.drawRRect(
      cutout,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );

    canvas.drawLine(
      Offset(scanWindow.left + 20, scanWindow.center.dy),
      Offset(scanWindow.right - 20, scanWindow.center.dy),
      Paint()
        ..strokeWidth = 2
        ..color = Colors.white70,
    );
  }

  @override
  bool shouldRepaint(covariant _BarcodeScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow;
  }
}
