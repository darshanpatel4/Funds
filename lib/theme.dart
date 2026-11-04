import 'package:flutter/material.dart';

/// Colours from the approved design (Instagram-style dark).
class C {
  C._();

  static const bg = Color(0xFF000000);
  static const surface = Color(0xFF121212);
  static const surface2 = Color(0xFF262626);
  static const line = Color(0xFF262626);
  static const border = Color(0xFF363636);
  static const dashed = Color(0xFF3D3D3D);

  static const text = Color(0xFFFFFFFF);
  static const muted = Color(0xFFA8A8A8);
  static const faint = Color(0xFF8E8E8E);

  static const accent = Color(0xFF0095F6);
  static const accentTint = Color(0xFF0B2338);
  static const accentDeep = Color(0xFF0077C5);
  static const onAccentSoft = Color(0xFFEAF5FF);

  /// Red card used when the monthly budget is overspent.
  static const danger = Color(0xFFB0182A);
  static const dangerDeep = Color(0xFF8A1220);
  static const onDangerSoft = Color(0xFFFFE3E6);

  static const income = Color(0xFF4ADE80);
  static const expense = Color(0xFFFF3040);
  static const transfer = Color(0xFF67D4F5);

  static const blue = Color(0xFF8EC5FF);
  static const orange = Color(0xFFFFB870);
  static const yellow = Color(0xFFF0C674);
  static const pink = Color(0xFFF08BD0);
  static const teal = Color(0xFF7FE0D0);
}

const _tabular = [FontFeature.tabularFigures()];

List<FontVariation> _weightAxis(FontWeight w) =>
    [FontVariation.weight(w.value.toDouble())];

/// Text style helper. Manrope is a variable font, so the weight is set both
/// as a [FontWeight] and as the font's `wght` axis.
TextStyle ts(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color color = C.text,
  double? height,
  double letterSpacing = 0,
}) {
  return TextStyle(
    fontFamily: 'Manrope',
    fontSize: size,
    fontWeight: weight,
    fontVariations: _weightAxis(weight),
    fontFeatures: _tabular,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'Manrope',
  );

  TextStyle f(TextStyle? s, FontWeight w) => (s ?? const TextStyle()).copyWith(
        fontFamily: 'Manrope',
        fontWeight: w,
        fontVariations: _weightAxis(w),
        color: C.text,
      );

  final t = base.textTheme;
  const scheme = ColorScheme.dark(
    primary: C.accent,
    onPrimary: Colors.white,
    secondary: C.accent,
    onSecondary: Colors.white,
    surface: C.surface,
    onSurface: C.text,
    onSurfaceVariant: C.muted,
    surfaceContainerHighest: C.surface2,
    surfaceContainerHigh: C.surface,
    surfaceContainer: C.surface,
    outline: C.border,
    outlineVariant: C.line,
    error: C.expense,
  );

  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.bg,
    colorScheme: scheme,
    dividerColor: C.line,
    splashFactory: InkSparkle.splashFactory,
    textTheme: t.copyWith(
      displaySmall: f(t.displaySmall, FontWeight.w800),
      headlineLarge: f(t.headlineLarge, FontWeight.w800),
      headlineMedium: f(t.headlineMedium, FontWeight.w800),
      headlineSmall: f(t.headlineSmall, FontWeight.w800),
      titleLarge: f(t.titleLarge, FontWeight.w800),
      titleMedium: f(t.titleMedium, FontWeight.w700),
      titleSmall: f(t.titleSmall, FontWeight.w700),
      bodyLarge: f(t.bodyLarge, FontWeight.w600),
      bodyMedium: f(t.bodyMedium, FontWeight.w500),
      bodySmall: f(t.bodySmall, FontWeight.w500),
      labelLarge: f(t.labelLarge, FontWeight.w700),
      labelMedium: f(t.labelMedium, FontWeight.w700),
      labelSmall: f(t.labelSmall, FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: C.bg,
      foregroundColor: C.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: ts(18, weight: FontWeight.w800),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.surface2,
      contentTextStyle: ts(14, weight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: ts(18, weight: FontWeight.w800),
      contentTextStyle: ts(14, color: C.muted, height: 1.45),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: C.border,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : C.faint,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? C.accent : C.border,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: C.accent,
      selectionColor: C.accentDeep,
      selectionHandleColor: C.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      labelStyle: ts(14, color: C.muted, weight: FontWeight.w600),
      floatingLabelStyle: ts(14, color: C.muted, weight: FontWeight.w700),
      hintStyle: ts(15, color: C.faint, weight: FontWeight.w600),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: C.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: C.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: C.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: C.expense),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: C.expense, width: 1.5),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: C.surface,
      headerForegroundColor: C.text,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.accent),
  );
}
