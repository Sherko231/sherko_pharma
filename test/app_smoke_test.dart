import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/main.dart';

void main() {
  for (final size in [const Size(360, 800), const Size(1280, 720)]) {
    testWidgets('scaffold launches at $size without rendering errors', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();

      expect(find.text('Hello World!'), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
      final textBounds = tester.getRect(find.text('Hello World!'));
      expect((Offset.zero & size).contains(textBounds.topLeft), isTrue);
      expect((Offset.zero & size).contains(textBounds.bottomRight), isTrue);
    });
  }
}
