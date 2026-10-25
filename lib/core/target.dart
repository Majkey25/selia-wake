import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'protocol.dart';

bool isTargetAddress(String host) =>
    isLanAddress(host) || isTailnetAddress(host);

Future<bool> checkTarget(
  String host,
  int port, {
  Duration wait = Duration.zero,
  bool Function()? cancelled,
}) async {
  if (!isTargetAddress(host) || port < 1 || port > 65535) {
    throw const FormatException('invalid_target');
  }
  final clock = Stopwatch()..start();
  do {
    if (cancelled?.call() == true) return false;
    final remaining = wait - clock.elapsed;
    final timeout = wait == Duration.zero
        ? const Duration(seconds: 3)
        : Duration(milliseconds: min(3000, remaining.inMilliseconds));
    if (timeout <= Duration.zero) return false;
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return cancelled?.call() != true;
    } on SocketException {
      // A timeout or closed port cannot distinguish sleep from a firewall.
    } on TimeoutException {
      // Retry only within the caller's bounded wait.
    }
    if (wait == Duration.zero || cancelled?.call() == true) return false;
    final delay = min(2000, (wait - clock.elapsed).inMilliseconds);
    if (delay > 0) await Future<void>.delayed(Duration(milliseconds: delay));
  } while (clock.elapsed < wait);
  return false;
}
