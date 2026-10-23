import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/protocol.dart';
import '../core/relay.dart';
import '../core/settings.dart';
import 'strings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.initial,
    required this.relay,
    required this.save,
    this.role,
  });
  final Settings initial;
  final Relay relay;
  final Future<void> Function(Settings) save;
  final DeviceRole? role;

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
  bool _saving = false;
  bool _detecting = false;
  String? _error;
  String? _networkNote;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial.copy();
    _draft.role = widget.role ?? _draft.role;
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
      _pairing.text = text;
      setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = s.text(
            'Clipboard unavailable. Enter the pairing link manually.',
            'Schránka není dostupná. Zadejte párovací odkaz ručně.',
          ),
        );
      }
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
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(s.settings)),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    _section(s.text('This device', 'Toto zařízení')),
                    _choices<DeviceRole>(
                      DeviceRole.values,
                      _draft.role,
                      (role) => role == DeviceRole.waker ? s.waker : s.user,
                      (role) => setState(() => _draft.role = role),
                      (role) => role == DeviceRole.waker
                          ? Icons.router_outlined
                          : Icons.touch_app_outlined,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isWaker
                          ? s.localHelp
                          : s.text(
                              'Import a link from your awake Waker, then press Wake. Both devices must be connected to Tailscale.',
                              'Načtěte odkaz ze zapnutého budiče a stiskněte Probudit. Obě zařízení musí být připojena k Tailscale.',
                            ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    if (isWaker) ...[
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
                                : () => setState(() => _draft.pairing = null),
                            icon: const Icon(Icons.link_off_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _pairing,
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
                      Text(
                        s.text(
                          'The link contains a secret. Clipboard access happens only when you press Paste.',
                          'Odkaz obsahuje tajný klíč. Schránka se čte pouze po stisknutí Vložit.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 28),
                    _section(s.text('Look & feel', 'Vzhled a chování')),
                    _choices<WakeTheme>(
                      WakeTheme.values,
                      _draft.theme,
                      (theme) => switch (theme) {
                        WakeTheme.material => 'Material You',
                        WakeTheme.glass => 'Glass',
                        WakeTheme.terminal => 'Terminal',
                      },
                      (theme) => setState(() => _draft.theme = theme),
                      (theme) => switch (theme) {
                        WakeTheme.material => Icons.palette_outlined,
                        WakeTheme.glass => Icons.blur_on_rounded,
                        WakeTheme.terminal => Icons.terminal_rounded,
                      },
                    ),
                    const SizedBox(height: 16),
                    _section(s.text('Appearance', 'Barevný režim')),
                    _choices<ThemeMode>(
                      ThemeMode.values,
                      _draft.appearance,
                      (mode) => switch (mode) {
                        ThemeMode.system => s.text('System', 'Systém'),
                        ThemeMode.light => s.text('Light', 'Světlý'),
                        ThemeMode.dark => s.text('Dark', 'Tmavý'),
                      },
                      (mode) => setState(() => _draft.appearance = mode),
                      (mode) => switch (mode) {
                        ThemeMode.system => Icons.brightness_auto_outlined,
                        ThemeMode.light => Icons.light_mode_outlined,
                        ThemeMode.dark => Icons.dark_mode_outlined,
                      },
                    ),
                    const SizedBox(height: 16),
                    _section(s.text('Language', 'Jazyk')),
                    _choices<String>(
                      const ['system', 'en', 'cs'],
                      _draft.language,
                      (language) => switch (language) {
                        'en' => 'English',
                        'cs' => 'Čeština',
                        _ => s.text('System', 'Systém'),
                      },
                      (language) => setState(() => _draft.language = language),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.text('Motion', 'Animace')),
                      subtitle: Text(
                        s.text(
                          'A brief RGB pulse on touch. Respects reduced motion.',
                          'Krátký RGB pulz při stisknutí. Respektuje omezení pohybu v systému.',
                        ),
                      ),
                      value: _draft.motion,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _draft.motion = value),
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
                      onPressed: _saving || _detecting ? null : _save,
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
                        onPressed: _saving || _detecting ? null : _share,
                        icon: const Icon(Icons.ios_share_rounded),
                        label: Text(
                          s.text(
                            'Save & share pairing',
                            'Uložit a sdílet párování',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _choices<T>(
    List<T> values,
    T selected,
    String Function(T) label,
    ValueChanged<T> change, [
    IconData Function(T)? icon,
  ]) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final value in values)
        ChoiceChip(
          label: Text(label(value)),
          avatar: icon == null ? null : Icon(icon(value), size: 18),
          selected: selected == value,
          onSelected: _saving ? null : (_) => change(value),
        ),
    ],
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
            const Icon(Icons.key_rounded),
            const SizedBox(height: 12),
            Text(
              s.text(
                'This link contains your secret key. Share it only with trusted devices. Anyone with it and tailnet access can wake this computer.',
                'Odkaz obsahuje váš tajný klíč. Sdílejte jej pouze s důvěryhodnými zařízeními. Každý s tímto odkazem a přístupem do tailnetu může počítač probudit.',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              s.text(
                'Paste the copied link in User settings on the remote device. Clear it from clipboard history after pairing.',
                'Vložte zkopírovaný odkaz do nastavení uživatele na vzdáleném zařízení. Po spárování jej odstraňte z historie schránky.',
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
