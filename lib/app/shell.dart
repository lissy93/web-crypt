import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:web_crypt/app/router.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/widgets/app_logo.dart';

class _Destination {
  const _Destination(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination(Routes.encrypt, 'Encrypt', Icons.lock_outline, Icons.lock),
  _Destination(
    Routes.decrypt,
    'Decrypt',
    Icons.lock_open_outlined,
    Icons.lock_open,
  ),
  _Destination(Routes.keys, 'Keys', Icons.key_outlined, Icons.key),
];

class AppShell extends StatelessWidget {
  const AppShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  int get _index {
    final found = _destinations.indexWhere((d) => location.startsWith(d.path));
    return found < 0 ? 0 : found;
  }

  bool get _onSettings => location.startsWith(Routes.settings);

  String get _page => _onSettings ? 'Settings' : _destinations[_index].label;

  @override
  Widget build(BuildContext context) {
    return Title(
      title: '$_page · web-crypt',
      color: context.colors.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= Layout.wideBreakpoint;
          return wide ? _wide(context) : _narrow(context);
        },
      ),
    );
  }

  Widget _wide(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: Row(
        children: [
          _Rail(
            index: _index,
            onSettings: _onSettings,
            onSelected: (i) => context.go(_destinations[i].path),
          ),
          Container(width: 1, color: colors.border),
          Expanded(child: _content(context)),
        ],
      ),
    );
  }

  Widget _narrow(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const _Wordmark(),
        actions: [
          IconButton(
            icon: Icon(
              _onSettings ? Icons.settings : Icons.settings_outlined,
              size: 20,
            ),
            tooltip: 'Settings',
            onPressed: () => context.go(Routes.settings),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: _content(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => context.go(_destinations[i].path),
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
              tooltip: destination.label,
            ),
        ],
      ),
    );
  }

  // a container, so the page's barrier can't hide the nav from screen readers
  Widget _content(BuildContext context) {
    return Semantics(
      container: true,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Layout.contentMaxWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.index,
    required this.onSelected,
    required this.onSettings,
  });

  final int index;
  final ValueChanged<int> onSelected;
  final bool onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          const SizedBox(height: Space.xl),
          const _Wordmark(compact: true),
          const SizedBox(height: Space.lg),
          Expanded(
            child: NavigationRail(
              selectedIndex: onSettings ? null : index,
              onDestinationSelected: onSelected,
              labelType: NavigationRailLabelType.all,
              minWidth: 96,
              backgroundColor: Colors.transparent,
              destinations: [
                for (final destination in _destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Space.lg),
            child: Column(
              children: [
                IconButton(
                  icon: Icon(
                    onSettings ? Icons.settings : Icons.settings_outlined,
                    size: 22,
                  ),
                  color: onSettings ? colors.accent : colors.textMuted,
                  tooltip: 'Settings',
                  onPressed: () => context.go(Routes.settings),
                ),
                // the button's tooltip already says it
                ExcludeSemantics(
                  child: Text(
                    'Settings',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: onSettings ? colors.text : colors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (compact) {
      return Semantics(
        header: true,
        label: 'web-crypt',
        child: const ExcludeSemantics(child: AppLogo()),
      );
    }
    return Semantics(
      header: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLogo(size: 26),
          const SizedBox(width: Space.md),
          Text(
            'web-crypt',
            style: theme.textTheme.titleMedium?.copyWith(letterSpacing: -0.2),
          ),
        ],
      ),
    );
  }
}
