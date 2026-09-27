import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/shared/formatting/whole_amount.dart';
import 'package:sherko_pharma/shared/presentation/whole_amount_text_input_formatter.dart';

void main() {
  group('whole amount formatting', () {
    test('adds comma thousands separators', () {
      expect(formatWholeAmount(0), '0');
      expect(formatWholeAmount(999), '999');
      expect(formatWholeAmount(1000), '1,000');
      expect(formatWholeAmount(200000), '200,000');
      expect(formatWholeAmount(123456789), '123,456,789');
    });

    test('preserves sign for defensive formatting', () {
      expect(formatWholeAmount(-200000), '-200,000');
    });

    test('parses formatted values back to exact integers', () {
      expect(parseWholeAmountText('200,000'), 200000);
      expect(parseWholeAmountText(' 1,234,567 '), 1234567);
      expect(parseWholeAmountText('1.5'), isNull);
    });
  });

  test('price input formatter groups digits while typing', () {
    const formatter = WholeAmountTextInputFormatter();

    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '200000',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );

    expect(result.text, '200,000');
    expect(result.selection.baseOffset, 7);
  });

  test('price input formatter accepts pasted comma-formatted amount', () {
    const formatter = WholeAmountTextInputFormatter();

    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '1,250,000',
        selection: TextSelection.collapsed(offset: 9),
      ),
    );

    expect(result.text, '1,250,000');
  });
}
