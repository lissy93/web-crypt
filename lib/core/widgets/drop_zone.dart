import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/services/file_service.dart';

/// takes a drop or a click, and Enter or Space from the keyboard
class DropZone extends ConsumerStatefulWidget {
  const DropZone({
    required this.onFiles,
    required this.title,
    this.subtitle,
    this.icon = Icons.upload_file_outlined,
    this.compact = false,
    this.enabled = true,
    super.key,
  });

  final ValueChanged<List<PickedFile>> onFiles;
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool compact;
  final bool enabled;

  @override
  ConsumerState<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends ConsumerState<DropZone> {
  bool _hovering = false;
  bool _focused = false;
  bool _busy = false;

  Future<void> _browse() async {
    if (_busy || !widget.enabled) return;
    setState(() => _busy = true);
    try {
      final files = await ref.read(fileServiceProvider).pickFiles();
      if (files.isNotEmpty) widget.onFiles(files);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final active = _hovering || _focused;

    return FileDropTarget(
      enabled: widget.enabled,
      onDragChanged: (value) => setState(() => _hovering = value),
      onFiles: widget.onFiles,
      child: Semantics(
        button: true,
        onTap: _browse,
        label: '${widget.title}. ${widget.subtitle ?? ''}',
        child: ExcludeSemantics(
          child: Focus(
            onFocusChange: (value) => setState(() => _focused = value),
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space) {
                _browse();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              onTap: _browse,
              child: MouseRegion(
                cursor: widget.enabled
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: AnimatedContainer(
                  duration: context.motion(Motion.fast),
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: Space.lg,
                    vertical: widget.compact ? Space.lg : Space.xxl,
                  ),
                  decoration: BoxDecoration(
                    color: active ? colors.accentMuted : colors.surfaceMuted,
                    border: Border.all(
                      color: active ? colors.accent : colors.borderStrong,
                      width: active ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(Radii.medium),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_busy)
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          widget.icon,
                          size: widget.compact ? 22 : 28,
                          color: active ? colors.accent : colors.textMuted,
                        ),
                      const SizedBox(height: Space.md),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge,
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: Space.xs),
                        Text(
                          widget.subtitle!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
