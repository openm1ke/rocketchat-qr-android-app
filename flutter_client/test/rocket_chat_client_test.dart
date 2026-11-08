import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:campus_pass/rocket_chat_client.dart';
import 'package:campus_pass/request_log.dart';
import 'package:campus_pass/pass_repository.dart';

import 'support/pass_fixtures.dart';

void main() {
  late HttpServer server;
  late RocketChatClient client;

  setUp(() async {
    RequestLog.instance.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = RocketChatClient(
      endpoint: Uri.parse('ws://127.0.0.1:${server.port}'),
    );
  });

  tearDown(() async => server.close(force: true));

  void serveLimited(
    String stage, {
    String? retryAfter,
    DateTime? reset,
    String? botWait,
    void Function()? onCommand,
  }) {
    server.listen((request) async {
      if (stage == 'handshake' ||
          request.uri.path == '/file-upload/limited.png') {
        request.response.statusCode = 429;
        if (retryAfter != null) {
          request.response.headers.set('Retry-After', retryAfter);
        }
        if (reset != null) {
          request.response.headers.set(
            'X-RateLimit-Reset',
            '${reset.millisecondsSinceEpoch}',
          );
        }
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      void send(Map<String, Object?> data) => socket.add(jsonEncode(data));
      await for (final frame in socket) {
        final data = jsonDecode(frame as String) as Map<String, dynamic>;
        if (data['msg'] == 'connect') {
          send({'msg': 'connected'});
        } else if (data['msg'] == 'sub') {
          send({
            'msg': 'ready',
            'subs': ['room'],
          });
        } else if (data['msg'] == 'method') {
          if (data['id'] == stage) {
            send({
              'msg': 'result',
              'id': data['id'],
              'error': {
                'error': 'too-many-requests',
                'details': {'timeToReset': 90000},
              },
            });
          } else if (data['id'] == 'login') {
            send({
              'msg': 'result',
              'id': 'login',
              'result': {'id': 'test-user'},
            });
          } else if (data['id'] == 'dm') {
            send({
              'msg': 'result',
              'id': 'dm',
              'result': {'rid': 'pass-room'},
            });
          } else if (data['id'] == 'enter') {
            onCommand?.call();
            send({
              'msg': 'changed',
              'collection': 'stream-room-messages',
              'fields': {
                'args': [
                  {
                    'rid': 'pass-room',
                    'u': {'username': 'qr-code-generator.bot'},
                    'msg': ?botWait,
                    if (botWait == null)
                      'attachments': [
                        {
                          'image_type': 'image/png',
                          'image_url': '/file-upload/limited.png',
                        },
                      ],
                  },
                ],
              },
            });
          }
        }
      }
    });
  }

  for (final seconds in [1, 24, 75]) {
    test('bot text requests an immediate $seconds-second wait', () async {
      serveLimited(
        'bot-message',
        botWait:
            'Please wait $seconds ${seconds == 1 ? 'second' : 'seconds'} before calling the command again.',
      );
      final started = DateTime.now();
      await expectLater(
        client.requestPass('test-token').timeout(const Duration(seconds: 2)),
        throwsA(
          isA<PassException>()
              .having((e) => e.kind, 'kind', PassError.rateLimit)
              .having(
                (e) => e.retryAt!.difference(started).inMilliseconds,
                'bot pause',
                greaterThanOrEqualTo(seconds * 1000),
              ),
        ),
      );
    });
  }

  for (final seconds in [24, 75]) {
    test(
      'bot wait $seconds persists the minimum pause and protects cached QR on relaunch',
      () async {
        var commands = 0;
        serveLimited(
          'bot-message',
          botWait:
              'Please wait $seconds seconds before calling the command again.',
          onCommand: () => commands++,
        );
        final now = DateTime.now();
        final store = MemoryPassStore()
          ..pass = CachedPass(
            owner: CachedPass.ownerFor('test-token'),
            image: testPng,
            receivedAt: now,
            expiresAt: now.add(const Duration(days: 1)),
          );
        PassRepository repository() =>
            PassRepository(client: client, store: store);
        final limited = isA<PassException>().having(
          (e) => e.kind,
          'kind',
          PassError.rateLimit,
        );
        await expectLater(repository().request('test-token'), throwsA(limited));
        expect(
          store.retryAt!.difference(now).inMilliseconds,
          greaterThanOrEqualTo((seconds < 30 ? 30 : seconds) * 1000),
        );
        expect((await repository().restore('test-token'))?.image, testPng);
        await expectLater(repository().request('test-token'), throwsA(limited));
        expect(commands, 1);
      },
    );
  }

  for (final stage in ['login', 'enter']) {
    test(
      'DDP rate limit at $stage preserves server wait and is not an auth failure',
      () async {
        serveLimited(stage);
        final started = DateTime.now();
        await expectLater(
          client.requestPass('test-token'),
          throwsA(
            isA<PassException>()
                .having((e) => e.kind, 'kind', PassError.rateLimit)
                .having(
                  (e) => e.retryAt!.difference(started).inSeconds,
                  'server pause',
                  greaterThanOrEqualTo(89),
                ),
          ),
        );
      },
    );
  }

  test('HTTP 429 during WebSocket handshake is a rate limit', () async {
    serveLimited('handshake');
    await expectLater(
      client.requestPass('test-token'),
      throwsA(
        isA<PassException>().having((e) => e.kind, 'kind', PassError.rateLimit),
      ),
    );
  });

  for (final dated in [false, true]) {
    test(
      'HTTP 429 for PNG honors ${dated ? 'HTTP date and reset' : 'Retry-After seconds'}',
      () async {
        final start = DateTime.now();
        final reset = DateTime.fromMillisecondsSinceEpoch(
          (start.millisecondsSinceEpoch ~/ 1000 + 120) * 1000,
        );
        serveLimited(
          'download',
          retryAfter: dated
              ? HttpDate.format(start.add(const Duration(seconds: 60)))
              : '90',
          reset: dated ? reset : null,
        );
        await expectLater(
          client.requestPass('test-token'),
          throwsA(
            isA<PassException>()
                .having((e) => e.kind, 'kind', PassError.rateLimit)
                .having(
                  (e) => e.retryAt!.millisecondsSinceEpoch,
                  'retry time',
                  dated
                      ? equals(reset.millisecondsSinceEpoch)
                      : greaterThanOrEqualTo(
                          start
                              .add(const Duration(seconds: 89))
                              .millisecondsSinceEpoch,
                        ),
                ),
          ),
        );
      },
    );
  }

  for (final attached in [false, true]) {
    test('requests a QR (attachment: $attached) and ignores other senders', () async {
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jK1sAAAAASUVORK5CYII=';
      server.listen((request) async {
        if (request.uri.path == '/file-upload/qr.png') {
          expect(attached, isTrue);
          expect(request.headers.value('X-Auth-Token'), 'test-token');
          expect(request.headers.value('X-User-Id'), 'test-user');
          request.response.add(base64Decode(png));
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        void send(Map<String, Object?> data) => socket.add(jsonEncode(data));
        await for (final frame in socket) {
          final data = jsonDecode(frame as String) as Map<String, dynamic>;
          switch (data['msg']) {
            case 'connect':
              send({'msg': 'connected'});
            case 'sub':
              expect(data['params'], ['pass-room', true]);
              send({
                'msg': 'ready',
                'subs': ['room'],
              });
            case 'method':
              switch (data['method']) {
                case 'login':
                  expect(data['params'], [
                    {'resume': 'test-token'},
                  ]);
                  send({
                    'msg': 'result',
                    'id': data['id'],
                    'result': {'id': 'test-user'},
                  });
                case 'createDirectMessage':
                  expect(data['params'], ['qr-code-generator.bot']);
                  send({
                    'msg': 'result',
                    'id': data['id'],
                    'result': {'rid': 'pass-room'},
                  });
                case 'slashCommand':
                  expect(data['params'], [
                    {
                      'cmd': 'enter',
                      'params': '',
                      'msg': {'rid': 'pass-room'},
                    },
                  ]);
                  for (final sender in [
                    'other-user',
                    'qr-code-generator.bot',
                  ]) {
                    send({
                      'msg': 'changed',
                      'collection': 'stream-room-messages',
                      'fields': {
                        'args': [
                          {
                            'rid': 'pass-room',
                            'u': {'username': sender},
                            'msg': sender == 'other-user'
                                ? 'Please wait 9999 seconds before calling the command again.'
                                : attached
                                ? ''
                                : 'The QR code <img src="data:image/png;base64,$png">',
                            if (attached)
                              'attachments': [
                                {
                                  'image_type': 'image/png',
                                  'image_url': '/file-upload/qr.png',
                                },
                              ],
                          },
                        ],
                      },
                    });
                  }
                  if (attached) {
                    send({
                      'msg': 'changed',
                      'collection': 'stream-room-messages',
                      'fields': {
                        'args': [
                          {
                            'rid': 'pass-room',
                            'u': {'username': 'qr-code-generator.bot'},
                            'msg': 'The QR code will expire on 11.11.2026.',
                          },
                        ],
                      },
                    });
                  }
              }
          }
        }
      });
      final pass = await client.requestPass('test-token');
      expect(pass.image, base64Decode(png));
      expect(pass.expiresOn, attached ? DateTime(2026, 11, 11) : null);
      expect(RequestLog.instance.webSocketMethods, 3);
      expect(RequestLog.instance.httpRequests, attached ? 1 : 0);
      final trace = RequestLog.instance.events.map((e) => e.details).join();
      expect(trace, isNot(contains('test-token')));
      expect(trace, isNot(contains(png)));
    });
  }

  test('reports an invalid token separately from network errors', () async {
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      await for (final frame in socket) {
        final data = jsonDecode(frame as String) as Map<String, dynamic>;
        if (data['msg'] == 'connect') {
          socket.add(jsonEncode({'msg': 'connected'}));
        } else {
          socket.add(
            jsonEncode({
              'msg': 'result',
              'id': data['id'],
              'error': {'error': 403},
            }),
          );
        }
      }
    });
    await expectLater(
      client.requestPass('invalid'),
      throwsA(
        isA<PassException>().having(
          (error) => error.kind,
          'kind',
          PassError.authorization,
        ),
      ),
    );
  });
}
