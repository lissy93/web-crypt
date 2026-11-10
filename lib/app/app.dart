import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:web_crypt/app/browser_stub.dart'
    if (dart.library.js_interop) 'package:web_crypt/app/browser_web.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/app/router.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
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
  void initState() {
    super.initState();
    onLaunch((route, file) {
      if (file != null) {
        ref.read(openedFileProvider.notifier).open(file);
        _router.go(Routes.decrypt);
      } else if (route != '/') {
        // a plain launch names no page, so the one showing stays
        _router.go(route);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final choice = ref.watch(themeChoiceProvider);
    // no title here, each page sets its own
    return MaterialApp.router(
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
      builder: (context, child) => _PageTheme(
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 2,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// keeps the browser bar and page colours in step with the app theme
class _PageTheme extends StatefulWidget {
  const _PageTheme({required this.child});

  final Widget child;

  @override
  State<_PageTheme> createState() => _PageThemeState();
}

class _PageThemeState extends State<_PageTheme> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setPageTheme(context.colors.background, Theme.of(context).brightness);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
