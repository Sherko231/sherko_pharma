class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.sellingAmount,
    required this.currency,
    required this.revision,
    required this.updatedAt,
    this.nameEn,
    this.nameAr,
    this.composition,
    this.manufacturer,
    this.strength,
    this.dosageForm,
    this.packageDescription,
    this.barcode,
    this.barcode2,
    this.notes,
  });

  final String id;
  final String? nameEn;
  final String? nameAr;
  final String? composition;
  final String? manufacturer;
  final String? strength;
  final String? dosageForm;
  final String? packageDescription;
  final String? barcode;
  final String? barcode2;
  final int sellingAmount;
  final String currency;
  final String? notes;
  final int revision;
  final DateTime updatedAt;

  String get displayName {
    final english = nameEn?.trim();
    if (english != null && english.isNotEmpty) {
      return english;
    }

    final arabic = nameAr?.trim();
    if (arabic != null && arabic.isNotEmpty) {
      return arabic;
    }

    return 'Unnamed product';
  }

  factory CatalogProduct.fromRpcRow(Map<String, dynamic> row) {
    return CatalogProduct(
      id: _requiredString(row, 'id'),
      nameEn: _optionalString(row, 'name_en'),
      nameAr: _optionalString(row, 'name_ar'),
      composition: _optionalString(row, 'composition'),
      manufacturer: _optionalString(row, 'manufacturer'),
      strength: _optionalString(row, 'strength'),
      dosageForm: _optionalString(row, 'dosage_form'),
      packageDescription: _optionalString(row, 'package_description'),
      barcode: _optionalString(row, 'barcode'),
      barcode2: _optionalString(row, 'barcode2'),
      sellingAmount: _requiredInt(row, 'selling_amount'),
      currency: _requiredString(row, 'currency'),
      notes: _optionalString(row, 'notes'),
      revision: _requiredInt(row, 'revision'),
      updatedAt: _requiredDateTime(row, 'updated_at'),
    );
  }

  static String _requiredString(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException('Catalog RPC field $key must be a nonempty string.');
  }

  static String? _optionalString(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw FormatException('Catalog RPC field $key must be text or null.');
  }

  static int _requiredInt(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is int) {
      return value;
    }
    throw FormatException('Catalog RPC field $key must be an integer.');
  }

  static DateTime _requiredDateTime(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String) {
      throw FormatException('Catalog RPC field $key must be a timestamp.');
    }

    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('Catalog RPC field $key is not a valid timestamp.');
    }
    return parsed;
  }
}
