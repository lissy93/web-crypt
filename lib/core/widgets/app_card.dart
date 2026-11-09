import 'package:flutter/material.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/spacing.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.muted = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: muted ? colors.surfaceMuted : colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(Radii.medium),
      ),
      child: child,
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {this.hint, super.key});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: theme.textTheme.titleSmall),
          if (hint != null) ...[
            const SizedBox(height: Space.xs),
            Text(hint!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
