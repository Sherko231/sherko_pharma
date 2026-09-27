import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    expect(window.width, 420);
    expect(window.center, preview.center(Offset.zero));
  });

  test('barcode scan window remains inside a short landscape preview', () {
    const preview = Size(800, 300);

    final window = barcodeScanWindowForSize(preview);

    expect(window.left, greaterThanOrEqualTo(0));
    expect(window.top, greaterThanOrEqualTo(0));
    expect(window.right, lessThanOrEqualTo(preview.width));
    expect(window.bottom, lessThanOrEqualTo(preview.height));
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
