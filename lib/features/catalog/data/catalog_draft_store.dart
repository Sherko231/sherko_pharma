import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/secure_supabase_local_storage.dart';
import '../domain/catalog_product.dart';
import '../domain/catalog_product_input.dart';

final catalogDraftStoreProvider = Provider<CatalogDraftStore>((ref) {
  throw StateError('CatalogDraftStore was not configured for this runtime.');
});

abstract interface class CatalogDraftStore {
  Future<CatalogProductDraft?> load({
    required String ownerId,
    required String scopeKey,
  });

  Future<void> save(CatalogProductDraft draft);

  Future<void> clear({
    required String ownerId,
    required String scopeKey,
  });
}

class CatalogDraftStorageException implements Exception {
  const CatalogDraftStorageException();
}

class SecureCatalogDraftStore implements CatalogDraftStore {
  const SecureCatalogDraftStore({
    required this.store,
    required this.keyPrefix,
  });

  final SecureKeyValueStore store;
  final String keyPrefix;

  @override
  Future<CatalogProductDraft?> load({
    required String ownerId,
    required String scopeKey,
  }) async {
    final key = _key(ownerId, scopeKey);
    final raw = await store.read(key);
    if (raw == null) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Draft root must be an object.');
      }
      final draft = CatalogProductDraft.fromJson(decoded);
      if (draft.ownerId != ownerId || draft.scopeKey != scopeKey) {
        throw const FormatException('Draft identity does not match its key.');
      }
      return draft;
    } catch (_) {
      try {
        await store.delete(key);
      } catch (_) {
        // The caller still receives a fail-closed storage error.
      }
      throw const CatalogDraftStorageException();
    }
  }

  @override
  Future<void> save(CatalogProductDraft draft) {
    return store.write(
      _key(draft.ownerId, draft.scopeKey),
      jsonEncode(draft.toJson()),
    );
  }

  @override
  Future<void> clear({
    required String ownerId,
    required String scopeKey,
  }) {
    return store.delete(_key(ownerId, scopeKey));
  }

  String _key(String ownerId, String scopeKey) {
    return '$keyPrefix:$ownerId:$scopeKey';
  }
}

class CatalogProductDraft {
  const CatalogProductDraft({
    required this.ownerId,
    required this.scopeKey,
    required this.productId,
    required this.formData,
    required this.baseProduct,
    required this.uncertain,
    this.pendingBase,
  });

  static const int schemaVersion = 1;

  final String ownerId;
  final String scopeKey;
  final String productId;
  final CatalogProductFormData formData;
  final CatalogProduct? baseProduct;
  final bool uncertain;
  final CatalogProduct? pendingBase;

  Map<String, dynamic> toJson() {
    return {
      'version': schemaVersion,
      'owner_id': ownerId,
      'scope_key': scopeKey,
      'product_id': productId,
      'form': _formToJson(formData),
      'base_product': baseProduct == null ? null : _productToJson(baseProduct!),
      'uncertain': uncertain,
      'pending_base':
          pendingBase == null ? null : _productToJson(pendingBase!),
    };
  }

  factory CatalogProductDraft.fromJson(Map<String, dynamic> json) {
    if (json['version'] != schemaVersion) {
      throw const FormatException('Unsupported catalog draft version.');
    }

    final ownerId = _requiredString(json, 'owner_id');
    final scopeKey = _requiredString(json, 'scope_key');
    final productId = _requiredString(json, 'product_id');
    final form = json['form'];
    if (form is! Map<String, dynamic>) {
      throw const FormatException('Draft form must be an object.');
    }

    final base = json['base_product'];
    final pendingBase = json['pending_base'];
    final uncertain = json['uncertain'];
    if (uncertain is! bool) {
      throw const FormatException('Draft uncertain flag must be boolean.');
    }

    return CatalogProductDraft(
      ownerId: ownerId,
      scopeKey: scopeKey,
      productId: productId,
      formData: _formFromJson(form),
      baseProduct: base == null
          ? null
          : _productFromJson(_requiredMap(base, 'base_product')),
      uncertain: uncertain,
      pendingBase: pendingBase == null
          ? null
          : _productFromJson(_requiredMap(pendingBase, 'pending_base')),
    );
  }

  static Map<String, dynamic> _formToJson(CatalogProductFormData data) {
    return {
      'name_en': data.nameEn,
      'name_ar': data.nameAr,
      'composition': data.composition,
      'manufacturer': data.manufacturer,
      'strength': data.strength,
      'dosage_form': data.dosageForm,
      'package_description': data.packageDescription,
      'barcode': data.barcode,
      'barcode2': data.barcode2,
      'selling_amount_text': data.sellingAmountText,
      'currency': data.currency,
      'notes': data.notes,
    };
  }

  static CatalogProductFormData _formFromJson(Map<String, dynamic> json) {
    return CatalogProductFormData(
      nameEn: _requiredText(json, 'name_en'),
      nameAr: _requiredText(json, 'name_ar'),
      composition: _requiredText(json, 'composition'),
      manufacturer: _requiredText(json, 'manufacturer'),
      strength: _requiredText(json, 'strength'),
      dosageForm: _requiredText(json, 'dosage_form'),
      packageDescription: _requiredText(json, 'package_description'),
      barcode: _requiredText(json, 'barcode'),
      barcode2: _requiredText(json, 'barcode2'),
      sellingAmountText: _requiredText(json, 'selling_amount_text'),
      currency: _requiredText(json, 'currency'),
      notes: _requiredText(json, 'notes'),
    );
  }

  static Map<String, dynamic> _productToJson(CatalogProduct product) {
    return {
      'id': product.id,
      'name_en': product.nameEn,
      'name_ar': product.nameAr,
      'composition': product.composition,
      'manufacturer': product.manufacturer,
      'strength': product.strength,
      'dosage_form': product.dosageForm,
      'package_description': product.packageDescription,
      'barcode': product.barcode,
      'barcode2': product.barcode2,
      'selling_amount': product.sellingAmount,
      'currency': product.currency,
      'notes': product.notes,
      'revision': product.revision,
      'updated_at': product.updatedAt.toIso8601String(),
    };
  }

  static CatalogProduct _productFromJson(Map<String, dynamic> json) {
    final updatedAt = DateTime.tryParse(_requiredString(json, 'updated_at'));
    if (updatedAt == null) {
      throw const FormatException('Draft product timestamp is invalid.');
    }

    return CatalogProduct(
      id: _requiredString(json, 'id'),
      nameEn: _optionalText(json, 'name_en'),
      nameAr: _optionalText(json, 'name_ar'),
      composition: _optionalText(json, 'composition'),
      manufacturer: _optionalText(json, 'manufacturer'),
      strength: _optionalText(json, 'strength'),
      dosageForm: _optionalText(json, 'dosage_form'),
      packageDescription: _optionalText(json, 'package_description'),
      barcode: _optionalText(json, 'barcode'),
      barcode2: _optionalText(json, 'barcode2'),
      sellingAmount: _requiredInt(json, 'selling_amount'),
      currency: _requiredString(json, 'currency'),
      notes: _optionalText(json, 'notes'),
      revision: _requiredInt(json, 'revision'),
      updatedAt: updatedAt,
    );
  }

  static Map<String, dynamic> _requiredMap(Object? value, String key) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    throw FormatException('Draft field $key must be an object.');
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException('Draft field $key must be a nonempty string.');
  }

  static String _requiredText(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) {
      return value;
    }
    throw FormatException('Draft field $key must be text.');
  }

  static String? _optionalText(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null || value is String) {
      return value as String?;
    }
    throw FormatException('Draft field $key must be text or null.');
  }

  static int _requiredInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    throw FormatException('Draft field $key must be an integer.');
  }
}
