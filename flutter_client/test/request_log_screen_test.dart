import 'package:campus_pass/pass_theme.dart';
import 'package:campus_pass/request_log.dart';
import 'package:campus_pass/request_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('copies only the sanitized event and clears the journal', (
    tester,
  ) async {
    final log = RequestLog();
    final id = log.beginHttp(
      Uri.parse('https://chat.example/api/v1/login'),
      'POST',
      body: {'user': 'private-user', 'password': 'private-pass'},
    );
    log.endHttp(id, statusCode: 200, response: {'authToken': 'private-token'});
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = call.arguments['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: passTheme(),
        home: RequestLogScreen(log: log),
      ),
    );
    await tester.tap(find.text('HTTP → POST'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Копировать запись'));
    await tester.tap(find.text('Копировать запись'));
    await tester.pump();
    expect(copied, isNotNull);
    for (final secret in ['private-user', 'private-pass', 'private-token']) {
      expect(copied, isNot(contains(secret)));
    }
    expect(copied, contains('[скрыто]'));
    await tester.tap(find.byTooltip('Очистить журнал'));
    await tester.pumpAndSettle();
    expect(log.events, isEmpty);
    expect(find.textContaining('Запросов пока нет.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
