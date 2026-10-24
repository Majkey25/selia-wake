import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/settings.dart';
import 'ui/home.dart';
import 'ui/strings.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SeliaWakeApp());
}

class SeliaWakeApp extends StatefulWidget {
  const SeliaWakeApp({super.key});

  @override
  State<SeliaWakeApp> createState() => _SeliaWakeAppState();
}

class _SeliaWakeAppState extends State<SeliaWakeApp> {
  final _store = SettingsStore();
  Settings? _settings;
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final settings = await _store.load();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(Settings settings) async {
    await _store.save(settings);
    if (mounted) setState(() => _settings = settings);
  }

  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
    builder: (light, dark) {
      final settings = _settings;
      return MaterialApp(
        title: 'Selia Wake',
        debugShowCheckedModeBanner: false,
        theme: wakeTheme(
          settings?.theme ?? WakeTheme.terminal,
          Brightness.light,
          light,
        ),
        darkTheme: wakeTheme(
          settings?.theme ?? WakeTheme.terminal,
          Brightness.dark,
          dark,
        ),
        themeMode: settings?.appearance ?? ThemeMode.system,
        themeAnimationDuration: Duration.zero,
        locale: settings == null || settings.language == 'system'
            ? null
            : Locale(settings.language),
        supportedLocales: const [Locale('en'), Locale('cs')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: settings != null
            ? WakeHome(settings: settings, save: _save)
            : Builder(
                builder: (context) {
                  final s = Strings.of(context);
                  return Scaffold(
                    body: SafeArea(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.power_settings_new_rounded,
                                size: 52,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Selia Wake',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 24),
                              if (_loading) ...[
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  s.text(
                                    'Loading settings…',
                                    'Načítání nastavení…',
                                  ),
                                ),
                              ],
                              if (_loadFailed) ...[
                                Text(
                                  s.text(
                                    'Settings could not be loaded. Check secure storage access, then retry.',
                                    'Nastavení se nepodařilo načíst. Zkontrolujte přístup k zabezpečenému úložišti a zkuste to znovu.',
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text(s.retry),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      );
    },
  );
}
