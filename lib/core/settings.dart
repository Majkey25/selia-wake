import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'protocol.dart';

enum DeviceRole { user, waker }

enum WakeTheme { platform, terminal, material, matrix, custom }

enum TargetConnection { ethernet, wifi, usbEthernet }

class CustomTheme {
  CustomTheme({
    this.accent = 0xFF3584E4,
    this.background = 0xFF202020,
    this.surface = 0xFF303030,
    this.foreground = 0xFFF6F5F4,
    this.muted = 0xFFCCCCCC,
    this.outline = 0xFF888888,
    this.error = 0xFFFF8080,
    this.fontFamily = 'IBM Plex Mono',
    this.fontSize = 14,
    this.radius = 6,
    this.borderWidth = 1,
  });

  int accent;
  int background;
  int surface;
  int foreground;
  int muted;
  int outline;
  int error;
  String fontFamily;
  double fontSize;
  double radius;
  double borderWidth;

  factory CustomTheme.fromJson(Object? value) {
    final data = value is Map<String, Object?> ? value : <String, Object?>{};
    final defaults = CustomTheme();
    int color(String key, int fallback) {
      final value = data[key];
      return value is int && value >= 0xFF000000 && value <= 0xFFFFFFFF
          ? value
          : fallback;
    }

    double number(String key, double fallback, double min, double max) {
      final value = data[key];
      return value is num && value.isFinite && value >= min && value <= max
          ? value.toDouble()
          : fallback;
    }

    final font = data['fontFamily'];
    return CustomTheme(
      accent: color('accent', defaults.accent),
      background: color('background', defaults.background),
      surface: color('surface', defaults.surface),
      foreground: color('foreground', defaults.foreground),
      muted: color('muted', defaults.muted),
      outline: color('outline', defaults.outline),
      error: color('error', defaults.error),
      fontFamily: font is String && font.trim().isNotEmpty && font.length <= 80
          ? font.trim()
          : defaults.fontFamily,
      fontSize: number('fontSize', defaults.fontSize, 11, 24),
      radius: number('radius', defaults.radius, 0, 32),
      borderWidth: number('borderWidth', defaults.borderWidth, .5, 3),
    );
  }

  CustomTheme copy() => CustomTheme.fromJson(toJson());

  Map<String, Object?> toJson() => {
    'accent': accent,
    'background': background,
    'surface': surface,
    'foreground': foreground,
    'muted': muted,
    'outline': outline,
    'error': error,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'radius': radius,
    'borderWidth': borderWidth,
  };
}

class Settings {
  Settings({
    this.role = DeviceRole.user,
    this.connection = TargetConnection.ethernet,
    this.theme = WakeTheme.platform,
    CustomTheme? customTheme,
    this.appearance = ThemeMode.system,
    this.language = 'system',
    this.targetName = '',
    this.mac = '',
    this.broadcast = '',
    this.lanIp = '',
    this.wakerHost = '',
    required this.wakerKey,
    this.pairing,
  }) : customTheme = customTheme ?? CustomTheme();
  DeviceRole role;
  TargetConnection connection;
  WakeTheme theme;
  CustomTheme customTheme;
  ThemeMode appearance;
  String language;
  String targetName;
  String mac;
  String broadcast;
  String lanIp;
  String wakerHost;
  String wakerKey;
  Pairing? pairing;

  Settings copy() => Settings(
    role: role,
    connection: connection,
    theme: theme,
    customTheme: customTheme.copy(),
    appearance: appearance,
    language: language,
    targetName: targetName,
    mac: mac,
    broadcast: broadcast,
    lanIp: lanIp,
    wakerHost: wakerHost,
    wakerKey: wakerKey,
    pairing: pairing,
  );

  Map<String, Object?> toJson() => {
    'role': role.name,
    'connection': connection.name,
    'theme': theme.name,
    'customTheme': customTheme.toJson(),
    'appearance': appearance.name,
    'language': language,
    'targetName': targetName,
    'mac': mac,
    'broadcast': broadcast,
    'lanIp': lanIp,
    'wakerHost': wakerHost,
    'pairedHost': pairing?.host,
    'pairedName': pairing?.name,
  };
}

class SettingsStore {
  static const _secure = FlutterSecureStorage();

  Future<Settings> load() async {
    final raw = await _secure.read(key: 'settings-v1');
    if (raw == null) {
      final initial = Settings(wakerKey: randomKey());
      await save(initial);
      return initial;
    }
    final parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('invalid_settings');
    }
    final data = parsed as Map<String, Object?>;
    String string(String key, [String fallback = '']) =>
        data[key] is String ? data[key]! as String : fallback;
    final wakerKey = string('wakerKey');
    decodeKey(wakerKey);
    final pairedKey = string('pairedKey');
    return Settings(
      role:
          DeviceRole.values
              .where((v) => v.name == string('role'))
              .firstOrNull ??
          DeviceRole.user,
      connection:
          TargetConnection.values
              .where((value) => value.name == string('connection'))
              .firstOrNull ??
          TargetConnection.ethernet,
      theme:
          WakeTheme.values
              .where((v) => v.name == string('theme'))
              .firstOrNull ??
          (string('theme') == 'glass'
              ? WakeTheme.terminal
              : WakeTheme.platform),
      customTheme: CustomTheme.fromJson(data['customTheme']),
      appearance:
          ThemeMode.values
              .where((v) => v.name == string('appearance'))
              .firstOrNull ??
          ThemeMode.system,
      language: ['system', 'cs', 'en'].contains(string('language'))
          ? string('language')
          : 'system',
      targetName: string('targetName'),
      mac: string('mac'),
      broadcast: string('broadcast'),
      lanIp: string('lanIp'),
      wakerHost: string('wakerHost'),
      wakerKey: wakerKey,
      pairing: pairedKey.isEmpty || string('pairedHost').isEmpty
          ? null
          : Pairing(
              host: string('pairedHost'),
              key: pairedKey,
              name: string('pairedName'),
            ),
    );
  }

  Future<void> save(Settings settings) async {
    // One secure record keeps pairing keys and their addresses in the same write.
    await _secure.write(
      key: 'settings-v1',
      value: jsonEncode({
        ...settings.toJson(),
        'wakerKey': settings.wakerKey,
        'pairedKey': settings.pairing?.key,
      }),
    );
  }
}
