import 'dart:convert';

import 'package:campus_pass/pass_repository.dart';
import 'package:campus_pass/rocket_chat_client.dart';

final testPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAE0lEQVR4nGP8//8/AwMDEwMYAAAkBgMBXaJOiAAAAABJRU5ErkJggg==',
);

class MemoryPassStore implements PassStore {
  CachedPass? pass;
  DateTime? retryAt;
  bool failCache = false;
  bool failDeadline = false;

  @override
  Future<CachedPass?> readPass() async => pass;
  @override
  Future<DateTime?> readRetryAt() async => retryAt;
  @override
  Future<void> writePass(CachedPass? value) async {
    if (failCache) throw StateError('Cache unavailable');
    pass = value;
  }

  @override
  Future<void> writeRetryAt(DateTime value) async {
    if (failDeadline) throw StateError('Storage unavailable');
    retryAt = value;
  }
}

class FixturePassClient extends RocketChatClient {
  int calls = 0;
  DateTime? expiresOn;
  Future<QrPass> Function()? respond;

  @override
  Future<QrPass> requestPass(String token) {
    calls++;
    return respond?.call() ??
        Future.value((image: testPng, expiresOn: expiresOn));
  }
}
