import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'protocol.dart';

enum DeviceRole { user, waker }

enum WakeTheme { material, glass, terminal }

class Settings {
  Settings({
    this.role = DeviceRole.user,
    this.theme = WakeTheme.material,
    this.appearance = ThemeMode.system,
    this.language = 'system',
    this.motion = true,
    this.targetName = '',
    this.mac = '',
    this.broadcast = '',
    this.lanIp = '',
    this.wakerHost = '',
    required this.wakerKey,
    this.pairing,
  });
  DeviceRole role;
  WakeTheme theme;
  ThemeMode appearance;
  String language;
  bool motion;
  String targetName;
  String mac;
  String broadcast;
  String lanIp;
  String wakerHost;
  String wakerKey;
  Pairing? pairing;

  Settings copy() => Settings(
    role: role,
    theme: theme,
    appearance: appearance,
    language: language,
    motion: motion,
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
    'theme': theme.name,
    'appearance': appearance.name,
    'language': language,
    'motion': motion,
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
      theme:
          WakeTheme.values
              .where((v) => v.name == string('theme'))
              .firstOrNull ??
          WakeTheme.material,
      appearance:
          ThemeMode.values
              .where((v) => v.name == string('appearance'))
              .firstOrNull ??
          ThemeMode.system,
      language: ['system', 'cs', 'en'].contains(string('language'))
          ? string('language')
          : 'system',
      motion: data['motion'] != false,
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
