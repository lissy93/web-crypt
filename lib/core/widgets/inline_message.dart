import 'package:flutter/material.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/errors/error_messages.dart';

enum MessageTone { error, warning, info, success }

class InlineMessage extends StatelessWidget {
  const InlineMessage({
    required this.title,
    this.hint,
    this.tone = MessageTone.error,
    this.action,
    super.key,
  });

  factory InlineMessage.forError(Object error, {Widget? action}) {
    final message = messageFor(error);
    return InlineMessage(
      title: message.title,
      hint: message.hint,
      action: action,
    );
  }

  final String title;
  final String? hint;
  final MessageTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final (foreground, background, icon) = switch (tone) {
      MessageTone.error => (
        colors.danger,
        colors.dangerMuted,
        Icons.error_outline,
      ),
      MessageTone.warning => (
        colors.warning,
        colors.warningMuted,
        Icons.warning_amber_outlined,
      ),
      MessageTone.info => (
        colors.textMuted,
        colors.surfaceMuted,
        Icons.info_outline,
      ),
      MessageTone.success => (
        colors.success,
        colors.successMuted,
        Icons.check_circle_outline,
      ),
    };

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: foreground.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(Radii.small),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: Space.xs),
                    Text(
                      hint!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: foreground.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                  if (action != null) ...[
                    const SizedBox(height: Space.sm),
                    action!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
