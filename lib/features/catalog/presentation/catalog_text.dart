import 'package:flutter/material.dart';

class CatalogText extends StatelessWidget {
  const CatalogText(
    this.value, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String value;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      textDirection: _containsArabic(value)
          ? TextDirection.rtl
          : TextDirection.ltr,
      textAlign: TextAlign.start,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  bool _containsArabic(String value) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
  }
}
