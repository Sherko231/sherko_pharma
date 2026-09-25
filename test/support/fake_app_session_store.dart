import 'dart:async';

import 'package:sherko_pharma/features/session/data/app_session_store.dart';

class FakeAppSessionStore implements AppSessionStore {
  final Map<String, AppSessionSnapshot> snapshots = {};
  final List<AppSessionSnapshot> savedSnapshots = [];
  final List<String> loadedOwners = [];

  bool failReads = false;
  bool failWrites = false;
  Completer<void>? readGate;
  Completer<void>? firstWriteGate;

  int _writeCount = 0;

  @override
  Future<AppSessionSnapshot?> load({
    required String ownerId,
  }) async {
    loadedOwners.add(ownerId);
    final gate = readGate;
    if (gate != null) {
      await gate.future;
    }
    if (failReads) {
      throw const AppSessionStorageException();
    }
    return snapshots[ownerId];
  }

  @override
  Future<void> save(AppSessionSnapshot snapshot) async {
    _writeCount += 1;
    savedSnapshots.add(snapshot);

    if (_writeCount == 1) {
      final gate = firstWriteGate;
      if (gate != null) {
        await gate.future;
      }
    }

    if (failWrites) {
      throw const AppSessionStorageException();
    }

    snapshots[snapshot.ownerId] = snapshot;
  }
}
