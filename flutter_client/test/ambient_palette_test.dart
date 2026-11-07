import 'dart:convert';

import 'package:campus_pass/pass_appearance.dart';
import 'package:campus_pass/pass_settings.dart';
import 'package:campus_pass/pass_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom palette and the shared solid base survive storage', () {
    const colors = [Color(0xff99ff55), Color(0xff064d20), Color(0xff000000)];
    final settings = const PassAppearance(theme: ThemeMode.dark).copyWith(
      ambientColors: colors,
      ambientIntensity: .8,
      ambientUseCustomBase: true,
      background: Colors.black,
    );
    final restored = PassAppearance.decode(settings.encode());
    expect(restored.ambientColors, colors);
    expect(restored.background, Colors.black);
    expect(restored.ambientUseCustomBase, true);
    expect(restored.ambientIntensity, .8);
    expect(restored.theme, ThemeMode.dark);
    expect(
      restored.copyWith(backdrop: PassBackdrop.solid).background,
      Colors.black,
    );
  });

  test(
    'invalid stored palettes fall back without discarding other preferences',
    () {
      for (final palette in [
        [],
        [0xff000000],
        [1, 2, 3, 4, 5, 6],
        ['bad', 'value'],
      ]) {
        final data = jsonDecode(
          const PassAppearance(theme: ThemeMode.dark, haptics: false).encode(),
        ) as Map<String, dynamic>;
        data['ambientColors'] = palette;
        final restored = PassAppearance.decode(jsonEncode(data));
        expect(restored.ambientColors, PassAppearance.defaultAmbientColors);
        expect(restored.theme, ThemeMode.dark);
        expect(restored.haptics, false);
      }
    },
  );

  testWidgets('applies Matrix and adds a color with the visual picker', (
    tester,
  ) async {
    var appearance = const PassAppearance(theme: ThemeMode.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: passTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: PassSettings(
          appearance: appearance,
          onChanged: (value) => appearance = value,
        ),
      ),
    );
    await tester.ensureVisible(find.text('Матрица'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Матрица'));
    await tester.pumpAndSettle();
    expect(appearance.background, Colors.black);
    expect(appearance.ambientUseCustomBase, true);
    expect(appearance.ambientColors, [
      const Color(0xff8df86b),
      const Color(0xff0a5e2a),
      Colors.black,
    ]);

    await tester.ensureVisible(find.byTooltip('Добавить цвет'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Добавить цвет'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('color-sv')), findsOneWidget);
    await tester.tap(find.byTooltip('Синий'));
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    expect(appearance.ambientColors.length, 4);
    expect(appearance.ambientColors.last, const Color(0xff325cf4));
    await tester.ensureVisible(find.byTooltip('Изменить цвет 4'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Изменить цвет 4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить этот цвет'));
    await tester.pumpAndSettle();
    expect(appearance.ambientColors.length, 3);
  });
}
