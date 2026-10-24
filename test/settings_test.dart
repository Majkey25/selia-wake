import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seliawake/core/protocol.dart';
import 'package:seliawake/core/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
