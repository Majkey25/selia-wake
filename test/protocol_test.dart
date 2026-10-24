import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:seliawake/core/protocol.dart';
import 'package:seliawake/core/settings.dart';

void main() {
  final key = base64Url.encode(List.generate(32, (i) => i)).replaceAll('=', '');
  final nonce = base64Url
      .encode(List.generate(16, (i) => i))
      .replaceAll('=', '');
  const now = 1800000000;
  Map<String, Object?> request({int timestamp = now, String? requestNonce}) {
    final n = requestNonce ?? nonce;
    return {
      'timestamp': timestamp,
      'nonce': n,
      'signature': signWake(key, timestamp, n),
    };
  }

  test(
    'magic packet follows the wire format and rejects non-unicast targets',
    () {
      final packet = magicPacket('02-11-22-33-44-55');
      expect(packet.length, 102);
      expect(packet.take(6), List.filled(6, 255));
      for (var i = 0; i < 16; i++) {
        expect(packet.skip(6 + i * 6).take(6), [2, 17, 34, 51, 68, 85]);
      }
      for (final value in [
        '00:00:00:00:00:00',
        'ff:ff:ff:ff:ff:ff',
        '01:00:5e:00:00:01',
        'hello',
        '02:11:22:33:44:5500',
      ]) {
        expect(() => magicPacket(value), throwsFormatException);
      }
    },
  );

  test('authorization accepts a signed request once and rejects replay', () {
    // Independently verified with Node.js crypto.createHmac.
    expect(
      signWake(key, now, nonce),
      '78b662fee46d77d5abb169a1148b0ddaad174ae3d0e21c1448ab0e9eaf48a009',
    );
    final auth = WakeAuthorizer(key);
    auth.authorize(request(), now);
    expect(
      () => auth.authorize(request(), now),
      throwsA(isA<ProtocolFailure>().having((e) => e.code, 'code', 'replay')),
    );
  });

  test(
    'authorization rejects invalid signatures, times and extra destinations',
    () {
      final auth = WakeAuthorizer(key);
      expect(
        () => auth.authorize({...request(), 'signature': '0' * 64}, now),
        throwsA(
          isA<ProtocolFailure>().having((e) => e.code, 'code', 'unauthorized'),
        ),
      );
      expect(
        () => auth.authorize(request(timestamp: now - 31), now),
        throwsA(
          isA<ProtocolFailure>().having((e) => e.code, 'code', 'expired'),
        ),
      );
      expect(
        () => auth.authorize(request(timestamp: now + 31), now),
        throwsA(
          isA<ProtocolFailure>().having((e) => e.code, 'code', 'expired'),
        ),
      );
      expect(
        () => auth.authorize({...request(), 'mac': '02:11:22:33:44:55'}, now),
        throwsA(
          isA<ProtocolFailure>().having(
            (e) => e.code,
            'code',
            'invalid_request',
          ),
        ),
      );
      // Invalid attempts must not reserve a valid nonce.
      auth.authorize(request(), now);
    },
  );

  test('expired replay entries and attempt windows are cleaned up', () {
    final auth = WakeAuthorizer(key);
    auth.authorize(request(), now);
    auth.authorize(request(timestamp: now + 61), now + 61);
    for (var i = 0; i < 59; i++) {
      auth.authorize(
        request(requestNonce: randomKey(16), timestamp: now + 61),
        now + 61,
      );
    }
    expect(
      () => auth.authorize(
        request(requestNonce: randomKey(16), timestamp: now + 61),
        now + 61,
      ),
      throwsA(
        isA<ProtocolFailure>().having((e) => e.code, 'code', 'rate_limited'),
      ),
    );
    auth.authorize(request(timestamp: now + 122), now + 122);
  });

  test('replay is rejected through the final accepted timestamp second', () {
    final auth = WakeAuthorizer(key);
    final body = request(timestamp: now + 30);
    auth.authorize(body, now);
    expect(
      () => auth.authorize(body, now + 60),
      throwsA(isA<ProtocolFailure>().having((e) => e.code, 'code', 'replay')),
    );
    expect(
      () => auth.authorize(body, now + 61),
      throwsA(isA<ProtocolFailure>().having((e) => e.code, 'code', 'expired')),
    );
    auth.authorize(request(timestamp: now + 61), now + 61);
  });

  test('unauthenticated traffic and replays cannot exhaust the wake quota', () {
    final auth = WakeAuthorizer(key);
    auth.authorize(request(), now);
    for (var i = 0; i < 65; i++) {
      for (final invalid in [
        <String, Object?>{},
        {...request(), 'signature': '0' * 64},
        request(timestamp: now - 31),
        request(),
      ]) {
        expect(
          () => auth.authorize(invalid, now),
          throwsA(isA<ProtocolFailure>()),
        );
      }
    }
    auth.authorize(request(requestNonce: randomKey(16)), now);
  });

  test('pairing only permits Tailscale IPv4 and canonical 256-bit secrets', () {
    final pairing = Pairing(host: '100.101.102.103', key: key, name: 'Home');
    final decoded = Pairing.parse(pairing.encode());
    expect(decoded.host, pairing.host);
    expect(decoded.key, key);
    expect(decoded.name, 'Home');
    for (final host in [
      '127.0.0.1',
      '192.168.1.1',
      '100.63.0.1',
      '100.128.0.1',
      'example.com',
    ]) {
      expect(
        () => Pairing(host: host, key: key, name: 'Home'),
        throwsFormatException,
      );
    }
    expect(
      () => Pairing(host: pairing.host, key: '$key=', name: 'Home'),
      throwsFormatException,
    );
    expect(
      () => Pairing.parse('seliawake://pair?data=${'a' * 3000}'),
      throwsFormatException,
    );
    final settings = Settings(wakerKey: key, pairing: pairing);
    expect(jsonEncode(settings.toJson()), isNot(contains(key)));
  });

  test('body reader rejects a response that exceeds its size limit', () async {
    await expectLater(
      readBoundedBody(Stream.value(List.filled(requestLimit + 1, 1))),
      throwsA(isA<ProtocolFailure>().having((e) => e.status, 'status', 413)),
    );
  });
}
