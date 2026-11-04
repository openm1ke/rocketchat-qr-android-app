import 'package:campus_pass/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens the token setup screen on first launch', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const CampusPassApp());
    await tester.pumpAndSettle();

    expect(find.text('Подключите Rocket.Chat'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );

    await tester.tap(find.text('Сохранить и получить QR'));
    await tester.pumpAndSettle();
    expect(find.text('Вставьте токен Rocket.Chat.'), findsOneWidget);
  });
}
