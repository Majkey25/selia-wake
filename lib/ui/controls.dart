import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool get _windows => defaultTargetPlatform == TargetPlatform.windows;

class WakeScaffold extends StatelessWidget {
  const WakeScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
  });
  final String title;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (!_windows) {
      return Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: body,
      );
    }
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: fluent.ScaffoldPage(
          padding: EdgeInsets.zero,
          header: fluent.PageHeader(
            leading: Navigator.canPop(context)
                ? WakeIconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.maybePop(context),
                  )
                : null,
            title: Text(title),
            commandBar: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
          content: body,
        ),
      ),
    );
  }
}

class WakeButton extends StatelessWidget {
  const WakeButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.subtle = false,
  });
  final Widget label;
  final Widget? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[icon!, const SizedBox(width: 10)],
        Flexible(child: label),
      ],
    );
    if (!_windows) {
      if (primary) return FilledButton(onPressed: onPressed, child: child);
      if (subtle) return TextButton(onPressed: onPressed, child: child);
      return OutlinedButton(onPressed: onPressed, child: child);
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final border =
        theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
    final style = fluent.ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: border.borderRadius,
          side: primary || subtle ? BorderSide.none : border.borderSide,
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurface.withValues(alpha: .08);
        }
        final color = primary
            ? scheme.primary
            : subtle
            ? Colors.transparent
            : scheme.surface;
        return states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)
            ? Color.alphaBlend(scheme.onSurface.withValues(alpha: .08), color)
            : color;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? scheme.onSurface.withValues(alpha: .38)
            : primary
            ? scheme.onPrimary
            : scheme.onSurface,
      ),
    );
    if (primary) {
      return fluent.FilledButton(
        onPressed: onPressed,
        style: style,
        child: child,
      );
    }
    if (subtle) {
      return fluent.HyperlinkButton(
        onPressed: onPressed,
        style: style,
        child: child,
      );
    }
    return fluent.Button(onPressed: onPressed, style: style, child: child);
  }
}

class WakeIconButton extends StatelessWidget {
  const WakeIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    this.onPressed,
  });
  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => _windows
      ? Tooltip(
          message: tooltip,
          child: Semantics(
            label: tooltip,
            child: fluent.IconButton(icon: icon, onPressed: onPressed),
          ),
        )
      : IconButton(tooltip: tooltip, icon: icon, onPressed: onPressed);
}

class WakeSelect<T> extends StatelessWidget {
  const WakeSelect({
    super.key,
    required this.label,
    required this.values,
    required this.value,
    required this.itemLabel,
    this.onChanged,
    this.icon = Icons.tune,
  });
  final String label;
  final List<T> values;
  final T value;
  final String Function(T) itemLabel;
  final ValueChanged<T>? onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    void change(T? next) {
      if (next != null) onChanged?.call(next);
    }

    if (_windows) {
      return fluent.InfoLabel(
        label: label,
        child: fluent.ComboBox<T>(
          value: value,
          isExpanded: true,
          items: [
            for (final item in values)
              fluent.ComboBoxItem(value: item, child: Text(itemLabel(item))),
          ],
          onChanged: onChanged == null ? null : change,
        ),
      );
    }
    return DropdownButtonFormField<T>(
      key: ValueKey(value),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: [
        for (final item in values)
          DropdownMenuItem(value: item, child: Text(itemLabel(item))),
      ],
      onChanged: onChanged == null ? null : change,
    );
  }
}

class WakeField extends StatelessWidget {
  const WakeField({
    super.key,
    this.controller,
    this.initialValue,
    required this.label,
    this.hint,
    this.validator,
    this.onChanged,
    this.readOnly = false,
    this.obscure = false,
    this.keyboardType,
    this.icon = Icons.edit_outlined,
    this.suffix,
  });
  final TextEditingController? controller;
  final String? initialValue;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final bool obscure;
  final TextInputType? keyboardType;
  final IconData icon;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    if (_windows) {
      final theme = Theme.of(context);
      final border =
          theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
      return fluent.InfoLabel(
        label: label,
        child: fluent.TextFormBox(
          controller: controller,
          initialValue: initialValue,
          placeholder: hint,
          validator: validator,
          onChanged: onChanged,
          readOnly: readOnly,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: !obscure,
          keyboardType: keyboardType,
          textInputAction: TextInputAction.next,
          style: theme.textTheme.bodyMedium,
          highlightColor: theme.colorScheme.primary,
          errorHighlightColor: theme.colorScheme.error,
          prefix: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20),
          ),
          suffix: suffix,
          decoration: WidgetStatePropertyAll(
            BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(
                color: border.borderSide.color,
                width: border.borderSide.width,
              ),
              borderRadius: border.borderRadius,
            ),
          ),
        ),
      );
    }
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      validator: validator,
      onChanged: onChanged,
      readOnly: readOnly,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: !obscure,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorMaxLines: 4,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
      ),
    );
  }
}

class WakeDialog extends StatelessWidget {
  const WakeDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });
  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => _windows
      ? fluent.ContentDialog(
          title: title,
          content: content,
          actions: actions,
          constraints: const BoxConstraints(maxWidth: 440),
        )
      : AlertDialog(title: title, content: content, actions: actions);
}
