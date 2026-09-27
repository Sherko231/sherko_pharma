import '../domain/catalog_alternative.dart';
import '../domain/catalog_product.dart';
import '../domain/catalog_product_input.dart';

enum CatalogReferenceKind {
  manufacturer('manufacturer'),
  dosageForm('dosage_form');

  const CatalogReferenceKind(this.rpcValue);

  final String rpcValue;
}

class CatalogReferenceOption {
  const CatalogReferenceOption({
    required this.id,
    required this.label,
  });

  final int id;
  final String label;
}

abstract interface class CatalogRepository {
  Future<List<CatalogProduct>> search(
    String query, {
    int limit = 25,
  });

  Future<CatalogProduct> getById(String productId);

  Future<List<CatalogAlternative>> alternatives(
    String productId, {
    int limitPerGroup = 10,
  });

  Future<List<CatalogProduct>> lookupBarcode(String code);

  Future<List<CatalogReferenceOption>> referenceOptions(
    CatalogReferenceKind kind, {
    String query = '',
    int limit = 500,
  });

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
