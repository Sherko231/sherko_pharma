String formatWholeAmount(int value) {
  final sign = value < 0 ? '-' : '';
  final digits = value.abs().toString();
  return '$sign${formatWholeAmountDigits(digits)}';
}

String formatWholeAmountDigits(String digits) {
  if (digits.isEmpty) {
    return '';
  }

  final buffer = StringBuffer();
  final firstGroupLength = digits.length % 3 == 0 ? 3 : digits.length % 3;
  buffer.write(digits.substring(0, firstGroupLength));

  for (var index = firstGroupLength; index < digits.length; index += 3) {
    buffer
      ..write(',')
      ..write(digits.substring(index, index + 3));
  }
  return buffer.toString();
}

String normalizeWholeAmountText(String text) {
  return text.replaceAll(',', '').trim();
}

int? parseWholeAmountText(String text) {
  final trimmed = text.trim();
  final validGrouping = RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)
);
  if (!validGrouping.hasMatch(trimmed)) {
    return null;
  }
  return int.tryParse(normalizeWholeAmountText(trimmed));
}
