import 'package:flutter/material.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/app_theme.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/widgets/app_button.dart';
import 'package:web_crypt/core/widgets/copy_field.dart';

/// read-only monospace result, with the actions that belong to it
class OutputPane extends StatefulWidget {
  const OutputPane({
    required this.title,
    required this.value,
    required this.onStartOver,
    this.onSave,
    this.sensitive = false,
    this.footnote,
    super.key,
  });

  final String title;
  final String value;
  final VoidCallback onStartOver;
  final VoidCallback? onSave;
  final bool sensitive;
  final String? footnote;

  @override
  State<OutputPane> createState() => _OutputPaneState();
}

class _OutputPaneState extends State<OutputPane> {
  /// its own, so it never fights the page for the primary scroll controller
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: colors.success),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                widget.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.success,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(Radii.small),
          ),
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              child: SelectableText(widget.value, style: monoStyle(context)),
            ),
          ),
        ),
        if (widget.footnote != null) ...[
          const SizedBox(height: Space.sm),
          Text(widget.footnote!, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            AppButton(
              label: 'Copy',
              icon: Icons.copy_outlined,
              kind: AppButtonKind.primary,
              onPressed: () => copyToClipboard(
                context,
                widget.value,
                what: widget.title,
                sensitive: widget.sensitive,
              ),
            ),
            if (widget.onSave != null)
              AppButton(
                label: 'Save as file',
                icon: Icons.download_outlined,
                onPressed: widget.onSave,
              ),
            AppButton(
              label: 'Start over',
              kind: AppButtonKind.quiet,
              onPressed: widget.onStartOver,
            ),
          ],
        ),
      ],
    );
  }
}
