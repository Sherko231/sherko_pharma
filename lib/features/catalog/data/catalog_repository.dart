import '../domain/catalog_product.dart';
import '../domain/catalog_product_input.dart';

abstract interface class CatalogRepository {
  Future<List<CatalogProduct>> search(
    String query, {
    int limit = 25,
  });

  Future<CatalogProduct> getById(String productId);

  Future<CatalogSaveResult> create({
    required String productId,
    required CatalogProductInput input,
  });

  Future<CatalogSaveResult> update({
    required CatalogProduct original,
    required CatalogProductInput input,
  });

  Future<CatalogSaveResult> reconcileCreate({
    required String productId,
    required CatalogProductInput input,
  });

  Future<CatalogSaveResult> reconcileUpdate({
    required CatalogProduct original,
    required CatalogProductInput input,
  });
}

sealed class CatalogSaveResult {
  const CatalogSaveResult();
}

class CatalogSaveConfirmed extends CatalogSaveResult {
  const CatalogSaveConfirmed(this.product);

  final CatalogProduct product;
}

class CatalogSaveRejected extends CatalogSaveResult {
  const CatalogSaveRejected();
}

class CatalogSaveConflict extends CatalogSaveResult {
  const CatalogSaveConflict(this.latest);

  final CatalogProduct? latest;
}

class CatalogSaveUncertain extends CatalogSaveResult {
  const CatalogSaveUncertain();
}

class CatalogSaveMissing extends CatalogSaveResult {
  const CatalogSaveMissing();
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

class CatalogRpcException implements Exception {
  const CatalogRpcException({
    this.code,
  });

  final String? code;
}
