import 'dart:async';

import 'package:campus_pass/home_screen_widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.campus_pass/widgets');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'publishes only QR and presentation data with an absolute expiry',
    () async {
      final widgets = HomeScreenWidgets(channel: channel);
      final expiry = DateTime.now().add(const Duration(hours: 1));
      final bytes = Uint8List.fromList([1, 2, 3]);
      await widgets.publish(
        WidgetPass(
          image: bytes,
          expiresAt: expiry,
          boostBrightness: false,
          scanSize: .85,
        ),
      );
      expect(calls.single.method, 'publish');
      final value = calls.single.arguments as Map;
      expect(value.keys.toSet(), {
        'image',
        'expiresAt',
        'expiresOn',
        'boostBrightness',
        'scanSize',
      });
      expect(value['image'], bytes);
      expect(value['expiresAt'], expiry.millisecondsSinceEpoch);
      expect(value['boostBrightness'], false);
      expect(value['scanSize'], .85);
    },
  );

  test(
    'an expired pass clears the widget instead of exporting an invalid QR',
    () async {
      await HomeScreenWidgets(channel: channel).publish(
        WidgetPass(
          image: Uint8List.fromList([1]),
          expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      );
      expect(calls.map((call) => call.method), ['clear']);
    },
  );

  test('clear follows an in-flight export and is not undone by it', () async {
    final release = Completer<void>();
    final started = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'publish') {
        started.complete();
        await release.future;
      }
      return null;
    });
    final widgets = HomeScreenWidgets(channel: channel);
    final publish = widgets.publish(
      WidgetPass(
        image: Uint8List.fromList([1]),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    await started.future;
    final clear = widgets.clear();
    expect(calls.length, 1);
    release.complete();
    await Future.wait([publish, clear]);
    expect(calls.map((call) => call.method), ['publish', 'clear']);
  });

  test('a failed export does not block subsequent clearing', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'publish') throw PlatformException(code: 'storage');
      return null;
    });
    final widgets = HomeScreenWidgets(channel: channel);
    await expectLater(
      widgets.publish(
        WidgetPass(
          image: Uint8List.fromList([1]),
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      ),
      throwsA(isA<PlatformException>()),
    );
    await widgets.clear();
    expect(calls.last.method, 'clear');
  });

  test(
    'expired or malformed snapshots never become the displayed pass',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'image': Uint8List.fromList([1]),
          'expiresAt': DateTime.now()
              .subtract(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        },
      );
      expect(await HomeScreenWidgets(channel: channel).read(), isNull);
      expect(
        WidgetPass.fromMessage({'image': 'not bytes', 'expiresAt': 1}),
        isNull,
      );
    },
  );
}
