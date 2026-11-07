import 'dart:convert';

import 'package:campus_pass/pass_appearance.dart';
import 'package:campus_pass/pass_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget settings(
  PassAppearance appearance,
  ValueChanged<PassAppearance> onChanged, {
  double textScale = 1,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: true,
      textScaler: TextScaler.linear(textScale),
    ),
    child: child!,
  ),
  home: PassSettings(appearance: appearance, onChanged: onChanged),
);

void main() {
  test(
    'the old plain background keeps following the menu theme after saving',
    () {
      final data = jsonDecode(
        const PassAppearance(
          theme: ThemeMode.dark,
          backdrop: PassBackdrop.plain,
        ).encode(),
      ) as Map<String, dynamic>;
      data['version'] = 4;
      final migrated = PassAppearance.decode(jsonEncode(data));
      final restored = PassAppearance.decode(migrated.encode());
      expect(restored.backdrop, PassBackdrop.solid);
      expect(restored.ambientUseCustomBase, isFalse);
      expect(
        restored.backgroundFor(const Color(0xff17191e)),
        const Color(0xff17191e),
      );
    },
  );

  test('migrates disabled motion without losing colors or the theme', () {
    final data = jsonDecode(
      const PassAppearance(
        theme: ThemeMode.dark,
        background: Colors.black,
        accent: Colors.green,
        ambientColors: [Colors.green, Colors.black],
      ).encode(),
    ) as Map<String, dynamic>;
    data['version'] = 4;
    data.remove('ambientIntensity');
    data['ambientMotion'] = false;
    final migrated = PassAppearance.decode(jsonEncode(data));
    expect(migrated.ambientIntensity, 0);
    expect(migrated.ambientMotion, isFalse);
    expect(migrated.ambientColors, [const Color(0xff4caf50), Colors.black]);
    expect(migrated.theme, ThemeMode.dark);
    expect(migrated.accent, const Color(0xff4caf50));
  });

  testWidgets(
    'color edits keep the selected mode and switching preserves the palette',
    (tester) async {
      var appearance = const PassAppearance();
      await tester.pumpWidget(settings(appearance, (v) => appearance = v));
      expect(find.text('Интенсивность движения'), findsOneWidget);
      await tester.tap(find.text('Сплошной цвет'));
      await tester.pumpAndSettle();
      expect(find.text('Интенсивность движения'), findsNothing);
      expect(find.text('Цвета свечения'), findsNothing);
      expect(appearance.backdrop, PassBackdrop.solid);

      await tester.ensureVisible(find.text('Цвет фона'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Цвет фона'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Чёрный'));
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();
      expect(appearance.backdrop, PassBackdrop.solid);
      expect(appearance.background, Colors.black);

      await tester.ensureVisible(find.text('Свечение'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Свечение'));
      await tester.pumpAndSettle();
      expect(appearance.backdrop, PassBackdrop.ambient);
      expect(appearance.background, Colors.black);
      expect(appearance.ambientColors, PassAppearance.defaultAmbientColors);

      await tester.ensureVisible(find.text('Цвет фона'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Цвет фона'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Белый'));
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();
      expect(appearance.backdrop, PassBackdrop.ambient);
      expect(appearance.background, Colors.white);

      await tester.ensureVisible(find.text('Цвет акцента'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Цвет акцента'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Тёмно-зелёный'));
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();
      expect(appearance.accent, const Color(0xff0a5e2a));
      expect(appearance.background, Colors.white);
      expect(appearance.backdrop, PassBackdrop.ambient);

      await tester.ensureVisible(find.text('Показывать срок действия'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Показывать срок действия'));
      await tester.pumpAndSettle();
      final restored = PassAppearance.decode(appearance.encode());
      expect(restored.showExpiry, isFalse);
      expect(restored.background, Colors.white);
      expect(restored.accent, const Color(0xff0a5e2a));
    },
  );

  testWidgets('motion slider saves the final value and can stop animation', (
    tester,
  ) async {
    var appearance = const PassAppearance();
    var writes = 0;
    await tester.pumpWidget(
      settings(appearance, (v) {
        appearance = v;
        writes++;
      }),
    );
    final slider = find.byKey(const ValueKey('ambient-intensity'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(appearance.ambientIntensity, 0);
    expect(appearance.ambientMotion, isFalse);
    expect(writes, 1);
    expect(PassAppearance.decode(appearance.encode()).ambientIntensity, 0);
  });

  testWidgets('both modes fit a narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      settings(const PassAppearance(), (_) {}, textScale: 1.4),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Тема меню'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Сплошной цвет'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сплошной цвет'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Тема меню'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
