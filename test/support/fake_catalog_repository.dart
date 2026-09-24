import 'package:sherko_pharma/features/catalog/data/catalog_repository.dart';
import 'package:sherko_pharma/features/catalog/domain/catalog_product.dart';

typedef SearchHandler = Future<List<CatalogProduct>> Function(
  String query,
  int limit,
);

typedef DetailHandler = Future<CatalogProduct> Function(String productId);

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
  List<CatalogProduct> searchResults = const [];
  final Map<String, CatalogProduct> products = {};
  final List<CatalogSearchCall> searchCalls = [];
  final List<String> detailCalls = [];

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
