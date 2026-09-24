import 'package:flutter/material.dart';

import 'app_shell.dart';

class SherkoPharmaApp extends StatelessWidget {
  const SherkoPharmaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sherko Pharma',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}
