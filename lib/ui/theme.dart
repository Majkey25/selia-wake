import 'package:flutter/material.dart';

import '../core/settings.dart';

ThemeData wakeTheme(
  WakeTheme style,
  Brightness brightness,
  ColorScheme? dynamic,
) {
  final material = style == WakeTheme.material;
  final matrix = style == WakeTheme.matrix;
  final dark = matrix || brightness == Brightness.dark;
  final surface = dark ? Colors.black : Colors.white;
  final ink = matrix
      ? const Color(0xFF75F59B)
      : dark
      ? Colors.white
      : Colors.black;
  final base = ColorScheme.fromSeed(
    seedColor: const Color(0xFF426844),
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  final scheme = material
      ? dynamic ?? base
      : base.copyWith(
          primary: ink,
          onPrimary: surface,
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: ink,
          outline: ink,
          outlineVariant: ink.withValues(alpha: .35),
        );
  final radius = BorderRadius.circular(material ? 12 : 0);
  final shape = RoundedRectangleBorder(borderRadius: radius);
  final border = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: scheme.outline),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: material ? null : 'IBM Plex Mono',
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 14),
      bodyMedium: TextStyle(fontSize: 13, height: 1.5),
      bodySmall: TextStyle(fontSize: 12, height: 1.5),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      scrolledUnderElevation: 0,
      elevation: 0,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outline,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.all(14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: scheme.onSurface,
        shape: shape,
      ),
    ),
    dialogTheme: DialogThemeData(shape: shape, elevation: 0),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
  );
}
