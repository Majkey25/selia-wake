import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/protocol.dart';
import '../core/relay.dart';
import '../core/settings.dart';
import 'strings.dart';
import 'setup_guide.dart';

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
  late final TextEditingController _name;
  late final TextEditingController _mac;
  late final TextEditingController _broadcast;
  late final TextEditingController _lan;
  late final TextEditingController _host;
  final _pairing = TextEditingController();
  Pairing? _pendingPairing;
  bool _saving = false;
  bool _detecting = false;
  bool _scanning = false;
  String? _error;
  String? _networkNote;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial.copy();
    _name = TextEditingController(text: _draft.targetName);
    _mac = TextEditingController(text: _draft.mac);
    _broadcast = TextEditingController(text: _draft.broadcast);
    _lan = TextEditingController(text: _draft.lanIp);
    _host = TextEditingController(text: _draft.wakerHost);
  }

  @override
  void dispose() {
    for (final controller in [_name, _mac, _broadcast, _lan, _host, _pairing]) {
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
      ..wakerHost = _host.text.trim();
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
      if (close) Navigator.of(context).pop();
      return true;
    } catch (_) {
      if (mounted) setState(() => _error = s.saveError);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
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
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      readOnly: _saving,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorMaxLines: 4,
      ),
      validator: validator,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      enableSuggestions: false,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isWaker = _draft.role == DeviceRole.waker;
    return PopScope(
      canPop: !_saving && !_scanning,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.settings),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    _select<DeviceRole>(
                      s.text('Mode', 'Režim'),
                      DeviceRole.values,
                      _draft.role,
                      (role) => role == DeviceRole.waker ? s.waker : s.user,
                      (role) => setState(() => _draft.role = role),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isWaker
                          ? s.localHelp
                          : s.text(
                              'Paste a pairing link from your Waker. Connect Tailscale on both devices.',
                              'Vložte párovací odkaz z budiče. Připojte Tailscale na obou zařízeních.',
                            ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    if (isWaker) ...[
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
                      ),
                      const SizedBox(height: 12),
                      Text(switch (_draft.connection) {
                        TargetConnection.ethernet => s.text(
                          'Connect the computer to the router by Ethernet. Enter the Ethernet adapter’s MAC below.',
                          'Připojte počítač Ethernetem k routeru. Níže zadejte MAC ethernetového adaptéru.',
                        ),
                        TargetConnection.wifi => s.text(
                          'Requires Wake on Wireless LAN support in the computer, firmware, and driver. Enter the Wi-Fi adapter’s MAC. A Wi-Fi connection alone is not enough.',
                          'Počítač, firmware a ovladač musí podporovat Wake on Wireless LAN. Zadejte MAC Wi-Fi adaptéru. Samotné připojení k Wi-Fi nestačí.',
                        ),
                        TargetConnection.usbEthernet => s.text(
                          'Requires a powered USB Ethernet adapter with Wake-on-LAN support and an Ethernet cable. A phone charging cable cannot send this wake signal.',
                          'Vyžaduje napájený USB Ethernet adaptér s podporou Wake-on-LAN a ethernetový kabel. Nabíjecí kabel telefonu tento probouzecí signál neposílá.',
                        ),
                      }, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 20),
                      _field(
                        _name,
                        s.name,
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
                        child: OutlinedButton.icon(
                          onPressed: _saving || _detecting ? null : _detect,
                          icon: _detecting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.radar_rounded),
                          label: Text(s.text('Detect network', 'Zjistit síť')),
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
                        s.tailscaleHelp,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ] else ...[
                      if (_draft.pairing case final paired?) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.link_rounded),
                          title: Text(paired.name),
                          subtitle: Text(paired.host),
                          trailing: IconButton(
                            tooltip: s.text(
                              'Forget pairing',
                              'Zapomenout párování',
                            ),
                            onPressed: _saving
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
                      TextFormField(
                        controller: _pairing,
                        onChanged: (_) =>
                            setState(() => _pendingPairing = null),
                        readOnly: _saving,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        decoration: InputDecoration(
                          labelText: s.pairing,
                          hintText: 'seliawake://pair?data=…',
                          errorMaxLines: 4,
                          suffixIcon: IconButton(
                            tooltip: s.text(
                              'Paste pairing link',
                              'Vložit párovací odkaz',
                            ),
                            onPressed: _saving ? null : _paste,
                            icon: const Icon(Icons.content_paste_rounded),
                          ),
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
                        OutlinedButton.icon(
                          onPressed: _saving || _scanning ? null : _scan,
                          icon: const Icon(Icons.qr_code_scanner, size: 18),
                          label: Text(s.text('Scan QR code', 'Načíst QR kód')),
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
                    _select<WakeTheme>(
                      s.text('Theme', 'Motiv'),
                      WakeTheme.values,
                      _draft.theme,
                      (theme) => switch (theme) {
                        WakeTheme.material => 'Material You',
                        WakeTheme.matrix => 'Matrix',
                        WakeTheme.terminal => 'Terminal',
                      },
                      (theme) => setState(() => _draft.theme = theme),
                    ),
                    if (_draft.theme != WakeTheme.matrix) ...[
                      const SizedBox(height: 16),
                      _select<ThemeMode>(
                        s.text('Appearance', 'Barevný režim'),
                        ThemeMode.values,
                        _draft.appearance,
                        (mode) => switch (mode) {
                          ThemeMode.system => s.text('System', 'Systém'),
                          ThemeMode.light => s.text('Light', 'Světlý'),
                          ThemeMode.dark => s.text('Dark', 'Tmavý'),
                        },
                        (mode) => setState(() => _draft.appearance = mode),
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
                      (language) => setState(() => _draft.language = language),
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
                    FilledButton.icon(
                      onPressed: _saving || _detecting || _scanning
                          ? null
                          : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(s.text('Save settings', 'Uložit nastavení')),
                    ),
                    if (isWaker) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _saving || _detecting || _scanning
                            ? null
                            : _share,
                        icon: const Icon(Icons.ios_share_rounded),
                        label: Text(
                          s.text('Pairing link / QR', 'Párovací odkaz / QR'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _saving || _scanning
                          ? null
                          : () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => const SetupGuide(),
                              ),
                            ),
                      child: Text(
                        s.text(
                          'Tailscale & pairing guide',
                          'Tailscale a párování: návod',
                        ),
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

  Widget _select<T>(
    String title,
    List<T> values,
    T selected,
    String Function(T) label,
    ValueChanged<T> change,
  ) => DropdownButtonFormField<T>(
    initialValue: selected,
    isExpanded: true,
    decoration: InputDecoration(labelText: title),
    items: [
      for (final value in values)
        DropdownMenuItem(value: value, child: Text(label(value))),
    ],
    onChanged: _saving
        ? null
        : (value) {
            if (value != null) change(value);
          },
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
    return AlertDialog(
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
              child: SizedBox(
                width: 260,
                child: AspectRatio(
                  aspectRatio: 1,
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.text('Close', 'Zavřít')),
        ),
        FilledButton.icon(
          onPressed: _copy,
          icon: const Icon(Icons.copy_rounded),
          label: Text(s.text('Copy link', 'Kopírovat odkaz')),
        ),
      ],
    );
  }
}
