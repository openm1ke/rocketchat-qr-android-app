import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_pass/qr_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('blurs the old QR and reveals the replacement in tiles', (
    tester,
  ) async {
    final oldImage = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jK1sAAAAASUVORK5CYII=',
    );
    final newImage = Uint8List.fromList(oldImage);
    Future<void> show(
      Uint8List image, {
      bool loading = false,
      bool reduced = false,
    }) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Center(
            child: SizedBox.square(
              dimension: 200,
              child: QrTransition(image: image, loading: loading),
            ),
          ),
        ),
      ),
    );

    await show(oldImage, loading: true);
    expect(
      tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled,
      isTrue,
    );
    await show(newImage);
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byType(ClipPath), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(ClipPath), findsNothing);

    await show(oldImage, reduced: true);
    expect(find.byType(ClipPath), findsNothing);
    expect(
      tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled,
      isFalse,
    );
  });
}
