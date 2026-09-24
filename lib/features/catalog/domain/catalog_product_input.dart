import 'catalog_product.dart';

class CatalogProductInput {
  const CatalogProductInput({
    required this.nameEn,
    required this.nameAr,
    required this.composition,
    required this.manufacturer,
    required this.strength,
    required this.dosageForm,
    required this.packageDescription,
    required this.barcode,
    required this.barcode2,
    required this.sellingAmount,
    required this.currency,
    required this.notes,
  });

  factory CatalogProductInput.fromProduct(CatalogProduct product) {
    return CatalogProductInput(
      nameEn: product.nameEn ?? '',
      nameAr: product.nameAr ?? '',
      composition: product.composition ?? '',
      manufacturer: product.manufacturer ?? '',
      strength: product.strength ?? '',
      dosageForm: product.dosageForm ?? '',
      packageDescription: product.packageDescription ?? '',
      barcode: product.barcode ?? '',
      barcode2: product.barcode2 ?? '',
      sellingAmount: product.sellingAmount,
      currency: product.currency,
      notes: product.notes ?? '',
    );
  }

  final String nameEn;
  final String nameAr;
  final String composition;
  final String manufacturer;
  final String strength;
  final String dosageForm;
  final String packageDescription;
  final String barcode;
  final String barcode2;
  final int sellingAmount;
  final String currency;
  final String notes;

  bool matchesProduct(CatalogProduct product) {
    return _serverText(nameEn) == product.nameEn &&
        _serverText(nameAr) == product.nameAr &&
        _serverText(composition) == product.composition &&
        _serverText(manufacturer) == product.manufacturer &&
        _serverText(strength) == product.strength &&
        _serverText(dosageForm) == product.dosageForm &&
        _serverText(packageDescription) == product.packageDescription &&
        _serverText(barcode) == product.barcode &&
        _serverText(barcode2) == product.barcode2 &&
        sellingAmount == product.sellingAmount &&
        currency == product.currency &&
        _serverText(notes) == product.notes;
  }

  static String? _serverText(String value) {
    return value.trim().isEmpty ? null : value;
  }
}

class CatalogProductFormData {
  const CatalogProductFormData({
    required this.nameEn,
    required this.nameAr,
    required this.composition,
    required this.manufacturer,
    required this.strength,
    required this.dosageForm,
    required this.packageDescription,
    required this.barcode,
    required this.barcode2,
    required this.sellingAmountText,
    required this.currency,
    required this.notes,
  });

  const CatalogProductFormData.empty()
      : this(
          nameEn: '',
          nameAr: '',
          composition: '',
          manufacturer: '',
          strength: '',
          dosageForm: '',
          packageDescription: '',
          barcode: '',
          barcode2: '',
          sellingAmountText: '',
          currency: 'SYP',
          notes: '',
        );

  factory CatalogProductFormData.fromProduct(CatalogProduct product) {
    return CatalogProductFormData(
      nameEn: product.nameEn ?? '',
      nameAr: product.nameAr ?? '',
      composition: product.composition ?? '',
      manufacturer: product.manufacturer ?? '',
      strength: product.strength ?? '',
      dosageForm: product.dosageForm ?? '',
      packageDescription: product.packageDescription ?? '',
      barcode: product.barcode ?? '',
      barcode2: product.barcode2 ?? '',
      sellingAmountText: product.sellingAmount.toString(),
      currency: product.currency,
      notes: product.notes ?? '',
    );
  }

  static const supportedCurrencies = {'SYP', 'USD'};

  final String nameEn;
  final String nameAr;
  final String composition;
  final String manufacturer;
  final String strength;
  final String dosageForm;
  final String packageDescription;
  final String barcode;
  final String barcode2;
  final String sellingAmountText;
  final String currency;
  final String notes;

  CatalogProductFormValidation validate() {
    final errors = <String, String>{};

    if (nameEn.trim().isEmpty && nameAr.trim().isEmpty) {
      errors['names'] = 'Enter an English or Arabic name.';
    }

    final amount = int.tryParse(sellingAmountText);
    if (amount == null || amount <= 0) {
      errors['sellingAmount'] = 'Enter a positive whole-number selling price.';
    }

    if (!supportedCurrencies.contains(currency)) {
      errors['currency'] = 'Choose SYP or USD.';
    }

    return CatalogProductFormValidation(errors);
  }

  CatalogProductInput toInput() {
    final validation = validate();
    if (!validation.isValid) {
      throw StateError('Cannot create catalog input from invalid form data.');
    }

    return CatalogProductInput(
      nameEn: nameEn,
      nameAr: nameAr,
      composition: composition,
      manufacturer: manufacturer,
      strength: strength,
      dosageForm: dosageForm,
      packageDescription: packageDescription,
      barcode: barcode,
      barcode2: barcode2,
      sellingAmount: int.parse(sellingAmountText),
      currency: currency,
      notes: notes,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CatalogProductFormData &&
        other.nameEn == nameEn &&
        other.nameAr == nameAr &&
        other.composition == composition &&
        other.manufacturer == manufacturer &&
        other.strength == strength &&
        other.dosageForm == dosageForm &&
        other.packageDescription == packageDescription &&
        other.barcode == barcode &&
        other.barcode2 == barcode2 &&
        other.sellingAmountText == sellingAmountText &&
        other.currency == currency &&
        other.notes == notes;
  }

  @override
  int get hashCode => Object.hash(
        nameEn,
        nameAr,
        composition,
        manufacturer,
        strength,
        dosageForm,
        packageDescription,
        barcode,
        barcode2,
        sellingAmountText,
        currency,
        notes,
      );
}

class CatalogProductFormValidation {
  const CatalogProductFormValidation(this.errors);

  final Map<String, String> errors;

  bool get isValid => errors.isEmpty;

  String? operator [](String key) => errors[key];
}
