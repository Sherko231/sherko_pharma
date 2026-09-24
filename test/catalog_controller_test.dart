import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/auth/application/auth_controller.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/features/catalog/application/catalog_detail_controller.dart';
import 'package:sherko_pharma/features/catalog/application/catalog_search_controller.dart';
import 'package:sherko_pharma/features/catalog/data/catalog_repository.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

ProviderContainer containerFor(
  FakeAuthGateway auth,
  FakeCatalogRepository catalog,
) {
  return ProviderContainer(
    overrides: [
      authGatewayProvider.overrideWithValue(auth),
      catalogRepositoryProvider.overrideWithValue(catalog),
    ],
  );
}

void main() {
  test('blank search performs no repository call', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner'),
    );
    final catalog = FakeCatalogRepository();
    final container = containerFor(auth, catalog);
    addTearDown(container.dispose);
    addTearDown(auth.dispose);

    await container
        .read(catalogSearchControllerProvider.notifier)
        .submit('   ');

    expect(catalog.searchCalls, isEmpty);
    expect(
      container.read(catalogSearchControllerProvider).status,
      CatalogSearchStatus.idle,
    );
  });

  test('search passes query unchanged with a maximum request of 25', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner'),
    );
    final catalog = FakeCatalogRepository()
      ..searchResults = [testProduct()];
    final container = containerFor(auth, catalog);
    addTearDown(container.dispose);
    addTearDown(auth.dispose);

    await container
        .read(catalogSearchControllerProvider.notifier)
        .submit('  أسبرين  ');

    expect(catalog.searchCalls, hasLength(1));
    expect(catalog.searchCalls.single.query, '  أسبرين  ');
    expect(catalog.searchCalls.single.limit, 25);
    expect(
      container.read(catalogSearchControllerProvider).status,
      CatalogSearchStatus.results,
    );
  });

  test('successful zero-row search is empty, not error', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner'),
    );
    final catalog = FakeCatalogRepository();
    final container = containerFor(auth, catalog);
    addTearDown(container.dispose);
    addTearDown(auth.dispose);

    await container
        .read(catalogSearchControllerProvider.notifier)
        .submit('missing');

    expect(
      container.read(catalogSearchControllerProvider).status,
      CatalogSearchStatus.empty,
    );
  });

  test('repository failure becomes retryable error state', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner'),
    );
    final catalog = FakeCatalogRepository()
      ..onSearch = (query, limit) async {
        throw const CatalogRepositoryException();
      };
    final container = containerFor(auth, catalog);
    addTearDown(container.dispose);
    addTearDown(auth.dispose);

    await container
        .read(catalogSearchControllerProvider.notifier)
        .submit('failure');

    expect(
      container.read(catalogSearchControllerProvider).status,
      CatalogSearchStatus.error,
    );
  });

  test('late older search cannot replace a newer search', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner'),
    );
    final first = Completer<List<dynamic>>();
    final second = Completer<List<dynamic>>();
    final catalog = FakeCatalogRepository()
      ..onSearch = (query, _) {
        if (query == 'first') {
          return first.future.then((rows) => rows.cast());
        }
        return second.future.then((rows) => rows.cast());
      };
    final container = containerFor(auth, catalog);
    addTearDown(container.dispose);
    addTearDown(auth.dispose);

    final firstSearch = container
        .read(catalogSearchControllerProvider.notifier)
        .submit('first');
    final secondSearch = container
        .read(catalogSearchControllerProvider.notifier)
        .submit('second');

    second.complete([testProduct(id: 'second', nameEn: 'Second')]);
    await secondSearch;

    expect(
      container.read(catalogSearchControllerProvider).products.single.id,
      'second',
    );

    first.complete([testProduct(id: 'first', nameEn: 'First')]);
    await firstSearch;

    expect(
      container.read(catalogSearchControllerProvider).products.single.id,
      'second',
    );
  });

  test('late older detail cannot replace the newer selected product', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner'),
    );
    final first = Completer<dynamic>();
    final second = Completer<dynamic>();
    final catalog = FakeCatalogRepository()
      ..onGet = (productId) {
        return productId == 'first'
            ? first.future.then((value) => value)
            : second.future.then((value) => value);
      };
    final container = containerFor(auth, catalog);
    addTearDown(container.dispose);
    addTearDown(auth.dispose);

    final firstLoad = container
        .read(catalogDetailControllerProvider.notifier)
        .load('first');
    final secondLoad = container
        .read(catalogDetailControllerProvider.notifier)
        .load('second');

    second.complete(testProduct(id: 'second', nameEn: 'Second'));
    await secondLoad;
    expect(
      container.read(catalogDetailControllerProvider).product?.id,
      'second',
    );

    first.complete(testProduct(id: 'first', nameEn: 'First'));
    await firstLoad;
    expect(
      container.read(catalogDetailControllerProvider).product?.id,
      'second',
    );
  });

  test('detail distinguishes not found from generic error', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner'),
    );
    final catalog = FakeCatalogRepository()
      ..onGet = (_) async {
        throw const CatalogNotFoundException();
      };
    final container = containerFor(auth, catalog);
    addTearDown(container.dispose);
    addTearDown(auth.dispose);

    await container
        .read(catalogDetailControllerProvider.notifier)
        .load('missing');

    expect(
      container.read(catalogDetailControllerProvider).status,
      CatalogDetailStatus.notFound,
    );

    catalog.onGet = (_) async {
      throw const CatalogRepositoryException();
    };
    await container
        .read(catalogDetailControllerProvider.notifier)
        .load('broken');

    expect(
      container.read(catalogDetailControllerProvider).status,
      CatalogDetailStatus.error,
    );
  });
}
