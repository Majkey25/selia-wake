import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seliawake/core/target.dart';

void main() {
  test(
    'checks an actual listener and reports a closed port without claiming power state',
    () async {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final ip = interfaces
          .expand((i) => i.addresses)
          .firstWhere((a) => isTargetAddress(a.address));
      final server = await ServerSocket.bind(ip, 0);
      final subscription = server.listen((socket) => socket.destroy());
      final port = server.port;
      expect(await checkTarget(ip.address, port), isTrue);
      await subscription.cancel();
      await server.close();
      expect(await checkTarget(ip.address, port), isFalse);
    },
  );

  test(
    'rejects public addresses and invalid ports before connecting',
    () async {
      for (final host in ['8.8.8.8', 'example.com', '127.0.0.1', '::1', '']) {
        await expectLater(checkTarget(host, 3389), throwsFormatException);
      }
      for (final port in [0, -1, 65536]) {
        await expectLater(
          checkTarget('100.73.153.127', port),
          throwsFormatException,
        );
      }
    },
  );

  test('wait is bounded and cancellation stops retries', () async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final ip = interfaces
        .expand((i) => i.addresses)
        .firstWhere((a) => isTargetAddress(a.address));
    final server = await ServerSocket.bind(ip, 0);
    final port = server.port;
    await server.close();
    final clock = Stopwatch()..start();
    expect(
      await checkTarget(
        ip.address,
        port,
        wait: const Duration(milliseconds: 100),
      ),
      isFalse,
    );
    expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    expect(
      await checkTarget(
        ip.address,
        port,
        wait: const Duration(seconds: 60),
        cancelled: () => true,
      ),
      isFalse,
    );
  });

  test(
    'retry detects a service that starts later, and cancellation interrupts waiting',
    () async {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final ip = interfaces
          .expand((i) => i.addresses)
          .firstWhere((a) => isTargetAddress(a.address));
      var server = await ServerSocket.bind(ip, 0);
      final port = server.port;
      await server.close();
      final pending = checkTarget(
        ip.address,
        port,
        wait: const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      server = await ServerSocket.bind(ip, port);
      final subscription = server.listen((socket) => socket.destroy());
      try {
        expect(await pending, isTrue);
      } finally {
        await subscription.cancel();
        await server.close();
      }
      var cancelled = false;
      final timer = Timer(
        const Duration(milliseconds: 50),
        () => cancelled = true,
      );
      final clock = Stopwatch()..start();
      try {
        expect(
          await checkTarget(
            ip.address,
            port,
            wait: const Duration(seconds: 60),
            cancelled: () => cancelled,
          ),
          isFalse,
        );
        expect(clock.elapsed, lessThan(const Duration(seconds: 4)));
      } finally {
        timer.cancel();
      }
    },
  );
}
