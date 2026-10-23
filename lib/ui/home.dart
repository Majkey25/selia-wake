import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/protocol.dart';
import '../core/relay.dart';
import '../core/settings.dart';
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
  int _pulse = 0;

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

  Future<void> _openSettings({DeviceRole? role}) async {
    if (_busy || _editing) return;
    setState(() => _editing = true);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          initial: widget.settings,
          relay: _relay,
          save: _save,
          role: role,
        ),
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
      _pulse++;
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
    final scheme = Theme.of(context).colorScheme;
    final waker = settings.role == DeviceRole.waker;
    final running = _status?.running == true;
    final target = waker ? settings.targetName : settings.pairing?.name;
    final terminal = settings.theme == WakeTheme.terminal;
    final statusLabel = waker
        ? _status == null
              ? s.text('Status unavailable', 'Stav není dostupný')
              : running
              ? s.text('Waker is listening', 'Budič naslouchá')
              : s.text('Waker is stopped', 'Budič je zastavený')
        : settings.pairing == null
        ? s.text('Pair your Waker', 'Spárujte budič')
        : s.text(
            'Paired · reachability checked on Wake',
            'Spárováno · dostupnost se ověří při probuzení',
          );
    final label = waker
        ? running
              ? s.stop
              : s.start
        : s.wake;
    final relayError = _status?.error;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SignalBackground(scheme.primary, terminal: terminal),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.power_settings_new_rounded,
                                  color: scheme.primary,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Selia Wake',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -.7,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _busy ? null : _openSettings,
                                  tooltip: s.settings,
                                  icon: const Icon(Icons.tune_rounded),
                                ),
                              ],
                            ),
                            SizedBox(
                              height: constraints.maxHeight < 650 ? 8 : 18,
                            ),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final role in DeviceRole.values)
                                  ChoiceChip(
                                    label: Text(
                                      role == DeviceRole.waker
                                          ? s.waker
                                          : s.user,
                                    ),
                                    avatar: Icon(
                                      role == DeviceRole.waker
                                          ? Icons.router_outlined
                                          : Icons.touch_app_outlined,
                                      size: 17,
                                    ),
                                    selected: settings.role == role,
                                    onSelected: _busy
                                        ? null
                                        : (_) => _openSettings(role: role),
                                  ),
                              ],
                            ),
                            SizedBox(
                              height: constraints.maxHeight > 700 ? 44 : 18,
                            ),
                            Text(
                              target == null || target.isEmpty
                                  ? s.computer
                                  : target,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: -1.2,
                                  ),
                            ),
                            SizedBox(
                              height: constraints.maxHeight < 650 ? 6 : 10,
                            ),
                            Text(
                              waker
                                  ? s.text(
                                      'Keep the connection awake.',
                                      'Nechte spojení vzhůru.',
                                    )
                                  : s.text(
                                      'Your computer. One touch away.',
                                      'Váš počítač. Na jeden dotyk.',
                                    ),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            SizedBox(
                              height: constraints.maxHeight < 650 ? 18 : 26,
                            ),
                            _WakeControl(
                              label: label,
                              busy: _busy,
                              enabled: !_editing && (!waker || _status != null),
                              running: waker && running,
                              pulse: _pulse,
                              style: settings.theme,
                              motion:
                                  settings.motion &&
                                  !MediaQuery.disableAnimationsOf(context),
                              onPressed: _act,
                            ),
                            SizedBox(
                              height: constraints.maxHeight < 650 ? 18 : 24,
                            ),
                            _statusPanel(context, statusLabel, relayError),
                            if (_message != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _message!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _messageError
                                          ? scheme.error
                                          : scheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            if (waker && _statusFailed)
                              TextButton.icon(
                                onPressed: _busy ? null : _refresh,
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(s.retry),
                              ),
                            SizedBox(
                              height: constraints.maxHeight < 650 ? 14 : 22,
                            ),
                            Text(
                              waker
                                  ? Platform.isAndroid
                                        ? s.text(
                                            'Runs in an Android foreground service. Use the notification to stop it.',
                                            'Běží jako služba Androidu na popředí. Zastavit ji můžete v oznámení.',
                                          )
                                        : s.text(
                                            'Keep this app open and this device awake. The desktop relay stops when the app closes.',
                                            'Nechte aplikaci otevřenou a zařízení zapnuté. Zavřením aplikace se relé zastaví.',
                                          )
                                  : s.text(
                                      'Wake-on-LAN through your own Tailscale devices.',
                                      'Wake-on-LAN přes vaše vlastní zařízení v Tailscale.',
                                    ),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPanel(BuildContext context, String label, String? error) {
    final s = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final waker = widget.settings.role == DeviceRole.waker;
    final terminal = widget.settings.theme == WakeTheme.terminal;
    final glass = widget.settings.theme == WakeTheme.glass;
    final host = waker
        ? widget.settings.wakerHost
        : widget.settings.pairing?.host;
    final detail = waker
        ? _statusFailed
              ? s.statusError
              : error != null
              ? s.failure(ProtocolFailure(error))
              : host == null || host.isEmpty
              ? s.text(
                  'No Tailscale IPv4. Add one in Settings to share remote pairing.',
                  'Chybí Tailscale IPv4. Pro sdílení vzdáleného párování ji doplňte v nastavení.',
                )
              : '$host:$relayPort'
        : host ??
              s.text(
                'Open Settings to import a pairing link.',
                'Otevřete nastavení a načtěte párovací odkaz.',
              );
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: terminal
            ? Colors.transparent
            : scheme.surfaceContainerHighest.withValues(
                alpha: glass ? .3 : .45,
              ),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
        borderRadius: BorderRadius.circular(terminal ? 4 : 22),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                waker
                    ? _status == null
                          ? Icons.help_outline_rounded
                          : _status?.running == true
                          ? Icons.sensors_rounded
                          : Icons.sensors_off_rounded
                    : Icons.link_rounded,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _statusFailed || error != null
                  ? scheme.error
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      liveRegion: true,
      child: glass
          ? ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: content,
              ),
            )
          : content,
    );
  }
}

class _WakeControl extends StatefulWidget {
  const _WakeControl({
    required this.label,
    required this.busy,
    required this.enabled,
    required this.running,
    required this.pulse,
    required this.style,
    required this.motion,
    required this.onPressed,
  });
  final String label;
  final bool busy;
  final bool enabled;
  final bool running;
  final int pulse;
  final WakeTheme style;
  final bool motion;
  final VoidCallback onPressed;

  @override
  State<_WakeControl> createState() => _WakeControlState();
}

class _WakeControlState extends State<_WakeControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  @override
  void didUpdateWidget(covariant _WakeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.motion) _animation.reset();
    if (widget.pulse != oldWidget.pulse && widget.motion) {
      _animation.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final terminal = widget.style == WakeTheme.terminal;
    final glass = widget.style == WakeTheme.glass;
    final active = widget.enabled && !widget.busy;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(terminal ? 6 : 100),
    );
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final split = _animation.isAnimating
            ? math.sin(_animation.value * math.pi * 6) *
                  (1 - _animation.value) *
                  2.5
            : 0.0;
        return Stack(
          alignment: Alignment.center,
          children: [
            if (split != 0) ...[
              Transform.translate(
                offset: Offset(split, 0),
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    borderRadius: shape.borderRadius,
                    border: Border.all(
                      color: const Color(0xFFE693A9).withValues(alpha: .4),
                      width: 2,
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(-split, 0),
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    borderRadius: shape.borderRadius,
                    border: Border.all(
                      color: const Color(0xFF8DDDE3).withValues(alpha: .4),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 184,
                minHeight: 184,
                maxWidth: 248,
              ),
              child: FilledButton(
                onPressed: active ? widget.onPressed : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 34,
                  ),
                  shape: shape,
                  backgroundColor: glass
                      ? scheme.primaryContainer.withValues(alpha: .7)
                      : terminal
                      ? scheme.surface
                      : scheme.primary,
                  foregroundColor: glass
                      ? scheme.onPrimaryContainer
                      : terminal
                      ? scheme.onSurface
                      : scheme.onPrimary,
                  side: BorderSide(
                    color: terminal
                        ? scheme.onSurface
                        : scheme.primary.withValues(alpha: .5),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.busy)
                      SizedBox.square(
                        dimension: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onSurface,
                          semanticsLabel: Strings.of(
                            context,
                          ).text('Working', 'Probíhá operace'),
                        ),
                      )
                    else
                      Icon(
                        widget.running
                            ? Icons.stop_rounded
                            : Icons.power_settings_new_rounded,
                        size: 54,
                      ),
                    const SizedBox(height: 12),
                    Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SignalBackground extends CustomPainter {
  const _SignalBackground(this.color, {required this.terminal});
  final Color color;
  final bool terminal;

  @override
  void paint(Canvas canvas, Size size) {
    if (terminal) {
      final paint = Paint()
        ..color = color.withValues(alpha: .12)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(24, size.height * .29),
        Offset(size.width - 24, size.height * .29),
        paint,
      );
      return;
    }
    final center = Offset(size.width * .88, size.height * .3);
    final radius = size.shortestSide * .8;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: .09), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    final paint = Paint()
      ..color = color.withValues(alpha: .06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final scale in [.55, .8, 1.05]) {
      canvas.drawCircle(
        Offset(size.width * .5, size.height * .48),
        size.shortestSide * scale,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignalBackground oldDelegate) =>
      oldDelegate.color != color || oldDelegate.terminal != terminal;
}
