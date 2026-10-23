import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const relayPort = 45879;
const requestLimit = 1024;

String randomKey([int length = 32]) {
  final random = Random.secure();
  return base64Url
      .encode(List.generate(length, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

bool isTailnetAddress(String value) {
  final ip = InternetAddress.tryParse(value);
  if (ip == null || ip.type != InternetAddressType.IPv4) return false;
  final bytes = ip.rawAddress;
  return bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127;
}

bool isLanAddress(String value) {
  final ip = InternetAddress.tryParse(value);
  if (ip == null || ip.type != InternetAddressType.IPv4) return false;
  final b = ip.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
}

Uint8List decodeKey(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) {
    throw const FormatException('invalid_key');
  }
  final key = base64Url.decode(base64Url.normalize(value));
  if (key.length != 32 || base64Url.encode(key).replaceAll('=', '') != value) {
    throw const FormatException('invalid_key');
  }
  return key;
}

Uint8List magicPacket(String mac) {
  if (!RegExp(r'^(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$').hasMatch(mac)) {
    throw const FormatException('invalid_mac');
  }
  final bytes = mac
      .split(RegExp('[:-]'))
      .map((v) => int.parse(v, radix: 16))
      .toList();
  if ((bytes.first & 1) != 0 || bytes.every((v) => v == 0)) {
    throw const FormatException('invalid_mac');
  }
  return Uint8List.fromList([
    ...List.filled(6, 255),
    for (var i = 0; i < 16; i++) ...bytes,
  ]);
}

String signWake(String key, int timestamp, String nonce) => Hmac(
  sha256,
  decodeKey(key),
).convert(utf8.encode('$timestamp\n$nonce\nwake-v1')).toString();

bool constantTimeEquals(String a, String b) {
  var difference = a.length ^ b.length;
  for (var i = 0; i < max(a.length, b.length); i++) {
    difference |=
        (i < a.length ? a.codeUnitAt(i) : 0) ^
        (i < b.length ? b.codeUnitAt(i) : 0);
  }
  return difference == 0;
}

class ProtocolFailure implements Exception {
  const ProtocolFailure(this.code, [this.status = 400]);
  final String code;
  final int status;
  @override
  String toString() => code;
}

class WakeAuthorizer {
  WakeAuthorizer(this.key) {
    decodeKey(key);
  }
  final String key;
  final _nonces = <String, int>{};
  int _window = 0;
  int _attempts = 0;

  void authorize(Map<String, Object?> body, int now) {
    if (now - _window >= 60 || now < _window) {
      _window = now;
      _attempts = 0;
    }
    if (++_attempts > 60) throw const ProtocolFailure('rate_limited', 429);
    _nonces.removeWhere((_, expiry) => expiry <= now);
    final timestamp = body['timestamp'];
    final nonce = body['nonce'];
    final signature = body['signature'];
    if (body.length != 3 ||
        timestamp is! int ||
        nonce is! String ||
        signature is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(nonce) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(signature)) {
      throw const ProtocolFailure('invalid_request');
    }
    if ((timestamp - now).abs() > 30) {
      throw const ProtocolFailure('expired', 401);
    }
    if (!constantTimeEquals(signWake(key, timestamp, nonce), signature)) {
      throw const ProtocolFailure('unauthorized', 401);
    }
    if (_nonces.containsKey(nonce)) throw const ProtocolFailure('replay', 409);
    if (_nonces.length >= 128) throw const ProtocolFailure('rate_limited', 429);
    _nonces[nonce] = now + 60;
  }
}

class Pairing {
  Pairing({required this.host, required this.key, required this.name}) {
    if (!isTailnetAddress(host) || name.length > 80 || name.trim().isEmpty) {
      throw const FormatException('invalid_pairing');
    }
    decodeKey(key);
  }
  final String host;
  final String key;
  final String name;

  String encode() =>
      'seliawake://pair?data=${base64Url.encode(utf8.encode(jsonEncode({'v': 1, 'host': host, 'key': key, 'name': name}))).replaceAll('=', '')}';

  factory Pairing.parse(String code) {
    if (code.length > 2048) throw const FormatException('invalid_pairing');
    final uri = Uri.tryParse(code.trim());
    if (uri == null ||
        uri.scheme != 'seliawake' ||
        uri.host != 'pair' ||
        uri.queryParameters.length != 1 ||
        uri.queryParameters['data'] == null) {
      throw const FormatException('invalid_pairing');
    }
    final decoded = jsonDecode(
      utf8.decode(
        base64Url.decode(base64Url.normalize(uri.queryParameters['data']!)),
      ),
    );
    if (decoded is! Map<String, dynamic> ||
        decoded['v'] != 1 ||
        decoded['host'] is! String ||
        decoded['key'] is! String ||
        decoded['name'] is! String) {
      throw const FormatException('invalid_pairing');
    }
    return Pairing(
      host: decoded['host'] as String,
      key: decoded['key'] as String,
      name: decoded['name'] as String,
    );
  }
}

Future<List<int>> readBoundedBody(Stream<List<int>> stream) async {
  final completed = Completer<List<int>>();
  final bytes = <int>[];
  final subscription = stream.listen(
    (chunk) {
      if (completed.isCompleted) return;
      if (bytes.length + chunk.length > requestLimit) {
        completed.completeError(const ProtocolFailure('invalid_request', 413));
      } else {
        bytes.addAll(chunk);
      }
    },
    onError: (Object error, StackTrace trace) {
      if (!completed.isCompleted) completed.completeError(error, trace);
    },
    onDone: () {
      if (!completed.isCompleted) completed.complete(bytes);
    },
  );
  try {
    return await completed.future.timeout(const Duration(seconds: 4));
  } finally {
    await subscription.cancel();
  }
}

Future<void> requestWake(Pairing pairing) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  client.findProxy = (_) => 'DIRECT';
  try {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final nonce = randomKey(16);
    final request = await client
        .postUrl(
          Uri(
            scheme: 'http',
            host: pairing.host,
            port: relayPort,
            path: '/v1/wake',
          ),
        )
        .timeout(const Duration(seconds: 8));
    request.headers.contentType = ContentType.json;
    request.followRedirects = false;
    final bodyBytes = utf8.encode(
      jsonEncode({
        'timestamp': timestamp,
        'nonce': nonce,
        'signature': signWake(pairing.key, timestamp, nonce),
      }),
    );
    request.contentLength = bodyBytes.length;
    request.add(bodyBytes);
    final response = await request.close().timeout(const Duration(seconds: 8));
    final bytes = await readBoundedBody(response);
    final body = jsonDecode(utf8.decode(bytes));
    if (body is! Map<String, dynamic>) {
      throw const ProtocolFailure('invalid_response');
    }
    if (response.statusCode != 200 || body['status'] != 'sent') {
      final error = body['error'];
      throw ProtocolFailure(
        error is String ? error : 'invalid_response',
        response.statusCode,
      );
    }
  } finally {
    client.close(force: true);
  }
}
