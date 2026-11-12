import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:web_crypt/app/shell.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/features/decrypt/decrypt_screen.dart';
import 'package:web_crypt/features/encrypt/encrypt_screen.dart';
import 'package:web_crypt/features/keys/keys_screen.dart';
import 'package:web_crypt/features/settings/settings_screen.dart';

class Routes {
  const Routes._();

  static const encrypt = '/encrypt';
  static const decrypt = '/decrypt';
  static const keys = '/keys';
  static const settings = '/settings';
}

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: Routes.encrypt,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: Routes.encrypt,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: EncryptScreen()),
          ),
          GoRoute(
            path: Routes.decrypt,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DecryptScreen()),
          ),
          GoRoute(
            path: Routes.keys,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: KeysScreen()),
          ),
          GoRoute(
            path: Routes.settings,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => const _NotFound(),
  );
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return Title(
      title: 'Not found · web-crypt',
      color: context.colors.background,
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('That page does not exist.'),
              const SizedBox(height: Space.lg),
              TextButton(
                onPressed: () => context.go(Routes.encrypt),
                child: const Text('Go to Encrypt'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
