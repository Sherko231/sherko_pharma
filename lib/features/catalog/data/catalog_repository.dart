import '../domain/catalog_product.dart';

abstract interface class CatalogRepository {
  Future<List<CatalogProduct>> search(
    String query, {
    int limit = 25,
  });

  Future<CatalogProduct> getById(String productId);
}

class CatalogRepositoryException implements Exception {
  const CatalogRepositoryException();
}

class CatalogNotFoundException extends CatalogRepositoryException {
  const CatalogNotFoundException();
}

class CatalogResponseException extends CatalogRepositoryException {
  const CatalogResponseException();
}
