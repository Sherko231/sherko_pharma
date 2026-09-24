import 'package:sherko_pharma/features/catalog/data/catalog_repository.dart';
import 'package:sherko_pharma/features/catalog/domain/catalog_product.dart';
import 'package:sherko_pharma/features/catalog/domain/catalog_product_input.dart';

typedef SearchHandler = Future<List<CatalogProduct>> Function(
  String query,
  int limit,
);

typedef DetailHandler = Future<CatalogProduct> Function(String productId);
typedef CreateHandler = Future<CatalogSaveResult> Function(
  String productId,
  CatalogProductInput input,
);
typedef UpdateHandler = Future<CatalogSaveResult> Function(
  CatalogProduct original,
  CatalogProductInput input,
);

class CatalogSearchCall {
  const CatalogSearchCall({
    required this.query,
    required this.limit,
  });

  final String query;
  final int limit;
}

class FakeCatalogRepository implements CatalogRepository {
  SearchHandler? onSearch;
  DetailHandler? onGet;
  CreateHandler? onCreate;
  UpdateHandler? onUpdate;
  CreateHandler? onReconcileCreate;
  UpdateHandler? onReconcileUpdate;
  List<CatalogProduct> searchResults = const [];
  final Map<String, CatalogProduct> products = {};
  final List<CatalogSearchCall> searchCalls = [];
  final List<String> detailCalls = [];
  final List<String> createIds = [];
  final List<CatalogProductInput> createInputs = [];
  final List<CatalogProduct> updateOriginals = [];
  final List<CatalogProductInput> updateInputs = [];

  @override
  Future<List<CatalogProduct>> search(
    String query, {
    int limit = 25,
  }) async {
    searchCalls.add(
      CatalogSearchCall(
        query: query,
        limit: limit,
      ),
    );

    final handler = onSearch;
    if (handler != null) {
      return handler(query, limit);
    }
    return searchResults;
  }


  @override
  Future<CatalogSaveResult> create({
    required String productId,
    required CatalogProductInput input,
  }) async {
    createIds.add(productId);
    createInputs.add(input);
    final handler = onCreate;
    if (handler != null) {
      return handler(productId, input);
    }
    return CatalogSaveConfirmed(
      testProduct(
        id: productId,
        nameEn: input.nameEn.isEmpty ? null : input.nameEn,
        nameAr: input.nameAr.isEmpty ? null : input.nameAr,
        composition: input.composition.isEmpty ? null : input.composition,
        manufacturer: input.manufacturer.isEmpty ? null : input.manufacturer,
        strength: input.strength.isEmpty ? null : input.strength,
        dosageForm: input.dosageForm.isEmpty ? null : input.dosageForm,
        packageDescription:
            input.packageDescription.isEmpty ? null : input.packageDescription,
        barcode: input.barcode.isEmpty ? null : input.barcode,
        barcode2: input.barcode2.isEmpty ? null : input.barcode2,
        sellingAmount: input.sellingAmount,
        currency: input.currency,
        notes: input.notes.isEmpty ? null : input.notes,
      ),
    );
  }

  @override
  Future<CatalogSaveResult> update({
    required CatalogProduct original,
    required CatalogProductInput input,
  }) async {
    updateOriginals.add(original);
    updateInputs.add(input);
    final handler = onUpdate;
    if (handler != null) {
      return handler(original, input);
    }
    return CatalogSaveConfirmed(
      testProduct(
        id: original.id,
        nameEn: input.nameEn.isEmpty ? null : input.nameEn,
        nameAr: input.nameAr.isEmpty ? null : input.nameAr,
        composition: input.composition.isEmpty ? null : input.composition,
        manufacturer: input.manufacturer.isEmpty ? null : input.manufacturer,
        strength: input.strength.isEmpty ? null : input.strength,
        dosageForm: input.dosageForm.isEmpty ? null : input.dosageForm,
        packageDescription:
            input.packageDescription.isEmpty ? null : input.packageDescription,
        barcode: input.barcode.isEmpty ? null : input.barcode,
        barcode2: input.barcode2.isEmpty ? null : input.barcode2,
        sellingAmount: input.sellingAmount,
        currency: input.currency,
        notes: input.notes.isEmpty ? null : input.notes,
        revision: original.revision + 1,
      ),
    );
  }

  @override
  Future<CatalogSaveResult> reconcileCreate({
    required String productId,
    required CatalogProductInput input,
  }) async {
    final handler = onReconcileCreate;
    if (handler != null) {
      return handler(productId, input);
    }
    return const CatalogSaveRejected();
  }

  @override
  Future<CatalogSaveResult> reconcileUpdate({
    required CatalogProduct original,
    required CatalogProductInput input,
  }) async {
    final handler = onReconcileUpdate;
    if (handler != null) {
      return handler(original, input);
    }
    return const CatalogSaveRejected();
  }

  @override
  Future<CatalogProduct> getById(String productId) async {
    detailCalls.add(productId);

    final handler = onGet;
    if (handler != null) {
      return handler(productId);
    }

    final product = products[productId];
    if (product == null) {
      throw const CatalogNotFoundException();
    }
    return product;
  }
}

CatalogProduct testProduct({
  String id = '00000000-0000-0000-0000-000000000001',
  String? nameEn = 'Aspirin',
  String? nameAr = 'أسبرين',
  String? composition = 'Acetylsalicylic acid',
  String? manufacturer = 'Test Pharma',
  String? strength = '100 mg',
  String? dosageForm = 'Tablet',
  String? packageDescription = '20 tablets',
  String? barcode = '0012345',
  String? barcode2 = 'ALT-001',
  int sellingAmount = 15000,
  String currency = 'SYP',
  String? notes,
  int revision = 1,
}) {
  return CatalogProduct(
    id: id,
    nameEn: nameEn,
    nameAr: nameAr,
    composition: composition,
    manufacturer: manufacturer,
    strength: strength,
    dosageForm: dosageForm,
    packageDescription: packageDescription,
    barcode: barcode,
    barcode2: barcode2,
    sellingAmount: sellingAmount,
    currency: currency,
    notes: notes,
    revision: revision,
    updatedAt: DateTime.utc(2026, 9, 24, 12),
  );
}
