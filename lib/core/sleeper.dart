import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'protocol.dart';
import 'settings.dart';

const _invalidSetup = FormatException('invalid_target_setup');
const _invalidReport = FormatException('invalid_sleeper_report');
const _linuxPersistence =
    "This app's ethtool configuration is runtime-only: it may be reset by a reboot, "
    'driver reload, or the network manager. Persistent NetworkManager '
    'configuration is not changed by this app.';
const _hardwareLimit =
    'OS settings do not verify firmware support or actual hardware wake.';
final _guid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _interfaceName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,14}$');

bool _validMac(String value) {
  if (!RegExp(
    r'^(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$|^(?:[0-9a-fA-F]{2}-){5}[0-9a-fA-F]{2}$',
  ).hasMatch(value)) {
    return false;
  }
  final bytes = value.split(RegExp('[:-]')).map((v) => int.parse(v, radix: 16));
  return (bytes.first & 1) == 0 && bytes.any((v) => v != 0);
}

String _canonicalMac(String value) => value.replaceAll('-', ':').toLowerCase();

bool _ipv4(String value) {
  final parsed = InternetAddress.tryParse(value);
  return parsed != null &&
      parsed.type == InternetAddressType.IPv4 &&
      parsed.address == value;
}

// A URI has no prefix to prove membership in the actual subnet. Accept only
// RFC1918 directed-broadcast candidates (/30 or wider); inspection derives
// the local adapter's broadcast from its reported prefix.
bool _privateBroadcast(String value) =>
    _ipv4(value) &&
    isLanAddress(value) &&
    (InternetAddress(value).rawAddress.last & 3) == 3;

String? _canonicalGuid(String value) {
  final bare = value.startsWith('{') && value.endsWith('}')
      ? value.substring(1, value.length - 1)
      : value;
  return _guid.hasMatch(bare) && bare != '00000000-0000-0000-0000-000000000000'
      ? bare.toLowerCase()
      : null;
}

/// A previewable network setup. Parsing never changes settings or executes code.
class TargetSetup {
  TargetSetup({
    required this.name,
    required this.mac,
    required this.broadcast,
    required this.connection,
    this.targetHost = '',
    this.targetPort = 3389,
  }) {
    if (name.trim().isEmpty ||
        name.length > 80 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) ||
        !_validMac(mac) ||
        !_privateBroadcast(broadcast) ||
        (targetHost.isNotEmpty &&
            (!_ipv4(targetHost) ||
                (!isLanAddress(targetHost) &&
                    !isTailnetAddress(targetHost)))) ||
        targetPort < 1 ||
        targetPort > 65535) {
      throw _invalidSetup;
    }
  }

  final String name;
  final String mac;
  final String broadcast;
  final TargetConnection connection;
  final String targetHost;
  final int targetPort;

  String encode() {
    final payload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'v': 1,
              'name': name,
              'mac': mac,
              'broadcast': broadcast,
              'connection': connection.name,
              'targetHost': targetHost,
              'targetPort': targetPort,
            }),
          ),
        )
        .replaceAll('=', '');
    final result = 'seliawake://sleeper?data=$payload';
    if (result.length > 2048) throw _invalidSetup;
    return result;
  }

  factory TargetSetup.parse(String value) {
    if (value.length > 2048) throw _invalidSetup;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'seliawake' ||
        !uri.hasAuthority ||
        uri.host != 'sleeper' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.path.isNotEmpty ||
        uri.hasFragment ||
        uri.queryParametersAll.length != 1 ||
        uri.queryParametersAll['data']?.length != 1) {
      throw _invalidSetup;
    }
    final payload = uri.queryParametersAll['data']!.single;
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(payload) ||
        value != 'seliawake://sleeper?data=$payload') {
      throw _invalidSetup;
    }
    final bytes = base64Url.decode(base64Url.normalize(payload));
    if (base64Url.encode(bytes).replaceAll('=', '') != payload) {
      throw _invalidSetup;
    }
    final Object? decoded = jsonDecode(utf8.decode(bytes));
    const keys = {
      'v',
      'name',
      'mac',
      'broadcast',
      'connection',
      'targetHost',
      'targetPort',
    };
    if (decoded is! Map<String, dynamic> ||
        decoded.length != keys.length ||
        !keys.every(decoded.containsKey) ||
        decoded['v'] is! int ||
        decoded['v'] != 1 ||
        decoded['name'] is! String ||
        decoded['mac'] is! String ||
        decoded['broadcast'] is! String ||
        decoded['connection'] is! String ||
        decoded['targetHost'] is! String ||
        decoded['targetPort'] is! int) {
      throw _invalidSetup;
    }
    final connection = TargetConnection.values
        .where((item) => item.name == decoded['connection'])
        .firstOrNull;
    if (connection == null) throw _invalidSetup;
    return TargetSetup(
      name: decoded['name'] as String,
      mac: decoded['mac'] as String,
      broadcast: decoded['broadcast'] as String,
      connection: connection,
      targetHost: decoded['targetHost'] as String,
      targetPort: decoded['targetPort'] as int,
    );
  }
}

/// Reported OS/driver state, never proof that a sleeping machine can wake.
class SleeperAdapter {
  const SleeperAdapter({
    required this.id,
    required this.name,
    required this.description,
    required this.mac,
    required this.ip,
    required this.broadcast,
    required this.connection,
    required this.wakeEnabled,
    required this.magicPacketEnabled,
    required this.supportsWake,
    required this.detail,
    this.restartRequired = false,
  });

  final String id;
  final String name;
  final String description;
  final String mac;
  final String ip;
  final String broadcast;
  final TargetConnection connection;
  final bool? wakeEnabled;

  /// On Windows this is the stored driver property, not confirmed activation.
  final bool? magicPacketEnabled;
  final bool? supportsWake;
  final String detail;

  /// A known pending change advisory. False does not establish activation or
  /// prove that an adapter restart has occurred.
  final bool restartRequired;

  factory SleeperAdapter.fromLinux({
    required String id,
    required String description,
    required String mac,
    required String ip,
    required int? prefixLength,
    required TargetConnection connection,
    String? ethtoolOutput,
    String detail = '',
  }) {
    if (!_interfaceName.hasMatch(id) ||
        !_validMac(mac) ||
        !_ipv4(ip) ||
        (prefixLength != null && (prefixLength < 0 || prefixLength > 32))) {
      throw _invalidReport;
    }
    final notes = <String>[if (detail.isNotEmpty) detail];
    var broadcast = '';
    if (prefixLength == null) {
      notes.add('IPv4 prefix unavailable; broadcast is unknown.');
    } else if (prefixLength >= 31) {
      notes.add('An IPv4 /$prefixLength has no directed broadcast for WoL.');
    } else {
      final bytes = InternetAddress(ip).rawAddress;
      broadcast = List.generate(4, (index) {
        final bits = (prefixLength - index * 8).clamp(0, 8);
        return bytes[index] | (255 >> bits);
      }).join('.');
    }
    bool? supportsWake;
    bool? wakeEnabled;
    bool? magicPacketEnabled;
    if (connection == TargetConnection.wifi) {
      notes.add(
        'Wi-Fi WoWLAN support and state are unknown; this backend does not verify WoWLAN.',
      );
    } else {
      final supported = _wakeFlags(ethtoolOutput, 'Supports Wake-on');
      final enabled = _wakeFlags(ethtoolOutput, 'Wake-on');
      supportsWake = supported == null ? null : supported != 'd';
      wakeEnabled = enabled == null ? null : enabled != 'd';
      magicPacketEnabled = enabled?.contains('g');
      if (supported == null || enabled == null) {
        notes.add(
          'ethtool did not provide a complete readable WoL report; unknown values remain unknown.',
        );
      } else {
        notes.add(
          'ethtool reports supported WoL modes: $supported; enabled: $enabled.',
        );
        if (!supported.contains('g')) {
          notes.add('The driver does not report Magic Packet support.');
        }
        if (enabled.contains('s')) {
          notes.add(
            'SecureOn is enabled; a passwordless Magic Packet is not verified to work.',
          );
        }
      }
    }
    notes.addAll([_linuxPersistence, _hardwareLimit]);
    return SleeperAdapter(
      id: id,
      name: id,
      description: description,
      mac: mac,
      ip: ip,
      broadcast: broadcast,
      connection: connection,
      wakeEnabled: wakeEnabled,
      magicPacketEnabled: magicPacketEnabled,
      supportsWake: supportsWake,
      detail: notes.join(' '),
    );
  }

  SleeperAdapter _withPendingRestart() => SleeperAdapter(
    id: id,
    name: name,
    description: description,
    mac: mac,
    ip: ip,
    broadcast: broadcast,
    connection: connection,
    wakeEnabled: wakeEnabled,
    magicPacketEnabled: magicPacketEnabled,
    supportsWake: supportsWake,
    detail:
        '$detail This app observed the stored Magic Packet setting change without restarting the adapter. Its effect remains unverified; this advisory is retained for this adapter identity during this app session.',
    restartRequired: true,
  );
}

String? _wakeFlags(String? output, String label) {
  if (output == null) return null;
  final lines = RegExp(
    '^\\s*${RegExp.escape(label)}:[ \\t]*([^\\r\\n]*)',
    multiLine: true,
  ).allMatches(output).toList();
  if (lines.length != 1) return null;
  final flags = lines.single.group(1)!.trim();
  if (!RegExp(r'^(?:d|[pumbagsf]+)$').hasMatch(flags) ||
      flags.split('').toSet().length != flags.length) {
    return null;
  }
  return flags;
}

class SleeperReport {
  const SleeperReport({
    required this.machineName,
    required this.sleepStates,
    required this.adapters,
    this.tailscaleIp,
  });

  final String machineName;
  final String sleepStates;
  final String? tailscaleIp;
  final List<SleeperAdapter> adapters;

  /// Resolve the displayed selection without accepting a reused interface name.
  SleeperAdapter selectedAdapter(
    String adapterId, {
    required String expectedMac,
  }) {
    if (!_validMac(expectedMac)) {
      throw const FormatException('invalid_adapter_mac');
    }
    final selected = adapters.where((a) => a.id == adapterId).firstOrNull;
    if (selected == null) {
      throw const SleeperFailure(
        'The selected interface is not a current physical IPv4 adapter.',
      );
    }
    if (_canonicalMac(selected.mac) != _canonicalMac(expectedMac)) {
      throw const SleeperFailure(
        'The selected physical adapter changed or disappeared. Inspect again.',
      );
    }
    return selected;
  }

  factory SleeperReport.fromWindowsJson(Object? value) {
    if (value is! Map<String, Object?>) {
      throw _invalidReport;
    }
    final data = value;
    if (data['platform'] != 'windows' ||
        data.containsKey('error') ||
        data['adapters'] is! List<Object?>) {
      throw _invalidReport;
    }
    final raw = data['adapters']! as List<Object?>;
    if (raw.length > 128) throw _invalidReport;
    final adapters = <SleeperAdapter>[];
    final ids = <String>{};
    for (final item in raw) {
      if (item is! Map<String, Object?>) throw _invalidReport;
      final id = _canonicalGuid(_reportString(item, 'id', 38));
      final mac = _reportString(item, 'mac', 17);
      final ip = _reportString(item, 'ip', 15);
      final broadcast = _reportString(item, 'broadcast', 15);
      final connection = item['connection'];
      if (id == null ||
          !ids.add(id) ||
          !_validMac(mac) ||
          !_ipv4(ip) ||
          (broadcast.isNotEmpty && !_ipv4(broadcast)) ||
          (connection != 'ethernet' && connection != 'wifi') ||
          (item.containsKey('restartRequired') &&
              item['restartRequired'] is! bool)) {
        throw _invalidReport;
      }
      adapters.add(
        SleeperAdapter(
          id: id,
          name: _reportString(item, 'name', 255),
          description: _reportString(item, 'description', 1024),
          mac: mac,
          ip: ip,
          broadcast: broadcast,
          connection: connection == 'wifi'
              ? TargetConnection.wifi
              : TargetConnection.ethernet,
          wakeEnabled: _reportBool(item, 'wakeEnabled'),
          magicPacketEnabled: _reportBool(item, 'magicPacketEnabled'),
          supportsWake: _reportBool(item, 'supportsWake'),
          detail: _reportString(item, 'detail', 32768),
          restartRequired: item['restartRequired'] == true,
        ),
      );
    }
    return SleeperReport(
      machineName: _reportString(data, 'machineName', 255),
      sleepStates: _reportString(data, 'sleepStates', 65536),
      adapters: List.unmodifiable(adapters),
    );
  }
}

String _reportString(Map<String, Object?> data, String key, int max) {
  final value = data[key];
  if (value is! String || value.length > max) throw _invalidReport;
  return value;
}

bool? _reportBool(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value != null && value is! bool) throw _invalidReport;
  return value as bool?;
}

class SleeperFailure implements Exception {
  const SleeperFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class Sleeper {
  Sleeper({
    Future<ProcessResult> Function(String, List<String>)? windowsCommand,
  }) : _windowsCommand = windowsCommand;

  // Tests replace only the process boundary, retaining report validation and
  // operation sequencing without invoking real adapter commands.
  final Future<ProcessResult> Function(String, List<String>)? _windowsCommand;

  // Retain only known advisories, across page/backend instances in this app
  // session. A fresh process has no history; inspection cannot confirm activation.
  static final _pendingWindowsRestarts = <(String, String)>{};

  static bool get supported => Platform.isWindows || Platform.isLinux;

  SleeperReport _retainWindowsAdvisories(Object? value) {
    // Validate the complete snapshot before it can affect session history.
    final report = SleeperReport.fromWindowsJson(value);
    final records = <(String, String)>[
      for (final adapter in report.adapters)
        if (adapter.restartRequired) (adapter.id, _canonicalMac(adapter.mac)),
    ];
    final pending = value is Map<String, Object?>
        ? value['pendingRestart']
        : null;
    if (pending != null) {
      if (pending is! Map<String, Object?> ||
          pending.length != 2 ||
          !pending.containsKey('id') ||
          !pending.containsKey('mac')) {
        throw _invalidReport;
      }
      final id = _canonicalGuid(_reportString(pending, 'id', 38));
      final mac = _reportString(pending, 'mac', 17);
      if (id == null || !_validMac(mac)) throw _invalidReport;
      records.add((id, _canonicalMac(mac)));
    }
    for (final record in records) {
      _pendingWindowsRestarts.add(record);
      if (_pendingWindowsRestarts.length > 128) {
        // Eviction returns old devices to unknown, never confirmed activation.
        _pendingWindowsRestarts.remove(_pendingWindowsRestarts.first);
      }
    }
    return SleeperReport(
      machineName: report.machineName,
      sleepStates: report.sleepStates,
      adapters: List.unmodifiable(
        report.adapters.map(
          (adapter) =>
              _pendingWindowsRestarts.contains((
                adapter.id,
                _canonicalMac(adapter.mac),
              ))
              ? adapter._withPendingRestart()
              : adapter,
        ),
      ),
    );
  }

  Future<SleeperReport> inspect() async {
    if (Platform.isWindows) return _windows('Inspect');
    if (Platform.isLinux) return _inspectLinux();
    throw UnsupportedError('Sleeper is available only on Windows and Linux.');
  }

  Future<SleeperReport> enableWake(
    String adapterId, {
    required String expectedMac,
  }) async {
    if (Platform.isWindows) {
      final id = _canonicalGuid(adapterId);
      if (id == null) throw const FormatException('invalid_adapter');
      return _windows('Enable', adapterId: id);
    }
    if (!_interfaceName.hasMatch(adapterId)) {
      throw const FormatException('invalid_adapter');
    }
    if (Platform.isLinux) {
      if (!_validMac(expectedMac)) {
        throw const FormatException('invalid_adapter_mac');
      }
      return _enableLinux(adapterId, _canonicalMac(expectedMac));
    }
    throw UnsupportedError('Sleeper is available only on Windows and Linux.');
  }

  Future<SleeperReport> _windows(String action, {String? adapterId}) async {
    final root = Platform.environment['SystemRoot'];
    if (root == null ||
        !RegExp(r'^[A-Za-z]:\\[^<>:"/|?*\x00-\x1f]+$').hasMatch(root) ||
        root
            .split('\\')
            .skip(1)
            .any(
              (v) =>
                  v.isEmpty ||
                  v == '.' ||
                  v == '..' ||
                  v.endsWith('.') ||
                  v.endsWith(' '),
            )) {
      throw const SleeperFailure(
        'A trusted local Windows SystemRoot is unavailable.',
      );
    }
    final executable =
        '$root\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
    if (!await File(executable).exists()) {
      throw const SleeperFailure(
        'Windows PowerShell is unavailable at the fixed system path.',
      );
    }
    final asset = await rootBundle.load('assets/scripts/windows-wake.ps1');
    final directory = await Directory.systemTemp.createTemp(
      'seliawake-sleeper-',
    );
    final script = File(
      '${directory.path}${Platform.pathSeparator}windows-wake.ps1',
    );
    try {
      await script.writeAsBytes(
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
        flush: true,
      );
      Future<SleeperReport> call(String requestedAction) async {
        final arguments = <String>[
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
          '-Action',
          requestedAction,
          if (adapterId != null) ...['-AdapterId', adapterId],
        ];
        final timeout = requestedAction == 'Enable'
            ? const Duration(minutes: 3)
            : const Duration(seconds: 90);
        final command = _windowsCommand;
        final result = command == null
            ? await _run(executable, arguments, timeout: timeout)
            : _CommandResult.fromProcessResult(
                await command(executable, arguments).timeout(timeout),
              );
        Object? data;
        try {
          data = jsonDecode(result.stdout.trim());
        } on FormatException {
          throw SleeperFailure(
            'Windows wake inspection returned invalid JSON (exit ${result.exitCode}).',
          );
        }
        final error = data is Map<String, Object?> ? data['error'] : null;
        if (result.exitCode != 0 ||
            (data is Map<String, Object?> && data.containsKey('error'))) {
          if (data is Map<String, Object?>) {
            try {
              // A failed ordinary-token operation may already have stored a
              // property. Keep a valid advisory before surfacing the failure.
              _retainWindowsAdvisories({...data}..remove('error'));
            } on FormatException {
              // Incomplete error reports cannot establish pending history.
            }
          }
          throw SleeperFailure(
            error is String && error.isNotEmpty
                ? error
                : 'Windows wake $requestedAction failed (exit ${result.exitCode}). Wake configuration requiring additional permissions must be performed separately in native Windows settings; this app does not request administrator permission automatically.',
          );
        }
        return _retainWindowsAdvisories(data);
      }

      var report = await call('Inspect');
      if (action == 'Enable') {
        if (!report.adapters.any((adapter) => adapter.id == adapterId)) {
          throw const SleeperFailure(
            'The selected GUID is not a current physical IPv4 adapter.',
          );
        }
        final enabled = await call('Enable');
        // Read again after the ordinary-token command. Session history retains
        // known pending advisories even though a fresh query cannot report them.
        report = await call('Inspect');
        final operation = enabled.adapters
            .where((a) => a.id == adapterId)
            .firstOrNull;
        if (operation == null) {
          throw const SleeperFailure(
            'The selected adapter disappeared during wake configuration. Inspect again.',
          );
        }
        final selected = report.adapters
            .where((a) => a.id == adapterId)
            .firstOrNull;
        if (selected?.wakeEnabled != true ||
            selected?.magicPacketEnabled != true) {
          throw const SleeperFailure(
            'Wake configuration ran, but fresh Windows reporting did not confirm both settings. Changes may have been applied; inspect again.',
          );
        }
      }
      return SleeperReport(
        machineName: report.machineName,
        sleepStates: report.sleepStates,
        tailscaleIp: await _tailscaleIp(),
        adapters: report.adapters,
      );
    } finally {
      // Only these two owned paths are removed; never recursively delete.
      try {
        if (await script.exists()) await script.delete();
        await directory.delete();
      } on FileSystemException {
        // Cleanup is best effort if an owned path is still in use.
      }
    }
  }

  Future<SleeperReport> _inspectLinux() async {
    final interfaces = await _interfaces();
    final (prefixes, prefixDetail) = await _linuxPrefixes();
    final ethtool = await _linuxExecutable('ethtool');
    final adapters = <SleeperAdapter>[];
    for (final interface in interfaces) {
      final device = await _linuxDevice(interface);
      if (device == null) continue;
      final addresses =
          interface.addresses.where((a) => _ipv4(a.address)).toList()
            ..sort((a, b) {
              final privateOrder = (isLanAddress(a.address) ? 0 : 1).compareTo(
                isLanAddress(b.address) ? 0 : 1,
              );
              return privateOrder != 0
                  ? privateOrder
                  : a.address.compareTo(b.address);
            });
      if (addresses.isEmpty) continue;
      final ip = addresses.first.address;
      String? output;
      final detail = <String>[
        if (prefixDetail.isNotEmpty) prefixDetail,
        device.detail,
      ];
      if (ethtool == null) {
        detail.add(
          'ethtool is not installed at a supported system path; WoL state is unknown. Nothing was installed.',
        );
      } else {
        try {
          final result = await _run(ethtool, [interface.name]);
          if (result.exitCode == 0) output = result.stdout;
          if (result.exitCode != 0 || result.stderr.trim().isNotEmpty) {
            detail.add(
              'ethtool query returned exit ${result.exitCode}${_permissionDenied(result) ? '; permission was denied' : ''}. Missing wake fields are unknown.',
            );
          }
        } on SleeperFailure catch (error) {
          detail.add(error.message);
        }
      }
      adapters.add(
        SleeperAdapter.fromLinux(
          id: interface.name,
          description: device.description,
          mac: device.mac,
          ip: ip,
          prefixLength: prefixes[interface.name]?[ip],
          connection: device.connection,
          ethtoolOutput: output,
          detail: detail.where((v) => v.isNotEmpty).join(' '),
        ),
      );
    }
    return SleeperReport(
      machineName: Platform.localHostname,
      sleepStates: await _linuxSleepStates(),
      tailscaleIp: _tailnetAddress(interfaces),
      adapters: List.unmodifiable(adapters),
    );
  }

  Future<SleeperReport> _enableLinux(
    String adapterId,
    String expectedMac,
  ) async {
    var report = await _inspectLinux();
    final selected = report.selectedAdapter(
      adapterId,
      expectedMac: expectedMac,
    );
    if (selected.connection == TargetConnection.wifi) {
      throw const SleeperFailure(
        'This Sleeper backend does not enable Wi-Fi WoWLAN. Its wake capability remains unknown; use driver-specific configuration.',
      );
    }
    if (selected.supportsWake == false) {
      throw const SleeperFailure(
        'The driver reports no supported WoL modes for the selected adapter.',
      );
    }
    final ethtool = await _linuxExecutable('ethtool');
    if (ethtool == null) {
      throw const SleeperFailure(
        'ethtool is missing. Install it through your distribution before enabling wake; the app does not install tools.',
      );
    }
    // Capture the OS instance as well as the MAC selected in the displayed report.
    final current = (await _interfaces())
        .where((i) => i.name == adapterId)
        .firstOrNull;
    final device = current == null ? null : await _linuxDevice(current);
    if (device == null || _canonicalMac(device.mac) != expectedMac) {
      throw const SleeperFailure(
        'The selected physical adapter changed or disappeared. Inspect again.',
      );
    }

    final expectedIndex = current!.index;
    Future<void> verifyIdentity() async {
      final freshInterface = (await _interfaces())
          .where((i) => i.name == adapterId && i.index == expectedIndex)
          .firstOrNull;
      final freshDevice = freshInterface == null
          ? null
          : await _linuxDevice(freshInterface);
      if (freshDevice == null ||
          freshDevice.connection == TargetConnection.wifi ||
          _canonicalMac(freshDevice.mac) != expectedMac) {
        throw const SleeperFailure(
          'The selected physical adapter changed or disappeared. Inspect again.',
        );
      }
    }

    const shell = '/bin/bash';
    final shellStat = await File(shell).stat();
    if (shellStat.type != FileSystemEntityType.file ||
        (shellStat.mode & 0x49) == 0) {
      throw const SleeperFailure(
        'Bash is unavailable at /bin/bash; no wake change was made.',
      );
    }
    final asset = await rootBundle.load('assets/scripts/linux-wake.sh');
    final directory = await Directory('/tmp').createTemp('seliawake-sleeper-');
    final script = File('${directory.path}/linux-wake.sh');
    try {
      // Keep the ordinary-privilege helper source private.
      final stat = await directory.stat();
      if (stat.type != FileSystemEntityType.directory ||
          (stat.mode & 0x1ff) != 0x1c0) {
        throw const SleeperFailure(
          'A private Linux helper directory could not be created. No wake change was made.',
        );
      }
      await script.writeAsBytes(
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
        flush: true,
      );
      // The helper revalidates sysfs immediately before ordinary-token ethtool.
      // No shell command string or privilege request is generated.
      final result = await _run(shell, [
        '--noprofile',
        '--norc',
        '-p',
        script.path,
        'enable',
        adapterId,
        expectedMac,
        '$expectedIndex',
      ]);
      if (result.exitCode == 65) {
        throw const SleeperFailure(
          'The selected physical adapter changed or disappeared. Inspect again.',
        );
      }
      if (result.exitCode != 0 && _permissionDenied(result)) {
        throw const SleeperFailure(
          'Wake configuration was denied by the current permissions. Native Linux wake configuration must be performed separately; this app does not request administrator permission automatically. Settings may have partially changed; inspect again. $_linuxPersistence',
        );
      }
      if (result.exitCode != 0) {
        throw SleeperFailure(
          'ethtool could not enable Magic Packet wake (exit ${result.exitCode}); the driver may reject this mode. Configuration requiring additional permissions must be performed separately in native Linux tools. Inspect again; partial changes cannot be excluded. $_linuxPersistence',
        );
      }
      report = await _inspectLinux();
      final fresh = report.selectedAdapter(adapterId, expectedMac: expectedMac);
      await verifyIdentity();
      // A denied read remains unknown; the setter's exit code is not evidence
      // that Magic Packet wake is enabled, and inspection never elevates.
      if (fresh.magicPacketEnabled != true || fresh.wakeEnabled != true) {
        throw const SleeperFailure(
          'The change command completed, but a fresh OS query did not confirm Magic Packet wake. Settings may have changed; inspect again. Inspection or configuration requiring additional permissions must be performed separately in native Linux tools. $_linuxPersistence',
        );
      }
      return report;
    } finally {
      try {
        if (await script.exists()) await script.delete();
        await directory.delete();
      } on FileSystemException {
        // Cleanup is best effort; never delete a tree.
      }
    }
  }
}

Future<List<NetworkInterface>> _interfaces() => NetworkInterface.list(
  type: InternetAddressType.IPv4,
  includeLoopback: false,
  includeLinkLocal: false,
).timeout(const Duration(seconds: 5));

String? _tailnetAddress(List<NetworkInterface> interfaces) => interfaces
    .where((i) => i.name.toLowerCase().contains('tailscale'))
    .expand((i) => i.addresses)
    .map((a) => a.address)
    .where(isTailnetAddress)
    .firstOrNull;

Future<String?> _tailscaleIp() async {
  try {
    return _tailnetAddress(await _interfaces());
  } on IOException {
    return null;
  } on TimeoutException {
    return null;
  }
}

Future<String?> _linuxExecutable(String name) async {
  for (final directory in ['/usr/sbin', '/sbin', '/usr/bin', '/bin']) {
    final path = '$directory/$name';
    final stat = await File(path).stat();
    if (stat.type == FileSystemEntityType.file && (stat.mode & 0x49) != 0) {
      return path;
    }
  }
  return null;
}

class _LinuxDevice {
  const _LinuxDevice(this.mac, this.description, this.connection, this.detail);
  final String mac;
  final String description;
  final TargetConnection connection;
  final String detail;
}

Future<_LinuxDevice?> _linuxDevice(NetworkInterface interface) async {
  if (!_interfaceName.hasMatch(interface.name)) return null;
  final root = '/sys/class/net/${interface.name}';
  if (!await Directory('$root/device').exists()) return null;
  try {
    final resolved = await Directory(root).resolveSymbolicLinks();
    if (resolved.startsWith('/sys/devices/virtual/')) return null;
    final type = (await File('$root/type').readAsString()).trim();
    final index = int.tryParse(
      (await File('$root/ifindex').readAsString()).trim(),
    );
    final link = int.tryParse(
      (await File('$root/iflink').readAsString()).trim(),
    );
    final flags = int.tryParse(
      (await File('$root/flags').readAsString()).trim(),
    );
    if (type != '1' ||
        index != interface.index ||
        link != index ||
        flags == null ||
        (flags & 1) == 0) {
      return null;
    }
    final mac = (await File('$root/address').readAsString()).trim();
    if (!_validMac(mac)) return null;
    final devicePath = await Directory('$root/device').resolveSymbolicLinks();
    final wifi =
        await Directory('$root/wireless').exists() ||
        await Directory('$root/phy80211').exists();
    final connection = wifi
        ? TargetConnection.wifi
        : RegExp(r'/usb[0-9]+/').hasMatch(devicePath)
        ? TargetConnection.usbEthernet
        : TargetConnection.ethernet;
    var description = 'Physical network interface reported by Linux sysfs';
    try {
      final driver = await Directory(
        '$root/device/driver',
      ).resolveSymbolicLinks();
      description = 'Linux driver: ${driver.split('/').last}';
    } on FileSystemException {
      // A driver name is optional, rather than evidence of wake support.
    }
    var detail = '';
    final assignment = File('$root/addr_assign_type');
    if (await assignment.exists() &&
        (await assignment.readAsString()).trim() != '0') {
      detail =
          'The current interface MAC is not reported as permanent; verify the address used while sleeping.';
    }
    return _LinuxDevice(mac, description, connection, detail);
  } on FileSystemException {
    throw SleeperFailure(
      'Linux could not read the physical adapter ${interface.name}. It may have disappeared; inspect again.',
    );
  }
}

Future<(Map<String, Map<String, int>>, String)> _linuxPrefixes() async {
  final executable = await _linuxExecutable('ip');
  const unknown =
      'The ip tool could not provide IPv4 prefixes; broadcast is unknown.';
  if (executable == null) return (<String, Map<String, int>>{}, unknown);
  try {
    final result = await _run(executable, ['-j', '-4', 'address', 'show']);
    if (result.exitCode != 0) return (<String, Map<String, int>>{}, unknown);
    final Object? data = jsonDecode(result.stdout);
    if (data is! List<Object?>) return (<String, Map<String, int>>{}, unknown);
    final prefixes = <String, Map<String, int>>{};
    for (final item in data) {
      if (item is! Map<String, Object?> ||
          item['ifname'] is! String ||
          item['addr_info'] is! List<Object?>) {
        continue;
      }
      final name = item['ifname']! as String;
      for (final address in item['addr_info']! as List<Object?>) {
        if (address is! Map<String, Object?> ||
            address['family'] != 'inet' ||
            address['local'] is! String ||
            address['prefixlen'] is! int) {
          continue;
        }
        final ip = address['local']! as String;
        final prefix = address['prefixlen']! as int;
        if (_ipv4(ip) && prefix >= 0 && prefix <= 32) {
          (prefixes[name] ??= {})[ip] = prefix;
        }
      }
    }
    return (prefixes, '');
  } on FormatException {
    return (<String, Map<String, int>>{}, unknown);
  } on SleeperFailure {
    return (<String, Map<String, int>>{}, unknown);
  }
}

Future<String> _linuxSleepStates() async {
  final parts = <String>[];
  for (final path in ['/sys/power/state', '/sys/power/mem_sleep']) {
    try {
      final value = (await File(path).readAsString()).trim();
      parts.add('$path: ${value.isEmpty ? 'not reported' : value}');
    } on FileSystemException {
      parts.add('$path: unavailable');
    }
  }
  return '${parts.join('\n')}\n$_hardwareLimit';
}

bool _permissionDenied(_CommandResult result) => RegExp(
  r'operation not permitted|permission denied|not authorized|must be root',
  caseSensitive: false,
).hasMatch(result.stderr);

class _CommandResult {
  const _CommandResult(this.exitCode, this.stdout, this.stderr);
  _CommandResult.fromProcessResult(ProcessResult result)
    : this(result.exitCode, result.stdout as String, result.stderr as String);
  final int exitCode;
  final String stdout;
  final String stderr;
}

Future<String> _readOutput(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    if (bytes.length + chunk.length > 1024 * 1024) {
      throw const SleeperFailure(
        'The OS command exceeded its bounded output limit.',
      );
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}

Future<_CommandResult> _run(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final Process process;
  try {
    process = await Process.start(
      executable,
      arguments,
      runInShell: false,
      workingDirectory: File(executable).parent.path,
      environment: Platform.isLinux ? {'LC_ALL': 'C', 'LANG': 'C'} : null,
    );
  } on ProcessException {
    throw SleeperFailure('The OS command could not be started at $executable.');
  }
  try {
    await process.stdin.close();
    final results = await Future.wait<Object>([
      process.exitCode,
      _readOutput(process.stdout),
      _readOutput(process.stderr),
    ], eagerError: true).timeout(timeout);
    return _CommandResult(
      results[0] as int,
      results[1] as String,
      results[2] as String,
    );
  } catch (error) {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
    if (error is TimeoutException) {
      throw const SleeperFailure(
        'The OS command timed out. Any requested setting may have partially changed; inspect again before relying on it.',
      );
    }
    if (error is SleeperFailure) rethrow;
    throw const SleeperFailure(
      'The OS command response could not be read. Any requested change must be inspected again.',
    );
  }
}
