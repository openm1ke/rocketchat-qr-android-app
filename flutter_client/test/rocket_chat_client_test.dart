import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:campus_pass/rocket_chat_client.dart';
import 'package:campus_pass/request_log.dart';

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
                                ? 'The QR code data:image/png;base64,invalid'
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
