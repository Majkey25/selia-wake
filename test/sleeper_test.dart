import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seliawake/core/settings.dart';
import 'package:seliawake/core/sleeper.dart';

const _adapterId = '12345678-1234-1234-1234-123456789abc';

Map<String, Object?> _setupJson() => {
  'v': 1,
  'name': 'Domácí PC',
  'mac': '02:11:22:33:44:55',
  'broadcast': '192.168.1.255',
  'connection': 'ethernet',
  'targetHost': '100.73.153.127',
  'targetPort': 3389,
};

String _uri(Object? json) =>
    'seliawake://sleeper?data=${base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '')}';

Map<String, Object?> _windowsReport() => {
  'platform': 'windows',
  'machineName': 'TEST-PC',
  'sleepStates': 'Standby (S3)',
  'adapters': <Object?>[
    <String, Object?>{
      'id': _adapterId,
      'name': 'Ethernet',
      'description': 'Test physical adapter',
      'mac': '02-11-22-33-44-55',
      'ip': '192.168.1.20',
      'broadcast': '192.168.1.255',
      'connection': 'ethernet',
      'wakeEnabled': null,
      'magicPacketEnabled': null,
      'supportsWake': null,
      'detail': 'Driver capability unavailable.',
    },
  ],
};

Map<String, Object?> _windowsAdapter(Map<String, Object?> report) =>
    (report['adapters']! as List<Object?>).single! as Map<String, Object?>;

Map<String, Object?> _configuredWindowsReport(
  int identity, {
  String mac = '02-AA-BB-CC-DD-EE',
  bool pending = false,
}) {
  final report = _windowsReport();
  _windowsAdapter(report).addAll({
    'id':
        '12345678-1234-1234-1234-${identity.toRadixString(16).padLeft(12, '0')}',
    'mac': mac,
    'wakeEnabled': true,
    'magicPacketEnabled': true,
    'restartRequired': pending,
  });
  return report;
}

SleeperAdapter _linuxAdapter({
  String mac = '02:11:22:33:44:55',
  String ip = '192.168.1.20',
  int? prefixLength = 24,
  TargetConnection connection = TargetConnection.ethernet,
  String? ethtoolOutput,
  String detail = '',
}) => SleeperAdapter.fromLinux(
  id: 'enp1s0',
  description: 'Test physical adapter',
  mac: mac,
  ip: ip,
  prefixLength: prefixLength,
  connection: connection,
  ethtoolOutput: ethtoolOutput,
  detail: detail,
);

SleeperReport _linuxReport(SleeperAdapter adapter) =>
    SleeperReport(machineName: 'fixture', sleepStates: '', adapters: [adapter]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TargetSetup', () {
    test(
      'exports only the versioned network setup and imports every connection',
      () {
        for (final connection in TargetConnection.values) {
          final setup = TargetSetup(
            name: 'Domácí PC',
            mac: '02:11:22:33:44:55',
            broadcast: '192.168.1.255',
            connection: connection,
            targetHost: '100.73.153.127',
            targetPort: 3389,
          );
          final encoded = setup.encode();
          final uri = Uri.parse(encoded);
          expect(uri.scheme, 'seliawake');
          expect(uri.host, 'sleeper');
          expect(uri.path, isEmpty);
          expect(uri.hasFragment, isFalse);
          final payload = uri.queryParameters['data']!;
          expect(payload, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
          expect(
            jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(payload))),
            ),
            {..._setupJson(), 'connection': connection.name},
          );
          final restored = TargetSetup.parse(encoded);
          expect(restored.name, 'Domácí PC');
          expect(restored.mac, '02:11:22:33:44:55');
          expect(restored.broadcast, '192.168.1.255');
          expect(restored.connection, connection);
          expect(restored.targetHost, '100.73.153.127');
          expect(restored.targetPort, 3389);
        }
      },
    );

    test(
      'accepts subnet broadcast candidates and optional private target hosts',
      () {
        for (final broadcast in [
          '10.255.255.255',
          '172.31.255.255',
          '192.168.1.63',
        ]) {
          final setup = TargetSetup(
            name: 'PC',
            mac: '02-11-22-33-44-55',
            broadcast: broadcast,
            connection: TargetConnection.usbEthernet,
          );
          final restored = TargetSetup.parse(setup.encode());
          expect(restored.broadcast, broadcast);
          expect(restored.targetHost, isEmpty);
          expect(restored.targetPort, 3389);
        }
        for (final host in [
          '10.0.0.2',
          '172.16.0.2',
          '192.168.1.2',
          '100.64.0.1',
          '100.127.255.254',
        ]) {
          expect(
            TargetSetup.parse(
              _uri({..._setupJson(), 'targetHost': host}),
            ).targetHost,
            host,
          );
        }
        for (final port in [1, 65535]) {
          expect(
            TargetSetup.parse(
              _uri({..._setupJson(), 'targetPort': port}),
            ).targetPort,
            port,
          );
        }
      },
    );

    test(
      'rejects alternate URI destinations, duplicate data, and fragments',
      () {
        final valid = _uri(_setupJson());
        final payload = Uri.parse(valid).queryParameters['data']!;
        for (final uri in [
          valid.replaceFirst('seliawake:', 'https:'),
          valid.replaceFirst('//sleeper', '//pair'),
          valid.replaceFirst('//sleeper', '//user@sleeper'),
          valid.replaceFirst('//sleeper', '//@sleeper'),
          valid.replaceFirst('//sleeper', '//sleeper:123'),
          valid.replaceFirst('//sleeper', '//sleeper:'),
          valid.replaceFirst('sleeper?', 'sleeper/?'),
          valid.replaceFirst('sleeper?', 'sleeper/run?'),
          '$valid#',
          '$valid#ignored',
          '$valid&data=$payload',
          '$valid&other=value',
          '$valid&',
          'seliawake://sleeper?data=',
          'seliawake://sleeper?%64ata=$payload',
          'seliawake://sleeper?data=$payload=',
          'seliawake://sleeper?data=%21',
        ]) {
          expect(
            () => TargetSetup.parse(uri),
            throwsFormatException,
            reason: uri,
          );
        }
      },
    );

    test('rejects invalid UTF8, malformed JSON, and noncanonical base64', () {
      for (final uri in [
        'seliawake://sleeper?data=_w',
        'seliawake://sleeper?data=ew',
        'seliawake://sleeper?data=e30',
        'seliawake://sleeper?data=e31',
        _uri([]),
        _uri(null),
      ]) {
        expect(() => TargetSetup.parse(uri), throwsFormatException);
      }
    });

    test('requires exact bounded JSON types and the documented fields', () {
      for (final entry in <MapEntry<String, Object?>>[
        const MapEntry('v', 1.0),
        const MapEntry('v', 2),
        const MapEntry('name', 7),
        const MapEntry('name', ''),
        const MapEntry('name', '   '),
        const MapEntry('name', 'PC\nrun something'),
        MapEntry('name', List.filled(81, 'a').join()),
        const MapEntry('mac', []),
        const MapEntry('broadcast', false),
        const MapEntry('connection', 'bluetooth'),
        const MapEntry('connection', 0),
        const MapEntry('targetHost', null),
        const MapEntry('targetPort', '3389'),
        const MapEntry('targetPort', 3389.0),
        const MapEntry('targetPort', 0),
        const MapEntry('targetPort', 65536),
        const MapEntry('secret', 'not-allowed'),
        const MapEntry('command', 'not-allowed'),
      ]) {
        expect(
          () => TargetSetup.parse(
            _uri({..._setupJson(), entry.key: entry.value}),
          ),
          throwsFormatException,
          reason: '${entry.key}: ${entry.value}',
        );
      }
      for (final key in _setupJson().keys) {
        final missing = _setupJson()..remove(key);
        expect(
          () => TargetSetup.parse(_uri(missing)),
          throwsFormatException,
          reason: key,
        );
      }
    });

    test('rejects multicast, zero, malformed, or mixed-separator MACs', () {
      for (final mac in [
        '00:00:00:00:00:00',
        'ff:ff:ff:ff:ff:ff',
        '01:11:22:33:44:55',
        '02:11:22:33:44',
        '02:11-22:33:44:55',
        '02:11:22:33:44:55;run',
      ]) {
        expect(
          () => TargetSetup.parse(_uri({..._setupJson(), 'mac': mac})),
          throwsFormatException,
        );
      }
    });

    test(
      'rejects public, nonliteral, and nonbroadcast network destinations',
      () {
        for (final broadcast in [
          '255.255.255.255',
          '8.8.8.255',
          '100.64.0.255',
          '127.0.0.255',
          '169.254.0.255',
          '192.168.1.20',
          '192.168.1.0',
          '192.168.001.255',
          '::1',
          'example.com',
        ]) {
          expect(
            () => TargetSetup.parse(
              _uri({..._setupJson(), 'broadcast': broadcast}),
            ),
            throwsFormatException,
          );
        }
        for (final host in [
          '8.8.8.8',
          '127.0.0.1',
          '169.254.0.1',
          '100.63.0.1',
          '100.128.0.1',
          'example.com',
          '::1',
          '192.168.001.2',
          '192.168.1.2:3389',
          '192.168.1.2/24',
          '192.168.1.2;run',
        ]) {
          expect(
            () =>
                TargetSetup.parse(_uri({..._setupJson(), 'targetHost': host})),
            throwsFormatException,
          );
        }
      },
    );

    test('validates constructors and bounds input before decoding', () {
      expect(
        () => TargetSetup(
          name: 'PC',
          mac: 'bad',
          broadcast: '192.168.1.255',
          connection: TargetConnection.wifi,
        ),
        throwsFormatException,
      );
      expect(
        () => TargetSetup(
          name: '',
          mac: '02:11:22:33:44:55',
          broadcast: '192.168.1.255',
          connection: TargetConnection.wifi,
        ),
        throwsFormatException,
      );
      final oversized =
          'seliawake://sleeper?data=${List.filled(2049, 'a').join()}';
      expect(() => TargetSetup.parse(oversized), throwsFormatException);
      final longestName = List.filled(80, 'ž').join();
      final setup = TargetSetup.parse(
        _uri({..._setupJson(), 'name': longestName}),
      );
      expect(setup.name, longestName);
      expect(setup.encode().length, lessThanOrEqualTo(2048));
    });
  });

  group('Windows report', () {
    test('preserves unknown capability instead of converting it to false', () {
      final report = SleeperReport.fromWindowsJson(_windowsReport());
      final adapter = report.adapters.single;
      expect(report.machineName, 'TEST-PC');
      expect(report.sleepStates, 'Standby (S3)');
      expect(adapter.wakeEnabled, isNull);
      expect(adapter.magicPacketEnabled, isNull);
      expect(adapter.supportsWake, isNull);
      expect(adapter.restartRequired, isFalse);
      expect(adapter.detail, contains('unavailable'));
      expect(adapter.connection, TargetConnection.ethernet);
    });

    test('keeps explicit states and restart requirements from the script', () {
      final data = _windowsReport();
      _windowsAdapter(data).addAll({
        'wakeEnabled': true,
        'magicPacketEnabled': false,
        'supportsWake': true,
        'restartRequired': true,
        'connection': 'wifi',
      });
      final adapter = SleeperReport.fromWindowsJson(data).adapters.single;
      expect(adapter.wakeEnabled, isTrue);
      expect(adapter.magicPacketEnabled, isFalse);
      expect(adapter.supportsWake, isTrue);
      expect(adapter.restartRequired, isTrue);
      expect(adapter.connection, TargetConnection.wifi);
    });

    test(
      'rejects error envelopes, invalid identifiers, and string booleans',
      () {
        for (final value in <Object?>[
          null,
          <Object?>[],
          {'error': 'access_denied'},
          {..._windowsReport(), 'platform': 'linux'},
        ]) {
          expect(
            () => SleeperReport.fromWindowsJson(value),
            throwsFormatException,
          );
        }
        for (final entry in <MapEntry<String, Object?>>[
          const MapEntry('id', '-Action Enable'),
          const MapEntry('mac', '01:11:22:33:44:55'),
          const MapEntry('ip', 'not-an-address'),
          const MapEntry('broadcast', '192.168.1.999'),
          const MapEntry('wakeEnabled', 'false'),
          const MapEntry('magicPacketEnabled', 1),
          const MapEntry('supportsWake', 'unknown'),
          const MapEntry('restartRequired', 'true'),
        ]) {
          final data = _windowsReport();
          _windowsAdapter(data)[entry.key] = entry.value;
          expect(
            () => SleeperReport.fromWindowsJson(data),
            throwsFormatException,
            reason: entry.key,
          );
        }
      },
    );
  });

  group('Windows helper with fixture OS commands', () {
    late _WindowsWakeFixture fixture;

    setUp(() async => fixture = await _WindowsWakeFixture.create());
    tearDown(() async => fixture.dispose());

    test('inspects stored settings without implying activation', () async {
      final (result, trace) = await fixture.run(
        'configured',
        action: 'Inspect',
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(trace, isEmpty);
      final adapter = _windowsAdapter(
        jsonDecode(result.stdout as String) as Map<String, Object?>,
      );
      expect(adapter['magicPacketEnabled'], isTrue);
      expect(adapter['restartRequired'], isFalse);
      expect(
        adapter['detail'],
        contains('do not verify firmware wake arming or physical wake'),
      );
      expect(adapter['detail'], contains('unknown'));
    });

    test(
      'enables with the current token without an administrator role gate',
      () async {
        final (result, trace) = await fixture.run('enable');
        expect(result.exitCode, 0, reason: '${result.stdout} ${result.stderr}');
        expect(trace, ['arm', 'magic']);
        final adapter = _windowsAdapter(
          jsonDecode(result.stdout as String) as Map<String, Object?>,
        );
        expect(adapter['wakeEnabled'], isTrue);
        expect(adapter['magicPacketEnabled'], isTrue);
        expect(adapter['restartRequired'], isTrue);
      },
    );

    test(
      'already configured enable is idempotent without any setter',
      () async {
        final (result, trace) = await fixture.run('configured');
        expect(result.exitCode, 0, reason: '${result.stdout} ${result.stderr}');
        expect(trace, isEmpty);
      },
    );

    test(
      'reports inactive NDIS wake despite an enabled stored setting',
      () async {
        final (result, trace) = await fixture.run(
          'inactive-wake',
          action: 'Inspect',
        );
        expect(result.exitCode, 0, reason: '${result.stdout} ${result.stderr}');
        expect(trace, isEmpty);
        final adapter = _windowsAdapter(
          jsonDecode(result.stdout as String) as Map<String, Object?>,
        );
        expect(adapter['magicPacketEnabled'], isTrue);
        expect(
          adapter['detail'],
          contains('NDIS Magic Packet capability: inactive'),
        );
      },
    );

    test(
      'does not infer an active capability from unavailable NDIS data',
      () async {
        for (final scenario in [
          'configured',
          'ambiguous-wake',
          'denied-wake',
        ]) {
          final (result, trace) = await fixture.run(
            scenario,
            action: 'Inspect',
          );
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout} ${result.stderr}',
          );
          expect(trace, isEmpty);
          final adapter = _windowsAdapter(
            jsonDecode(result.stdout as String) as Map<String, Object?>,
          );
          expect(adapter['magicPacketEnabled'], isTrue);
          expect(
            adapter['detail'],
            contains('NDIS Magic Packet capability: unknown'),
          );
        }
      },
    );

    test(
      'denied setter reports manual OS configuration without elevation',
      () async {
        final (result, trace) = await fixture.run('deny-arm');
        expect(result.exitCode, 1, reason: '${result.stderr}');
        expect(trace, ['arm']);
        final report =
            jsonDecode(result.stdout as String) as Map<String, Object?>;
        expect(report['error'], contains('separately'));
        expect(report['error'], contains('does not request administrator'));
      },
    );

    test(
      'denial after arming preserves the partial state and uncertainty',
      () async {
        final (result, trace) = await fixture.run('deny-magic');
        expect(result.exitCode, 1, reason: '${result.stderr}');
        expect(trace, ['arm', 'magic']);
        final report =
            jsonDecode(result.stdout as String) as Map<String, Object?>;
        expect(_windowsAdapter(report)['wakeEnabled'], isTrue);
        expect(_windowsAdapter(report)['magicPacketEnabled'], isFalse);
        expect(report['error'], contains('may have changed settings'));
        expect(report['error'], contains('separately'));
      },
    );

    test(
      'a setter that changes the property before failing reports pending state',
      () async {
        final (result, trace) = await fixture.run('partial-magic');
        expect(result.exitCode, 1, reason: '${result.stderr}');
        expect(trace, ['magic']);
        final report =
            jsonDecode(result.stdout as String) as Map<String, Object?>;
        expect(_windowsAdapter(report)['magicPacketEnabled'], isTrue);
        expect(_windowsAdapter(report)['restartRequired'], isTrue);
        expect(report['error'], contains('may have changed settings'));
      },
    );

    test(
      'retains original identity if the adapter disappears after the setter',
      () async {
        final (result, trace) = await fixture.run('disappear-after-magic');
        expect(result.exitCode, 1, reason: '${result.stderr}');
        expect(trace, ['arm', 'magic']);
        final report =
            jsonDecode(result.stdout as String) as Map<String, Object?>;
        expect(report['adapters'], isEmpty);
        expect(report['pendingRestart'], {
          'id': '12345678-1234-1234-1234-123456789abc',
          'mac': '02-11-22-33-44-55',
        });
      },
    );
  }, skip: Platform.isWindows ? false : 'Windows PowerShell is unavailable.');

  group('Windows pending configuration history', () {
    test(
      'rejects malformed detached pending identities before retaining them',
      () async {
        final original = _configuredWindowsReport(7);
        final identity = _windowsAdapter(original);
        for (final pending in <Object?>[
          false,
          {'id': 'invalid', 'mac': identity['mac']},
          {'id': identity['id'], 'mac': '01:11:22:33:44:55'},
          {'id': identity['id'], 'mac': identity['mac'], 'extra': true},
        ]) {
          final commands = _WindowsCommands([
            ('Inspect', 0, original),
            (
              'Enable',
              1,
              {
                ...original,
                'adapters': <Object?>[],
                'pendingRestart': pending,
                'error': 'Invalid operation report.',
              },
            ),
            ('Inspect', 0, original),
          ]);
          await expectLater(
            Sleeper(windowsCommand: commands.run).enableWake(
              identity['id']! as String,
              expectedMac: identity['mac']! as String,
            ),
            throwsA(isA<SleeperFailure>()),
          );
          expect(
            (await Sleeper(
              windowsCommand: commands.run,
            ).inspect()).adapters.single.restartRequired,
            isFalse,
          );
          expect(commands.responses, isEmpty);
          await commands.expectScriptsRemoved();
        }
      },
    );

    test(
      'retains pending identity through disappearance and later refresh',
      () async {
        final original = _configuredWindowsReport(6);
        final identity = _windowsAdapter(original);
        final commands = _WindowsCommands([
          ('Inspect', 0, original),
          (
            'Enable',
            1,
            {
              ...original,
              'adapters': <Object?>[],
              'pendingRestart': {'id': identity['id'], 'mac': identity['mac']},
              'error': 'Adapter disappeared after storing the setting.',
            },
          ),
          ('Inspect', 0, original),
        ]);
        await expectLater(
          Sleeper(windowsCommand: commands.run).enableWake(
            identity['id']! as String,
            expectedMac: identity['mac']! as String,
          ),
          throwsA(isA<SleeperFailure>()),
        );
        expect(
          (await Sleeper(
            windowsCommand: commands.run,
          ).inspect()).adapters.single.restartRequired,
          isTrue,
        );
        expect(commands.responses, isEmpty);
        await commands.expectScriptsRemoved();
      },
    );

    test(
      'bounds advisory history without claiming old settings activated',
      () async {
        final commands = _WindowsCommands([
          for (var i = 1000; i <= 1128; i++)
            ('Inspect', 0, _configuredWindowsReport(i, pending: true)),
          ('Inspect', 0, _configuredWindowsReport(1000)),
          ('Inspect', 0, _configuredWindowsReport(1128)),
        ]);
        final sleeper = Sleeper(windowsCommand: commands.run);
        for (var i = 1000; i <= 1128; i++) {
          expect(
            (await sleeper.inspect()).adapters.single.restartRequired,
            isTrue,
          );
        }
        expect(
          (await sleeper.inspect()).adapters.single.restartRequired,
          isFalse,
        );
        expect(
          (await sleeper.inspect()).adapters.single.restartRequired,
          isTrue,
        );
        expect(commands.responses, isEmpty);
        await commands.expectScriptsRemoved();
      },
    );

    test(
      'retains a pending advisory across refresh and new Sleeper instances',
      () async {
        final fresh = _configuredWindowsReport(1);
        final id = _windowsAdapter(fresh)['id']! as String;
        final commands = _WindowsCommands([
          ('Inspect', 0, fresh),
          ('Enable', 0, _configuredWindowsReport(1, pending: true)),
          ('Inspect', 0, fresh),
          ('Inspect', 0, fresh),
          ('Inspect', 0, _configuredWindowsReport(1, mac: '02:aa:bb:cc:dd:ee')),
        ]);
        final sleeper = Sleeper(windowsCommand: commands.run);
        final enabled = await sleeper.enableWake(
          id,
          expectedMac: '02:aa:bb:cc:dd:ee',
        );
        expect(enabled.adapters.single.restartRequired, isTrue);
        expect(
          (await sleeper.inspect()).adapters.single.restartRequired,
          isTrue,
        );
        final reopened = await Sleeper(windowsCommand: commands.run).inspect();
        expect(reopened.adapters.single.restartRequired, isTrue);
        expect(reopened.adapters.single.magicPacketEnabled, isTrue);
        expect(reopened.adapters.single.detail, contains('without restarting'));
        expect(reopened.adapters.single.detail, contains('unverified'));
        expect(commands.responses, isEmpty);
        await commands.expectScriptsRemoved();
      },
    );

    test('remembers valid partial-failure reports before throwing', () async {
      final fresh = _configuredWindowsReport(2);
      final id = _windowsAdapter(fresh)['id']! as String;
      final commands = _WindowsCommands([
        ('Inspect', 0, fresh),
        (
          'Enable',
          1,
          {
            ..._configuredWindowsReport(2, pending: true),
            'error': 'Permission denied after storing the setting.',
          },
        ),
        ('Inspect', 0, fresh),
      ]);
      await expectLater(
        Sleeper(
          windowsCommand: commands.run,
        ).enableWake(id, expectedMac: '02:aa:bb:cc:dd:ee'),
        throwsA(isA<SleeperFailure>()),
      );
      final report = await Sleeper(windowsCommand: commands.run).inspect();
      expect(report.adapters.single.restartRequired, isTrue);
      expect(commands.responses, isEmpty);
      await commands.expectScriptsRemoved();
    });

    test('keys pending history by both GUID and canonical MAC', () async {
      final original = _configuredWindowsReport(3);
      final id = _windowsAdapter(original)['id']! as String;
      final commands = _WindowsCommands([
        ('Inspect', 0, original),
        ('Enable', 0, _configuredWindowsReport(3, pending: true)),
        ('Inspect', 0, original),
        ('Inspect', 0, _configuredWindowsReport(3, mac: '02-AA-BB-CC-DD-FF')),
        ('Inspect', 0, _configuredWindowsReport(4)),
        ('Inspect', 0, original),
      ]);
      await Sleeper(
        windowsCommand: commands.run,
      ).enableWake(id, expectedMac: '02:aa:bb:cc:dd:ee');
      expect(
        (await Sleeper(
          windowsCommand: commands.run,
        ).inspect()).adapters.single.restartRequired,
        isFalse,
      );
      expect(
        (await Sleeper(
          windowsCommand: commands.run,
        ).inspect()).adapters.single.restartRequired,
        isFalse,
      );
      expect(
        (await Sleeper(
          windowsCommand: commands.run,
        ).inspect()).adapters.single.restartRequired,
        isTrue,
      );
      expect(commands.responses, isEmpty);
    });

    test(
      'an invalid partial-failure report cannot poison pending history',
      () async {
        final original = _configuredWindowsReport(5);
        final invalid = _configuredWindowsReport(5, pending: true);
        (invalid['adapters']! as List<Object?>).add({'id': 'invalid'});
        final commands = _WindowsCommands([
          ('Inspect', 0, original),
          ('Enable', 1, {...invalid, 'error': 'Permission denied.'}),
          ('Inspect', 0, original),
        ]);
        await expectLater(
          Sleeper(windowsCommand: commands.run).enableWake(
            _windowsAdapter(original)['id']! as String,
            expectedMac: '02:aa:bb:cc:dd:ee',
          ),
          throwsA(isA<SleeperFailure>()),
        );
        expect(
          (await Sleeper(
            windowsCommand: commands.run,
          ).inspect()).adapters.single.restartRequired,
          isFalse,
        );
        expect(commands.responses, isEmpty);
      },
    );
  }, skip: Platform.isWindows ? false : 'Windows backend requires Windows.');

  group('Linux report', () {
    test('rejects an interface name reused after the displayed selection', () {
      final displayed = _linuxAdapter();
      for (final output in <String?>[
        null,
        'Supports Wake-on: g\nWake-on: g\n',
      ]) {
        final fresh = _linuxReport(
          _linuxAdapter(mac: '02:aa:bb:cc:dd:ee', ethtoolOutput: output),
        );
        expect(
          () => fresh.selectedAdapter(displayed.id, expectedMac: displayed.mac),
          throwsA(isA<SleeperFailure>()),
        );
      }
    });

    test('matches the displayed MAC across case and separator differences', () {
      final adapter = _linuxAdapter(mac: '02:aa:bb:cc:dd:ee');
      final report = _linuxReport(adapter);
      expect(
        report.selectedAdapter(adapter.id, expectedMac: '02-AA-BB-CC-DD-EE'),
        same(adapter),
      );
    });

    test('rejects a malformed displayed MAC before selecting an adapter', () {
      final report = _linuxReport(_linuxAdapter());
      for (final mac in [
        '',
        '00:00:00:00:00:00',
        '01:11:22:33:44:55',
        '02:11-22:33:44:55',
        '02:11:22:33:44:55;run',
      ]) {
        expect(
          () => report.selectedAdapter('enp1s0', expectedMac: mac),
          throwsFormatException,
        );
      }
    });

    test(
      'derives broadcast from each actual prefix instead of assuming /24',
      () {
        for (final sample in [
          ('192.168.1.20', 24, '192.168.1.255'),
          ('192.168.10.130', 26, '192.168.10.191'),
          ('10.23.7.8', 16, '10.23.255.255'),
          ('172.16.2.4', 23, '172.16.3.255'),
          ('192.168.1.5', 30, '192.168.1.7'),
        ]) {
          expect(
            _linuxAdapter(ip: sample.$1, prefixLength: sample.$2).broadcast,
            sample.$3,
          );
        }
        for (final prefix in <int?>[null, 31, 32]) {
          final adapter = _linuxAdapter(prefixLength: prefix);
          expect(adapter.broadcast, isEmpty);
          expect(adapter.detail.toLowerCase(), contains('broadcast'));
        }
      },
    );

    test(
      'reads ethtool magic packet state and discloses runtime-only configuration',
      () {
        final enabled = _linuxAdapter(
          ethtoolOutput:
              'Settings for enp1s0:\n\tSupports Wake-on: pumbg\n\tWake-on: g\n',
        );
        expect(enabled.supportsWake, isTrue);
        expect(enabled.wakeEnabled, isTrue);
        expect(enabled.magicPacketEnabled, isTrue);
        expect(enabled.detail.toLowerCase(), contains('runtime-only'));
        final disabled = _linuxAdapter(
          ethtoolOutput: '\tSupports Wake-on: g\n\tWake-on: d\n',
        );
        expect(disabled.supportsWake, isTrue);
        expect(disabled.wakeEnabled, isFalse);
        expect(disabled.magicPacketEnabled, isFalse);
        final otherTrigger = _linuxAdapter(
          ethtoolOutput: '\tSupports Wake-on: pumbg\n\tWake-on: p\n',
        );
        expect(otherTrigger.wakeEnabled, isTrue);
        expect(otherTrigger.magicPacketEnabled, isFalse);
      },
    );

    test('reports no capability only when ethtool explicitly reports none', () {
      final adapter = _linuxAdapter(
        ethtoolOutput: 'Supports Wake-on: d\nWake-on: d\n',
      );
      expect(adapter.supportsWake, isFalse);
      expect(adapter.wakeEnabled, isFalse);
      expect(adapter.magicPacketEnabled, isFalse);
    });

    test('missing, denied, or malformed ethtool evidence stays unknown', () {
      for (final output in <String?>[
        null,
        '',
        'netlink error: Operation not permitted',
        'Supports Wake-on: unknown\nWake-on: unknown',
        'Supports Wake-on: g\nWake-on: d\nWake-on: g',
      ]) {
        final adapter = _linuxAdapter(
          ethtoolOutput: output,
          detail: 'Query unavailable.',
        );
        expect(adapter.wakeEnabled, isNull);
        expect(adapter.magicPacketEnabled, isNull);
        expect(adapter.detail, contains('Query unavailable'));
      }
    });

    test(
      'does not infer WiFi WoWLAN support from an Ethernet ethtool response',
      () {
        final adapter = _linuxAdapter(
          connection: TargetConnection.wifi,
          ethtoolOutput: 'Supports Wake-on: d\nWake-on: d',
        );
        expect(adapter.supportsWake, isNull);
        expect(adapter.wakeEnabled, isNull);
        expect(adapter.magicPacketEnabled, isNull);
        expect(adapter.detail, contains('WoWLAN'));
      },
    );
  });

  final bash = Platform.isWindows
      ? 'C:/Program Files/Git/bin/bash.exe'
      : '/bin/bash';
  group('Linux helper identity checks', () {
    late _LinuxWakeFixture fixture;

    setUp(() async => fixture = await _LinuxWakeFixture.create(bash));
    tearDown(() async => fixture.dispose());

    test(
      'accepts an unchanged physical Ethernet identity for enable and query',
      () async {
        for (final operation in ['enable', 'query']) {
          final result = await fixture.check(
            arguments: [operation, 'enp1s0', '02:11:22:33:44:55', '7'],
          );
          expect(result.exitCode, 0, reason: '${result.stderr}');
        }
      },
    );

    test('rejects a MAC replaced before the helper identity check', () async {
      await fixture.write('address', '02:aa:bb:cc:dd:ee');
      final result = await fixture.check();
      expect(result.exitCode, 65, reason: '${result.stderr}');
      expect(result.stderr, contains('changed or disappeared'));
    });

    test('accepts the maximum supported interface index', () async {
      await fixture.write('ifindex', '2147483647');
      await fixture.write('iflink', '2147483647');
      final result = await fixture.check(
        arguments: ['enable', 'enp1s0', '02:11:22:33:44:55', '2147483647'],
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
    });

    test(
      'rejects a reused name and MAC with a different interface index',
      () async {
        await fixture.write('ifindex', '8');
        await fixture.write('iflink', '8');
        final result = await fixture.check();
        expect(result.exitCode, 65, reason: '${result.stderr}');
      },
    );

    for (final sample in [
      ('type', '772'),
      ('iflink', '8'),
      ('flags', '0x1002'),
      ('flags', '0x1;run'),
      ('address', '00:00:00:00:00:00'),
    ]) {
      test('rejects an ineligible sysfs ${sample.$1} value', () async {
        await fixture.write(sample.$1, sample.$2);
        final result = await fixture.check();
        expect(result.exitCode, 65, reason: '${result.stderr}');
      });
    }

    test('rejects disappearance of the physical device', () async {
      await Directory('${fixture.interfacePath}/device').delete();
      final result = await fixture.check();
      expect(result.exitCode, 65, reason: '${result.stderr}');
    });

    test('rejects WiFi even when its Ethernet type and MAC match', () async {
      await Directory('${fixture.interfacePath}/wireless').create();
      final result = await fixture.check();
      expect(result.exitCode, 65, reason: '${result.stderr}');
    });

    test(
      'rejects unsafe or unbounded helper argv before reading sysfs',
      () async {
        for (final arguments in <List<String>>[
          [],
          ['enable', 'enp1s0', '02:11:22:33:44:55'],
          ['enable', 'enp1s0', '02:11:22:33:44:55', '7', 'extra'],
          ['enable;run', 'enp1s0', '02:11:22:33:44:55', '7'],
          ['enable', '../enp1s0', '02:11:22:33:44:55', '7'],
          ['enable', '--help', '02:11:22:33:44:55', '7'],
          ['enable', 'enp1s0', '02:11:22:33:44:55;run', '7'],
          ['enable', 'enp1s0', '01:11:22:33:44:55', '7'],
          ['enable', 'enp1s0', '00:00:00:00:00:00', '7'],
          ['enable', 'enp1s0', '02:11:22:33:44:55', '0'],
          ['enable', 'enp1s0', '02:11:22:33:44:55', '7+1'],
          ['enable', 'enp1s0', '02:11:22:33:44:55', '2147483648'],
          ['enable', 'enp1s0', '02:11:22:33:44:55', '99999999999999999999'],
        ]) {
          final result = await fixture.check(arguments: arguments);
          expect(result.exitCode, 64, reason: '$arguments: ${result.stderr}');
        }
      },
    );

    test(
      'ignores shell startup hooks and PATH during identity checks',
      () async {
        final startup = File('${fixture.root.path}/startup.sh');
        final marker = File('${fixture.root.path}/startup-ran');
        await startup.writeAsString(
          r'printf injected > "$SLEEPER_TEST_STARTUP_MARKER"'
          '\n',
        );
        final result = await fixture.check(
          environment: {
            'BASH_ENV': startup.path,
            'ENV': startup.path,
            'PATH': '${fixture.root.path}/untrusted-bin',
            'SLEEPER_TEST_STARTUP_MARKER': marker.path,
          },
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(await marker.exists(), isFalse);
      },
    );
  }, skip: File(bash).existsSync() ? false : 'Bash is unavailable.');

  test(
    'rejects unsafe adapter arguments before any inspection or OS command',
    () async {
      for (final id in [
        '',
        '../eth0',
        '--help',
        'eth0;run',
        'eth0\nrun',
        'a b',
      ]) {
        await expectLater(
          Sleeper().enableWake(id, expectedMac: '02:11:22:33:44:55'),
          throwsFormatException,
        );
      }
    },
  );
}

class _LinuxWakeFixture {
  _LinuxWakeFixture(this.bash, this.root);

  final String bash;
  final Directory root;
  String get interfacePath => '${root.path}/sys/class/net/enp1s0';

  static Future<_LinuxWakeFixture> create(String bash) async {
    final root = await Directory.systemTemp.createTemp('seliawake-linux-test-');
    final fixture = _LinuxWakeFixture(bash, root);
    await Directory('${fixture.interfacePath}/device').create(recursive: true);
    for (final entry in {
      'type': '1',
      'ifindex': '7',
      'iflink': '7',
      'flags': '0x1003',
      'address': '02:11:22:33:44:55',
    }.entries) {
      await fixture.write(entry.key, entry.value);
    }
    // Source the actual helper, then execute its identity validator against
    // fixture files. No production setter or real sysfs is invoked.
    await File('${root.path}/check.sh').writeAsString(r'''
set -eu
. "$1"
sleeper_test_sysfs="$2"
shift 2
linux_wake_validate_arguments "$@"
linux_wake_check_identity "$sleeper_test_sysfs" "$2" "$3" "$4"
''');
    return fixture;
  }

  Future<void> write(String name, String value) =>
      File('$interfacePath/$name').writeAsString('$value\n');

  Future<ProcessResult> check({
    List<String>? arguments,
    Map<String, String>? environment,
  }) => Process.run(
    bash,
    [
      '--noprofile',
      '--norc',
      '-p',
      '${root.path}/check.sh',
      File('assets/scripts/linux-wake.sh').absolute.path,
      '${root.path}/sys',
      ...(arguments ?? ['enable', 'enp1s0', '02:11:22:33:44:55', '7']),
    ],
    environment: environment,
    runInShell: false,
  );

  Future<void> dispose() async {
    // The fixture owns only these files/directories; avoid recursive deletion.
    for (final name in ['type', 'ifindex', 'iflink', 'flags', 'address']) {
      await File('$interfacePath/$name').delete();
    }
    for (final name in ['device', 'wireless']) {
      final directory = Directory('$interfacePath/$name');
      if (await directory.exists()) await directory.delete();
    }
    await File('${root.path}/check.sh').delete();
    for (final name in ['startup.sh', 'startup-ran']) {
      final file = File('${root.path}/$name');
      if (await file.exists()) await file.delete();
    }
    for (final suffix in [
      'sys/class/net/enp1s0',
      'sys/class/net',
      'sys/class',
      'sys',
    ]) {
      await Directory('${root.path}/$suffix').delete();
    }
    await root.delete();
  }
}

class _WindowsWakeFixture {
  _WindowsWakeFixture(this.root);

  final Directory root;

  static Future<_WindowsWakeFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'seliawake-windows-test-',
    );
    // Run the production functions and main body with fixture cmdlets. Every
    // setter and process launch is intercepted, so no real adapter is touched.
    await File('${root.path}/check.ps1').writeAsString(r'''
param([string] $Source, [string] $Scenario, [string] $Action, [string] $TracePath)
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($Source, [ref] $tokens, [ref] $errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) {
        . ([scriptblock]::Create($statement.Extent.Text))
    }
}

$script:scenario = $Scenario
$script:armed = $Scenario -in @('configured', 'partial-magic')
$script:magic = if ($Scenario -in @('configured', 'inactive-wake', 'ambiguous-wake', 'denied-wake')) { '1' } else { '0' }
$script:trace = [Collections.Generic.List[string]]::new()
$AdapterId = '12345678-1234-1234-1234-123456789abc'
$ElevatedWorker = $false
$script:deviceName = 'Fixture physical adapter'
function Import-Module { }
function New-Object([string] $TypeName) {
    if ($TypeName -notlike 'Security.Principal.WindowsPrincipal*') { throw "Unexpected constructor: $TypeName" }
    $principal = [pscustomobject]@{}
    Add-Member -InputObject $principal -MemberType ScriptMethod -Name IsInRole -Value { param($Role) return $false }
    return $principal
}
function Start-Process {
    $script:trace.Add('elevation')
    throw 'Process launch blocked by fixture.'
}
function Invoke-PowerCfg([string[]] $NativeArguments) {
    if ($NativeArguments[0] -eq '/deviceenablewake') {
        $script:trace.Add('arm')
        if ($script:scenario -eq 'deny-arm') { throw [UnauthorizedAccessException]::new('Access is denied.') }
        $script:armed = $true
        return ''
    }
    if ($NativeArguments[0] -eq '/a') { return 'Standby (S3)' }
    if ($NativeArguments[0] -ne '/devicequery') { throw 'Unexpected powercfg operation.' }
    if ($NativeArguments[1] -ne 'wake_armed' -or $script:armed) { return $script:deviceName }
    return ''
}
function Get-NetAdapter {
    if ($script:scenario -eq 'disappear-after-magic' -and $script:magic -eq '1') { return }
    return [pscustomobject]@{
        InterfaceGuid = $AdapterId; InterfaceIndex = 7; HardwareInterface = $true
        Virtual = $false; Status = 'Up'; InterfaceType = 6; NdisPhysicalMedium = 0
        Name = 'Fixture Ethernet'; InterfaceDescription = 'Fixture Ethernet'
        MacAddress = '02-11-22-33-44-55'; PnPDeviceID = 'FIXTURE\WAKE\1'; DriverProvider = 'Fixture'
    }
}
function Get-NetIPAddress {
    return [pscustomobject]@{
        AddressState = 'Preferred'; SkipAsSource = $false; InterfaceIndex = 7
        IPAddress = '192.168.1.20'; PrefixLength = 24
    }
}
function Get-CimInstance([string] $ClassName) {
    if ($ClassName -eq 'MSNdis_PMCapabilities') {
        if ($script:scenario -eq 'denied-wake') { throw 'NDIS query denied.' }
        if ($script:scenario -notin @('inactive-wake', 'ambiguous-wake')) { return }
        $capability = [pscustomobject]@{
            InstanceName = 'Fixture Ethernet'
            PMCapabilitiesParam = [pscustomobject]@{
                WakeOnMagicPacket = [pscustomobject]@{ NdisPMCapabilityState = 1 }
            }
        }
        if ($script:scenario -eq 'ambiguous-wake') { return @($capability, $capability) }
        return $capability
    }
    return [pscustomobject]@{ DeviceID = 'FIXTURE\WAKE\1'; Name = $script:deviceName }
}
function Get-NetAdapterAdvancedProperty {
    return [pscustomobject]@{
        InstanceID = ([guid] $AdapterId).ToString('B') + '::*WakeOnMagicPacket'
        RegistryKeyword = '*WakeOnMagicPacket'; RegistryValue = @($script:magic)
    }
}
function Set-NetAdapterAdvancedProperty {
    $script:trace.Add('magic')
    if ($script:scenario -eq 'deny-magic') { throw [UnauthorizedAccessException]::new('Access is denied.') }
    $script:magic = '1'
    if ($script:scenario -eq 'partial-magic') { throw [UnauthorizedAccessException]::new('Access is denied after storing the property.') }
}
$body = ($ast.EndBlock.Statements | Where-Object {
    $_ -isnot [Management.Automation.Language.FunctionDefinitionAst]
} | ForEach-Object { $_.Extent.Text }) -join "`n"
$body = '$PSCommandPath = $Source' + "`n" + $body
try { . ([scriptblock]::Create($body)) }
finally { [IO.File]::WriteAllText($TracePath, (ConvertTo-Json -InputObject @($script:trace) -Compress)) }
''');
    return _WindowsWakeFixture(root);
  }

  Future<(ProcessResult, List<Object?>)> run(
    String scenario, {
    String action = 'Enable',
  }) async {
    final result = await Process.run(
      '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        '${root.path}/check.ps1',
        '-Source',
        File('assets/scripts/windows-wake.ps1').absolute.path,
        '-Scenario',
        scenario,
        '-Action',
        action,
        '-TracePath',
        '${root.path}/trace.json',
      ],
      runInShell: false,
    ).timeout(const Duration(seconds: 20));
    final trace =
        jsonDecode(await File('${root.path}/trace.json').readAsString())
            as List<Object?>;
    return (result, trace);
  }

  Future<void> dispose() async {
    for (final name in ['check.ps1', 'trace.json']) {
      final file = File('${root.path}/$name');
      if (await file.exists()) await file.delete();
    }
    await root.delete();
  }
}

class _WindowsCommands {
  _WindowsCommands(this.responses);

  final List<(String, int, Map<String, Object?>)> responses;
  final Set<String> scripts = {};

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    expect(
      executable,
      '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
    );
    final script = arguments[arguments.indexOf('-File') + 1];
    expect(await File(script).exists(), isTrue);
    scripts.add(script);
    final response = responses.removeAt(0);
    expect(arguments[arguments.indexOf('-Action') + 1], response.$1);
    return ProcessResult(0, response.$2, jsonEncode(response.$3), '');
  }

  Future<void> expectScriptsRemoved() async {
    for (final path in scripts) {
      expect(await File(path).exists(), isFalse);
      expect(await Directory(File(path).parent.path).exists(), isFalse);
    }
  }
}
