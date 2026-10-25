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

  Future<void> autosave(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is WakeField && widget.label == label,
  );

  Future<void> edit(WidgetTester tester, String label, String value) async {
    final target = field(label);
    await reveal(tester, target);
    await tester.enterText(
      find.descendant(of: target, matching: find.byType(EditableText)),
      value,
    );
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
        expect(find.byTooltip('Save settings'), findsNothing);
        expect(find.byTooltip('Revert changes'), findsNothing);
        for (final style in WakeTheme.values) {
          final label = find.text(const Strings(false).themeName(style));
          await reveal(tester, label);
          expect(label.hitTestable(), findsOneWidget);
        }
        await reveal(tester, find.text('Reset defaults'));
        expect(find.text('Reset defaults').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      '$platform theme previews automatically persist valid appearance changes',
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
        await autosave(tester);
        expect(find.byTooltip('Revert changes'), findsNothing);
        expect(find.text('Save settings'), findsNothing);
        expect((await store.load()).appearance, ThemeMode.dark);
        final mode = find.byType(WakeSelect<ThemeMode>);
        await reveal(tester, mode);
        await tester.tap(mode);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Light').last);
        await autosave(tester);
        expect((await store.load()).appearance, ThemeMode.light);
        for (final style in WakeTheme.values) {
          final preview = find.byKey(ValueKey('theme-preview-${style.name}'));
          await reveal(tester, preview);
          await tester.tap(
            find.descendant(
              of: preview,
              matching: find.text(const Strings(false).themeName(style)),
            ),
          );
          await autosave(tester);
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
          expect((await store.load()).theme, style);
          expect((await store.load()).appearance, ThemeMode.light);
        }
        expect(find.byType(SettingsPage), findsOneWidget);
        expect(find.byTooltip('Revert changes'), findsOneWidget);
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

    testWidgets('$platform autosave validates only the selected role', (
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
      await edit(tester, const Strings(false).name, 'Updated PC');
      await autosave(tester);
      expect(saved, isNull);
      await reveal(tester, field('MAC'));
      expect(find.text(const Strings(false).macError), findsOneWidget);
      final role = find.byType(WakeSelect<DeviceRole>);
      await reveal(tester, role);
      await tester.tap(role);
      await tester.pumpAndSettle();
      await tester.tap(find.text('User').last);
      await autosave(tester);
      expect(initial.role, DeviceRole.waker);
      expect(saved?.role, DeviceRole.user);
      expect(saved?.mac, initial.mac);
      saved = null;
      await edit(tester, const Strings(false).pairing, 'invalid-pairing');
      await autosave(tester);
      expect(saved, isNull);
      expect(initial.pairing, isNull);
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
        await autosave(tester);
        expect(reads, 1);
        final field = tester.widget<WakeField>(find.byType(WakeField).first);
        expect(field.obscure, isTrue);
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
        await edit(tester, const Strings(false).name, 'Updated Home');
        await autosave(tester);
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
        expect(Pairing.parse(copied!).name, 'Updated Home');
        expect(find.text('Pairing link copied.'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('opening settings does not save or offer Revert', (tester) async {
    final initial = Settings(wakerKey: randomKey());
    await tester.pumpWidget(
      app(initial, save: (_) async => fail('Opening settings must not save')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await autosave(tester);
    expect(find.text(const Strings(false).autoSaveHelp), findsOneWidget);
    expect(find.byTooltip('Revert changes'), findsNothing);
    expect(find.text('Revert changes'), findsNothing);
    expect(find.text('Save settings'), findsNothing);
    expect(find.byTooltip('Save settings'), findsNothing);
    expect(find.text('Reset custom theme'), findsNothing);
    await reveal(tester, find.text('Reset defaults'));
    expect(find.widgetWithText(WakeButton, 'Reset defaults'), findsOneWidget);
    expect(find.text(const Strings(false).resetDefaultsHelp), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Revert restores the opening snapshot and invalid custom text', (
    tester,
  ) async {
    final initial = Settings(
      wakerKey: randomKey(),
      role: DeviceRole.waker,
      theme: WakeTheme.custom,
      customTheme: CustomTheme(accent: 0xFFAA5533, radius: 18),
      targetName: 'Original PC',
      mac: '02:11:22:33:44:55',
      lanIp: '192.168.1.20',
      wakerHost: '100.100.100.1',
      pairing: Pairing(host: '100.100.100.3', key: randomKey(), name: 'Office'),
    );
    Settings? saved;
    await tester.pumpWidget(
      app(
        initial,
        home: SettingsPage(
          initial: initial,
          relay: _TestRelay(),
          save: (value) async => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await edit(tester, const Strings(false).name, 'Changed PC');
    await autosave(tester);
    expect(saved?.targetName, 'Changed PC');
    await edit(tester, 'Accent', '#12AB34');
    await autosave(tester);
    expect(saved?.customTheme.accent, 0xFF12AB34);
    expect(find.text('Revert changes'), findsOneWidget);
    await edit(tester, 'Accent', '#123');
    await autosave(tester);
    expect(saved?.customTheme.accent, 0xFF12AB34);
    await tester.tap(find.byTooltip('Revert changes'));
    await autosave(tester);
    expect(saved?.toJson(), initial.toJson());
    expect(saved?.wakerKey, initial.wakerKey);
    expect(saved?.pairing?.key, initial.pairing?.key);
    expect(find.byTooltip('Revert changes'), findsNothing);
    expect(find.text('Revert changes'), findsNothing);
    await reveal(tester, field(const Strings(false).name));
    expect(
      tester
          .widget<WakeField>(field(const Strings(false).name))
          .controller
          ?.text,
      'Original PC',
    );
    await reveal(tester, field('Accent'));
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: field('Accent'),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      '#AA5533',
    );
    expect(initial.targetName, 'Original PC');
    expect(initial.customTheme.accent, 0xFFAA5533);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Reset defaults clears connection, rotates the key, and can Revert',
    (tester) async {
      final initial = Settings(
        wakerKey: randomKey(),
        role: DeviceRole.waker,
        connection: TargetConnection.wifi,
        theme: WakeTheme.custom,
        customTheme: CustomTheme(accent: 0xFFAA5533, radius: 18),
        appearance: ThemeMode.dark,
        language: 'en',
        targetName: 'Original PC',
        mac: '02:11:22:33:44:55',
        broadcast: '192.168.1.255',
        lanIp: '192.168.1.20',
        wakerHost: '100.100.100.1',
        targetHost: '100.100.100.2',
        targetPort: 22,
        sleeperAdapter: 'wifi',
        pairing: Pairing(
          host: '100.100.100.3',
          key: randomKey(),
          name: 'Office',
        ),
      );
      final original = initial.copy();
      final relay = _TestRelay();
      Settings? saved;
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
      await reveal(tester, find.text('Reset defaults'));
      expect(find.text(const Strings(false).resetDefaultsHelp), findsOneWidget);
      expect(find.text('Reset custom theme'), findsNothing);
      await tester.tap(find.text('Reset defaults'));
      await autosave(tester);
      expect(saved, isNotNull);
      expect(saved!.toJson(), Settings(wakerKey: saved!.wakerKey).toJson());
      decodeKey(saved!.wakerKey);
      expect(saved!.wakerKey, isNot(original.wakerKey));
      expect(saved!.pairing, isNull);
      expect(relay.sent, isNull);
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.byTooltip('Revert changes'), findsOneWidget);
      await tester.tap(find.byTooltip('Revert changes'));
      await autosave(tester);
      expect(saved!.toJson(), original.toJson());
      expect(saved!.wakerKey, original.wakerKey);
      expect(saved!.pairing?.key, original.pairing?.key);
      expect(initial.toJson(), original.toJson());
      expect(initial.wakerKey, original.wakerKey);
      expect(find.byTooltip('Revert changes'), findsNothing);
      await reveal(tester, field(const Strings(false).name));
      expect(
        tester
            .widget<WakeField>(field(const Strings(false).name))
            .controller
            ?.text,
        original.targetName,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('relay uses the latest configuration across consecutive saves', (
    tester,
  ) async {
    final initial = Settings(
      wakerKey: randomKey(),
      role: DeviceRole.waker,
      mac: '02:11:22:33:44:55',
      lanIp: '192.168.1.20',
    );
    final relay = _TestRelay();
    await tester.pumpWidget(
      app(
        initial,
        home: WakeHome(settings: initial, relay: relay, save: (_) async {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(const Strings(false).start));
    await tester.pumpAndSettle();
    expect(relay.active?.mac, initial.mac);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final save = tester.widget<SettingsPage>(find.byType(SettingsPage)).save;
    final appearance = initial.copy()..theme = WakeTheme.matrix;
    await save(appearance);
    expect(relay.starts.length, 1);
    await save(appearance.copy()..mac = '02:11:22:33:44:66');
    await save(appearance);
    expect(relay.starts.map((config) => config.mac), [
      initial.mac,
      '02:11:22:33:44:66',
      initial.mac,
    ]);
    expect(relay.active?.mac, initial.mac);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Reset defaults rejects a pending clipboard pairing result', (
    tester,
  ) async {
    final initial = Settings(wakerKey: randomKey());
    final clipboard = Completer<Map<String, Object?>>();
    final pairing = Pairing(
      host: '100.100.100.1',
      key: randomKey(),
      name: 'Old',
    );
    final writes = <Settings>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? clipboard.future : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      app(initial, save: (settings) async => writes.add(settings.copy())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Paste pairing link'));
    await tester.pump();
    await reveal(tester, find.text('Reset defaults'));
    await tester.tap(find.text('Reset defaults'));
    await autosave(tester);
    expect(writes.length, 1);
    expect(writes.single.wakerKey, isNot(initial.wakerKey));
    clipboard.complete({'text': pairing.encode()});
    await autosave(tester);
    expect(writes.length, 1);
    expect(writes.single.pairing, isNull);
    expect(find.textContaining('New pairing: Old'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('typing during a write is saved before Back leaves settings', (
    tester,
  ) async {
    final initial = Settings(wakerKey: randomKey(), role: DeviceRole.waker);
    final firstWrite = Completer<void>();
    final names = <String>[];
    await tester.pumpWidget(
      app(
        initial,
        save: (settings) async {
          names.add(settings.targetName);
          if (names.length == 1) await firstWrite.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await edit(tester, const Strings(false).name, 'First');
    await tester.pump(const Duration(milliseconds: 500));
    expect(names, ['First']);
    await tester.enterText(
      find.descendant(
        of: field(const Strings(false).name),
        matching: find.byType(EditableText),
      ),
      'Latest',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(names, ['First']);
    await tester.pageBack();
    await tester.pump();
    expect(find.byType(SettingsPage), findsOneWidget);
    firstWrite.complete();
    await tester.pumpAndSettle();
    expect(names, ['First', 'Latest']);
    expect(find.byType(SettingsPage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('back flushes the latest typing and waits for persistence', (
    tester,
  ) async {
    final initial = Settings(
      wakerKey: randomKey(),
      role: DeviceRole.waker,
      targetName: 'Original PC',
    );
    final writes = <Settings>[];
    final persisted = Completer<void>();
    await tester.pumpWidget(
      app(
        initial,
        save: (value) async {
          writes.add(value.copy());
          await persisted.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await edit(tester, const Strings(false).name, 'First edit');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.descendant(
        of: field(const Strings(false).name),
        matching: find.byType(EditableText),
      ),
      'Latest edit',
    );
    expect(writes, isEmpty);
    await tester.pageBack();
    await tester.pump();
    expect(writes.map((value) => value.targetName), ['Latest edit']);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(
      tester
          .widget<WakeSelect<DeviceRole>>(find.byType(WakeSelect<DeviceRole>))
          .onChanged,
      isNull,
    );
    expect(
      tester.widget<WakeField>(field(const Strings(false).name)).readOnly,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(writes, hasLength(1));
    persisted.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
    expect(initial.targetName, 'Original PC');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final custom in [false, true]) {
    testWidgets('appearance edit $custom auto-applies before pair or test', (
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
      await autosave(tester);
      await reveal(tester, find.text('Pairing link / QR'));
      for (final label in ['Pairing link / QR', 'Send local test packet']) {
        final button = tester.widget<WakeButton>(
          find.widgetWithText(WakeButton, label),
        );
        expect(button.onPressed, isNotNull);
      }
      expect(relay.sent, isNull);
      if (custom) {
        expect(saved?.customTheme.accent, 0xFF12AB34);
        expect(initial.customTheme.accent, 0xFF3584E4);
      } else {
        expect(saved?.theme, WakeTheme.matrix);
        expect(initial.theme, WakeTheme.platform);
      }
      await tester.tap(find.text('Pairing link / QR'));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Send local test packet'));
      await tester.tap(find.text('Send local test packet'));
      await tester.pumpAndSettle();
      expect(relay.sent, (initial.mac, initial.broadcast, initial.lanIp));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'Waker imports only after Paste and auto-applies a valid target',
    (tester) async {
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
      await tester.pumpWidget(
        app(initial, save: (value) async => saved = value),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(reads, 0);
      expect(saved, isNull);
      final role = tester.widget<WakeSelect<DeviceRole>>(
        find.byType(WakeSelect<DeviceRole>),
      );
      expect(role.values.contains(DeviceRole.sleeper), Sleeper.supported);
      expect(role.itemLabel(DeviceRole.sleeper), 'The Sleeper');
      await tester.tap(find.text('Paste Sleeper setup'));
      await autosave(tester);
      expect(reads, 1);
      expect(initial.mac, isEmpty);
      expect(saved?.targetName, setup.name);
      expect(saved?.mac, setup.mac);
      expect(saved?.broadcast, setup.broadcast);
      expect(saved?.connection, setup.connection);
      expect(saved?.targetHost, setup.targetHost);
      expect(saved?.targetPort, setup.targetPort);
      expect(saved?.wakerKey, initial.wakerKey);
      await reveal(tester, find.textContaining('Imported Sleeping PC.'));
      expect(find.textContaining('Imported Sleeping PC.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

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

  testWidgets('import auto-applies before explicit sharing or local testing', (
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
    await autosave(tester);
    expect(reads, 0);
    expect(saves, 0);
    await tester.tap(find.text('Paste Sleeper setup'));
    await autosave(tester);
    expect(reads, 1);
    expect(saves, 1);
    expect(saved?.mac, setup.mac);
    expect(initial.mac, isEmpty);
    expect(relay.sent, isNull);
    expect(find.byType(QrImageView), findsNothing);
    for (final action in ['Pairing link / QR', 'Send local test packet']) {
      await reveal(tester, find.text(action));
      expect(
        tester
            .widget<WakeButton>(find.widgetWithText(WakeButton, action))
            .onPressed,
        isNotNull,
      );
    }
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

  testWidgets('local test waits for autosave and sends only the saved values', (
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
            expect(value.mac, '02:11:22:33:44:66');
            await saved.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await edit(tester, 'MAC', '02:11:22:33:44:66');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
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
    expect(relay.sent, isNull);
    await reveal(tester, find.text('Send local test packet'));
    await tester.tap(find.text('Send local test packet'));
    await tester.pumpAndSettle();
    expect(relay.sent, ('02:11:22:33:44:66', initial.broadcast, initial.lanIp));
    expect(initial.mac, '02:11:22:33:44:55');
    expect(find.text('Packet sent. Boot not confirmed.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('local test does not send when save fails', (tester) async {
    final initial = Settings(
      wakerKey: randomKey(),
      role: DeviceRole.waker,
      mac: '02:11:22:33:44:55',
    );
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
    await edit(tester, 'MAC', '02:11:22:33:44:66');
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
    'custom edits validate colors and auto-save without mutating initial settings',
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
      await autosave(tester);
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
      await autosave(tester);
      expect(saved?.customTheme.accent, 0xFF12AB34);
      expect(saved?.customTheme.radius, 18);
      expect(saved?.wakerKey, initial.wakerKey);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'autosave failure keeps settings open, Revert, and initial pairing',
    (tester) async {
      final initial = Settings(
        wakerKey: randomKey(),
        pairing: Pairing(host: '100.100.100.1', key: randomKey(), name: 'Home'),
      );
      await tester.pumpWidget(
        app(
          initial,
          save: (_) async => throw StateError('storage_unavailable'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Forget pairing'));
      await autosave(tester);
      expect(find.byType(SettingsPage), findsOneWidget);
      await reveal(tester, find.text(const Strings(false).saveError));
      expect(find.text(const Strings(false).saveError), findsOneWidget);
      expect(find.byTooltip('Revert changes'), findsOneWidget);
      expect(initial.pairing?.name, 'Home');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text(const Strings(false).saveError), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _TestRelay extends Relay {
  (String, String, String)? sent;
  RelayConfig? active;
  final starts = <RelayConfig>[];

  @override
  Future<RelayStatus> status() async => RelayStatus(active != null);

  @override
  Future<void> start(RelayConfig config) async {
    active = config;
    starts.add(config);
  }

  @override
  Future<void> stop() async {
    active = null;
  }

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
