import 'package:campus_pass/home_screen_widgets.dart';
import 'package:campus_pass/widget_settings.dart';
import 'package:campus_pass/widget_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeWidgets extends HomeScreenWidgets {
  FakeWidgets(this.platform);
  final String platform;
  bool overlay = false;
  WidgetAppearance appearance = const WidgetAppearance();
  int appearanceWrites = 0;
  final actions = <String>[];

  @override
  Future<WidgetCapabilities> capabilities() async => WidgetCapabilities(
    platform: platform,
    supported: true,
    pinSupported: platform == 'android',
    overlayAllowed: overlay,
  );
  @override
  Future<WidgetPass?> read() async => null;
  @override
  Future<WidgetAppearance> readAppearance() async => appearance;
  @override
  Future<void> saveAppearance(WidgetAppearance value) async {
    appearance = value;
    appearanceWrites++;
  }

  @override
  Future<void> requestOverlayPermission() async {
    actions.add('permission');
    overlay = true;
  }

  @override
  Future<bool> requestPin() async {
    actions.add('pin');
    return true;
  }
}

void main() {
  testWidgets(
    'Android requests overlay access before offering widget pinning',
    (tester) async {
      final widgets = FakeWidgets('android');
      var synced = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeWidgetSettings(
            widgets: widgets,
            onSync: () async {
              synced++;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Разрешить показ поверх экрана'));
      await tester.pumpAndSettle();
      expect(widgets.actions, ['permission']);
      expect(synced, 0);
      await tester.tap(find.text('Добавить виджет'));
      await tester.pumpAndSettle();
      expect(widgets.actions, ['permission', 'pin']);
      expect(synced, 1);
    },
  );

  testWidgets('iOS explains widget taps and syncs without asking to pin', (
    tester,
  ) async {
    final widgets = FakeWidgets('ios');
    await tester.pumpWidget(
      MaterialApp(
        home: HomeWidgetSettings(widgets: widgets, onSync: () async => true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('показать QR на весь экран'), findsOneWidget);
    await tester.tap(find.text('Обновить виджет'));
    await tester.pumpAndSettle();
    expect(widgets.actions, isEmpty);
    expect(find.text('Содержимое виджета обновлено'), findsOneWidget);
  });

  testWidgets('widget setup fits a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.4)),
          child: child!,
        ),
        home: HomeWidgetSettings(
          widgets: FakeWidgets('android'),
          onSync: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Разрешить показ поверх экрана'), findsOneWidget);
  });

  testWidgets(
    'switching widget content and colors saves appearance without requesting a pass',
    (tester) async {
      final widgets = FakeWidgets('ios');
      var synced = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeWidgetSettings(
            widgets: widgets,
            onSync: () async {
              synced++;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(widgets.appearance.content, WidgetContent.logo);
      expect(widgets.appearance.background, Colors.black);
      expect(find.bySemanticsLabel('Логотип School 21'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.text('QR-код')),
        alignment: .25,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('QR-код'));
      await tester.pumpAndSettle();
      expect(widgets.appearance.content, WidgetContent.qr);
      expect(find.text('Цвет QR-кода'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.text('Цвет фона')),
        alignment: .25,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Цвет фона'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Белый'));
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();
      expect(widgets.appearance.background, Colors.white);
      expect(widgets.appearanceWrites, 2);
      expect(synced, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: HomeWidgetSettings(widgets: widgets, onSync: () async => true),
        ),
      );
      await tester.pumpAndSettle();
      expect(widgets.appearance.background, Colors.white);
      await tester.scrollUntilVisible(
        find.text('Цвет QR-кода'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Цвет QR-кода'), findsOneWidget);
    },
  );
}
