import 'package:flutter/material.dart';

import '../features/auth/presentation/auth_gate.dart';
import 'app_runtime.dart';

class SherkoPharmaApp extends StatelessWidget {
  const SherkoPharmaApp({
    required this.runtime,
    super.key,
  });

  final AppRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sherko Pharma',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF176B87),
        ),
        visualDensity: VisualDensity.compact,
        scaffoldBackgroundColor: const Color(0xFFF7F9FA),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF7F9FA),
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          isDense: true,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: switch (runtime.status) {
        AppRuntimeStatus.configured => const AuthGate(),
        AppRuntimeStatus.configurationBlocked ||
        AppRuntimeStatus.initializationFailed =>
          _ConfigurationBlockedScreen(
            problems: runtime.problems,
          ),
      },
    );
  }
}

class _ConfigurationBlockedScreen extends StatelessWidget {
  const _ConfigurationBlockedScreen({
    required this.problems,
  });

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sherko Pharma'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              key: const Key('configuration-blocked'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App configuration required',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Protected catalog access stays disabled until the '
                      'Supabase runtime configuration is available.',
                    ),
                    if (problems.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      for (final problem in problems)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• $problem'),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
