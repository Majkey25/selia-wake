import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seliawake/core/protocol.dart';
import 'package:seliawake/core/relay.dart';

Future<({Socket socket, Future<void> closed})> incompleteRequest() async {
  final socket = await Socket.connect('127.0.0.1', relayPort);
  final closed = Completer<void>();
  void complete() {
    if (!closed.isCompleted) closed.complete();
  }

  socket.listen((_) {}, onDone: complete, onError: (Object _) => complete());
  socket.write('POST /v1/wake HTTP/1.1\r\nHost: localhost\r\nX-Incomplete:');
  try {
    await socket.flush();
  } on SocketException {
    complete();
  }
  return (socket: socket, closed: closed.future);
}

void main() {
  late _RecordingRelay relay;
  late String key;

  setUp(() async {
    key = randomKey();
    relay = _RecordingRelay();
    await relay.start(
      RelayConfig(
        mac: '02:11:22:33:44:55',
        broadcast: '192.168.1.255',
        secret: key,
        name: 'Test',
        language: 'en',
        lanIp: '192.168.1.20',
      ),
    );
  });
  tearDown(() => relay.stop());

  test('connection budget includes incomplete HTTP headers', () async {
    final clients = <({Socket socket, Future<void> closed})>[];
    try {
      for (var i = 0; i < 24; i++) {
        clients.add(await incompleteRequest());
      }
      await Future.wait(
        clients.skip(8).map((client) => client.closed),
      ).timeout(const Duration(seconds: 2));
      expect(relay.sent, isEmpty);
    } finally {
      for (final client in clients) {
        client.socket.destroy();
      }
    }
  });

  test('incomplete HTTP headers have an absolute deadline', () async {
    final client = await incompleteRequest();
    try {
      await client.closed.timeout(const Duration(seconds: 7));
      expect(relay.sent, isEmpty);
    } finally {
      client.socket.destroy();
    }
  });

  test(
    'invalid traffic cannot wake or exhaust the authenticated quota',
    () async {
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      Future<int> post(String body) async {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$relayPort/v1/wake'),
        );
        request.headers.contentType = ContentType.json;
        final bytes = utf8.encode(body);
        request.contentLength = bytes.length;
        request.add(bytes);
        final response = await request.close().timeout(
          const Duration(seconds: 3),
        );
        await response.drain<void>();
        return response.statusCode;
      }

      try {
        for (var i = 0; i < 65; i++) {
          try {
            expect(await post('{}'), 400);
          } on SocketException catch (error) {
            fail('Ordinary request $i was rejected: $error');
          }
        }
        final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final nonce = randomKey(16);
        final signed = {
          'timestamp': timestamp,
          'nonce': nonce,
          'signature': signWake(key, timestamp, nonce),
        };
        expect(await post(jsonEncode({...signed, 'signature': '0' * 64})), 401);
        expect(
          await post(jsonEncode({...signed, 'mac': '02:11:22:33:44:66'})),
          400,
        );
        expect(await post(' ' * 1025), 400);
        expect(relay.sent, isEmpty);
        final body = jsonEncode(signed);
        expect(await post(body), 200);
        expect(await post(body), 409);
        expect(relay.sent, [
          ('02:11:22:33:44:55', '192.168.1.255', '192.168.1.20'),
        ]);
      } finally {
        client.close(force: true);
      }
    },
  );
}

class _RecordingRelay extends Relay {
  final sent = <(String, String, String)>[];

  @override
  Future<void> sendLocal(
    String mac,
    String broadcast, {
    String lanIp = '',
  }) async {
    sent.add((mac, broadcast, lanIp));
  }
}
