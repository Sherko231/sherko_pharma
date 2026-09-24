import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/catalog/domain/catalog_product_input.dart';
import 'package:sherko_pharma/features/catalog/domain/catalog_product_id.dart';

void main() {
  test('either English or Arabic name satisfies the name requirement', () {
    const englishOnly = CatalogProductFormData(
      nameEn: 'Aspirin',
      nameAr: '',
      composition: '',
      manufacturer: '',
      strength: '',
      dosageForm: '',
      packageDescription: '',
      barcode: '',
      barcode2: '',
      sellingAmountText: '10',
      currency: 'SYP',
      notes: '',
    );
    const arabicOnly = CatalogProductFormData(
      nameEn: '',
      nameAr: 'أسبرين',
      composition: '',
      manufacturer: '',
      strength: '',
      dosageForm: '',
      packageDescription: '',
      barcode: '',
      barcode2: '',
      sellingAmountText: '10',
      currency: 'USD',
      notes: '',
    );

    expect(englishOnly.validate().isValid, isTrue);
    expect(arabicOnly.validate().isValid, isTrue);
  });

  test('whitespace-only names are rejected', () {
    const data = CatalogProductFormData(
      nameEn: '   ',
      nameAr: '\t',
      composition: '',
      manufacturer: '',
      strength: '',
      dosageForm: '',
      packageDescription: '',
      barcode: '',
      barcode2: '',
      sellingAmountText: '10',
      currency: 'SYP',
      notes: '',
    );

    expect(data.validate()['names'], isNotNull);
  });

  test('selling amount must be a positive whole integer', () {
    CatalogProductFormData data(String amount) => CatalogProductFormData(
          nameEn: 'A',
          nameAr: '',
          composition: '',
          manufacturer: '',
          strength: '',
          dosageForm: '',
          packageDescription: '',
          barcode: '',
          barcode2: '',
          sellingAmountText: amount,
          currency: 'SYP',
          notes: '',
        );

    expect(data('0').validate()['sellingAmount'], isNotNull);
    expect(data('-1').validate()['sellingAmount'], isNotNull);
    expect(data('1.5').validate()['sellingAmount'], isNotNull);
    expect(data('100').validate()['sellingAmount'], isNull);
  });

  test('only SYP and USD are supported', () {
    const data = CatalogProductFormData(
      nameEn: 'A',
      nameAr: '',
      composition: '',
      manufacturer: '',
      strength: '',
      dosageForm: '',
      packageDescription: '',
      barcode: '',
      barcode2: '',
      sellingAmountText: '100',
      currency: 'EUR',
      notes: '',
    );

    expect(data.validate()['currency'], isNotNull);
  });

  test('barcode text preserves leading zeros and non-digit characters', () {
    const data = CatalogProductFormData(
      nameEn: 'A',
      nameAr: '',
      composition: '',
      manufacturer: '',
      strength: '',
      dosageForm: '',
      packageDescription: '',
      barcode: '00012-A',
      barcode2: '-ALT-001',
      sellingAmountText: '100',
      currency: 'SYP',
      notes: '',
    );

    final input = data.toInput();
    expect(input.barcode, '00012-A');
    expect(input.barcode2, '-ALT-001');
  });

  test('generated product identity is RFC4122 version 4 shaped', () {
    final id = generateCatalogProductId(Random(42));

    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(id),
      isTrue,
    );
  });
}
