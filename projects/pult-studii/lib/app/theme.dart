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
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  const minSize = Size(64, 48);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Rubka.bg,
    fontFamily: Rubka.bodyFont,
    fontFamilyFallback: Rubka.fallback,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: minSize,
        shape: shape,
        disabledBackgroundColor: Rubka.disabledBg,
        disabledForegroundColor: Rubka.disabledFg,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: minSize,
        shape: shape,
        side: const BorderSide(color: Rubka.primary),
        foregroundColor: Rubka.primary,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: shape),
    ),
  );
}
