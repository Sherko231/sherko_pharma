import 'package:sherko_pharma/features/catalog/data/catalog_draft_store.dart';

class FakeCatalogDraftStore implements CatalogDraftStore {
  final Map<String, CatalogProductDraft> drafts = {};

  bool failLoad = false;
  bool failSave = false;
  bool failClear = false;
  int loadCalls = 0;
  int saveCalls = 0;
  int clearCalls = 0;

  @override
  Future<CatalogProductDraft?> load({
    required String ownerId,
    required String scopeKey,
  }) async {
    loadCalls += 1;
    if (failLoad) {
      throw const CatalogDraftStorageException();
    }
    return drafts[_key(ownerId, scopeKey)];
  }

  @override
  Future<void> save(CatalogProductDraft draft) async {
    saveCalls += 1;
    if (failSave) {
      throw const CatalogDraftStorageException();
    }
    drafts[_key(draft.ownerId, draft.scopeKey)] = draft;
  }

  @override
  Future<void> clear({
    required String ownerId,
    required String scopeKey,
  }) async {
    clearCalls += 1;
    if (failClear) {
      throw const CatalogDraftStorageException();
    }
    drafts.remove(_key(ownerId, scopeKey));
  }

  CatalogProductDraft? draftFor(String ownerId, String scopeKey) {
    return drafts[_key(ownerId, scopeKey)];
  }

  String _key(String ownerId, String scopeKey) => '$ownerId::$scopeKey';
}
