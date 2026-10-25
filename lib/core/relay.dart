import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'protocol.dart';

const _maxConnections = 8;
const _connectionDeadline = Duration(seconds: 5);

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
  _BoundedServerSocket? _listener;
  String? _error;
  final _requests = <HttpRequest>{};
  bool get _android => Platform.isAndroid;

  Future<String?> scanPairing(String language) =>
      _channel.invokeMethod<String>('scanPairing', {'language': language});

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
    final listener = _BoundedServerSocket(
      await ServerSocket.bind(
        InternetAddress.anyIPv4,
        relayPort,
        backlog: _maxConnections,
        shared: false,
      ),
    );
    late final HttpServer server;
    try {
      server = HttpServer.listenOn(listener);
    } catch (_) {
      await listener.close();
      rethrow;
    }
    server.idleTimeout = const Duration(seconds: 5);
    server.defaultResponseHeaders.clear();
    _error = null;
    _listener = listener;
    _server = server;
    server.listen(
      (request) {
        if (_requests.length >= _maxConnections) {
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
    final listener = _listener;
    _server = null;
    _listener = null;
    try {
      await server?.close(force: true);
    } finally {
      await listener?.close();
      _requests.clear();
    }
  }
}

// Bound accepted sockets before HttpServer parses their headers.
class _BoundedServerSocket extends Stream<Socket> implements ServerSocket {
  _BoundedServerSocket(this._socket);
  final ServerSocket _socket;
  final _connections = <Socket, Timer>{};

  @override
  InternetAddress get address => _socket.address;
  @override
  int get port => _socket.port;

  void _release(Socket socket) => _connections.remove(socket)?.cancel();

  void _pruneClosed() {
    // HttpServer destroys sockets without completing their IOSink.done future.
    _connections.removeWhere((socket, timer) {
      try {
        socket.remotePort;
        return false;
      } on SocketException {
        timer.cancel();
        return true;
      }
    });
  }

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _socket.listen(
    (socket) {
      _pruneClosed();
      if (_connections.length >= _maxConnections) {
        socket.destroy();
        return;
      }
      _connections[socket] = Timer(_connectionDeadline, () {
        _release(socket);
        socket.destroy();
      });
      onData?.call(socket);
    },
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Future<ServerSocket> close() async {
    for (final socket in _connections.keys.toList()) {
      _release(socket);
      socket.destroy();
    }
    await _socket.close();
    return this;
  }
}
