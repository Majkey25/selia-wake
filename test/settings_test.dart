import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seliawake/core/protocol.dart';
import 'package:seliawake/core/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'new settings use platform controls and preserve their generated key',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SettingsStore();
      final initial = await store.load();
      expect(initial.theme, WakeTheme.platform);
      expect((await store.load()).wakerKey, initial.wakerKey);
    },
  );

  test(
    'custom appearance round trips without changing relay or pairing secrets',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final settings = Settings(
        wakerKey: randomKey(),
        pairing: Pairing(host: '100.100.100.2', key: randomKey(), name: 'Home'),
        role: DeviceRole.waker,
        appearance: ThemeMode.dark,
        theme: WakeTheme.custom,
        customTheme: CustomTheme(
          accent: 0xFFAA5533,
          background: 0xFF111122,
          surface: 0xFF222233,
          foreground: 0xFFEEEEFF,
          muted: 0xFFAABBCC,
          outline: 0xFF778899,
          error: 0xFFEE3355,
          fontFamily: 'Consolas',
          fontSize: 17,
          radius: 12,
          borderWidth: 2,
        ),
      );
      final copy = settings.copy();
      copy.customTheme.radius = 0;
      expect(settings.customTheme.radius, 12);
      final store = SettingsStore();
      await store.save(settings);
      final restored = await store.load();
      expect(restored.toJson(), settings.toJson());
      expect(restored.wakerKey, settings.wakerKey);
      expect(restored.pairing?.key, settings.pairing?.key);
      expect(jsonEncode(restored.toJson()), isNot(contains(settings.wakerKey)));
      expect(
        jsonEncode(restored.toJson()),
        isNot(contains(settings.pairing!.key)),
      );
    },
  );

  test(
    'malformed appearance values fall back individually and keep valid preferences',
    () async {
      final key = randomKey();
      FlutterSecureStorage.setMockInitialValues({
        'settings-v1': jsonEncode({
          'wakerKey': key,
          'theme': 'future-style',
          'language': 'en',
          'mac': '02:11:22:33:44:55',
          'customTheme': {
            'accent': 'blue',
            'background': -1,
            'foreground': 0x00112233,
            'radius': 900,
            'fontSize': 'large',
            'borderWidth': 0,
            'fontFamily': '',
            'surface': 0xFF123456,
          },
        }),
      });
      final settings = await SettingsStore().load();
      final defaults = CustomTheme();
      expect(settings.theme, WakeTheme.platform);
      expect(settings.wakerKey, key);
      expect(settings.mac, '02:11:22:33:44:55');
      expect(settings.customTheme.accent, defaults.accent);
      expect(settings.customTheme.background, defaults.background);
      expect(settings.customTheme.foreground, defaults.foreground);
      expect(settings.customTheme.radius, defaults.radius);
      expect(settings.customTheme.fontSize, defaults.fontSize);
      expect(settings.customTheme.borderWidth, defaults.borderWidth);
      expect(settings.customTheme.fontFamily, defaults.fontFamily);
      expect(settings.customTheme.surface, 0xFF123456);
      expect(
        CustomTheme.fromJson({'fontSize': double.nan}).fontSize,
        defaults.fontSize,
      );
      expect(
        CustomTheme.fromJson({'radius': double.infinity}).radius,
        defaults.radius,
      );
      expect(CustomTheme.fromJson('invalid').toJson(), defaults.toJson());
    },
  );

  test('existing theme names survive migration', () async {
    for (final theme in [
      WakeTheme.terminal,
      WakeTheme.material,
      WakeTheme.matrix,
    ]) {
      final key = randomKey();
      FlutterSecureStorage.setMockInitialValues({
        'settings-v1': jsonEncode({'theme': theme.name, 'wakerKey': key}),
      });
      final restored = await SettingsStore().load();
      expect(restored.theme, theme);
      expect(restored.wakerKey, key);
    }
  });

  test(
    'an upgrade from Glass preserves pairing and relay configuration',
    () async {
      final wakerKey = randomKey();
      final pairedKey = randomKey();
      FlutterSecureStorage.setMockInitialValues({
        'settings-v1': jsonEncode({
          'role': 'waker',
          'theme': 'glass',
          'appearance': 'dark',
          'language': 'cs',
          'motion': true,
          'targetName': 'Domácí PC',
          'mac': '02:11:22:33:44:55',
          'broadcast': '192.168.1.255',
          'lanIp': '192.168.1.20',
          'wakerHost': '100.100.100.1',
          'wakerKey': wakerKey,
          'pairedHost': '100.100.100.2',
          'pairedName': 'Druhý počítač',
          'pairedKey': pairedKey,
        }),
      });
      final store = SettingsStore();
      final upgraded = await store.load();
      expect(upgraded.theme, WakeTheme.terminal);
      expect(upgraded.connection, TargetConnection.ethernet);
      upgraded.connection = TargetConnection.usbEthernet;
      await store.save(upgraded);
      final restored = await store.load();
      expect(restored.role, DeviceRole.waker);
      expect(restored.language, 'cs');
      expect(restored.targetName, 'Domácí PC');
      expect(restored.mac, '02:11:22:33:44:55');
      expect(restored.broadcast, '192.168.1.255');
      expect(restored.lanIp, '192.168.1.20');
      expect(restored.wakerHost, '100.100.100.1');
      expect(restored.wakerKey, wakerKey);
      expect(restored.pairing?.key, pairedKey);
      expect(restored.pairing?.host, '100.100.100.2');
      expect(restored.connection, TargetConnection.usbEthernet);
    },
  );
}
