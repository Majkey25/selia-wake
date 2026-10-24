import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/settings.dart';

ThemeData wakeTheme(
  WakeTheme style,
  Brightness brightness,
  ColorScheme? dynamic, {
  CustomTheme? custom,
}) {
  final colors = custom ?? CustomTheme();
  final personal = style == WakeTheme.custom;
  final terminal = style == WakeTheme.terminal || style == WakeTheme.matrix;
  final linux =
      style == WakeTheme.platform &&
      defaultTargetPlatform == TargetPlatform.linux;
  final windows =
      style == WakeTheme.platform &&
      defaultTargetPlatform == TargetPlatform.windows;
  final material =
      style == WakeTheme.material ||
      (style == WakeTheme.platform && !linux && !windows);
  final dark =
      style == WakeTheme.matrix ||
      (personal
          ? ThemeData.estimateBrightnessForColor(Color(colors.background)) ==
                Brightness.dark
          : brightness == Brightness.dark);
  final background = personal
      ? Color(colors.background)
      : terminal
      ? (dark ? Colors.black : Colors.white)
      : linux
      ? Color(dark ? 0xFF242424 : 0xFFF6F5F4)
      : windows
      ? Color(dark ? 0xFF202020 : 0xFFF3F3F3)
      : null;
  final ink = personal
      ? Color(colors.foreground)
      : style == WakeTheme.matrix
      ? const Color(0xFF75F59B)
      : dark
      ? Colors.white
      : Colors.black;
  final base = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3584E4),
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  var scheme = !personal && !terminal && !linux && !windows
      ? dynamic ?? base
      : base;
  if (terminal || personal) {
    final accent = personal ? Color(colors.accent) : ink;
    scheme = scheme.copyWith(
      primary: accent,
      onPrimary: _contrasting(accent),
      secondary: accent,
      onSecondary: _contrasting(accent),
      surface: personal ? Color(colors.surface) : background,
      surfaceContainerLowest: personal ? Color(colors.surface) : background,
      surfaceContainerLow: personal ? Color(colors.surface) : background,
      surfaceContainer: personal ? Color(colors.surface) : background,
      surfaceContainerHigh: personal ? Color(colors.surface) : background,
      surfaceContainerHighest: personal ? Color(colors.surface) : background,
      surfaceTint: Colors.transparent,
      onSurface: ink,
      onSurfaceVariant: personal ? Color(colors.muted) : ink,
      outline: personal ? Color(colors.outline) : ink,
      outlineVariant: personal
          ? Color(colors.outline)
          : ink.withValues(alpha: .25),
      error: personal ? Color(colors.error) : base.error,
      onError: personal ? _contrasting(Color(colors.error)) : base.onError,
    );
  } else if (linux || windows) {
    scheme = scheme.copyWith(
      primary: const Color(0xFF3584E4),
      onPrimary: Colors.white,
      surface: Color(dark ? 0xFF303030 : 0xFFFFFFFF),
      onSurface: Color(dark ? 0xFFF6F5F4 : 0xFF202020),
      onSurfaceVariant: Color(dark ? 0xFFCCCCCC : 0xFF505050),
      outline: Color(dark ? 0xFF858585 : 0xFF777777),
      outlineVariant: Color(dark ? 0xFF505050 : 0xFFD4D4D4),
    );
  }
  final radius = BorderRadius.circular(
    personal
        ? colors.radius
        : terminal
        ? 0
        : windows
        ? 4
        : linux
        ? 6
        : 4,
  );
  final shape = RoundedRectangleBorder(borderRadius: radius);
  final border = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(
      color: scheme.outline,
      width: personal ? colors.borderWidth : 1,
    ),
  );
  final size = personal ? colors.fontSize : 14.0;
  final font = personal ? colors.fontFamily : 'IBM Plex Mono';
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background ?? scheme.surface,
    fontFamily: font,
    fontFamilyFallback: const ['IBM Plex Mono'],
    splashFactory: linux || windows ? NoSplash.splashFactory : null,
    textTheme: TextTheme(
      bodyLarge: TextStyle(fontSize: size, height: 1.5),
      bodyMedium: TextStyle(fontSize: size, height: 1.5),
      bodySmall: TextStyle(
        fontSize: size - 2,
        height: 1.5,
        color: scheme.onSurfaceVariant,
      ),
      titleMedium: TextStyle(fontSize: size + 2, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontSize: size + 6, fontWeight: FontWeight.w700),
      labelLarge: TextStyle(fontSize: size, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: background ?? scheme.surface,
      foregroundColor: scheme.onSurface,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: linux,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: border,
      enabledBorder: border,
      filled: !terminal,
      fillColor: scheme.surface,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.all(14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: material ? null : shape,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: material ? null : shape,
        foregroundColor: scheme.onSurface,
        backgroundColor: linux ? scheme.surface : null,
        side: border.borderSide,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: scheme.primary,
        shape: material ? null : shape,
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: material ? null : shape,
      backgroundColor: scheme.surface,
      elevation: 0,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
  );
}

Color _contrasting(Color color) =>
    color.computeLuminance() > .179 ? Colors.black : Colors.white;

Widget wakePlatformBuilder(BuildContext context, Widget? child) {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    return child ?? const SizedBox();
  }
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final border =
      theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
  final reduced = MediaQuery.disableAnimationsOf(context);
  return fluent.FluentTheme(
    data: fluent.FluentThemeData(
      brightness: scheme.brightness,
      accentColor: fluent.AccentColor.swatch({'normal': scheme.primary}),
      activeColor: scheme.onPrimary,
      inactiveColor: scheme.onSurface,
      scaffoldBackgroundColor: theme.scaffoldBackgroundColor,
      menuColor: scheme.surface,
      cardColor: scheme.surface,
      resources: scheme.brightness == Brightness.dark
          ? fluent.ResourceDictionary.dark(
              textFillColorPrimary: scheme.onSurface,
              textFillColorSecondary: scheme.onSurfaceVariant,
              textOnAccentFillColorPrimary: scheme.onPrimary,
              controlFillColorDefault: scheme.surface,
              controlFillColorInputActive: scheme.surface,
              controlSolidFillColorDefault: scheme.surface,
              controlStrokeColorDefault: scheme.outline,
              controlStrokeColorSecondary: scheme.outline,
              focusStrokeColorOuter: scheme.primary,
              systemFillColorCritical: scheme.error,
            )
          : fluent.ResourceDictionary.light(
              textFillColorPrimary: scheme.onSurface,
              textFillColorSecondary: scheme.onSurfaceVariant,
              textOnAccentFillColorPrimary: scheme.onPrimary,
              controlFillColorDefault: scheme.surface,
              controlFillColorInputActive: scheme.surface,
              controlSolidFillColorDefault: scheme.surface,
              controlStrokeColorDefault: scheme.outline,
              controlStrokeColorSecondary: scheme.outline,
              focusStrokeColorOuter: scheme.primary,
              systemFillColorCritical: scheme.error,
            ),
      buttonTheme: fluent.ButtonThemeData(
        defaultButtonStyle: fluent.ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: border.borderRadius,
              side: border.borderSide,
            ),
          ),
        ),
      ),
      dialogTheme: fluent.ContentDialogThemeData(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: border.borderRadius,
        ),
        actionsDecoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: border.borderRadius,
        ),
      ),
      typography: fluent.Typography.raw(
        body: theme.textTheme.bodyMedium,
        bodyStrong: theme.textTheme.labelLarge,
        caption: theme.textTheme.bodySmall,
        subtitle: theme.textTheme.titleMedium,
        title: theme.textTheme.titleLarge,
      ),
      fontFamily: theme.textTheme.bodyMedium?.fontFamily,
      iconTheme: IconThemeData(color: scheme.onSurface, size: 20),
      fasterAnimationDuration: reduced ? Duration.zero : null,
      fastAnimationDuration: reduced ? Duration.zero : null,
      mediumAnimationDuration: reduced ? Duration.zero : null,
      slowAnimationDuration: reduced ? Duration.zero : null,
    ),
    child: child ?? const SizedBox(),
  );
}
