import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'protocol.dart';

class NetworkInfo {
  const NetworkInfo({this.lanIp, this.broadcast, this.tailscaleIp});
  final String? lanIp;
  final String? broadcast;
  final String? tailscaleIp;
}

class RelayStatus {
  const RelayStatus(this.running, [this.error]);
  final bool running;
  final String? error;
}

class RelayConfig {
  const RelayConfig({
    required this.mac,
    required this.broadcast,
    required this.secret,
    required this.name,
    required this.language,
    this.lanIp = '',
  });
  final String mac;
  final String broadcast;
  final String secret;
  final String name;
  final String language;
  final String lanIp;
}

class Relay {
  static const _channel = MethodChannel('selia_wake/relay');
  HttpServer? _server;
  String? _error;
  final _requests = <HttpRequest>{};
  bool get _android => Platform.isAndroid;

  Future<NetworkInfo> networkInfo() async {
    if (_android) {
      final data = await _channel.invokeMapMethod<String, Object?>(
        'networkInfo',
      );
      return NetworkInfo(
        lanIp: data?['wifiIp'] as String?,
        broadcast: data?['broadcast'] as String?,
        tailscaleIp: data?['tailscaleIp'] as String?,
      );
    }
    final addresses = (await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )).expand((i) => i.addresses).map((a) => a.address).toList();
    return NetworkInfo(
      lanIp: addresses.where(isLanAddress).firstOrNull,
      broadcast: '255.255.255.255',
      tailscaleIp: addresses.where(isTailnetAddress).firstOrNull,
    );
  }

  Future<RelayStatus> status() async {
    if (_android) {
      final data = await _channel.invokeMapMethod<String, Object?>('status');
      return RelayStatus(data?['running'] == true, data?['error'] as String?);
    }
    return RelayStatus(_server != null, _error);
  }

  Future<void> start(RelayConfig config) async {
    magicPacket(config.mac);
    decodeKey(config.secret);
    if (config.broadcast.isNotEmpty &&
        config.broadcast != '255.255.255.255' &&
        !isLanAddress(config.broadcast)) {
      throw const FormatException('invalid_broadcast');
    }
    if (_android) {
      final broadcast =
          config.broadcast.isEmpty || config.broadcast == '255.255.255.255'
          ? (await networkInfo()).broadcast
          : config.broadcast;
      if (broadcast == null || broadcast.isEmpty) {
        throw const ProtocolFailure('wifi_unavailable', 503);
      }
      await _channel.invokeMethod<void>('start', {
        'mac': config.mac,
        'broadcast': broadcast,
        'secret': config.secret,
        'port': relayPort,
        'name': config.name,
        'language': config.language,
      });
      return;
    }
    if (!isLanAddress(config.lanIp)) throw const FormatException('invalid_lan');
    await stop();
    final authorizer = WakeAuthorizer(config.secret);
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      relayPort,
      shared: false,
    );
    server.idleTimeout = const Duration(seconds: 5);
    server.defaultResponseHeaders.clear();
    _error = null;
    _server = server;
    server.listen(
      (request) {
        if (_requests.length >= 8) {
          request.response.statusCode = 503;
          unawaited(request.response.close());
          return;
        }
        _requests.add(request);
        unawaited(
          _handle(
            request,
            config,
            authorizer,
          ).whenComplete(() => _requests.remove(request)),
        );
      },
      onError: (Object error) {
        _error = 'relay_failed';
        unawaited(stop());
      },
      onDone: () {
        if (identical(_server, server)) _server = null;
      },
    );
  }

  Future<void> _handle(
    HttpRequest request,
    RelayConfig config,
    WakeAuthorizer auth,
  ) async {
    request.response.persistentConnection = false;
    var code = 200;
    var result = <String, String>{'status': 'sent'};
    try {
      if (request.method != 'POST' ||
          request.uri.path != '/v1/wake' ||
          request.uri.hasQuery ||
          request.headers.contentType?.mimeType != 'application/json' ||
          request.contentLength < 0 ||
          request.contentLength > requestLimit) {
        throw const ProtocolFailure('invalid_request');
      }
      final bytes = await readBoundedBody(request);
      final body = jsonDecode(utf8.decode(bytes));
      if (body is! Map<String, dynamic>) {
        throw const ProtocolFailure('invalid_request');
      }
      auth.authorize(body, DateTime.now().millisecondsSinceEpoch ~/ 1000);
      await sendLocal(config.mac, config.broadcast, lanIp: config.lanIp);
    } on ProtocolFailure catch (error) {
      code = error.status;
      result = {'error': error.code};
    } on FormatException {
      code = 400;
      result = {'error': 'invalid_request'};
    } on TimeoutException {
      code = 408;
      result = {'error': 'invalid_request'};
    } catch (_) {
      code = 503;
      result = {'error': 'send_failed'};
    }
    try {
      request.response.statusCode = code;
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.write(jsonEncode(result));
      await request.response.close();
    } on IOException {
      // The peer may disconnect before the bounded request finishes.
    }
  }

  Future<void> sendLocal(
    String mac,
    String broadcast, {
    String lanIp = '',
  }) async {
    if (_android) {
      final destination = broadcast.isEmpty || broadcast == '255.255.255.255'
          ? (await networkInfo()).broadcast
          : broadcast;
      if (destination == null || destination.isEmpty) {
        throw const ProtocolFailure('wifi_unavailable', 503);
      }
      await _channel.invokeMethod<void>('wakeLocal', {
        'mac': mac,
        'broadcast': destination,
      });
      return;
    }
    if (!isLanAddress(lanIp)) throw const FormatException('invalid_lan');
    final packet = magicPacket(mac);
    final socket = await RawDatagramSocket.bind(InternetAddress(lanIp), 0);
    try {
      socket.broadcastEnabled = true;
      final sent = socket.send(
        packet,
        InternetAddress(broadcast.isEmpty ? '255.255.255.255' : broadcast),
        9,
      );
      if (sent != packet.length) {
        throw const ProtocolFailure('send_failed', 503);
      }
    } finally {
      socket.close();
    }
  }

  Future<void> stop() async {
    if (_android) {
      await _channel.invokeMethod<void>('stop');
      return;
    }
    final server = _server;
    _server = null;
    await server?.close(force: true);
    _requests.clear();
  }
}
