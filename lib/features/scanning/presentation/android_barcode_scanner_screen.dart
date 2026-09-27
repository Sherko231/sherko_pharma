import 'dart:async';
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

  const horizontalPadding = 16.0;
  const verticalPadding = 12.0;
  final availableWidth = math.max(0.0, size.width - (horizontalPadding * 2));
  final availableHeight = math.max(0.0, size.height - (verticalPadding * 2));
  final width = math.min(420.0, availableWidth);
  final preferredHeight = math.max(72.0, width * 0.28);
  final height = math.min(104.0, math.min(preferredHeight, availableHeight));

  return Rect.fromCenter(
    center: size.center(Offset.zero),
    width: width,
    height: height,
  );
}


class BarcodePresentationGate {
  BarcodePresentationGate({
    this.releaseAfter = const Duration(milliseconds: 650),
  });

  final Duration releaseAfter;
  String? _lockedCode;
  DateTime? _lastSeen;

  String? get lockedCode => _lockedCode;

  void observe(Iterable<String> codes, DateTime now) {
    final locked = _lockedCode;
    if (locked != null && codes.contains(locked)) {
      _lastSeen = now;
    }
  }

  String? nextCandidate(Iterable<String> codes) {
    final locked = _lockedCode;
    for (final code in codes) {
      if (code.isNotEmpty && code != locked) {
        return code;
      }
    }
    return null;
  }

  void lock(String code, DateTime now) {
    _lockedCode = code;
    _lastSeen = now;
  }

  void releaseIfAbsent(DateTime now) {
    final lastSeen = _lastSeen;
    if (_lockedCode == null || lastSeen == null) {
      return;
    }
    if (now.difference(lastSeen) >= releaseAfter) {
      _lockedCode = null;
      _lastSeen = null;
    }
  }
}

class AndroidBarcodeScannerPanel extends ConsumerStatefulWidget {
  const AndroidBarcodeScannerPanel({
    super.key,
    required this.onClose,
  });

  final VoidCallback onClose;

  @override
  ConsumerState<AndroidBarcodeScannerPanel> createState() =>
      _AndroidBarcodeScannerPanelState();
}

class _AndroidBarcodeScannerPanelState
    extends ConsumerState<AndroidBarcodeScannerPanel>
    with WidgetsBindingObserver {
  static const _releasePoll = Duration(milliseconds: 150);

  late final MobileScannerController _camera;
  late final BarcodeScanController _scan;
  final BarcodePresentationGate _presentationGate = BarcodePresentationGate();
  Timer? _releaseTimer;
  bool _processing = false;
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
    _releaseTimer = Timer.periodic(_releasePoll, (_) => _releaseCodeIfAbsent());
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
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
        _camera.start();
        break;
    }
  }

  void _releaseCodeIfAbsent() {
    _presentationGate.releaseIfAbsent(DateTime.now());
  }

  Future<void> _detected(BarcodeCapture capture) async {
    final values = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (values.isEmpty) {
      return;
    }

    final now = DateTime.now();
    _presentationGate.observe(values, now);

    if (_processing) {
      return;
    }

    final code = _presentationGate.nextCandidate(values);
    if (code == null) {
      return;
    }

    setState(() {
      _processing = true;
      _message = 'Checking...';
    });

    final result = await _scan.accept(code);
    if (!mounted) {
      return;
    }

    _presentationGate.lock(code, DateTime.now());

    setState(() {
      _processing = false;
      _message = _messageFor(result);
    });
  }

  String _messageFor(BarcodeScanResult? result) {
    if (result == null) {
      return 'Ready for the next barcode.';
    }

    final productName = result.product?.displayName;
    return switch (result.status) {
      BarcodeScanStatus.added =>
        productName == null ? 'Product added.' : '$productName added.',
      BarcodeScanStatus.incremented => productName == null
          ? 'Quantity increased.'
          : '$productName quantity increased.',
      BarcodeScanStatus.unknown => 'Barcode not found.',
      BarcodeScanStatus.ambiguous => 'Barcode matches more than one product.',
      BarcodeScanStatus.invalidPrice =>
        'Product price is not valid for an order.',
      BarcodeScanStatus.overflow => 'Order amount is too large.',
      BarcodeScanStatus.failed =>
        'Could not verify this barcode. Check the connection.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('android-barcode-scanner-panel'),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Barcode scanner',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                IconButton(
                  key: const Key('scanner-close'),
                  tooltip: 'Close scanner',
                  onPressed: widget.onClose,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SizedBox(
                  height: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
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
                              padding: const EdgeInsets.all(16),
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
                ),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_processing) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      _message!,
                      key: const Key('scanner-status'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BarcodeScannerOverlay extends StatelessWidget {
  const _BarcodeScannerOverlay({required this.scanWindow});

  final Rect scanWindow;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BarcodeScannerOverlayPainter(scanWindow: scanWindow),
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
      const Radius.circular(12),
    );

    final shadePath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(cutout);
    canvas.drawPath(
      shadePath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.black45,
    );

    canvas.drawRRect(
      cutout,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );

    canvas.drawLine(
      Offset(scanWindow.left + 18, scanWindow.center.dy),
      Offset(scanWindow.right - 18, scanWindow.center.dy),
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
