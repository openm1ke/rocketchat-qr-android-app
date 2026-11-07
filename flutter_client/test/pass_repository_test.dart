import 'dart:async';
import 'dart:io';

import 'package:campus_pass/pass_repository.dart';
import 'package:campus_pass/rocket_chat_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pass_fixtures.dart';

void main() {
  late DateTime now;
  late MemoryPassStore store;
  late FixturePassClient client;
  PassRepository repository() =>
      PassRepository(client: client, store: store, now: () => now);
  final limited = isA<PassException>().having(
    (e) => e.kind,
    'kind',
    PassError.rateLimit,
  );

  setUp(() {
    now = DateTime(2026, 11, 8, 12);
    store = MemoryPassStore();
    client = FixturePassClient()..expiresOn = now.add(const Duration(days: 1));
  });

  test('relaunch uses the same cached PNG and original expiry without any requests', () async {
    final saved = await repository().request('account-a');
    now = now.add(const Duration(hours: 1));
    for (var launch = 0; launch < 5; launch++) {
      final restored = await repository().restore('account-a');
      expect(restored?.image, testPng);
      expect(restored?.expiresAt, saved.expiresAt);
      expect(restored?.receivedAt, saved.receivedAt);
    }
    expect(client.calls, 1);
  });

  test(
    '30 seconds starts when the image arrives and survives restart',
    () async {
      client.respond = () async {
        now = now.add(const Duration(seconds: 12));
        return (image: testPng, expiresOn: client.expiresOn);
      };
      final saved = await repository().request('account-a');
      now = now.add(const Duration(seconds: 29));
      await expectLater(repository().request('account-a'), throwsA(limited));
      expect(client.calls, 1);
      expect(store.retryAt, saved.receivedAt.add(const Duration(seconds: 30)));
      now = now.add(const Duration(seconds: 1));
      await repository().request('account-a');
      expect(client.calls, 2);
    },
  );

  test('rapid concurrent requests share one bot request', () async {
    final response = Completer<QrPass>();
    client.respond = () => response.future;
    final passes = repository();
    final first = passes.request('account-a');
    final second = passes.request('account-a');
    response.complete((image: testPng, expiresOn: client.expiresOn));
    expect(await first, same(await second));
    expect(client.calls, 1);
  });

  test(
    'request deadline is written before connecting, even if app dies in flight',
    () async {
      final response = Completer<QrPass>();
      final entered = Completer<void>();
      client.respond = () {
        expect(store.retryAt!.isAfter(now), true);
        entered.complete();
        return response.future;
      };
      final pending = repository().request('account-a');
      await entered.future;
      await expectLater(repository().request('account-a'), throwsA(limited));
      expect(client.calls, 1);
      response.complete((image: testPng, expiresOn: client.expiresOn));
      await pending;
    },
  );

  test('expiry or account change does not erase throttling or expose another account QR', () async {
    final passes = repository();
    await passes.request('account-a');
    expect(await passes.restore('account-b'), isNull);
    await passes.clearPass();
    await expectLater(repository().request('account-b'), throwsA(limited));
    expect(client.calls, 1);
  });

  test('expired or absent cache never causes an automatic request', () async {
    client.expiresOn = null;
    await repository().request('account-a');
    now = now.add(const Duration(seconds: 31));
    expect(await repository().restore('account-a'), isNull);
    await repository().clearPass();
    expect(await repository().restore('account-a'), isNull);
    expect(client.calls, 1);
  });

  test(
    'failed refresh preserves a valid cached pass and blocks immediate retry',
    () async {
      final saved = await repository().request('account-a');
      now = now.add(const Duration(seconds: 31));
      client.respond = () =>
          Future.error(const PassException(PassError.network));
      await expectLater(
        repository().request('account-a'),
        throwsA(isA<PassException>()),
      );
      expect((await repository().restore('account-a'))?.image, saved.image);
      await expectLater(repository().request('account-a'), throwsA(limited));
      expect(client.calls, 2);
    },
  );

  test(
    'server rate limit longer than 30 seconds is persisted across restart',
    () async {
      final retry = now.add(const Duration(minutes: 3));
      client.respond = () =>
          Future.error(PassException(PassError.rateLimit, retryAt: retry));
      await expectLater(repository().request('account-a'), throwsA(limited));
      expect(store.retryAt, retry);
      now = now.add(const Duration(minutes: 2));
      await expectLater(repository().request('account-a'), throwsA(limited));
      expect(client.calls, 1);
    },
  );

  test(
    'no socket is opened if the request guard cannot be persisted',
    () async {
      store.failDeadline = true;
      await expectLater(repository().request('account-a'), throwsStateError);
      expect(client.calls, 0);
    },
  );

  test(
    'image cache failure retains usable QR and durable request deadline',
    () async {
      store.failCache = true;
      final passes = repository();
      expect((await passes.request('account-a')).image, testPng);
      expect(passes.cachePersisted, false);
      await expectLater(repository().request('account-a'), throwsA(limited));
      expect(client.calls, 1);
    },
  );

  test('real local files restore across instances and image eviction keeps secure deadline', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp(
      'campus-pass-cache-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/pass.json');
    PassRepository local() => PassRepository(
      client: client,
      now: () => now,
      store: LocalPassStore(cacheFile: () async => file),
    );
    await local().request('test-personal-token');
    expect((await local().restore('test-personal-token'))?.image, testPng);
    expect(await file.readAsString(), isNot(contains('test-personal-token')));
    await file.delete();
    expect(await local().restore('test-personal-token'), isNull);
    await expectLater(local().request('test-personal-token'), throwsA(limited));
    expect(client.calls, 1);
    await file.writeAsString('{partial cache');
    expect(await local().restore('test-personal-token'), isNull);
    await expectLater(local().request('test-personal-token'), throwsA(limited));
    expect(client.calls, 1);
  });
}
