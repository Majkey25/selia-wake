import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/protocol.dart';
import '../core/relay.dart';
import '../core/settings.dart';
import '../core/sleeper.dart';
import '../core/target.dart';
import 'controls.dart';
import 'custom_theme_editor.dart';
import 'strings.dart';
import 'setup_guide.dart';
import 'privacy_page.dart';
import 'theme_previews.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.initial,
    required this.relay,
    required this.save,
  });
  final Settings initial;
  final Relay relay;
  final Future<void> Function(Settings) save;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _form = GlobalKey<FormState>();
  late final Settings _draft;
  late Map<String, Object?> _savedAppearance;
  late final TextEditingController _name;
  late final TextEditingController _mac;
  late final TextEditingController _broadcast;
  late final TextEditingController _lan;
  late final TextEditingController _host;
  late final TextEditingController _targetHost;
  late final TextEditingController _targetPort;
  final _pairing = TextEditingController();
  Pairing? _pendingPairing;
  TargetSetup? _pendingSetup;
  bool _saving = false;
  bool _detecting = false;
  bool _scanning = false;
  bool _testing = false;
  String? _error;
  String? _networkNote;
  String? _testNote;

  bool get _locked => _saving || _detecting || _scanning || _testing;
  Map<String, Object?> get _appearanceValues => {
    'theme': _draft.theme,
    'appearance': _draft.appearance,
    'language': _draft.language,
    ..._draft.customTheme.toJson(),
  };
  bool get _appearancePending =>
      !mapEquals(_appearanceValues, _savedAppearance);
  bool get _needsExplicitSave => _pendingSetup != null || _appearancePending;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial.copy();
    if (_draft.role == DeviceRole.sleeper && !Sleeper.supported) {
      _draft.role = DeviceRole.user;
    }
    _savedAppearance = _appearanceValues;
    _name = TextEditingController(text: _draft.targetName);
    _mac = TextEditingController(text: _draft.mac);
    _broadcast = TextEditingController(text: _draft.broadcast);
    _lan = TextEditingController(text: _draft.lanIp);
    _host = TextEditingController(text: _draft.wakerHost);
    _targetHost = TextEditingController(text: _draft.targetHost);
    _targetPort = TextEditingController(text: '${_draft.targetPort}');
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _mac,
      _broadcast,
      _lan,
      _host,
      _pairing,
      _targetHost,
      _targetPort,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _detect() async {
    final s = Strings.of(context);
    setState(() {
      _detecting = true;
      _networkNote = null;
    });
    try {
      final network = await widget.relay.networkInfo();
      if (!mounted) return;
      if (_lan.text.trim().isEmpty) _lan.text = network.lanIp ?? '';
      if (_broadcast.text.trim().isEmpty) {
        _broadcast.text = network.broadcast ?? '';
      }
      if (_host.text.trim().isEmpty) _host.text = network.tailscaleIp ?? '';
      setState(
        () => _networkNote = network.tailscaleIp == null
            ? s.text(
                'Empty fields filled where detected. No Tailscale IPv4 found. Connect Tailscale or enter it manually.',
                'Prázdná pole byla doplněna dostupnými údaji. Tailscale IPv4 nebyla nalezena. Připojte Tailscale nebo ji zadejte ručně.',
              )
            : s.text(
                'Detected addresses added to empty fields. Check the physical LAN address before saving.',
                'Nalezené adresy byly doplněny do prázdných polí. Před uložením zkontrolujte adresu místní sítě.',
              ),
      );
    } catch (error) {
      if (mounted) setState(() => _networkNote = s.failure(error));
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _paste() async {
    final s = Strings.of(context);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || _saving) return;
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) {
        setState(
          () => _error = s.text(
            'Clipboard has no pairing link.',
            'Schránka neobsahuje párovací odkaz.',
          ),
        );
        return;
      }
      final pairing = Pairing.parse(text);
      _pairing.text = pairing.encode();
      setState(() {
        _pendingPairing = pairing;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? s.failure(error)
              : s.text(
                  'Clipboard unavailable. Enter the pairing link manually.',
                  'Schránka není dostupná. Zadejte párovací odkaz ručně.',
                ),
        );
      }
    }
  }

  Future<void> _scan() async {
    final s = Strings.of(context);
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final code = await widget.relay.scanPairing(s.czech ? 'cs' : 'en');
      if (!mounted || code == null) return;
      final pairing = Pairing.parse(code);
      _pairing.text = pairing.encode();
      setState(() => _pendingPairing = pairing);
    } catch (error) {
      if (mounted) setState(() => _error = s.failure(error));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<bool> _save({bool close = true}) async {
    if (!_form.currentState!.validate()) return false;
    final s = Strings.of(context);
    _draft
      ..targetName = _name.text.trim()
      ..mac = _mac.text.trim()
      ..broadcast = _broadcast.text.trim()
      ..lanIp = _lan.text.trim()
      ..wakerHost = _host.text.trim()
      ..targetHost = _targetHost.text.trim()
      ..targetPort = int.tryParse(_targetPort.text.trim()) ?? 3389;
    if (_draft.role == DeviceRole.user && _pairing.text.trim().isNotEmpty) {
      try {
        _draft.pairing = Pairing.parse(_pairing.text.trim());
      } catch (error) {
        setState(() => _error = s.failure(error));
        return false;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(_draft.copy());
      if (!mounted) return false;
      _pairing.clear();
      _pendingPairing = null;
      _pendingSetup = null;
      _savedAppearance = _appearanceValues;
      if (close) Navigator.of(context).pop();
      return true;
    } catch (_) {
      if (mounted) setState(() => _error = s.saveError);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _importSetup({bool scan = false}) async {
    if (_locked) return;
    final s = Strings.of(context);
    setState(() {
      _scanning = true;
      _error = null;
      _testNote = null;
    });
    try {
      final text = scan
          ? await widget.relay.scanPairing(s.czech ? 'cs' : 'en')
          : (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (!mounted || (scan && text == null)) return;
      final setup = TargetSetup.parse(text?.trim() ?? '');
      _name.text = setup.name;
      _mac.text = setup.mac;
      _broadcast.text = setup.broadcast;
      _targetHost.text = setup.targetHost;
      _targetPort.text = '${setup.targetPort}';
      setState(() {
        _draft.connection = setup.connection;
        _pendingSetup = setup;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error is FormatException ||
                  (error is PlatformException &&
                      error.code == 'invalid_pairing')
              ? s.invalidSetup
              : s.failure(error),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _testLocal() async {
    if (_locked || _needsExplicitSave) return;
    final s = Strings.of(context);
    setState(() {
      _testing = true;
      _testNote = null;
    });
    try {
      if (!await _save(close: false) || !mounted) return;
      await widget.relay.sendLocal(
        _draft.mac,
        _draft.broadcast,
        lanIp: _draft.lanIp,
      );
      if (mounted) setState(() => _testNote = s.sent);
    } catch (error) {
      if (mounted) setState(() => _error = s.failure(error));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _share() async {
    if (_locked || _needsExplicitSave) return;
    final s = Strings.of(context);
    if (!isTailnetAddress(_host.text.trim())) {
      setState(() => _error = '${s.hostError}\n${s.tailscaleHelp}');
      return;
    }
    if (!await _save(close: false) || !mounted) return;
    final pairing = Pairing(
      host: _draft.wakerHost,
      key: _draft.wakerKey,
      name: _draft.targetName.isEmpty ? s.computer : _draft.targetName,
    );
    await showDialog<void>(
      context: context,
      builder: (context) => _PairingDialog(pairing: pairing),
    );
  }

  String? _validateMac(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      magicPacket(value.trim());
      return null;
    } on FormatException {
      return Strings.of(context).macError;
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    String? Function(String?)? validator,
    bool numeric = false,
    IconData icon = Icons.edit_outlined,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: WakeField(
      controller: controller,
      readOnly: _locked,
      label: label,
      hint: hint,
      icon: icon,
      validator: validator,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
    ),
  );

  Widget _heading(String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Semantics(
      header: true,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isWaker = _draft.role == DeviceRole.waker;
    final isSleeper = _draft.role == DeviceRole.sleeper;
    return PopScope(
      canPop: !_locked,
      child: WakeScaffold(
        title: s.settings,
        actions: [
          WakeIconButton(
            tooltip: s.saveSettings,
            icon: const Icon(Icons.save_outlined),
            onPressed: _locked ? null : _save,
          ),
        ],
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Form(
                key: _form,
                onChanged: () => setState(() {}),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _heading(
                        s.text('This device', 'Toto zařízení'),
                        Icons.devices_outlined,
                      ),
                      _select<DeviceRole>(
                        s.text('Mode', 'Režim'),
                        [
                          DeviceRole.user,
                          DeviceRole.waker,
                          if (Sleeper.supported) DeviceRole.sleeper,
                        ],
                        _draft.role,
                        (role) => switch (role) {
                          DeviceRole.user => s.user,
                          DeviceRole.waker => s.waker,
                          DeviceRole.sleeper => s.sleeper,
                        },
                        (role) => setState(() => _draft.role = role),
                        icon: Icons.devices_outlined,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isWaker
                            ? s.localHelp
                            : isSleeper
                            ? s.text(
                                'Save to set up this PC’s wake adapter. A separate Waker must stay awake on this LAN.',
                                'Uložte nastavení a nastavte probouzení tohoto PC. Samostatný budič musí zůstat zapnutý ve stejné síti.',
                              )
                            : s.text(
                                'Paste a pairing link from your Waker. Connect Tailscale on both devices.',
                                'Vložte párovací odkaz z budiče. Připojte Tailscale na obou zařízeních.',
                              ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      WakeButton(
                        subtle: true,
                        icon: const Icon(Icons.help_outline),
                        onPressed: _locked
                            ? null
                            : () => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => const SetupGuide(),
                                ),
                              ),
                        label: Text(s.text('Setup guide', 'Návod k propojení')),
                      ),
                      const SizedBox(height: 24),
                      if (isWaker) ...[
                        _heading(s.targetSetup, Icons.download_outlined),
                        WakeButton(
                          onPressed: _locked ? null : _importSetup,
                          icon: const Icon(Icons.content_paste_rounded),
                          label: Text(
                            s.text(
                              'Paste Sleeper setup',
                              'Vložit nastavení spáče',
                            ),
                          ),
                        ),
                        if (Platform.isAndroid)
                          WakeButton(
                            onPressed: _locked
                                ? null
                                : () => _importSetup(scan: true),
                            icon: const Icon(Icons.qr_code_scanner),
                            label: Text(
                              s.text('Scan Sleeper QR', 'Načíst QR spáče'),
                            ),
                          ),
                        if (_pendingSetup case final setup?)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                '${s.text('Preview', 'Náhled')}: ${setup.name}\nMAC: ${setup.mac}\n${s.text('Review the fields below. Save settings to apply.', 'Zkontrolujte pole níže. Použijte tlačítko Uložit nastavení.')}',
                              ),
                            ),
                          ),
                        Text(
                          s.networkDetails,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 20),
                        _select<TargetConnection>(
                          s.text('Computer connection', 'Připojení počítače'),
                          TargetConnection.values,
                          _draft.connection,
                          (connection) => switch (connection) {
                            TargetConnection.ethernet => 'Ethernet',
                            TargetConnection.wifi => 'Wi-Fi (WoWLAN)',
                            TargetConnection.usbEthernet => 'USB Ethernet',
                          },
                          (connection) =>
                              setState(() => _draft.connection = connection),
                          icon: Icons.cable_outlined,
                        ),
                        const SizedBox(height: 12),
                        Text(switch (_draft.connection) {
                          TargetConnection.ethernet => s.text(
                            'Use the connected Ethernet adapter’s MAC.',
                            'Použijte MAC připojeného ethernetového adaptéru.',
                          ),
                          TargetConnection.wifi => s.text(
                            'Use the Wi-Fi MAC. Requires WoWLAN support in the PC, firmware and driver.',
                            'Použijte MAC Wi-Fi adaptéru. PC, firmware a ovladač musí podporovat WoWLAN.',
                          ),
                          TargetConnection.usbEthernet => s.text(
                            'Requires a powered, wake-capable USB Ethernet adapter. A charging cable cannot wake the PC.',
                            'Vyžaduje napájený USB Ethernet adaptér s podporou probouzení. Nabíjecí kabel PC neprobudí.',
                          ),
                        }, style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 20),
                        _field(
                          _name,
                          s.name,
                          icon: Icons.computer_outlined,
                          hint: s.computer,
                          validator: (v) => (v?.trim().length ?? 0) > 80
                              ? s.text(
                                  'Use at most 80 characters.',
                                  'Použijte nejvýše 80 znaků.',
                                )
                              : null,
                        ),
                        _field(
                          _mac,
                          'MAC',
                          icon: Icons.memory_outlined,
                          hint: '00:11:22:33:44:55',
                          validator: _validateMac,
                        ),
                        _field(
                          _broadcast,
                          s.text(
                            'Broadcast IPv4 · optional',
                            'Broadcast IPv4 · volitelné',
                          ),
                          hint: s.text('Automatic', 'Automaticky'),
                          icon: Icons.broadcast_on_personal_outlined,
                          numeric: true,
                          validator: (v) =>
                              v == null ||
                                  v.trim().isEmpty ||
                                  v.trim() == '255.255.255.255' ||
                                  isLanAddress(v.trim())
                              ? null
                              : s.broadcastError,
                        ),
                        if (!Platform.isAndroid)
                          _field(
                            _lan,
                            s.text('Waker LAN IPv4', 'LAN IPv4 budiče'),
                            hint: '192.168.1.20',
                            icon: Icons.lan_outlined,
                            numeric: true,
                            validator: (v) =>
                                v == null ||
                                    v.trim().isEmpty ||
                                    isLanAddress(v.trim())
                                ? null
                                : s.lanError,
                          ),
                        _field(
                          _host,
                          s.text(
                            'Waker Tailscale IPv4 · optional',
                            'Tailscale IPv4 budiče · volitelné',
                          ),
                          hint: '100.x.x.x',
                          icon: Icons.vpn_lock_outlined,
                          numeric: true,
                          validator: (v) =>
                              v == null ||
                                  v.trim().isEmpty ||
                                  isTailnetAddress(v.trim())
                              ? null
                              : s.hostError,
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: WakeButton(
                            onPressed: _locked ? null : _detect,
                            icon: _detecting
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.radar_rounded),
                            label: Text(
                              s.text('Detect network', 'Zjistit síť'),
                            ),
                          ),
                        ),
                        if (_networkNote != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _networkNote!,
                              semanticsLabel: _networkNote,
                            ),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          s.text(
                            'For remote pairing, connect Tailscale on both devices. Local wake works without it.',
                            'Pro vzdálené párování připojte Tailscale na obou zařízeních. Místní probouzení funguje i bez něj.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 24),
                        _heading(
                          s.text('Pair and test', 'Párování a test'),
                          Icons.phonelink_outlined,
                        ),
                        if (_pendingSetup != null)
                          Semantics(
                            liveRegion: true,
                            child: Text(s.saveImportedSetup),
                          ),
                        if (_appearancePending)
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              s.text(
                                'Save settings to apply appearance changes first.',
                                'Nejprve uložte nastavení vzhledu.',
                              ),
                            ),
                          ),
                        WakeButton(
                          onPressed: _locked || _needsExplicitSave
                              ? null
                              : _share,
                          icon: const Icon(Icons.ios_share_rounded),
                          label: Text(
                            s.text('Pairing link / QR', 'Párovací odkaz / QR'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        WakeButton(
                          onPressed: _locked || _needsExplicitSave
                              ? null
                              : _testLocal,
                          icon: const Icon(Icons.send_outlined),
                          label: Text(
                            s.text(
                              'Send local test packet',
                              'Odeslat místní testovací paket',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          s.text(
                            'Saves settings, then sends a wake packet on this LAN. Keep this Waker awake. Packet delivery does not confirm hardware wake.',
                            'Uloží nastavení a odešle probouzecí paket do místní sítě. Nechte budič zapnutý. Odeslání paketu nepotvrzuje probuzení počítače.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_testNote != null)
                          Semantics(liveRegion: true, child: Text(_testNote!)),
                      ] else if (!isSleeper) ...[
                        _heading(
                          s.text('Connect to your Waker', 'Připojení k budiči'),
                          Icons.link_rounded,
                        ),
                        if (_draft.pairing case final paired?) ...[
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.link_rounded),
                            title: Text(paired.name),
                            subtitle: Text(paired.host),
                            trailing: WakeIconButton(
                              tooltip: s.text(
                                'Forget pairing',
                                'Zapomenout párování',
                              ),
                              onPressed: _locked
                                  ? null
                                  : () => setState(() {
                                      _draft.pairing = null;
                                      _pendingPairing = null;
                                      _pairing.clear();
                                    }),
                              icon: const Icon(Icons.link_off_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        WakeField(
                          controller: _pairing,
                          label: s.pairing,
                          hint: 'seliawake://pair?data=…',
                          icon: Icons.key_outlined,
                          onChanged: (_) =>
                              setState(() => _pendingPairing = null),
                          readOnly: _locked,
                          obscure: true,
                          keyboardType: TextInputType.visiblePassword,
                          suffix: WakeIconButton(
                            tooltip: s.text(
                              'Paste pairing link',
                              'Vložit párovací odkaz',
                            ),
                            onPressed: _locked ? null : _paste,
                            icon: const Icon(Icons.content_paste_rounded),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            try {
                              Pairing.parse(v.trim());
                              return null;
                            } catch (error) {
                              return s.failure(error);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        if (_pendingPairing case final pairing?) ...[
                          Text(
                            '${s.text('New pairing', 'Nové párování')}: ${pairing.name}\n${pairing.host}',
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (Platform.isAndroid) ...[
                          WakeButton(
                            onPressed: _locked ? null : _scan,
                            icon: const Icon(Icons.qr_code_scanner, size: 18),
                            label: Text(
                              s.text('Scan QR code', 'Načíst QR kód'),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          s.text(
                            'The link contains a secret. Clipboard access happens only when you press Paste.',
                            'Odkaz obsahuje tajný klíč. Schránka se čte pouze po stisknutí Vložit.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 24),
                      _heading(
                        s.text(
                          'Check computer availability',
                          'Ověřit dostupnost počítače',
                        ),
                        Icons.network_check_outlined,
                      ),
                      _field(
                        _targetHost,
                        s.text(
                          'Computer IPv4 · optional',
                          'IPv4 počítače · volitelné',
                        ),
                        hint: '100.x.x.x',
                        icon: Icons.computer_outlined,
                        numeric: true,
                        validator: (v) =>
                            v == null ||
                                v.trim().isEmpty ||
                                isTargetAddress(v.trim())
                            ? null
                            : s.text(
                                'Enter the computer’s Tailscale or private LAN IPv4.',
                                'Zadejte Tailscale nebo soukromou LAN IPv4 počítače.',
                              ),
                      ),
                      _field(
                        _targetPort,
                        s.text('Computer TCP port', 'TCP port počítače'),
                        icon: Icons.lan_outlined,
                        numeric: true,
                        validator: (v) {
                          if (_targetHost.text.trim().isEmpty) return null;
                          final port = int.tryParse(v?.trim() ?? '');
                          return port != null && port >= 1 && port <= 65535
                              ? null
                              : s.text(
                                  'Enter a port from 1 to 65535.',
                                  'Zadejte port od 1 do 65535.',
                                );
                        },
                      ),
                      Text(
                        s.text(
                          'Use the target PC’s address and a running service, such as RDP 3389 or SSH 22. A response confirms service access, not boot or login. Leave the address empty to skip checks. Details are in the setup guide.',
                          'Zadejte adresu cílového PC a port běžící služby, například RDP 3389 nebo SSH 22. Odpověď potvrzuje dostupnost služby, ne boot či přihlášení. Prázdná adresa kontrolu vypne. Podrobnosti najdete v návodu.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 24),
                      _heading(s.appearance, Icons.palette_outlined),
                      if (_draft.theme != WakeTheme.matrix &&
                          _draft.theme != WakeTheme.custom) ...[
                        _select<ThemeMode>(
                          s.text('Color mode', 'Barevný režim'),
                          ThemeMode.values,
                          _draft.appearance,
                          (mode) => switch (mode) {
                            ThemeMode.system => s.text('System', 'Systém'),
                            ThemeMode.light => s.text('Light', 'Světlý'),
                            ThemeMode.dark => s.text('Dark', 'Tmavý'),
                          },
                          (mode) => setState(() => _draft.appearance = mode),
                          icon: Icons.brightness_6_outlined,
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        s.platformStyleHelp,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      ThemePreviews(
                        value: _draft.theme,
                        appearance: _draft.appearance,
                        custom: _draft.customTheme,
                        onChanged: _locked
                            ? null
                            : (theme) => setState(() => _draft.theme = theme),
                      ),
                      if (_draft.theme == WakeTheme.custom) ...[
                        const SizedBox(height: 20),
                        CustomThemeEditor(
                          key: ObjectKey(_draft.customTheme),
                          value: _draft.customTheme,
                          readOnly: _locked,
                        ),
                        WakeButton(
                          subtle: true,
                          onPressed: _locked
                              ? null
                              : () => setState(
                                  () => _draft.customTheme = CustomTheme(),
                                ),
                          icon: const Icon(Icons.restore),
                          label: Text(
                            s.text(
                              'Reset custom theme',
                              'Obnovit vlastní motiv',
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _select<String>(
                        s.text('Language', 'Jazyk'),
                        const ['system', 'en', 'cs'],
                        _draft.language,
                        (language) => switch (language) {
                          'en' => 'English',
                          'cs' => 'Čeština',
                          _ => s.text('System', 'Systém'),
                        },
                        (language) =>
                            setState(() => _draft.language = language),
                        icon: Icons.language_outlined,
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              style: TextStyle(color: scheme.error),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      WakeButton(
                        primary: true,
                        onPressed: _locked ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(s.saveSettings),
                      ),
                      const SizedBox(height: 8),
                      WakeButton(
                        subtle: true,
                        icon: const Icon(Icons.privacy_tip_outlined),
                        onPressed: _locked
                            ? null
                            : () => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => const PrivacyPage(),
                                ),
                              ),
                        label: Text(
                          s.text('Privacy & support', 'Soukromí a podpora'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _select<T>(
    String title,
    List<T> values,
    T selected,
    String Function(T) label,
    ValueChanged<T> change, {
    IconData icon = Icons.tune,
  }) => WakeSelect<T>(
    label: title,
    value: selected,
    values: values,
    itemLabel: label,
    icon: icon,
    onChanged: _locked ? null : change,
  );
}

class _PairingDialog extends StatefulWidget {
  const _PairingDialog({required this.pairing});
  final Pairing pairing;

  @override
  State<_PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<_PairingDialog> {
  bool _copied = false;
  bool _failed = false;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.pairing.encode()));
      if (mounted) {
        setState(() {
          _copied = true;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return WakeDialog(
      title: Text(
        s.text('Pair a trusted device', 'Spárovat důvěryhodné zařízení'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.pairing.name}\n${widget.pairing.host}'),
            const SizedBox(height: 16),
            Center(
              child: SizedBox.square(
                dimension: 260,
                child: QrImageView(
                  data: widget.pairing.encode(),
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                  semanticsLabel: s.text(
                    'Secret pairing QR code',
                    'Tajný párovací QR kód',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              s.text(
                'This QR code and link contain your secret key. Share only with your trusted devices. Anyone with it and tailnet access can wake this computer.',
                'QR kód a odkaz obsahují tajný klíč. Sdílejte je pouze se svými důvěryhodnými zařízeními. Každý s tímto klíčem a přístupem do tailnetu může počítač probudit.',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              s.text(
                'On the other Android device, select User and Scan QR code. On desktop, paste the copied link. Press Save settings to finish. Clear clipboard history after pairing.',
                'Na druhém Androidu vyberte Uživatel a Načíst QR kód. Na počítači vložte zkopírovaný odkaz. Dokončete tlačítkem Uložit nastavení. Po párování odstraňte odkaz z historie schránky.',
              ),
            ),
            if (_copied || _failed)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _failed
                        ? s.text(
                            'Copy failed. Check clipboard access and retry.',
                            'Kopírování selhalo. Zkontrolujte přístup ke schránce a zkuste to znovu.',
                          )
                        : s.text(
                            'Pairing link copied.',
                            'Párovací odkaz zkopírován.',
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        WakeButton(
          subtle: true,
          onPressed: () => Navigator.pop(context),
          label: Text(s.text('Close', 'Zavřít')),
        ),
        WakeButton(
          primary: true,
          onPressed: _copy,
          icon: const Icon(Icons.copy_rounded),
          label: Text(s.text('Copy link', 'Kopírovat odkaz')),
        ),
      ],
    );
  }
}
