import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/secure_supabase_local_storage.dart';
import '../../navigation/application/app_navigation_controller.dart';
import '../../order/domain/order_model.dart';

final appSessionStoreProvider = Provider<AppSessionStore>((ref) {
  return const DisabledAppSessionStore();
});

abstract interface class AppSessionStore {
  Future<AppSessionSnapshot?> load({
    required String ownerId,
  });

  Future<void> save(AppSessionSnapshot snapshot);
}

class AppSessionStorageException implements Exception {
  const AppSessionStorageException();
}

class DisabledAppSessionStore implements AppSessionStore {
  const DisabledAppSessionStore();

  @override
  Future<AppSessionSnapshot?> load({
    required String ownerId,
  }) async {
    return null;
  }

  @override
  Future<void> save(AppSessionSnapshot snapshot) async {}
}

class SecureAppSessionStore implements AppSessionStore {
  const SecureAppSessionStore({
    required this.store,
    required this.keyPrefix,
  });

  final SecureKeyValueStore store;
  final String keyPrefix;

  @override
  Future<AppSessionSnapshot?> load({
    required String ownerId,
  }) async {
    final key = _key(ownerId);
    final raw = await store.read(key);
    if (raw == null) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Session root must be an object.');
      }

      final snapshot = AppSessionSnapshot.fromJson(decoded);
      if (snapshot.ownerId != ownerId) {
        throw const FormatException('Session owner does not match its key.');
      }
      return snapshot;
    } catch (_) {
      try {
        await store.delete(key);
      } catch (_) {
        // The caller still receives a fail-closed storage error.
      }
      throw const AppSessionStorageException();
    }
  }

  @override
  Future<void> save(AppSessionSnapshot snapshot) {
    return store.write(
      _key(snapshot.ownerId),
      jsonEncode(snapshot.toJson()),
    );
  }

  String _key(String ownerId) => '$keyPrefix:$ownerId';
}

class AppSessionSnapshot {
  const AppSessionSnapshot({
    required this.ownerId,
    required this.destination,
    required this.order,
  });

  static const int schemaVersion = 1;

  final String ownerId;
  final AppDestination destination;
  final OrderState order;

  Map<String, dynamic> toJson() {
    return {
      'version': schemaVersion,
      'owner_id': ownerId,
      'destination': destination.name,
      'order_lines': [
        for (final line in order.lines)
          {
            'product_id': line.productId,
            'display_name': line.displayName,
            'quantity': line.quantity,
            'unit_amount': line.unitAmount,
            'currency': line.currency,
            'product_revision': line.productRevision,
          },
      ],
    };
  }

  factory AppSessionSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['version'] != schemaVersion) {
      throw const FormatException('Unsupported app session version.');
    }

    final ownerId = _requiredString(json, 'owner_id');
    final destinationName = _requiredString(json, 'destination');
    final destination = switch (destinationName) {
      'catalog' => AppDestination.catalog,
      'order' => AppDestination.order,
      _ => throw const FormatException('Unsupported app destination.'),
    };

    final rawLines = json['order_lines'];
    if (rawLines is! List) {
      throw const FormatException('Order lines must be a list.');
    }

    final seenProductIds = <String>{};
    final lines = <OrderLine>[];
    for (final rawLine in rawLines) {
      if (rawLine is! Map<String, dynamic>) {
        throw const FormatException('Order line must be an object.');
      }

      final productId = _requiredString(rawLine, 'product_id');
      if (!seenProductIds.add(productId)) {
        throw const FormatException('Duplicate order product identity.');
      }

      final displayName = _requiredString(rawLine, 'display_name');
      final quantity = _requiredInt(rawLine, 'quantity');
      final unitAmount = _requiredInt(rawLine, 'unit_amount');
      final productRevision = _requiredInt(rawLine, 'product_revision');
      final currency = _requiredString(rawLine, 'currency');

      if (quantity <= 0 ||
          unitAmount <= 0 ||
          productRevision < 0 ||
          (currency != 'SYP' && currency != 'USD')) {
        throw const FormatException('Invalid persisted order line.');
      }

      final line = OrderLine(
        productId: productId,
        displayName: displayName,
        quantity: quantity,
        unitAmount: unitAmount,
        currency: currency,
        productRevision: productRevision,
      );
      line.lineAmount;
      lines.add(line);
    }

    final order = OrderState(
      lines: List<OrderLine>.unmodifiable(lines),
    );
    order.totalSyp;
    order.totalUsd;

    return AppSessionSnapshot(
      ownerId: ownerId,
      destination: destination,
      order: order,
    );
  }

  static String _requiredString(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException('$key must be a nonempty string.');
  }

  static int _requiredInt(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is int && value >= 0 && value <= maxOrderAmount) {
      return value;
    }
    throw FormatException('$key must be a safe nonnegative integer.');
  }
}
