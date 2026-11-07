import 'package:campus_pass/pass_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'selects an arbitrary saturation and brightness without a text field',
    (tester) async {
      Color? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showDialog<Color>(
                    context: context,
                    builder: (_) =>
                        const PassColorDialog(color: Color(0xff00ff00)),
                  );
                },
                child: const Text('Выбрать'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Выбрать'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('color-sv'))),
      );
      await tester.pump();
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();
      expect(selected, const Color(0xff408040));
    },
  );
}
