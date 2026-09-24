import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/shared/presentation/async_value_view.dart';

void main() {
  testWidgets('renders loading state explicitly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AsyncValueView<String>(
          value: const AsyncLoading(),
          dataBuilder: (context, data) {
            return Text(data);
          },
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders data state explicitly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AsyncValueView<String>(
          value: const AsyncData('ready'),
          dataBuilder: (context, data) {
            return Text(data);
          },
        ),
      ),
    );

    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('renders error state explicitly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AsyncValueView<String>(
          value: AsyncError(
            StateError('boom'),
            StackTrace.empty,
          ),
          dataBuilder: (context, data) {
            return Text(data);
          },
        ),
      ),
    );

    expect(find.text('Something went wrong.'), findsOneWidget);
  });
}
