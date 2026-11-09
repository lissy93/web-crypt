import 'package:flutter/material.dart';

/// every colour the app uses, read through
/// `Theme.of(context).extension<AppColors>()` and never as a literal
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.accentText,
    required this.accentMuted,
    required this.success,
    required this.successMuted,
    required this.danger,
    required this.dangerMuted,
    required this.warning,
    required this.warningMuted,
    required this.focus,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color accent;
  final Color accentText;
  final Color accentMuted;
  final Color success;
  final Color successMuted;
  final Color danger;
  final Color dangerMuted;
  final Color warning;
  final Color warningMuted;
  final Color focus;

  static const light = AppColors(
    background: Color(0xFFFBFBFA),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF4F4F2),
    border: Color(0xFFE2E2DE),
    borderStrong: Color(0xFFC7C7C1),
    text: Color(0xFF1A1A18),
    textMuted: Color(0xFF56564F),
    textFaint: Color(0xFF6B6B63),
    accent: Color(0xFF1E5F74),
    accentText: Color(0xFFFFFFFF),
    accentMuted: Color(0xFFE8F0F3),
    success: Color(0xFF2C6E49),
    successMuted: Color(0xFFE7F1EB),
    danger: Color(0xFFA4262C),
    dangerMuted: Color(0xFFFAEAEA),
    warning: Color(0xFF8A5A00),
    warningMuted: Color(0xFFFBF1DF),
    focus: Color(0xFF1E5F74),
  );

  static const dark = AppColors(
    background: Color(0xFF191A19),
    surface: Color(0xFF212322),
    surfaceMuted: Color(0xFF2A2C2B),
    border: Color(0xFF383A39),
    borderStrong: Color(0xFF4E5150),
    text: Color(0xFFECECE8),
    textMuted: Color(0xFFB2B3AE),
    textFaint: Color(0xFF8B8D88),
    accent: Color(0xFF6FB3C6),
    accentText: Color(0xFF10221E),
    accentMuted: Color(0xFF223034),
    success: Color(0xFF7FC49B),
    successMuted: Color(0xFF20302A),
    danger: Color(0xFFE79A9D),
    dangerMuted: Color(0xFF362426),
    warning: Color(0xFFD9AE6A),
    warningMuted: Color(0xFF322A1D),
    focus: Color(0xFF6FB3C6),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? textMuted,
    Color? textFaint,
    Color? accent,
    Color? accentText,
    Color? accentMuted,
    Color? success,
    Color? successMuted,
    Color? danger,
    Color? dangerMuted,
    Color? warning,
    Color? warningMuted,
    Color? focus,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      accent: accent ?? this.accent,
      accentText: accentText ?? this.accentText,
      accentMuted: accentMuted ?? this.accentMuted,
      success: success ?? this.success,
      successMuted: successMuted ?? this.successMuted,
      danger: danger ?? this.danger,
      dangerMuted: dangerMuted ?? this.dangerMuted,
      warning: warning ?? this.warning,
      warningMuted: warningMuted ?? this.warningMuted,
      focus: focus ?? this.focus,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceMuted: mix(surfaceMuted, other.surfaceMuted),
      border: mix(border, other.border),
      borderStrong: mix(borderStrong, other.borderStrong),
      text: mix(text, other.text),
      textMuted: mix(textMuted, other.textMuted),
      textFaint: mix(textFaint, other.textFaint),
      accent: mix(accent, other.accent),
      accentText: mix(accentText, other.accentText),
      accentMuted: mix(accentMuted, other.accentMuted),
      success: mix(success, other.success),
      successMuted: mix(successMuted, other.successMuted),
      danger: mix(danger, other.danger),
      dangerMuted: mix(dangerMuted, other.dangerMuted),
      warning: mix(warning, other.warning),
      warningMuted: mix(warningMuted, other.warningMuted),
      focus: mix(focus, other.focus),
    );
  }
}

extension AppColorsOf on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
