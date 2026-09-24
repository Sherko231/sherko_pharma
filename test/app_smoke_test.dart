import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/main.dart';

void main() {
  for (final size in [const Size(360, 800), const Size(1280, 720)]) {
    testWidgets('app launches at $size without rendering errors', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const AppBootstrap());
      await tester.pumpAndSettle();

      expect(find.text('Sherko Pharma'), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);

      final titleBounds = tester.getRect(find.text('Sherko Pharma'));
      expect((Offset.zero & size).contains(titleBounds.topLeft), isTrue);
      expect((Offset.zero & size).contains(titleBounds.bottomRight), isTrue);
    });
  }
}
