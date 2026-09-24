import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_shell.dart';
import '../application/auth_controller.dart';
import 'sign_in_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return switch (auth.status) {
      AuthStatus.signedIn => AppShell(
          onSignOut: () {
            ref.read(authControllerProvider.notifier).signOut();
          },
        ),
      AuthStatus.signedOut => const SignInScreen(),
    };
  }
}
