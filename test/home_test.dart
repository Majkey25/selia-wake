import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:seliawake/core/protocol.dart';
import 'package:seliawake/core/settings.dart';
import 'package:seliawake/ui/home.dart';
import 'package:seliawake/ui/controls.dart';
import 'package:seliawake/ui/settings_page.dart';
import 'package:seliawake/ui/theme.dart';

void main() {
  Widget app(
    Settings settings, {
    Future<void> Function(Settings)? save,
    Locale locale = const Locale('en'),
    double textScale = 1,
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
    home: WakeHome(settings: settings, save: save ?? (_) async {}),
  );

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      250,
      scrollable: find.byType(Scrollable).first,
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
        await reveal(tester, find.text('Save settings'));
        expect(find.text('Save settings').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );

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
          expect(find.byType(fluent.TextFormBox), findsOneWidget);
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
      await reveal(tester, find.text('Save settings'));
      await tester.tap(find.text('Save settings'));
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
      await reveal(tester, find.text('Save settings'));
      await tester.tap(find.text('Save settings'));
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
