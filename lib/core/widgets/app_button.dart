import 'package:flutter/material.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/spacing.dart';

enum AppButtonKind { primary, secondary, quiet, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.kind = AppButtonKind.secondary,
    this.icon,
    this.busy = false,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onPressed != null && !busy;
    final (background, foreground, border) = switch (kind) {
      AppButtonKind.primary => (
        colors.accent,
        colors.accentText,
        colors.accent,
      ),
      AppButtonKind.secondary => (
        colors.surface,
        colors.text,
        colors.borderStrong,
      ),
      AppButtonKind.quiet => (
        Colors.transparent,
        colors.textMuted,
        Colors.transparent,
      ),
      AppButtonKind.danger => (colors.surface, colors.danger, colors.danger),
    };

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: Layout.minTapTarget,
        minWidth: expand ? double.infinity : 0,
      ),
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (!enabled) return colors.surfaceMuted;
            if (states.contains(WidgetState.focused)) {
              return Color.alphaBlend(
                colors.focus.withValues(alpha: 0.18),
                background,
              );
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return Color.alphaBlend(
                colors.text.withValues(alpha: 0.06),
                background,
              );
            }
            return background;
          }),
          foregroundColor: WidgetStateProperty.all(
            enabled ? foreground : colors.textFaint,
          ),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          side: WidgetStateProperty.resolveWith((states) {
            if (!enabled) return BorderSide(color: colors.border);
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: colors.focus, width: 2);
            }
            return BorderSide(color: border);
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.small),
            ),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: Space.lg),
          ),
          textStyle: WidgetStateProperty.all(
            Theme.of(context).textTheme.labelLarge,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: enabled ? foreground : colors.textFaint,
                  ),
                ),
              )
            else if (icon != null)
              Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: Icon(
                  icon,
                  size: 18,
                  color: enabled ? foreground : colors.textFaint,
                ),
              ),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        color: color ?? context.colors.textMuted,
        splashRadius: 20,
        constraints: const BoxConstraints(
          minWidth: Layout.minTapTarget,
          minHeight: Layout.minTapTarget,
        ),
        // the Tooltip above already announces it
        tooltip: null,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.small),
          ),
        ),
      ),
    );
  }
}
