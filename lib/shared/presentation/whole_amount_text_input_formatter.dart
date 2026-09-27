import 'package:flutter/services.dart';

import '../formatting/whole_amount.dart';

class WholeAmountTextInputFormatter extends TextInputFormatter {
  const WholeAmountTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(',', '');
    if (digits.isEmpty) {
      return const TextEditingValue();
    }
    if (!RegExp(r'^\d+$').hasMatch(digits)) {
      return oldValue;
    }

    final formatted = formatWholeAmountDigits(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
