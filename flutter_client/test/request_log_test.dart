import 'dart:typed_data';

import 'package:campus_pass/request_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts identities and credentials before retaining HTTP data', () {
    final log = RequestLog();
    final id = log.beginHttp(
      Uri.parse(
        'https://url-user:url-pass@chat.example/api/v1/login?token=query-secret',
      ),
      'POST',
      headers: {
        'X-Auth-Token': 'header-secret',
        'X-User-Id': 'private-id',
        'Cookie': 'cookie-secret',
        'X-2fa-Code': 'otp-secret',
        'X-2fa-Method': 'password',
      },
      body: {
        'user': 'private-login',
        'password': 'private-password',
        'nested': {
          'digest': 'password-hash',
          'credentialSecret': 'oauth-secret',
        },
        'bypassTwoFactor': true,
      },
    );
    log.endHttp(
      id,
      statusCode: 200,
      response: {
        'data': {
          'authToken': 'response-secret',
          'userId': 'another-private-id',
          'me': {
            'name': 'private-name',
            'emails': ['private@example.test'],
          },
        },
        'success': true,
      },
      durationMs: 123,
    );
    final entry = log.events.single;
    for (final secret in [
      'url-user',
      'url-pass',
      'query-secret',
      'header-secret',
      'private-id',
      'cookie-secret',
      'otp-secret',
      'private-login',
      'private-password',
      'password-hash',
      'oauth-secret',
      'response-secret',
      'private-name',
      'private@example.test',
    ]) {
      expect(
        entry.details,
        isNot(contains(secret)),
        reason: 'Must not retain $secret',
      );
    }
    expect(entry.details, contains('bypassTwoFactor'));
    expect(entry.details, contains('true'));
    expect(entry.details, contains('X-2fa-Method'));
    expect(entry.details, contains('password'));
    expect(entry.durationMs, 123);
    expect(log.httpRequests, 1);
  });

  test(
    'hides QR messages, binary data, error echoes, and upload identifiers',
    () {
      final log = RequestLog();
      log.webSocketFrame(Uri.parse('wss://chat.example/websocket'), {
        'msg': 'changed',
        'fields': {
          'args': [
            {
              'msg': 'data:image/png;base64,PRIVATE_QR_CONTENT',
              'u': {'username': 'student-login'},
              'rid': 'private-room',
              'attachments': [
                {
                  'image_url':
                      '/file-upload/private-image-id/qr.png?auth=private-query',
                  'image_type': 'image/png',
                },
              ],
            },
          ],
        },
      }, incoming: true);
      final id = log.beginHttp(
        Uri.parse('https://chat.example/api/v1/login'),
        'POST',
      );
      log.endHttp(
        id,
        statusCode: 401,
        response: {
          'error': 'The password private-echo-secret is incorrect',
          'binary': Uint8List.fromList([1, 2, 3, 4]),
        },
      );
      final all = log.events.map((e) => e.details).join();
      for (final secret in [
        'PRIVATE_QR_CONTENT',
        'student-login',
        'private-room',
        'private-image-id',
        'private-query',
        'private-echo-secret',
      ]) {
        expect(all, isNot(contains(secret)));
      }
      expect(all, contains('image/png'));
      expect(all, contains('file-upload'));
      expect(all, contains('бинарные данные скрыты'));
    },
  );

  test(
    'counts HTTP attempts and WS methods without counting replies twice',
    () {
      final log = RequestLog(capacity: 3);
      final url = Uri.parse('https://chat.example/api/v1/login');
      final first = log.beginHttp(url, 'POST');
      log.endHttp(first, statusCode: 400, challenge: true);
      final second = log.beginHttp(url, 'POST');
      log.endHttp(second, statusCode: 403);
      final ws = Uri.parse('wss://chat.example/websocket');
      log.webSocketFrame(ws, {
        'msg': 'method',
        'method': 'login',
        'id': 'login',
        'params': [
          {'resume': 'secret'},
        ],
      }, incoming: false);
      log.webSocketFrame(ws, {
        'msg': 'result',
        'id': 'login',
        'result': {'token': 'secret'},
      }, incoming: true);
      log.webSocketFrame(ws, {'msg': 'pong'}, incoming: false);
      expect(log.httpRequests, 2);
      expect(log.webSocketMethods, 1);
      expect(log.errors, 1);
      expect(log.events.length, 3);
      expect(log.totalEvents, 5);
    },
  );

  test(
    'clearing does not let an in-flight response overwrite a new request',
    () {
      final log = RequestLog();
      final url = Uri.parse('https://chat.example/api/v1/login');
      final old = log.beginHttp(url, 'POST');
      log.clear();
      final current = log.beginHttp(url, 'POST');
      log.endHttp(old, statusCode: 401);
      log.endHttp(current, statusCode: 200);
      expect(current, greaterThan(old));
      expect(log.events.single.status, 'HTTP 200');
      expect(log.httpRequests, 1);
      expect(log.errors, 0);
    },
  );
}
