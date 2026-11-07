import 'dart:convert';

import 'package:campus_pass/pass_appearance.dart';
import 'package:campus_pass/pass_home.dart';
import 'package:campus_pass/pass_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migrates the old design while keeping scan preferences', () {
    final old = jsonDecode(
      const PassAppearance(
        qrSize: .8,
        haptics: false,
        showExpiry: false,
      ).encode(),
    ) as Map<String, dynamic>;
    old.remove('version');
    old.addAll({'theme': 'dark', 'accent': 0xff78f1bd, 'backdrop': 'gradient'});
    final migrated = PassAppearance.decode(jsonEncode(old));
    expect(migrated.theme, ThemeMode.light);
    expect(migrated.backdrop, PassBackdrop.ambient);
    expect(migrated.qrSize, .8);
    expect(migrated.haptics, false);
    expect(migrated.showExpiry, false);
  });

  testWidgets('pass stays usable on a narrow display with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var reconnected = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: passTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.4)),
          child: child!,
        ),
        home: PassHome(
          appearance: const PassAppearance(),
          loading: false,
          reconnectRequired: true,
          error: 'Подключитесь к Rocket.Chat заново.',
          onRefresh: () {},
          onConnect: () => reconnected = true,
          onSettings: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Подключиться заново'));
    await tester.tap(find.text('Подключиться заново'));
    await tester.pump();
    expect(reconnected, true);
    expect(tester.takeException(), isNull);
  });

  test('adding the ambient backdrop preserves the chosen dark theme', () {
    final old = jsonDecode(
      const PassAppearance(
        theme: ThemeMode.dark,
        backdrop: PassBackdrop.plain,
      ).encode(),
    ) as Map<String, dynamic>;
    old['version'] = 2;
    final migrated = PassAppearance.decode(jsonEncode(old));
    expect(migrated.theme, ThemeMode.dark);
    expect(migrated.backdrop, PassBackdrop.ambient);
  });

  testWidgets('cooldown disables refresh and counts down on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var now = DateTime(2026, 11, 8, 12);
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: passTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.4)),
          child: child!,
        ),
        home: PassHome(
          appearance: const PassAppearance(backdrop: PassBackdrop.solid),
          loading: false,
          qr: const SizedBox.expand(),
          nextRequestAt: now.add(const Duration(seconds: 30)),
          now: () => now,
          onRefresh: () => requests++,
          onConnect: () {},
          onSettings: () {},
        ),
      ),
    );
    final refresh = find.widgetWithIcon(IconButton, Icons.refresh_rounded);
    expect(tester.widget<IconButton>(refresh).onPressed, isNull);
    expect(find.text('Обновить через 30 с'), findsOneWidget);
    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    expect(requests, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'hides hints after three seconds but keeps errors and pass information available',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: passTheme(),
          home: PassHome(
            appearance: const PassAppearance(backdrop: PassBackdrop.plain),
            loading: false,
            qr: const SizedBox.expand(),
            expiresOn: DateTime(2026, 11, 11),
            error: 'Не удалось обновить QR. Можно повторить запрос.',
            onRefresh: () {},
            onConnect: () {},
            onSettings: () {},
          ),
        ),
      );
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
      expect(
        find.text('Не удалось обновить QR. Можно повторить запрос.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Обновить QR'), findsOneWidget);
      await tester.tap(find.byTooltip('Информация о пропуске'));
      await tester.pumpAndSettle();
      expect(find.text('О пропуске'), findsOneWidget);
      expect(find.text('До 11.11.2026'), findsWidgets);
    },
  );
}
