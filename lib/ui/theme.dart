import 'package:flutter/material.dart';

import '../core/settings.dart';

ThemeData wakeTheme(
  WakeTheme style,
  Brightness brightness,
  ColorScheme? dynamic,
) {
  final dark = brightness == Brightness.dark;
  final terminal = style == WakeTheme.terminal;
  final base = ColorScheme.fromSeed(
    seedColor: const Color(0xFFB4D9F8),
    brightness: brightness,
  );
  final scheme = style == WakeTheme.material && dynamic != null
      ? dynamic
      : base.copyWith(
          primary: terminal
              ? (dark ? Colors.white : Colors.black)
              : (dark ? const Color(0xFFB4D9F8) : const Color(0xFF285879)),
          onPrimary: dark ? const Color(0xFF151A25) : Colors.white,
          surface: terminal
              ? (dark ? Colors.black : Colors.white)
              : (dark ? const Color(0xFF151A25) : const Color(0xFFF4F6FA)),
          onSurface: dark ? const Color(0xFFF4F6FA) : const Color(0xFF151A25),
        );
  final radius = terminal ? 4.0 : 22.0;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'Space Grotesk',
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: .35),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
  );
}
