import 'package:campus_pass/pass_appearance.dart';
import 'package:campus_pass/pass_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('expiry visibility and photo selection persist in appearance', (
    tester,
  ) async {
    var appearance = const PassAppearance();
    await tester.pumpWidget(
      MaterialApp(
        home: PassSettings(
          appearance: appearance,
          onChanged: (value) => appearance = value,
          onChoosePhoto: () async => true,
        ),
      ),
    );

    await tester.tap(find.text('Показывать срок действия'));
    await tester.pumpAndSettle();
    expect(appearance.showExpiry, isFalse);

    await tester.tap(find.text('Выбрать фото для фона'));
    await tester.pumpAndSettle();
    final restored = PassAppearance.decode(appearance.encode());
    expect(restored.backdrop, PassBackdrop.photo);
    expect(restored.showExpiry, isFalse);
  });
}
