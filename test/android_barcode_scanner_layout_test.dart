import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/scanning/application/barcode_scan_controller.dart';
import 'package:sherko_pharma/features/scanning/presentation/android_barcode_scanner_screen.dart';

void main() {
  test('barcode scan window is centered, horizontal, and inside preview', () {
    const preview = Size(360, 640);

    final window = barcodeScanWindowForSize(preview);

    expect(window.center, preview.center(Offset.zero));
    expect(window.left, greaterThanOrEqualTo(0));
    expect(window.top, greaterThanOrEqualTo(0));
    expect(window.right, lessThanOrEqualTo(preview.width));
    expect(window.bottom, lessThanOrEqualTo(preview.height));
    expect(window.width, greaterThan(window.height * 2));
  });

  test('barcode scan window caps width on a large preview', () {
    const preview = Size(1000, 700);

    final window = barcodeScanWindowForSize(preview);

    expect(window.width, 300);
    expect(window.center, preview.center(Offset.zero));
  });

  test('compact phone preview keeps a smaller guide exactly centered', () {
    const preview = Size(340, 112);

    final window = barcodeScanWindowForSize(preview);

    expect(window.center, preview.center(Offset.zero));
    expect(window.width, lessThan(preview.width * 0.8));
    expect(window.height, lessThanOrEqualTo(58));
    expect(window.width, greaterThan(window.height * 4));
  });

  test('barcode scan window remains inside a short landscape preview', () {
    const preview = Size(800, 300);

    final window = barcodeScanWindowForSize(preview);

    expect(window.left, greaterThanOrEqualTo(0));
    expect(window.top, greaterThanOrEqualTo(0));
    expect(window.right, lessThanOrEqualTo(preview.width));
    expect(window.bottom, lessThanOrEqualTo(preview.height));
  });

  group('scanner feedback', () {
    test('added and incremented scans map to success', () {
      expect(
        scannerFeedbackStateForResult(
          const BarcodeScanResult(BarcodeScanStatus.added),
        ),
        ScannerFeedbackState.success,
      );
      expect(
        scannerFeedbackStateForResult(
          const BarcodeScanResult(BarcodeScanStatus.incremented),
        ),
        ScannerFeedbackState.success,
      );
    });

    test('non-mutating scan outcomes map to error', () {
      for (final status in [
        BarcodeScanStatus.unknown,
        BarcodeScanStatus.ambiguous,
        BarcodeScanStatus.invalidPrice,
        BarcodeScanStatus.overflow,
        BarcodeScanStatus.failed,
      ]) {
        expect(
          scannerFeedbackStateForResult(BarcodeScanResult(status)),
          ScannerFeedbackState.error,
        );
      }
    });

    test('feedback colors are distinct for each scanner state', () {
      expect(scannerFeedbackColor(ScannerFeedbackState.idle), Colors.white);
      expect(scannerFeedbackColor(ScannerFeedbackState.checking), Colors.amber);
      expect(
        scannerFeedbackColor(ScannerFeedbackState.success),
        Colors.greenAccent,
      );
      expect(
        scannerFeedbackColor(ScannerFeedbackState.error),
        Colors.redAccent,
      );
    });
  });

  group('barcode presentation gate', () {
    test('held barcode stays locked while it is still being observed', () {
      final gate = BarcodePresentationGate();
      final start = DateTime.utc(2026, 9, 27, 9);

      gate.lock('A', start);
      gate.observe(['A'], start.add(const Duration(milliseconds: 500)));
      gate.releaseIfAbsent(start.add(const Duration(milliseconds: 1000)));

      expect(gate.lockedCode, 'A');
      expect(gate.nextCandidate(['A']), isNull);
    });

    test('barcode unlocks after it has been absent long enough', () {
      final gate = BarcodePresentationGate();
      final start = DateTime.utc(2026, 9, 27, 9);

      gate.lock('A', start);
      gate.releaseIfAbsent(start.add(const Duration(milliseconds: 700)));

      expect(gate.lockedCode, isNull);
      expect(gate.nextCandidate(['A']), 'A');
    });

    test('different barcode can be scanned while previous code is locked', () {
      final gate = BarcodePresentationGate();
      final start = DateTime.utc(2026, 9, 27, 9);

      gate.lock('A', start);

      expect(gate.nextCandidate(['A', 'B']), 'B');
    });
  });
}
