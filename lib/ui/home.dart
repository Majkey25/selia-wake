import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/protocol.dart';
import '../core/relay.dart';
import '../core/settings.dart';
import 'controls.dart';
import 'settings_page.dart';
import 'strings.dart';

class WakeHome extends StatefulWidget {
  const WakeHome({super.key, required this.settings, required this.save});
  final Settings settings;
  final Future<void> Function(Settings) save;

  @override
  State<WakeHome> createState() => _WakeHomeState();
}

class _WakeHomeState extends State<WakeHome> with WidgetsBindingObserver {
  final _relay = Relay();
  RelayStatus? _status;
  bool _statusFailed = false;
  bool _refreshing = false;
  bool _busy = false;
  bool _editing = false;
  bool _foreground = true;
  bool _messageError = false;
  String? _message;
  Timer? _timer;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (_foreground) _startPolling();
  }

  void _startPolling() {
    _timer?.cancel();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _startPolling();
    } else {
      _timer?.cancel();
      _timer = null;
      _epoch++;
    }
  }

  Future<void> _refresh() async {
    if (_busy || _refreshing || !_foreground) return;
    _refreshing = true;
    final epoch = _epoch;
    try {
      final status = await _relay.status();
      if (mounted && epoch == _epoch) {
        setState(() {
          _status = status;
          _statusFailed = false;
        });
      }
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _status = null;
          _statusFailed = true;
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    // Android's foreground service owns its lifetime independently of this view.
    if (!Platform.isAndroid) unawaited(_relay.stop());
    super.dispose();
  }

  RelayConfig _config(Settings settings) {
    final language = settings.language == 'system'
        ? basicLocaleListResolution(
            WidgetsBinding.instance.platformDispatcher.locales,
            const [Locale('en'), Locale('cs')],
          ).languageCode
        : settings.language;
    return RelayConfig(
      mac: settings.mac,
      broadcast: settings.broadcast,
      secret: settings.wakerKey,
      name: settings.targetName.isEmpty
          ? Strings(language == 'cs').computer
          : settings.targetName,
      language: language,
      lanIp: settings.lanIp,
    );
  }

  Future<void> _readAfterOperation() async {
    if (!mounted) {
      if (!Platform.isAndroid) await _relay.stop();
      return;
    }
    try {
      final status = await _relay.status();
      if (mounted) {
        setState(() {
          _status = status;
          _statusFailed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = null;
          _statusFailed = true;
        });
      }
    }
  }

  Future<void> _save(Settings next) async {
    final s = Strings.of(context);
    setState(() {
      _busy = true;
      _epoch++;
    });
    try {
      // Re-read native state: the notification may have stopped the service.
      final actual = await _relay.status();
      final restart = actual.running && next.role == DeviceRole.waker;
      if (actual.running) {
        await _relay.stop();
        final stopped = await _relay.status();
        if (stopped.running) throw StateError('stop_failed');
      }
      await widget.save(next);
      if (!mounted) return;
      setState(() {
        _message = null;
        _messageError = false;
      });
      if (restart) {
        try {
          await _relay.start(_config(next));
          final started = await _relay.status();
          if (!started.running) throw StateError('restart_failed');
        } catch (error) {
          if (mounted) {
            setState(() {
              _messageError = true;
              _message =
                  '${s.text('Settings saved. Waker restart failed.', 'Nastavení uloženo. Budič se nepodařilo znovu spustit.')} ${s.failure(error)}';
            });
          }
        }
      }
    } finally {
      await _readAfterOperation();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettings() async {
    if (_busy || _editing) return;
    setState(() => _editing = true);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            SettingsPage(initial: widget.settings, relay: _relay, save: _save),
      ),
    );
    if (mounted) setState(() => _editing = false);
  }

  Future<void> _act() async {
    if (_busy || _editing) return;
    final settings = widget.settings;
    final s = Strings.of(context);
    final waker = settings.role == DeviceRole.waker;
    if (!waker && settings.pairing == null) {
      await _openSettings();
      return;
    }
    if (waker && _status == null) {
      await _refresh();
      return;
    }
    if (waker && _status?.running != true) {
      try {
        magicPacket(settings.mac);
        if (!Platform.isAndroid && !isLanAddress(settings.lanIp)) {
          throw const FormatException('invalid_lan');
        }
      } catch (error) {
        setState(() {
          _message =
              '${s.failure(error)} ${s.text('Open Settings to finish setup.', 'Dokončete nastavení aplikace.')}';
          _messageError = true;
        });
        return;
      }
    }
    final stopRequested = waker && _status?.running == true;
    setState(() {
      _busy = true;
      _epoch++;
      _message = null;
    });
    try {
      if (waker) {
        // Preserve the pressed action if the notification changed native state.
        final actual = await _relay.status();
        if (!mounted) return;
        if (stopRequested) {
          if (actual.running) await _relay.stop();
        } else if (!actual.running) {
          await _relay.start(_config(settings));
        }
      } else {
        await requestWake(settings.pairing!);
        if (mounted) {
          setState(() {
            _message = s.sent;
            _messageError = false;
          });
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = s.failure(error);
          _messageError = true;
        });
      }
    } finally {
      if (waker) await _readAfterOperation();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final settings = widget.settings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final waker = settings.role == DeviceRole.waker;
    final running = _status?.running == true;
    final target = waker ? settings.targetName : settings.pairing?.name;
    final host = waker ? settings.wakerHost : settings.pairing?.host;
    final error = _status?.error;
    final status = waker
        ? _status == null
              ? s.text('Status unavailable', 'Stav není dostupný')
              : running
              ? s.text('Listening', 'Naslouchá')
              : s.text('Stopped', 'Zastaveno')
        : settings.pairing == null
        ? s.text('Not paired', 'Nespárováno')
        : s.text('Paired', 'Spárováno');
    final detail = waker
        ? _statusFailed
              ? s.statusError
              : error != null
              ? s.failure(ProtocolFailure(error))
              : host == null || host.isEmpty
              ? s.text(
                  'Add Tailscale IPv4 in Settings.',
                  'Doplňte Tailscale IPv4 v nastavení.',
                )
              : '$host:$relayPort'
        : host ??
              s.text(
                'Import a pairing link in Settings.',
                'Vložte párovací odkaz v nastavení.',
              );
    final label = waker ? (running ? s.stop : s.start) : s.wake;
    return WakeScaffold(
      title: 'Selia Wake',
      actions: [
        WakeIconButton(
          tooltip: s.settings,
          onPressed: _busy || _editing ? null : _openSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
        const SizedBox(width: 8),
      ],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.computer_outlined),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  target == null || target.isEmpty
                                      ? s.computer
                                      : target,
                                  style: theme.textTheme.titleLarge,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Semantics(
                            liveRegion: true,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                waker
                                    ? Icons.router_outlined
                                    : Icons.devices_outlined,
                              ),
                              title: Text(waker ? s.waker : s.user),
                              subtitle: Text(status),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Semantics(
                            liveRegion: true,
                            child: SelectableText(
                              detail,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _statusFailed || error != null
                                    ? scheme.error
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          WakeButton(
                            primary: true,
                            onPressed:
                                _busy || _editing || (waker && _status == null)
                                ? null
                                : _act,
                            icon: _busy
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    waker && running
                                        ? Icons.stop_rounded
                                        : Icons.power_settings_new_rounded,
                                  ),
                            label: Text(label, textAlign: TextAlign.center),
                          ),
                          if (_message != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  _message!,
                                  style: TextStyle(
                                    color: _messageError ? scheme.error : null,
                                  ),
                                ),
                              ),
                            ),
                          if (waker && _statusFailed)
                            WakeButton(
                              subtle: true,
                              onPressed: _busy ? null : _refresh,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(s.retry),
                            ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        waker
                            ? Platform.isAndroid
                                  ? s.text(
                                      'Keep this device awake. Stop from the notification.',
                                      'Nechte zařízení zapnuté. Zastavit lze i v oznámení.',
                                    )
                                  : s.text(
                                      'Keep this app open and this device awake.',
                                      'Nechte aplikaci otevřenou a zařízení zapnuté.',
                                    )
                            : s.text(
                                'Connect Tailscale on both devices.',
                                'Připojte Tailscale na obou zařízeních.',
                              ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
