import 'package:flutter/material.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/utils/passphrase_strength.dart';

class PassphraseField extends StatefulWidget {
  const PassphraseField({
    required this.controller,
    required this.label,
    this.hint,
    this.autofocus = false,
    this.errorText,
    this.onSubmitted,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool autofocus;
  final String? errorText;
  final VoidCallback? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<PassphraseField> createState() => _PassphraseFieldState();
}

class _PassphraseFieldState extends State<PassphraseField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: !_visible,
      autofocus: widget.autofocus,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: widget.onChanged,
      onSubmitted: (_) => widget.onSubmitted?.call(),
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          constraints: const BoxConstraints(
            minWidth: Layout.minTapTarget,
            minHeight: Layout.minTapTarget,
          ),
          icon: Icon(
            _visible
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 18,
          ),
          tooltip: _visible ? 'Hide passphrase' : 'Show passphrase',
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}

class PassphraseStrengthBar extends StatelessWidget {
  const PassphraseStrengthBar({required this.passphrase, super.key});

  final String passphrase;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    if (passphrase.isEmpty) return const SizedBox.shrink();

    final score = scorePassphrase(passphrase);
    final colour = switch (score.level) {
      PassphraseLevel.weak => colors.danger,
      PassphraseLevel.fair => colors.warning,
      PassphraseLevel.good => colors.success,
      PassphraseLevel.strong => colors.success,
    };

    return Semantics(
      liveRegion: true,
      label: 'Passphrase strength ${score.label}. ${score.advice}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i == 3 ? 0 : Space.xs),
                        child: AnimatedContainer(
                          duration: context.motion(Motion.fast),
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= score.level.index
                                ? colour
                                : colors.surfaceMuted,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(
                '${score.label}. ${score.advice}',
                style: theme.textTheme.bodySmall?.copyWith(color: colour),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
