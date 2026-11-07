import 'package:campus_pass/ambient_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget scene({bool reduced = false, double intensity = .5}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(
        body: AmbientBackground(
          base: Color(0xff17191e),
          enabled: true,
          intensity: intensity,
        ),
      ),
    ),
  );

  testWidgets('zero motion intensity stops ticking', (tester) async {
    await tester.pumpWidget(scene());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(scene(intensity: 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(scene(intensity: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion uses a static backdrop', (tester) async {
    await tester.pumpWidget(scene(reduced: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ambient animation stops when the application leaves the foreground',
    (tester) async {
      await tester.pumpWidget(scene());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
