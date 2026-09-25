import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_shell.dart';
import '../../session/application/app_session_controller.dart';
import '../application/auth_controller.dart';
import 'sign_in_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final session = ref.watch(appSessionControllerProvider);

    if (auth.status == AuthStatus.signedOut) {
      return SignInScreen(
        localSessionError: session.errorMessage,
      );
    }

    final ownerId = auth.identity!.userId;
    if (session.status != AppSessionStatus.ready ||
        session.ownerId != ownerId) {
      return const _SessionRestoreScreen();
    }

    return AppShell(
      onSignOut: () {
        ref
            .read(appSessionControllerProvider.notifier)
            .prepareForSignOut();
        ref.read(authControllerProvider.notifier).signOut();
      },
    );
  }
}

class _SessionRestoreScreen extends StatelessWidget {
  const _SessionRestoreScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('session-restoring'),
      appBar: AppBar(
        title: const Text('Sherko Pharma'),
      ),
      body: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
