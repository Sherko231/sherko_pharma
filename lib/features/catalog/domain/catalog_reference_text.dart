String? normalizeCatalogReferenceText(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  const source = 'آأإٱؤئىيک٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹';
  const target = 'ااااويييك01234567890123456789';

  final buffer = StringBuffer();
  for (final rune in value.trim().toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    final index = source.indexOf(character);
    buffer.write(index >= 0 ? target[index] : character);
  }

  return buffer
      .toString()
      .replaceAll(RegExp(r'[ًٌٍَُِّْٰـ]'), '')
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}
