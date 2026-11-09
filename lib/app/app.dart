import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/app/router.dart';
import 'package:web_crypt/app/theme/app_theme.dart';
import 'package:web_crypt/services/storage_service.dart';

class WebCryptApp extends ConsumerStatefulWidget {
  const WebCryptApp({super.key});

  @override
  ConsumerState<WebCryptApp> createState() => _WebCryptAppState();
}

class _WebCryptAppState extends ConsumerState<WebCryptApp> {
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    final choice = ref.watch(themeChoiceProvider);
    return MaterialApp.router(
      title: 'web-crypt',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (choice) {
        ThemeChoice.system => ThemeMode.system,
        ThemeChoice.light => ThemeMode.light,
        ThemeChoice.dark => ThemeMode.dark,
      },
      routerConfig: _router,
      // stops very large system text from overflowing
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 2,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
