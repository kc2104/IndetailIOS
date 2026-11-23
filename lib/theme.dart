import 'package:material_ui/material_ui.dart';

abstract final class Palette {
  static const ivory = Color(0xFFF8F6F1);
  static const sand = Color(0xFFEDE6D9);
  static const navy = Color(0xFF183B63);
  static const blue = Color(0xFF326DA8);
  static const powder = Color(0xFFA9C5DF);
  static const ink = Color(0xFF263445);
  static const muted = Color(0xFF718096);
  static const line = Color(0xFFD7DCE3);
  static const green = Color(0xFF3D936E);
  static const amber = Color(0xFFD99A40);
  static const red = Color(0xFFC65D5D);
  static const surface = Color(0xFFFFFEFC);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.blue,
    primary: Palette.blue,
    secondary: Palette.navy,
    surface: Palette.surface,
    error: Palette.red,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.ivory,
    fontFamily: 'sans-serif',
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.ivory,
      foregroundColor: Palette.ink,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: Palette.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Palette.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.blue, width: 1.5),
      ),
      hintStyle: const TextStyle(color: Palette.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.navy,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.navy,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: Palette.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: Palette.surface,
      indicatorColor: Palette.powder.withValues(alpha: .42),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? Palette.navy
              : Palette.muted,
        ),
      ),
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.12,
        fontWeight: FontWeight.w800,
        letterSpacing: -.7,
        color: Palette.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -.35,
        color: Palette.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Palette.ink,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: Palette.ink),
      bodyMedium: TextStyle(fontSize: 13, height: 1.4, color: Palette.muted),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
  );
}
