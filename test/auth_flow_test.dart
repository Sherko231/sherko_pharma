import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/app/app_runtime.dart';
import 'package:sherko_pharma/app/app_shell.dart';
import 'package:sherko_pharma/features/auth/application/auth_controller.dart';
import 'package:sherko_pharma/features/auth/domain/auth_identity.dart';
import 'package:sherko_pharma/main.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_catalog_repository.dart';

void main() {
  testWidgets('missing runtime configuration blocks protected UI', (tester) async {
    await tester.pumpWidget(const AppBootstrap());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('configuration-blocked')), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    expect(find.text('Owner sign in'), findsNothing);
  });

  testWidgets('configured signed-out runtime shows sign-in only', (tester) async {
    final gateway = FakeAuthGateway();
    addTearDown(gateway.dispose);

    await tester.pumpWidget(
      AppBootstrap(
        runtime: AppRuntime.configured(
          gateway,
          catalogRepository: FakeCatalogRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Owner sign in'), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    expect(find.textContaining('Register'), findsNothing);
    expect(find.textContaining('Create account'), findsNothing);
  });

  testWidgets('successful email/password sign-in reveals protected shell', (
    tester,
  ) async {
    final gateway = FakeAuthGateway();
    addTearDown(gateway.dispose);

    await tester.pumpWidget(
      AppBootstrap(
        runtime: AppRuntime.configured(
          gateway,
          catalogRepository: FakeCatalogRepository(),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('sign-in-email')),
      'owner@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('sign-in-password')),
      'temporary-secret',
    );

    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pumpAndSettle();

    expect(gateway.signInCalls, 1);
    expect(gateway.lastEmail, 'owner@example.test');
    expect(gateway.lastPassword, 'temporary-secret');
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byKey(const Key('catalog-workspace')), findsOneWidget);
  });

  testWidgets('failed sign-in is generic and clears only the password', (
    tester,
  ) async {
    final gateway = FakeAuthGateway()..failSignIn = true;
    addTearDown(gateway.dispose);

    await tester.pumpWidget(
      AppBootstrap(
        runtime: AppRuntime.configured(
          gateway,
          catalogRepository: FakeCatalogRepository(),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('sign-in-email')),
      'owner@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('sign-in-password')),
      'wrong-password',
    );

    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text(AuthController.signInErrorMessage),
      findsOneWidget,
    );
    final emailField = tester.widget<TextFormField>(
      find.byKey(const Key('sign-in-email')),
    );
    final passwordField = tester.widget<TextFormField>(
      find.byKey(const Key('sign-in-password')),
    );
    expect(emailField.controller?.text, 'owner@example.test');
    expect(passwordField.controller?.text, isEmpty);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('busy sign-in blocks duplicate authentication requests', (
    tester,
  ) async {
    final gateway = FakeAuthGateway();
    final gate = Completer<void>();
    gateway.signInGate = gate;
    addTearDown(gateway.dispose);

    await tester.pumpWidget(
      AppBootstrap(
        runtime: AppRuntime.configured(
          gateway,
          catalogRepository: FakeCatalogRepository(),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('sign-in-email')),
      'owner@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('sign-in-password')),
      'temporary-secret',
    );

    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('sign-in-submit')),
    );
    expect(button.onPressed, isNull);
    expect(gateway.signInCalls, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('sign-out hides protected UI before gateway work completes', (
    tester,
  ) async {
    final gateway = FakeAuthGateway(
      initialIdentity: const AuthIdentity(
        userId: 'owner-user-id',
        email: 'owner@example.test',
      ),
    );
    final gate = Completer<void>();
    gateway.signOutGate = gate;
    addTearDown(gateway.dispose);

    await tester.pumpWidget(
      AppBootstrap(
        runtime: AppRuntime.configured(
          gateway,
          catalogRepository: FakeCatalogRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);

    await tester.tap(find.byKey(const Key('sign-out-button')));
    await tester.pump();

    expect(gateway.signOutCalls, 1);
    expect(find.byType(AppShell), findsNothing);
    expect(find.text('Owner sign in'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('signed-out auth event removes an already visible shell', (
    tester,
  ) async {
    final gateway = FakeAuthGateway(
      initialIdentity: const AuthIdentity(
        userId: 'owner-user-id',
        email: 'owner@example.test',
      ),
    );
    addTearDown(gateway.dispose);

    await tester.pumpWidget(
      AppBootstrap(
        runtime: AppRuntime.configured(
          gateway,
          catalogRepository: FakeCatalogRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);

    gateway.emitIdentity(null);
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsNothing);
    expect(find.text(AuthController.sessionEndedMessage), findsOneWidget);
  });

  testWidgets('restored authenticated identity starts in protected shell', (
    tester,
  ) async {
    final gateway = FakeAuthGateway(
      initialIdentity: const AuthIdentity(
        userId: 'owner-user-id',
      ),
    );
    addTearDown(gateway.dispose);

    await tester.pumpWidget(
      AppBootstrap(
        runtime: AppRuntime.configured(
          gateway,
          catalogRepository: FakeCatalogRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('Owner sign in'), findsNothing);
  });
}
