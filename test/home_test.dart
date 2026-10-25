import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:seliawake/core/protocol.dart';
import 'package:seliawake/core/relay.dart';
import 'package:seliawake/core/settings.dart';
import 'package:seliawake/core/sleeper.dart';
import 'package:seliawake/ui/home.dart';
import 'package:seliawake/ui/controls.dart';
import 'package:seliawake/ui/settings_page.dart';
import 'package:seliawake/ui/strings.dart';
import 'package:seliawake/ui/sleeper_page.dart';
import 'package:seliawake/ui/theme.dart';

void main() {
  Widget app(
    Settings settings, {
    Future<void> Function(Settings)? save,
    Locale locale = const Locale('en'),
    double textScale = 1,
    Widget? home,
  }) => MaterialApp(
    theme: wakeTheme(
      settings.theme,
      Brightness.light,
      null,
      custom: settings.customTheme,
    ),
    builder: (context, child) => wakePlatformBuilder(
      context,
      MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
    locale: locale,
    localizationsDelegates: const [
      ...GlobalMaterialLocalizations.delegates,
      fluent.FluentLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('cs')],
    home: home ?? WakeHome(settings: settings, save: save ?? (_) async {}),
  );

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      250,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    await tester.pumpAndSettle();
  }

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      '$platform keeps large custom text reachable on a narrow screen',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final initial = Settings(
          wakerKey: randomKey(),
          theme: WakeTheme.custom,
          customTheme: CustomTheme(fontSize: 24, radius: 32, borderWidth: 3),
        );
        await tester.pumpWidget(app(initial, textScale: 2));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Wake'));
        expect(find.text('Wake').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Save settings').hitTestable(), findsOneWidget);
        for (final style in WakeTheme.values) {
          final label = find.text(const Strings(false).themeName(style));
          await reveal(tester, label);
          expect(label.hitTestable(), findsOneWidget);
        }
        await reveal(tester, find.text('Save settings'));
        expect(find.text('Save settings').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      '$platform theme previews select a draft and persist only after Save',
      (tester) async {
        final semantics = tester.ensureSemantics();
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        FlutterSecureStorage.setMockInitialValues({});
        final store = SettingsStore();
        final initial = Settings(
          wakerKey: randomKey(),
          appearance: ThemeMode.dark,
          customTheme: CustomTheme(accent: 0xFFAA5533, fontFamily: 'Consolas'),
        );
        await store.save(initial);
        await tester.pumpWidget(app(initial, save: store.save));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        final mode = find.byType(WakeSelect<ThemeMode>);
        await reveal(tester, mode);
        await tester.tap(mode);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Light').last);
        await tester.pumpAndSettle();
        for (final style in WakeTheme.values) {
          final preview = find.byKey(ValueKey('theme-preview-${style.name}'));
          await reveal(tester, preview);
          await tester.tap(
            find.descendant(
              of: preview,
              matching: find.text(const Strings(false).themeName(style)),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(preview).flagsCollection.isSelected,
            Tristate.isTrue,
          );
          final sample = find.descendant(
            of: preview,
            matching: find.text('Selia Wake'),
          );
          final expected = wakeTheme(
            style,
            Brightness.light,
            null,
            custom: initial.customTheme,
          );
          expect(
            Theme.of(tester.element(sample)).colorScheme,
            expected.colorScheme,
          );
          expect(
            tester.widget<Text>(sample).style?.fontFamily,
            expected.textTheme.bodyMedium?.fontFamily,
          );
          expect(initial.theme, WakeTheme.platform);
          expect((await store.load()).theme, WakeTheme.platform);
          expect((await store.load()).appearance, ThemeMode.dark);
        }
        await tester.tap(find.byTooltip('Save settings'));
        await tester.pumpAndSettle();
        final restored = await store.load();
        expect(restored.theme, WakeTheme.custom);
        expect(restored.appearance, ThemeMode.light);
        expect(restored.customTheme.accent, initial.customTheme.accent);
        expect(restored.wakerKey, initial.wakerKey);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(app(restored, save: store.save));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        final selected = find.byKey(const ValueKey('theme-preview-custom'));
        await reveal(tester, selected);
        expect(
          tester.getSemantics(selected).flagsCollection.isSelected,
          Tristate.isTrue,
        );
        semantics.dispose();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets('$platform header Save validates only the selected role', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final initial = Settings(
        wakerKey: randomKey(),
        role: DeviceRole.waker,
        mac: 'invalid-mac',
      );
      Settings? saved;
      await tester.pumpWidget(
        app(initial, save: (value) async => saved = value),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save settings'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text(const Strings(false).macError), findsOneWidget);
      final role = find.byType(WakeSelect<DeviceRole>);
      await reveal(tester, role);
      await tester.tap(role);
      await tester.pumpAndSettle();
      await tester.tap(find.text('User').last);
      await tester.pumpAndSettle();
      expect(initial.role, DeviceRole.waker);
      await tester.tap(find.byTooltip('Save settings'));
      await tester.pumpAndSettle();
      expect(saved?.role, DeviceRole.user);
      expect(saved?.mac, initial.mac);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'all themes keep the wake action visible on a small Czech $platform screen',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final theme in WakeTheme.values) {
          for (final brightness in Brightness.values) {
            final settings = Settings(wakerKey: randomKey(), theme: theme);
            await tester.pumpWidget(
              MaterialApp(
                theme: wakeTheme(theme, brightness, null),
                builder: wakePlatformBuilder,
                locale: const Locale('cs'),
                localizationsDelegates: const [
                  ...GlobalMaterialLocalizations.delegates,
                  fluent.FluentLocalizations.delegate,
                ],
                supportedLocales: const [Locale('en'), Locale('cs')],
                home: WakeHome(settings: settings, save: (_) async {}),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('Probudit').hitTestable(), findsOneWidget);
            expect(find.byTooltip('Nastavení'), findsOneWidget);
            expect(
              tester.takeException(),
              isNull,
              reason: '$theme $brightness',
            );
            await tester.pumpWidget(const SizedBox());
          }
        }
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      '$platform uses its controls and reads clipboard only after Paste',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final pairing = Pairing(
          host: '100.100.100.1',
          key: randomKey(),
          name: 'Office',
        );
        var reads = 0;
        Settings? saved;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.getData') {
              reads++;
              return {'text': pairing.encode()};
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          app(
            Settings(wakerKey: randomKey()),
            save: (value) async {
              saved = value;
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        expect(reads, 0);
        expect(find.byType(SettingsPage), findsOneWidget);
        if (platform == TargetPlatform.windows) {
          expect(find.byType(fluent.ComboBox<DeviceRole>), findsOneWidget);
          expect(find.byType(fluent.TextFormBox), findsNWidgets(3));
        } else {
          expect(
            find.byType(DropdownButtonFormField<DeviceRole>),
            findsOneWidget,
          );
        }
        await tester.tap(find.byTooltip('Paste pairing link'));
        await tester.pumpAndSettle();
        expect(reads, 1);
        expect(find.textContaining('New pairing: Office'), findsOneWidget);
        final field = tester.widget<WakeField>(find.byType(WakeField).first);
        expect(field.obscure, isTrue);
        await reveal(tester, find.text('Save settings'));
        await tester.tap(find.text('Save settings'));
        await tester.pumpAndSettle();
        expect(saved?.pairing?.key, pairing.key);
        expect(saved?.pairing?.host, pairing.host);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      '$platform exports a saved secret QR and copies only on request',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final initial = Settings(
          wakerKey: randomKey(),
          role: DeviceRole.waker,
          mac: '02:11:22:33:44:55',
          lanIp: '192.168.1.20',
          wakerHost: '100.100.100.1',
          targetName: 'Home',
        );
        Settings? saved;
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          app(
            initial,
            save: (value) async {
              saved = value;
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Pairing link / QR'));
        await tester.tap(find.text('Pairing link / QR'));
        await tester.pumpAndSettle();
        expect(saved?.wakerKey, initial.wakerKey);
        expect(copied, isNull);
        expect(
          find.textContaining('This QR code and link contain your secret key.'),
          findsOneWidget,
        );
        final qr = tester.widget<QrImageView>(find.byType(QrImageView));
        expect(qr.semanticsLabel, 'Secret pairing QR code');
        await tester.tap(find.text('Copy link'));
        await tester.pumpAndSettle();
        expect(Pairing.parse(copied!).key, initial.wakerKey);
        expect(Pairing.parse(copied!).host, initial.wakerHost);
        expect(find.text('Pairing link copied.'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  for (final custom in [false, true]) {
    testWidgets('appearance draft $custom requires Save before pair or test', (
      tester,
    ) async {
      final initial = Settings(
        wakerKey: randomKey(),
        role: DeviceRole.waker,
        theme: custom ? WakeTheme.custom : WakeTheme.platform,
        mac: '02:11:22:33:44:55',
        wakerHost: '100.100.100.1',
        lanIp: '192.168.1.20',
      );
      Settings? saved;
      final relay = _TestRelay();
      await tester.pumpWidget(
        app(
          initial,
          home: SettingsPage(
            initial: initial,
            relay: relay,
            save: (value) async => saved = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (custom) {
        final accent = find.byWidgetPredicate(
          (w) => w is WakeField && w.label == 'Accent',
        );
        await reveal(tester, accent);
        await tester.enterText(
          find.descendant(of: accent, matching: find.byType(EditableText)),
          '#12AB34',
        );
      } else {
        final preview = find.byKey(const ValueKey('theme-preview-matrix'));
        await reveal(tester, preview);
        await tester.tap(preview);
      }
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Pairing link / QR'));
      for (final label in ['Pairing link / QR', 'Send local test packet']) {
        final button = tester.widget<WakeButton>(
          find.widgetWithText(WakeButton, label),
        );
        expect(button.onPressed, isNull);
      }
      expect(saved, isNull);
      expect(relay.sent, isNull);
      await tester.tap(find.byTooltip('Save settings'));
      await tester.pumpAndSettle();
      if (custom) {
        expect(saved?.customTheme.accent, 0xFF12AB34);
        expect(initial.customTheme.accent, 0xFF3584E4);
      } else {
        expect(saved?.theme, WakeTheme.matrix);
        expect(initial.theme, WakeTheme.platform);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Waker imports only after Paste and saves the reviewed target', (
    tester,
  ) async {
    final setup = TargetSetup(
      name: 'Sleeping PC',
      mac: '02:11:22:33:44:66',
      broadcast: '192.168.2.255',
      connection: TargetConnection.wifi,
      targetHost: '100.100.100.2',
      targetPort: 22,
    );
    final initial = Settings(wakerKey: randomKey(), role: DeviceRole.waker);
    Settings? saved;
    var reads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          reads++;
          return {'text': setup.encode()};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(app(initial, save: (value) async => saved = value));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(reads, 0);
    final role = tester.widget<WakeSelect<DeviceRole>>(
      find.byType(WakeSelect<DeviceRole>),
    );
    expect(role.values.contains(DeviceRole.sleeper), Sleeper.supported);
    expect(role.itemLabel(DeviceRole.sleeper), 'The Sleeper');
    await tester.tap(find.text('Paste Sleeper setup'));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(saved, isNull);
    expect(initial.mac, isEmpty);
    expect(
      find.textContaining('Preview: Sleeping PC\nMAC: 02:11:22:33:44:66'),
      findsOneWidget,
    );
    await reveal(tester, find.text('Save settings'));
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(saved?.targetName, setup.name);
    expect(saved?.mac, setup.mac);
    expect(saved?.broadcast, setup.broadcast);
    expect(saved?.connection, setup.connection);
    expect(saved?.targetHost, setup.targetHost);
    expect(saved?.targetPort, setup.targetPort);
    expect(saved?.wakerKey, initial.wakerKey);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Waker rejects a pairing link as a Sleeper target', (
    tester,
  ) async {
    final initial = Settings(wakerKey: randomKey(), role: DeviceRole.waker);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? {
              'text': Pairing(
                host: '100.100.100.1',
                key: randomKey(),
                name: 'Waker',
              ).encode(),
            }
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(app(initial));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste Sleeper setup'));
    await tester.pumpAndSettle();
    await reveal(tester, find.textContaining('Invalid Sleeper setup.'));
    expect(find.textContaining('Invalid Sleeper setup.'), findsOneWidget);
    expect(initial.mac, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('import requires explicit Save before sharing or local testing', (
    tester,
  ) async {
    final setup = TargetSetup(
      name: 'Imported PC',
      mac: '02:11:22:33:44:66',
      broadcast: '192.168.2.255',
      connection: TargetConnection.ethernet,
    );
    final initial = Settings(
      wakerKey: randomKey(),
      role: DeviceRole.waker,
      wakerHost: '100.100.100.1',
    );
    final relay = _TestRelay();
    var reads = 0;
    var saves = 0;
    Settings? saved;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          reads++;
          return {'text': setup.encode()};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      app(
        initial,
        home: Builder(
          builder: (context) => Scaffold(
            body: WakeButton(
              label: const Text('Open settings'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    initial: saved ?? initial,
                    relay: relay,
                    save: (value) async {
                      saves++;
                      saved = value;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(reads, 0);
    final shareBeforeImport = tester
        .widget<WakeButton>(
          find.widgetWithText(WakeButton, 'Pairing link / QR'),
        )
        .onPressed!;
    final testBeforeImport = tester
        .widget<WakeButton>(
          find.widgetWithText(WakeButton, 'Send local test packet'),
        )
        .onPressed!;
    await tester.tap(find.text('Paste Sleeper setup'));
    await tester.pumpAndSettle();
    expect(reads, 1);
    for (final action in ['Pairing link / QR', 'Send local test packet']) {
      await reveal(tester, find.text(action));
      expect(
        tester
            .widget<WakeButton>(find.widgetWithText(WakeButton, action))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(saved, isNull);
      expect(relay.sent, isNull);
      expect(find.byType(QrImageView), findsNothing);
    }
    shareBeforeImport();
    testBeforeImport();
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(relay.sent, isNull);
    expect(
      find.text('Save settings to apply imported setup first'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Save settings'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(saved?.mac, setup.mac);
    expect(initial.mac, isEmpty);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Pairing link / QR'));
    await tester.tap(find.text('Pairing link / QR'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Send local test packet'));
    await tester.tap(find.text('Send local test packet'));
    await tester.pumpAndSettle();
    expect(relay.sent, (setup.mac, setup.broadcast, initial.lanIp));
    expect(reads, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('local test waits for save and sends only the saved values', (
    tester,
  ) async {
    final initial = Settings(
      wakerKey: randomKey(),
      role: DeviceRole.waker,
      mac: '02:11:22:33:44:55',
      broadcast: '192.168.1.255',
      lanIp: '192.168.1.20',
    );
    final saved = Completer<void>();
    final relay = _TestRelay();
    var saves = 0;
    await tester.pumpWidget(
      app(
        initial,
        home: SettingsPage(
          initial: initial,
          relay: relay,
          save: (value) async {
            saves++;
            expect(value.mac, initial.mac);
            await saved.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Send local test packet'));
    await tester.tap(find.text('Send local test packet'));
    await tester.pump();
    expect(saves, 1);
    expect(relay.sent, isNull);
    expect(
      tester
          .widget<WakeButton>(
            find.widgetWithText(WakeButton, 'Send local test packet'),
          )
          .onPressed,
      isNull,
    );
    saved.complete();
    await tester.pumpAndSettle();
    expect(relay.sent, (initial.mac, initial.broadcast, initial.lanIp));
    expect(find.text('Packet sent. Boot not confirmed.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('local test does not send when save fails', (tester) async {
    final initial = Settings(wakerKey: randomKey(), role: DeviceRole.waker);
    final relay = _TestRelay();
    await tester.pumpWidget(
      app(
        initial,
        home: SettingsPage(
          initial: initial,
          relay: relay,
          save: (_) async => throw StateError('storage_unavailable'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Send local test packet'));
    await tester.tap(find.text('Send local test packet'));
    await tester.pumpAndSettle();
    expect(relay.sent, isNull);
    await reveal(tester, find.textContaining('Settings could not be saved.'));
    expect(find.textContaining('Settings could not be saved.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Sleeper inspects without enabling and exports only on Copy', (
    tester,
  ) async {
    final initial = Settings(
      wakerKey: randomKey(),
      role: DeviceRole.sleeper,
      sleeperAdapter: 'wifi',
    );
    final sleeper = _TestSleeper();
    Settings? saved;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      app(
        initial,
        home: SleeperPage(
          settings: initial,
          sleeper: sleeper,
          save: (value) async => saved = value,
          openSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sleeper.inspections, 1);
    expect(sleeper.enabled, isNull);
    expect(saved, isNull);
    expect(copied, isNull);
    expect(
      tester.widget<WakeSelect<String>>(find.byType(WakeSelect<String>)).value,
      'wifi',
    );
    expect(
      find.textContaining('OS reports wake support: Unknown'),
      findsOneWidget,
    );
    await reveal(tester, find.text('Export target / QR'));
    await tester.tap(find.text('Export target / QR'));
    await tester.pumpAndSettle();
    expect(saved?.sleeperAdapter, 'wifi');
    expect(copied, isNull);
    expect(sleeper.enabled, isNull);
    expect(
      tester.widget<QrImageView>(find.byType(QrImageView)).semanticsLabel,
      'Sleeper target QR code',
    );
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    final setup = TargetSetup.parse(copied!);
    expect(setup.name, 'Sleeping PC');
    expect(setup.mac, '02:11:22:33:44:66');
    expect(setup.targetHost, '100.100.100.2');
    expect(setup.connection, TargetConnection.wifi);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Sleeper saves selected adapter before explicit enable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final initial = Settings(wakerKey: randomKey(), role: DeviceRole.sleeper);
    final sleeper = _TestSleeper();
    Settings? saved;
    await tester.pumpWidget(
      app(
        initial,
        locale: const Locale('cs'),
        textScale: 2,
        home: SleeperPage(
          settings: initial,
          sleeper: sleeper,
          save: (value) async => saved = value,
          openSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final select = find.byType(WakeSelect<String>);
    await reveal(tester, select);
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wi-Fi adapter').last);
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(sleeper.enabled, isNull);
    await reveal(tester, find.text('Povolit probouzení'));
    await tester.tap(find.text('Povolit probouzení'));
    await tester.pumpAndSettle();
    expect(saved?.sleeperAdapter, 'wifi');
    expect(sleeper.enabled, 'wifi');
    expect(sleeper.expectedMac, '02:11:22:33:44:66');
    expect(initial.sleeperAdapter, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Sleeper requires selection when its saved adapter is missing', (
    tester,
  ) async {
    final initial = Settings(
      wakerKey: randomKey(),
      role: DeviceRole.sleeper,
      sleeperAdapter: 'removed-adapter',
    );
    final sleeper = _TestSleeper();
    await tester.pumpWidget(
      app(
        initial,
        home: SleeperPage(
          settings: initial,
          sleeper: sleeper,
          save: (_) async => fail('Must not save an automatic replacement'),
          openSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<WakeSelect<String>>(find.byType(WakeSelect<String>)).value,
      isEmpty,
    );
    expect(find.text('Enable wake'), findsNothing);
    expect(find.text('Export target / QR'), findsNothing);
    expect(sleeper.enabled, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Sleeper does not enable wake after adapter save fails', (
    tester,
  ) async {
    final initial = Settings(wakerKey: randomKey(), role: DeviceRole.sleeper);
    final sleeper = _TestSleeper();
    await tester.pumpWidget(
      app(
        initial,
        home: SleeperPage(
          settings: initial,
          sleeper: sleeper,
          save: (_) async => throw StateError('storage_unavailable'),
          openSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Enable wake'));
    await tester.tap(find.text('Enable wake'));
    await tester.pumpAndSettle();
    expect(sleeper.enabled, isNull);
    await reveal(tester, find.textContaining('Settings could not be saved.'));
    expect(find.textContaining('Settings could not be saved.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'custom draft validates colors, saves changes, and does not alter initial settings',
    (tester) async {
      final initial = Settings(wakerKey: randomKey(), theme: WakeTheme.custom);
      Settings? saved;
      await tester.pumpWidget(
        app(
          initial,
          save: (value) async {
            saved = value;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final accent = find.byWidgetPredicate(
        (widget) => widget is WakeField && widget.label == 'Accent',
      );
      await reveal(tester, accent);
      await tester.enterText(
        find.descendant(of: accent, matching: find.byType(EditableText)),
        '#123',
      );
      await tester.tap(find.byTooltip('Save settings'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await reveal(tester, accent);
      expect(find.text('Use #RRGGBB, for example #3584E4.'), findsOneWidget);
      await tester.enterText(
        find.descendant(of: accent, matching: find.byType(EditableText)),
        '#12AB34',
      );
      final radius = find.byWidgetPredicate(
        (widget) => widget is WakeField && widget.label == 'Corner radius',
      );
      await reveal(tester, radius);
      await tester.enterText(
        find.descendant(of: radius, matching: find.byType(EditableText)),
        '18',
      );
      expect(initial.customTheme.accent, 0xFF3584E4);
      expect(initial.customTheme.radius, 6);
      await tester.tap(find.byTooltip('Save settings'));
      await tester.pumpAndSettle();
      expect(saved?.customTheme.accent, 0xFF12AB34);
      expect(saved?.customTheme.radius, 18);
      expect(saved?.wakerKey, initial.wakerKey);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('save failure keeps settings open and pairing unmodified', (
    tester,
  ) async {
    final initial = Settings(
      wakerKey: randomKey(),
      pairing: Pairing(host: '100.100.100.1', key: randomKey(), name: 'Home'),
    );
    await tester.pumpWidget(
      app(initial, save: (_) async => throw StateError('storage_unavailable')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Forget pairing'));
    await reveal(tester, find.text('Save settings'));
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.textContaining('Settings could not be saved.'), findsOneWidget);
    expect(initial.pairing?.name, 'Home');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _TestRelay extends Relay {
  (String, String, String)? sent;

  @override
  Future<void> sendLocal(
    String mac,
    String broadcast, {
    String lanIp = '',
  }) async {
    sent = (mac, broadcast, lanIp);
  }
}

class _TestSleeper extends Sleeper {
  int inspections = 0;
  String? enabled;
  String? expectedMac;

  final report = SleeperReport(
    machineName: 'Sleeping PC',
    sleepStates: 'S3',
    tailscaleIp: '100.100.100.2',
    adapters: [
      SleeperAdapter(
        id: 'ethernet',
        name: 'Ethernet adapter',
        description: 'Ethernet',
        mac: '02:11:22:33:44:55',
        ip: '192.168.1.2',
        broadcast: '192.168.1.255',
        connection: TargetConnection.ethernet,
        wakeEnabled: false,
        magicPacketEnabled: false,
        supportsWake: true,
        detail: 'OS report',
      ),
      SleeperAdapter(
        id: 'wifi',
        name: 'Wi-Fi adapter',
        description: 'Wireless',
        mac: '02:11:22:33:44:66',
        ip: '192.168.2.2',
        broadcast: '192.168.2.255',
        connection: TargetConnection.wifi,
        wakeEnabled: null,
        magicPacketEnabled: null,
        supportsWake: null,
        detail: 'OS report',
      ),
    ],
  );

  @override
  Future<SleeperReport> inspect() async {
    inspections++;
    return report;
  }

  @override
  Future<SleeperReport> enableWake(
    String adapterId, {
    required String expectedMac,
  }) async {
    enabled = adapterId;
    this.expectedMac = expectedMac;
    return report;
  }
}
