import 'package:flutter/material.dart';
import 'package:web_crypt/app/theme/spacing.dart';

/// the same page frame everywhere: heading, a line of context, then content
class ScreenScaffold extends StatefulWidget {
  const ScreenScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  State<ScreenScaffold> createState() => _ScreenScaffoldState();
}

class _ScreenScaffoldState extends State<ScreenScaffold> {
  /// its own, because desktop does not hand out a primary scroll controller
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(
          Space.xl,
          Space.xl,
          Space.xl,
          Space.xxxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          widget.title,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: Space.xs),
                        Text(
                          widget.subtitle!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: Space.lg),
                  widget.trailing!,
                ],
              ],
            ),
            const SizedBox(height: Space.xl),
            ...widget.children,
          ],
        ),
      ),
    );
  }
}
