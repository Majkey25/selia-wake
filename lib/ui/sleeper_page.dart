import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/settings.dart';
import '../core/sleeper.dart';
import 'controls.dart';
import 'strings.dart';

class SleeperPage extends StatefulWidget {
  const SleeperPage({
    super.key,
    required this.settings,
    required this.save,
    required this.openSettings,
    this.sleeper,
  });

  final Settings settings;
  final Future<void> Function(Settings) save;
  final VoidCallback openSettings;
  final Sleeper? sleeper;

  @override
  State<SleeperPage> createState() => _SleeperPageState();
}

class _SleeperPageState extends State<SleeperPage> {
  late final _sleeper = widget.sleeper ?? Sleeper();
  SleeperReport? _report;
  String _adapterId = '';
  bool _busy = false;
  String? _error;
  String? _note;

  SleeperAdapter? get _adapter =>
      _report?.adapters.where((a) => a.id == _adapterId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _adapterId = widget.settings.sleeperAdapter;
    unawaited(_inspect());
  }

  void _accept(SleeperReport report) {
    _report = report;
    if (_adapterId.isEmpty && widget.settings.sleeperAdapter.isEmpty) {
      _adapterId = report.adapters.firstOrNull?.id ?? '';
    }
    if (!report.adapters.any((a) => a.id == _adapterId)) _adapterId = '';
  }

  Future<void> _inspect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
      _report = null;
    });
    try {
      final report = await _sleeper.inspect();
      if (mounted) setState(() => _accept(report));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAdapter() async {
    await widget.save(widget.settings.copy()..sleeperAdapter = _adapterId);
  }

  Future<void> _act({bool enable = false, bool export = false}) async {
    final adapter = _adapter;
    final report = _report;
    if (_busy || adapter == null || report == null) return;
    final s = Strings.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });
    try {
      try {
        await _saveAdapter();
      } catch (_) {
        if (mounted) setState(() => _error = s.saveError);
        return;
      }
      if (!mounted) return;
      if (enable) {
        final updated = await _sleeper.enableWake(
          adapter.id,
          expectedMac: adapter.mac,
        );
        if (mounted) {
          setState(() {
            _accept(updated);
            _note = s.text(
              'Review the refreshed OS status below. Hardware wake is not verified.',
              'Zkontrolujte obnovený stav hlášený systémem níže. Probuzení počítače není ověřené.',
            );
          });
        }
      } else if (export) {
        final setup = TargetSetup(
          name: report.machineName,
          mac: adapter.mac,
          broadcast: adapter.broadcast,
          connection: adapter.connection,
          targetHost: report.tailscaleIp ?? adapter.ip,
        );
        final link = setup.encode();
        if (!mounted) return;
        setState(() => _busy = false);
        await showDialog<void>(
          context: context,
          builder: (_) => _TargetDialog(setup: setup, link: link),
        );
      } else {
        setState(() => _note = s.text('Adapter saved.', 'Adaptér uložen.'));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          if (enable) _report = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final report = _report;
    final adapter = _adapter;
    final theme = Theme.of(context);
    String status(bool? value) => value == null
        ? s.text('Unknown', 'Neznámé')
        : value
        ? s.text('Yes', 'Ano')
        : s.text('No', 'Ne');
    return PopScope(
      canPop: !_busy,
      child: WakeScaffold(
        title: s.sleeper,
        actions: [
          WakeIconButton(
            tooltip: s.text('Refresh', 'Obnovit'),
            onPressed: _busy ? null : _inspect,
            icon: const Icon(Icons.refresh_rounded),
          ),
          WakeIconButton(
            tooltip: s.settings,
            onPressed: _busy ? null : widget.openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(s.sleeperHelp),
                  const SizedBox(height: 16),
                  if (_busy) const LinearProgressIndicator(),
                  if (report != null) ...[
                    Text(report.machineName, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    Text(s.text('OS sleep states', 'Režimy spánku systému')),
                    SelectableText(report.sleepStates),
                    const SizedBox(height: 16),
                    if (report.adapters.isEmpty)
                      Text(
                        s.text(
                          'No active physical IPv4 adapter found. Connect the PC to its LAN and refresh.',
                          'Nebyl nalezen aktivní fyzický adaptér s IPv4. Připojte PC do místní sítě a obnovte stav.',
                        ),
                      )
                    else
                      WakeSelect<String>(
                        label: s.text('Wake adapter', 'Adaptér pro probouzení'),
                        values: ['', for (final a in report.adapters) a.id],
                        value: _adapterId,
                        itemLabel: (id) => id.isEmpty
                            ? s.text('Select adapter', 'Vyberte adaptér')
                            : report.adapters
                                  .firstWhere((a) => a.id == id)
                                  .name,
                        onChanged: _busy
                            ? null
                            : (id) => setState(() {
                                _adapterId = id;
                                _note = null;
                              }),
                        icon: Icons.lan_outlined,
                      ),
                  ],
                  if (adapter != null) ...[
                    const SizedBox(height: 16),
                    SelectableText(
                      '${adapter.description}\nMAC: ${adapter.mac}\nIPv4: ${adapter.ip}\nBroadcast: ${adapter.broadcast.isEmpty ? s.text('Unknown', 'Neznámý') : adapter.broadcast}',
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        '${s.text('OS reports wake support', 'Systém hlásí podporu probouzení')}: ${status(adapter.supportsWake)}\n'
                        '${s.text('Wake enabled', 'Probouzení povoleno')}: ${status(adapter.wakeEnabled)}\n'
                        'Magic Packet: ${status(adapter.magicPacketEnabled)}\n${adapter.detail}',
                      ),
                    ),
                    if (adapter.restartRequired)
                      Text(
                        s.text(
                          'The driver reports a restart is required. Restart manually when ready. No restart was requested by this app.',
                          'Ovladač hlásí nutnost restartu. Restartujte ručně, až budete připraveni. Aplikace restart nevyžádala.',
                        ),
                      ),
                    const SizedBox(height: 16),
                    WakeButton(
                      primary: true,
                      onPressed: _busy ? null : () => _act(enable: true),
                      icon: const Icon(Icons.power_settings_new_rounded),
                      label: Text(s.text('Enable wake', 'Povolit probouzení')),
                    ),
                    const SizedBox(height: 12),
                    WakeButton(
                      onPressed: _busy ? null : _act,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(s.text('Save adapter', 'Uložit adaptér')),
                    ),
                    const SizedBox(height: 12),
                    WakeButton(
                      onPressed: _busy || adapter.broadcast.isEmpty
                          ? null
                          : () => _act(export: true),
                      icon: const Icon(Icons.qr_code_rounded),
                      label: Text(
                        s.text('Export target / QR', 'Sdílet počítač / QR'),
                      ),
                    ),
                    if (adapter.broadcast.isEmpty)
                      Text(
                        s.text(
                          'A LAN broadcast address is unavailable. Target export needs an IPv4 subnet with a broadcast address.',
                          'Broadcast místní sítě není dostupný. Sdílení cíle vyžaduje IPv4 podsíť s broadcast adresou.',
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    s.text(
                      'These values describe OS settings only. BIOS, firmware and hardware wake are not verified. Enable wake changes only the selected adapter and may request administrator permission. On Linux, changes may last only until restart. This app does not restart or put the PC to sleep.',
                      'Tyto údaje popisují pouze nastavení systému. BIOS, firmware a skutečné probuzení nejsou ověřené. Povolení probouzení mění pouze vybraný adaptér a může vyžádat oprávnění správce. V Linuxu mohou změny platit jen do restartu. Aplikace počítač nerestartuje ani neuspává.',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (_error != null || _note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error == null
                              ? _note!
                              : '${s.text('Operation failed.', 'Operace selhala.')} $_error',
                          style: TextStyle(
                            color: _error == null
                                ? null
                                : theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TargetDialog extends StatefulWidget {
  const _TargetDialog({required this.setup, required this.link});
  final TargetSetup setup;
  final String link;

  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  String? _message;
  bool _copying = false;

  Future<void> _copy() async {
    final s = Strings.of(context);
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: widget.link));
      if (mounted) {
        setState(
          () => _message = s.text(
            'Target link copied.',
            'Odkaz počítače zkopírován.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = s.text(
            'Copy failed. Retry clipboard access.',
            'Kopírování selhalo. Zkuste přístup ke schránce znovu.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return WakeDialog(
      title: Text(s.targetSetup),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.setup.name}\nMAC: ${widget.setup.mac}'),
            const SizedBox(height: 16),
            Center(
              child: SizedBox.square(
                dimension: 260,
                child: QrImageView(
                  data: widget.link,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                  semanticsLabel: s.text(
                    'Sleeper target QR code',
                    'QR kód počítače spáče',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(widget.link),
            const SizedBox(height: 12),
            Text(s.networkDetails),
            const SizedBox(height: 12),
            Text(
              s.text(
                'On the Waker, open Settings and paste or scan this setup. Valid settings apply automatically. Check the imported name and MAC.',
                'Na budiči otevřete Nastavení a vložte nebo načtěte toto nastavení. Platné údaje se použijí automaticky. Zkontrolujte načtený název a MAC.',
              ),
            ),
            if (_message != null)
              Semantics(liveRegion: true, child: Text(_message!)),
          ],
        ),
      ),
      actions: [
        WakeButton(
          subtle: true,
          onPressed: _copying ? null : () => Navigator.pop(context),
          label: Text(s.text('Close', 'Zavřít')),
        ),
        WakeButton(
          primary: true,
          onPressed: _copying ? null : _copy,
          icon: const Icon(Icons.copy_rounded),
          label: Text(s.text('Copy link', 'Kopírovat odkaz')),
        ),
      ],
    );
  }
}
