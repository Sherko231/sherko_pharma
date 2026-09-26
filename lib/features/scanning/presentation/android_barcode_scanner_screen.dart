import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../catalog/application/catalog_search_controller.dart';
import '../../order/application/order_controller.dart';
import '../application/barcode_scan_controller.dart';

class AndroidBarcodeScannerScreen extends ConsumerStatefulWidget {
  const AndroidBarcodeScannerScreen({super.key});

  @override
  ConsumerState<AndroidBarcodeScannerScreen> createState() =>
      _AndroidBarcodeScannerScreenState();
}

class _AndroidBarcodeScannerScreenState
    extends ConsumerState<AndroidBarcodeScannerScreen> {
  late final MobileScannerController _camera;
  late final BarcodeScanController _scan;
  bool _accepting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _camera = MobileScannerController(
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.codabar,
        BarcodeFormat.itf,
      ],
    );
    _scan = BarcodeScanController(
      catalog: ref.read(catalogRepositoryProvider),
      order: ref.read(orderControllerProvider.notifier),
    );
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
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
    await _camera.stop();
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
        _message = 'Could not verify this barcode. Check the connection and try again.';
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
            child: MobileScanner(
              key: const Key('android-barcode-camera'),
              controller: _camera,
              onDetect: _detected,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'Camera permission is required to scan barcodes.'
                        : 'Camera is unavailable. Close other camera apps and try again.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
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
