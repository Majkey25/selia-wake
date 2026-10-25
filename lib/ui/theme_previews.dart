import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import '../core/settings.dart';
import 'controls.dart';
import 'strings.dart';
import 'theme.dart';

class ThemePreviews extends StatelessWidget {
  const ThemePreviews({
    super.key,
    required this.value,
    required this.appearance,
    required this.custom,
    this.onChanged,
  });

  final WakeTheme value;
  final ThemeMode appearance;
  final CustomTheme custom;
  final ValueChanged<WakeTheme>? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final brightness = switch (appearance) {
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
    };
    return DynamicColorBuilder(
      builder: (light, dark) => LayoutBuilder(
        builder: (context, constraints) {
          final columns =
              constraints.maxWidth >= 520 &&
              MediaQuery.textScalerOf(context).scale(14) <= 18;
          final width = columns
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final style in WakeTheme.values)
                SizedBox(
                  width: width,
                  child: Semantics(
                    key: ValueKey('theme-preview-${style.name}'),
                    selected: value == style,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: onChanged == null
                          ? null
                          : () => onChanged!(style),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(switch (style) {
                                  WakeTheme.platform => Icons.devices_outlined,
                                  WakeTheme.material => Icons.palette_outlined,
                                  WakeTheme.terminal => Icons.terminal,
                                  WakeTheme.matrix => Icons.code,
                                  WakeTheme.custom => Icons.tune,
                                }),
                                const SizedBox(width: 8),
                                Expanded(child: Text(s.themeName(style))),
                                const SizedBox(width: 8),
                                Icon(
                                  value == style
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Theme(
                              data: wakeTheme(
                                style,
                                brightness,
                                brightness == Brightness.dark ? dark : light,
                                custom: custom,
                              ),
                              child: Builder(
                                builder: (context) => wakePlatformBuilder(
                                  context,
                                  ExcludeSemantics(
                                    child: ExcludeFocus(
                                      child: IgnorePointer(
                                        child: ColoredBox(
                                          color: Theme.of(
                                            context,
                                          ).scaffoldBackgroundColor,
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Text(
                                                  'Selia Wake',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodyMedium,
                                                ),
                                                const SizedBox(height: 8),
                                                WakeButton(
                                                  primary: true,
                                                  onPressed: () {},
                                                  icon: const Icon(
                                                    Icons.power_settings_new,
                                                  ),
                                                  label: Text(s.wake),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
