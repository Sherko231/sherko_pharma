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

  test('search refresh replaces results without clearing visible state first', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner'),
    );
    final catalog = FakeCatalogRepository()
      ..searchResults = [
        testProduct(id: 'p1', nameEn: 'Old', revision: 1),
      ];
    final container = containerFor(auth, catalog);
    addTearDown(container.dispose);
    addTearDown(auth.dispose);

    await container
        .read(catalogSearchControllerProvider.notifier)
        .submit('aspirin');

    catalog.searchResults = [
      testProduct(id: 'p1', nameEn: 'New', revision: 2),
    ];

    final refreshed =
        await container.read(catalogSearchControllerProvider.notifier).refresh();

    expect(refreshed, isTrue);
    final state = container.read(catalogSearchControllerProvider);
    expect(state.status, CatalogSearchStatus.results);
    expect(state.products.single.displayName, 'New');
    expect(state.products.single.revision, 2);
    expect(state.refreshFailed, isFalse);
  });

  test('failed search refresh keeps last known results visible', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner'),
    );
    final catalog = FakeCatalogRepository()
      ..searchResults = [
        testProduct(id: 'p1', nameEn: 'Known', revision: 1),
      ];
    final container = containerFor(auth, catalog);
    addTearDown(container.dispose);
    addTearDown(auth.dispose);

    await container
        .read(catalogSearchControllerProvider.notifier)
        .submit('aspirin');

    catalog.onSearch = (_, __) async {
      throw const CatalogRepositoryException();
    };

    final refreshed =
        await container.read(catalogSearchControllerProvider.notifier).refresh();

    expect(refreshed, isFalse);
    final state = container.read(catalogSearchControllerProvider);
    expect(state.status, CatalogSearchStatus.results);
    expect(state.products.single.displayName, 'Known');
    expect(state.refreshFailed, isTrue);
    expect(state.isRefreshing, isFalse);
  });

  test('failed detail refresh keeps last known product visible', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner'),
    );
    final catalog = FakeCatalogRepository()
      ..products['p1'] = testProduct(
        id: 'p1',
        nameEn: 'Known detail',
        revision: 1,
      );
    final container = containerFor(auth, catalog);
    addTearDown(container.dispose);
    addTearDown(auth.dispose);

    await container
        .read(catalogDetailControllerProvider.notifier)
        .load('p1');

    catalog.onGet = (_) async {
      throw const CatalogRepositoryException();
    };

    final refreshed =
        await container.read(catalogDetailControllerProvider.notifier).refresh();

    expect(refreshed, isFalse);
    final state = container.read(catalogDetailControllerProvider);
    expect(state.status, CatalogDetailStatus.loaded);
    expect(state.product?.displayName, 'Known detail');
    expect(state.refreshFailed, isTrue);
    expect(state.isRefreshing, isFalse);
  });


  test('refresh does not supersede an in-flight initial search', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner'),
    );
    final gate = Completer<List<dynamic>>();
    final catalog = FakeCatalogRepository()
      ..onSearch = (_, __) => gate.future.then((rows) => rows.cast());
    final container = containerFor(auth, catalog);
    addTearDown(container.dispose);
    addTearDown(auth.dispose);

    final pending = container
        .read(catalogSearchControllerProvider.notifier)
        .submit('aspirin');
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(catalogSearchControllerProvider).status,
      CatalogSearchStatus.loading,
    );
    expect(
      await container.read(catalogSearchControllerProvider.notifier).refresh(),
      isTrue,
    );
    expect(catalog.searchCalls, hasLength(1));

    gate.complete([testProduct(id: 'p1', nameEn: 'Loaded')]);
    await pending;

    final state = container.read(catalogSearchControllerProvider);
    expect(state.status, CatalogSearchStatus.results);
    expect(state.products.single.displayName, 'Loaded');
  });

  test('refresh does not supersede an in-flight initial detail load', () async {
    final auth = FakeAuthGateway(
      initialIdentity: const AuthIdentity(userId: 'owner'),
    );
    final gate = Completer<dynamic>();
    final catalog = FakeCatalogRepository()
      ..onGet = (_) => gate.future.then((value) => value);
    final container = containerFor(auth, catalog);
    addTearDown(container.dispose);
    addTearDown(auth.dispose);

    final pending = container
        .read(catalogDetailControllerProvider.notifier)
        .load('p1');
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(catalogDetailControllerProvider).status,
      CatalogDetailStatus.loading,
    );
    expect(
      await container.read(catalogDetailControllerProvider.notifier).refresh(),
      isTrue,
    );
    expect(catalog.detailCalls, ['p1']);

    gate.complete(testProduct(id: 'p1', nameEn: 'Loaded detail'));
    await pending;

    final state = container.read(catalogDetailControllerProvider);
    expect(state.status, CatalogDetailStatus.loaded);
    expect(state.product?.displayName, 'Loaded detail');
  });

}
