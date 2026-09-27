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
}
