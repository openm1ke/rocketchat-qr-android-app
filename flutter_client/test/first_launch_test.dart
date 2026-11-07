import 'package:campus_pass/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offers login and a guided manual-token fallback', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const CampusPassApp());
    await tester.pumpAndSettle();

    expect(find.text('Подключить Rocket.Chat'), findsOneWidget);
    expect(find.text('Логин или почта Rocket.Chat'), findsOneWidget);
    await tester.tap(find.text('У меня есть токен'));
    await tester.pumpAndSettle();
    expect(find.text('Где взять токен?'), findsWidgets);
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );

    await tester.tap(find.text('Сохранить и получить QR'));
    await tester.pumpAndSettle();
    expect(find.text('Вставьте токен Rocket.Chat.'), findsOneWidget);
  });
}
