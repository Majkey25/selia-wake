import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seliawake/core/protocol.dart';
import 'package:seliawake/core/settings.dart';
import 'package:seliawake/ui/home.dart';
import 'package:seliawake/ui/theme.dart';

void main() {
  testWidgets(
    'all themes keep the wake action visible on a small Czech screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final theme in WakeTheme.values) {
        for (final brightness in Brightness.values) {
          final settings = Settings(
            wakerKey: randomKey(),
            theme: theme,
            motion: false,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: wakeTheme(theme, brightness, null),
              locale: const Locale('cs'),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('en'), Locale('cs')],
              home: WakeHome(settings: settings, save: (_) async {}),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Probudit'), findsOneWidget);
          expect(find.byTooltip('Nastavení'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$theme $brightness');
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );
}
