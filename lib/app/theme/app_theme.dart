import 'package:flutter/material.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/spacing.dart';

const fontFamily = 'Inter';
const monoFontFamily = 'JetBrainsMono';

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final textTheme = _textTheme(colors);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: colors.accentText,
      secondary: colors.accent,
      onSecondary: colors.accentText,
      error: colors.danger,
      onError: colors.accentText,
      surface: colors.surface,
      onSurface: colors.text,
      surfaceContainerHighest: colors.surfaceMuted,
      outline: colors.border,
      outlineVariant: colors.borderStrong,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      fontFamily: fontFamily,
      textTheme: textTheme,
      extensions: [colors],
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium,
      ),
      iconTheme: IconThemeData(color: colors.textMuted, size: 20),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.border),
          borderRadius: BorderRadius.circular(Radii.medium),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        hintStyle: textTheme.bodyMedium?.copyWith(color: colors.textFaint),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.md,
        ),
        border: _inputBorder(colors.border),
        enabledBorder: _inputBorder(colors.border),
        focusedBorder: _inputBorder(colors.focus, width: 2),
        errorBorder: _inputBorder(colors.danger),
        focusedErrorBorder: _inputBorder(colors.danger, width: 2),
        errorStyle: textTheme.bodySmall?.copyWith(color: colors.danger),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.background,
        indicatorColor: colors.accentMuted,
        selectedIconTheme: IconThemeData(color: colors.accent, size: 22),
        unselectedIconTheme: IconThemeData(color: colors.textMuted, size: 22),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colors.text,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colors.textMuted,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.accentMuted,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? colors.accent
                : colors.textMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? colors.text
                : colors.textMuted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.text,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.background,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.small),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.border),
          borderRadius: BorderRadius.circular(Radii.medium),
        ),
        titleTextStyle: textTheme.titleMedium,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: colors.borderStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Radii.medium),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.text,
          borderRadius: BorderRadius.circular(Radii.small),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: colors.background),
        waitDuration: const Duration(milliseconds: 400),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.surfaceMuted,
        circularTrackColor: colors.surfaceMuted,
        linearMinHeight: 4,
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: colors.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.small / 2),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accentText
              : colors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accent
              : colors.surfaceMuted,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accent
              : colors.borderStrong,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.accent,
        selectionColor: colors.accentMuted,
        selectionHandleColor: colors.accent,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.small),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme(AppColors colors) {
    TextStyle style(
      double size,
      FontWeight weight,
      double height, [
      Color? color,
    ]) {
      return TextStyle(
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color ?? colors.text,
        letterSpacing: size >= 24 ? -0.4 : 0,
      );
    }

    return TextTheme(
      headlineSmall: style(24, FontWeight.w600, 1.3),
      titleLarge: style(18, FontWeight.w600, 1.4),
      titleMedium: style(15, FontWeight.w600, 1.45),
      titleSmall: style(13, FontWeight.w600, 1.45),
      bodyLarge: style(15, FontWeight.w400, 1.55),
      bodyMedium: style(15, FontWeight.w400, 1.55),
      bodySmall: style(13, FontWeight.w400, 1.5, colors.textMuted),
      labelLarge: style(15, FontWeight.w500, 1.4),
      labelMedium: style(13, FontWeight.w500, 1.4),
      labelSmall: style(13, FontWeight.w400, 1.4, colors.textMuted),
    );
  }
}

TextStyle monoStyle(BuildContext context, {double size = 13, Color? color}) {
  return TextStyle(
    fontFamily: monoFontFamily,
    fontSize: size,
    height: 1.6,
    color: color ?? context.colors.text,
  );
}
