import 'package:material_ui/material_ui.dart';

/// Цвета и шрифты по docs/design.md.
class Rubka {
  static const primary = Color(0xFF0F5C63);
  static const amber = Color(0xFFF2B33D);
  static const onAmber = Color(0xFF3A2600);
  static const bg = Color(0xFFF6F1E7);
  static const panel = Color(0xFFEDE6D6);
  static const surface = Color(0xFFFFFFFF);
  static const text = Color(0xFF1F2A2E);
  static const text2 = Color(0xFF5A6468);
  static const border = Color(0xFFD9D0BC);
  static const success = Color(0xFF1B6E3A);
  static const working = Color(0xFF8A5A00);
  static const error = Color(0xFFB3261E);
  static const selected = Color(0xFFDCEBEB);
  static const summaryBg = Color(0xFFFFF3D6);
  static const errorBg = Color(0xFFFBE9E7);
  static const codeBg = Color(0xFFEFE9DA);
  static const disabledBg = Color(0xFFE3DCCB);
  static const disabledFg = Color(0xFF76706A);

  // Версия 1.2 «Минимал».
  static const side = Color(0xFFFAFAF7);
  static const sideSelected = Color(0xFFE9EFEF);
  static const line = Color(0xFFECE8E0);
  static const field = Color(0xFFF3F1EC);
  static const mute = Color(0xFF8A8F92);
  static const dotGray = Color(0xFFC9C4BA);
  static const askBg = Color(0xFFFFFBF0);

  // Версия 1.2 «Плитки».
  static const bento = Color(0xFFEEF0F2);
  static const ink = Color(0xFF111315);
  static const ink2 = Color(0xFF6B7177);
  static const bubble = Color(0xFFF4F5F6);
  static const orange1 = Color(0xFFFF7A30);
  static const orange2 = Color(0xFFFF4D2E);
  static const send = Color(0xFFFF5A2E);
  static const yes = Color(0xFF16A34A);
  static const tagWaitBg = Color(0xFFFFE7D6);
  static const tagWaitFg = Color(0xFFC2410C);
  static const tagOkBg = Color(0xFFE7F8D0);
  static const tagOkFg = Color(0xFF3F6212);
  static const tagBadBg = Color(0xFFFDE2E2);
  static const tagBadFg = Color(0xFFB91C1C);
  static const tagIdleBg = Color(0xFFEEF0F2);
  static const tagIdleFg = Color(0xFF555555);

  static const headFont = 'Bahnschrift';
  static const bodyFont = 'Segoe UI Variable';
  static const monoFont = 'Cascadia Mono';
  static const fallback = ['Segoe UI'];
  static const monoFallback = ['Consolas'];

  static TextStyle head(double size,
          {FontWeight weight = FontWeight.w600, Color color = text}) =>
      TextStyle(
          fontFamily: headFont,
          fontFamilyFallback: fallback,
          fontSize: size,
          fontWeight: weight,
          color: color);

  static TextStyle body(
          {double size = 15, Color color = text, FontWeight? weight}) =>
      TextStyle(
          fontFamily: bodyFont,
          fontFamilyFallback: fallback,
          fontSize: size,
          height: 1.5,
          fontWeight: weight,
          color: color);

  static TextStyle mono({double size = 13, Color color = text}) => TextStyle(
      fontFamily: monoFont,
      fontFamilyFallback: monoFallback,
      fontSize: size,
      color: color);
}

/// Стиль главного действия: оранжевая кнопка.
final ButtonStyle accentButtonStyle = FilledButton.styleFrom(
  backgroundColor: Rubka.send,
  foregroundColor: Colors.white,
  disabledBackgroundColor: Rubka.disabledBg,
  disabledForegroundColor: Rubka.disabledFg,
);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Rubka.primary).copyWith(
    primary: Rubka.primary,
    onPrimary: Colors.white,
    secondary: Rubka.amber,
    onSecondary: Rubka.onAmber,
    surface: Rubka.surface,
    onSurface: Rubka.text,
    error: Rubka.error,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  const minSize = Size(64, 48);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Rubka.bento,
    fontFamily: Rubka.bodyFont,
    fontFamilyFallback: Rubka.fallback,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: minSize,
        shape: shape,
        backgroundColor: Rubka.ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Rubka.disabledBg,
        disabledForegroundColor: Rubka.disabledFg,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: minSize,
        shape: shape,
        side: const BorderSide(color: Rubka.ink),
        foregroundColor: Rubka.ink,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: shape, foregroundColor: Rubka.ink),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: Rubka.head(22, weight: FontWeight.w700),
      contentTextStyle: Rubka.body(color: Rubka.ink2),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Rubka.ink,
      contentTextStyle: Rubka.body(size: 14, color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Rubka.ink : Rubka.dotGray),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Rubka.ink : null),
      checkColor: const WidgetStatePropertyAll(Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
  );
}
