import 'package:flutter/material.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/spacing.dart';

class SegmentedOption<T> {
  const SegmentedOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// each option is its own focus stop, and reads as one choice out of a group
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    super.key,
  });

  final List<SegmentedOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      label: label,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(Radii.small),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              Flexible(
                child: _Segment<T>(
                  option: option,
                  selected: option.value == value,
                  onSelected: () => onChanged(option.value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.option,
    required this.selected,
    required this.onSelected,
  });

  final SegmentedOption<T> option;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      onTap: onSelected,
      label: option.label,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(Radii.small - 2),
          focusColor: colors.focus.withValues(alpha: 0.25),
          hoverColor: colors.border.withValues(alpha: 0.4),
          child: AnimatedContainer(
            duration: context.motion(Motion.fast),
            constraints: const BoxConstraints(minHeight: Layout.minTapTarget),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.sm,
            ),
            decoration: BoxDecoration(
              color: selected ? colors.surface : Colors.transparent,
              border: Border.all(
                color: selected ? colors.borderStrong : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(Radii.small - 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (option.icon != null) ...[
                  Icon(
                    option.icon,
                    size: 16,
                    color: selected ? colors.text : colors.textMuted,
                  ),
                  const SizedBox(width: Space.sm),
                ],
                Flexible(
                  child: Text(
                    option.label,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected ? colors.text : colors.textMuted,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
