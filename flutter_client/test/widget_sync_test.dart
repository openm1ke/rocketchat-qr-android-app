import 'package:campus_pass/home_screen_widgets.dart';
import 'package:campus_pass/main.dart';
import 'package:campus_pass/pass_appearance.dart';
import 'package:campus_pass/pass_repository.dart';
import 'package:campus_pass/qr_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pass_fixtures.dart';

class MemoryWidgets extends HomeScreenWidgets {
  WidgetPass? pass;
  bool fail = false;
  @override
  Future<void> publish(WidgetPass next) async {
    if (fail) throw StateError('Storage failed');
    pass = next;
  }

  @override
  Future<void> clear() async {
    pass = null;
  }
}

Future<void> showPass(
  WidgetTester tester,
  MemoryWidgets widgets, {
  PassRepository? passes,
  bool request = true,
}) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold()));
  final context = tester.element(find.byType(Scaffold));
  // Decode outside the test's fake clock, then let PassScreen load the cached
  // image normally. Its 30-second expiry timer still uses the fake clock.
  await tester.runAsync(() => precacheImage(MemoryImage(testPng), context));
  await tester.pumpWidget(
    MaterialApp(
      home: PassScreen(
        passes:
            passes ??
            PassRepository(
              client: FixturePassClient(),
              store: MemoryPassStore(),
            ),
        widgets: widgets,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (request) {
    await tester.ensureVisible(find.text('Получить QR'));
    await tester.tap(find.text('Получить QR'));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'rocketchat_token': 'test-personal-token',
      'pass_appearance_v1': const PassAppearance(
        backdrop: PassBackdrop.solid,
        haptics: false,
      ).encode(),
    });
  });

  testWidgets(
    'receiving a pass updates the widget and expiry clears both views',
    (tester) async {
      final widgets = MemoryWidgets();
      await showPass(tester, widgets);
      expect(widgets.pass?.image, testPng);
      expect(find.byType(QrTransition), findsOneWidget);
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(widgets.pass, isNull);
      expect(find.byType(QrTransition), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a widget storage error never discards a usable in-app QR', (
    tester,
  ) async {
    final widgets = MemoryWidgets()..fail = true;
    await showPass(tester, widgets);
    expect(find.byType(QrTransition), findsOneWidget);
    expect(find.text('Не удалось открыть изображение QR-кода.'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'opening never requests a QR; cached QR and pause survive a fresh screen',
    (tester) async {
      final widgets = MemoryWidgets();
      final store = MemoryPassStore();
      var now = DateTime(2026, 11, 8, 12);
      final client = FixturePassClient()
        ..expiresOn = now.add(const Duration(hours: 2));
      PassRepository repository() =>
          PassRepository(client: client, store: store, now: () => now);
      await showPass(tester, widgets, passes: repository(), request: false);
      expect(client.calls, 0);
      await tester.ensureVisible(find.text('Получить QR'));
      await tester.tap(find.text('Получить QR'));
      await tester.pumpAndSettle();
      expect(client.calls, 1);
      expect(find.text('Обновить через 30 с'), findsOneWidget);
      await showPass(tester, widgets, passes: repository(), request: false);
      expect(find.byType(QrTransition), findsOneWidget);
      final waiting = find.ancestor(
        of: find.text('Обновить через 30 с'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(tester.widget<FilledButton>(waiting).onPressed, isNull);
      expect(client.calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(client.calls, 1);
      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(client.calls, 1);
      final refresh = find.widgetWithIcon(IconButton, Icons.refresh_rounded);
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(client.calls, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'an expired cached QR is hidden on reopen until an explicit request',
    (tester) async {
      final store = MemoryPassStore();
      final client = FixturePassClient();
      var now = DateTime(2026, 11, 8, 12);
      PassRepository repository() =>
          PassRepository(client: client, store: store, now: () => now);
      await repository().request('test-personal-token');
      now = now.add(const Duration(seconds: 31));
      final widgets = MemoryWidgets();
      await showPass(tester, widgets, passes: repository(), request: false);
      expect(find.byType(QrTransition), findsNothing);
      expect(widgets.pass, isNull);
      expect(client.calls, 1);
      await tester.ensureVisible(find.text('Получить QR'));
      await tester.tap(find.text('Получить QR'));
      await tester.pumpAndSettle();
      expect(find.byType(QrTransition), findsOneWidget);
      expect(client.calls, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
