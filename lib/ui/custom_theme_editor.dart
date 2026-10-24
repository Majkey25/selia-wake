import 'package:flutter/material.dart';

import '../core/settings.dart';
import 'controls.dart';
import 'strings.dart';
import 'theme.dart';

class CustomThemeEditor extends StatefulWidget {
  const CustomThemeEditor({
    super.key,
    required this.value,
    required this.readOnly,
  });
  final CustomTheme value;
  final bool readOnly;

  @override
  State<CustomThemeEditor> createState() => _CustomThemeEditorState();
}

class _CustomThemeEditorState extends State<CustomThemeEditor>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Widget _color(String label, int value, ValueChanged<int> change) {
    final s = Strings.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: WakeField(
        label: label,
        initialValue: '#${value.toRadixString(16).substring(2).toUpperCase()}',
        hint: '#3584E4',
        icon: Icons.palette_outlined,
        readOnly: widget.readOnly,
        validator: (text) =>
            RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text?.trim() ?? '')
            ? null
            : s.text(
                'Use #RRGGBB, for example #3584E4.',
                'Použijte #RRGGBB, například #3584E4.',
              ),
        onChanged: (text) {
          if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text.trim())) {
            setState(
              () => change(
                0xFF000000 | int.parse(text.trim().substring(1), radix: 16),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _number(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> change,
  ) {
    final s = Strings.of(context);
    bool valid(String? text) {
      final value = double.tryParse(text?.trim() ?? '');
      return value != null && value.isFinite && value >= min && value <= max;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: WakeField(
        label: label,
        initialValue: value.toString(),
        icon: Icons.straighten,
        readOnly: widget.readOnly,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (text) => valid(text)
            ? null
            : s.text('Enter $min to $max.', 'Zadejte $min až $max.'),
        onChanged: (text) {
          if (valid(text)) setState(() => change(double.parse(text.trim())));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = Strings.of(context);
    final value = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.text('Custom colors', 'Vlastní barvy'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        _color(
          s.text('Accent', 'Zvýraznění'),
          value.accent,
          (color) => value.accent = color,
        ),
        _color(
          s.text('Page background', 'Pozadí stránky'),
          value.background,
          (color) => value.background = color,
        ),
        _color(
          s.text('Control background', 'Pozadí ovládacích prvků'),
          value.surface,
          (color) => value.surface = color,
        ),
        _color(
          s.text('Text', 'Text'),
          value.foreground,
          (color) => value.foreground = color,
        ),
        _color(
          s.text('Secondary text', 'Vedlejší text'),
          value.muted,
          (color) => value.muted = color,
        ),
        _color(
          s.text('Borders', 'Okraje'),
          value.outline,
          (color) => value.outline = color,
        ),
        _color(
          s.text('Errors', 'Chyby'),
          value.error,
          (color) => value.error = color,
        ),
        WakeField(
          label: s.text('Font family', 'Rodina písma'),
          initialValue: value.fontFamily,
          hint: 'IBM Plex Mono',
          icon: Icons.font_download_outlined,
          readOnly: widget.readOnly,
          validator: (text) =>
              text == null || text.trim().isEmpty || text.length > 80
              ? s.text(
                  'Enter a font name, up to 80 characters.',
                  'Zadejte název písma, nejvýše 80 znaků.',
                )
              : null,
          onChanged: (text) {
            if (text.trim().isNotEmpty && text.length <= 80) {
              setState(() => value.fontFamily = text.trim());
            }
          },
        ),
        const SizedBox(height: 12),
        Text(
          s.text(
            'Use IBM Plex Mono or a font installed on this device. Unavailable fonts use IBM Plex Mono. Custom colors use the same palette in light and dark modes.',
            'Použijte IBM Plex Mono nebo písmo nainstalované v tomto zařízení. Nedostupná písma nahradí IBM Plex Mono. Vlastní barvy používají stejnou paletu ve světlém i tmavém režimu.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        _number(
          s.text('Font size', 'Velikost písma'),
          value.fontSize,
          11,
          24,
          (size) => value.fontSize = size,
        ),
        _number(
          s.text('Corner radius', 'Zaoblení rohů'),
          value.radius,
          0,
          32,
          (radius) => value.radius = radius,
        ),
        _number(
          s.text('Border width', 'Šířka okraje'),
          value.borderWidth,
          .5,
          3,
          (width) => value.borderWidth = width,
        ),
        Text(
          s.text('Preview', 'Náhled'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Theme(
          data: wakeTheme(
            WakeTheme.custom,
            Brightness.dark,
            null,
            custom: value,
          ),
          child: Builder(
            builder: (context) => wakePlatformBuilder(
              context,
              ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Selia Wake',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        s.text(
                          'Example text | 100.100.100.1',
                          'Ukázkový text | 100.100.100.1',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Color(value.muted),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ExcludeFocus(
                        child: IgnorePointer(
                          child: WakeButton(
                            primary: true,
                            icon: const Icon(Icons.power_settings_new),
                            label: Text(
                              s.text('Button preview', 'Náhled tlačítka'),
                            ),
                            onPressed: widget.readOnly ? null : () {},
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
