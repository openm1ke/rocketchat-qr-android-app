import 'dart:convert';
import 'dart:io';

import 'package:campus_pass/rocket_chat_auth.dart';
import 'package:campus_pass/request_log.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late RocketChatAuthClient client;
  late Future<void> Function(HttpRequest) handle;

  setUp(() async {
    RequestLog.instance.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = RocketChatAuthClient(
      origin: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    server.listen((request) => handle(request));
  });
  tearDown(() => server.close(force: true));

  Future<void> reply(
    HttpRequest request,
    Map<String, Object?> data, {
    int status = 200,
  }) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
    await request.response.close();
  }

  test('exchanges credentials for a separate PAT and closes only the login session', () async {
    final endpoints = <String>[];
    handle = (request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      endpoints.add(request.uri.path);
      switch (request.uri.path) {
        case '/api/v1/login':
          expect(body, {'user': 'student', 'password': 'test-password'});
          await reply(request, {
            'status': 'success',
            'data': {'authToken': 'temporary', 'userId': 'student-id'},
          });
        case '/api/v1/users.generatePersonalAccessToken':
          expect(request.headers.value('X-Auth-Token'), 'temporary');
          expect(request.headers.value('X-User-Id'), 'student-id');
          expect(body, {
            'tokenName': 'Campus Pass test',
            'bypassTwoFactor': true,
          });
          await reply(request, {'success': true, 'token': 'permanent'});
        case '/api/v1/logout':
          expect(request.headers.value('X-Auth-Token'), 'temporary');
          await reply(request, {'status': 'success'});
      }
    };
    final session = await client.login('student', 'test-password');
    final token = await client.createPersonalToken(session, 'Campus Pass test');
    expect(token, 'permanent');
    expect(token, isNot(session.token));
    await client.logout(session);
    expect(RequestLog.instance.httpRequests, 3);
    final trace = RequestLog.instance.events.map((e) => e.details).join();
    expect(trace, isNot(contains('test-password')));
    expect(trace, isNot(contains('temporary')));
    expect(trace, isNot(contains('permanent')));
    expect(trace, isNot(contains('student-id')));
    expect(trace, contains('"bypassTwoFactor": true'));
    expect(endpoints, [
      '/api/v1/login',
      '/api/v1/users.generatePersonalAccessToken',
      '/api/v1/logout',
    ]);
  });

  test('preserves the required second factor and available methods', () async {
    handle = (request) => reply(request, {
      'success': false,
      'errorType': 'totp-required',
      'details': {
        'method': 'totp',
        'availableMethods': ['totp', 'email'],
        'codeGenerated': false,
      },
    }, status: 400);
    await expectLater(
      client.createPersonalToken(
        const AuthSession(token: 'session', userId: 'user'),
        'test',
      ),
      throwsA(
        isA<AuthException>()
            .having((e) => e.challenge?.method, 'method', 'totp')
            .having((e) => e.challenge?.availableMethods, 'methods', [
              'totp',
              'email',
            ]),
      ),
    );
  });

  test(
    'confirms creation with SHA-256 and requests the selected PAT 2FA mode',
    () async {
      handle = (request) async {
        expect(request.headers.value('X-2fa-Method'), 'password');
        expect(
          request.headers.value('X-2fa-Code'),
          sha256.convert(utf8.encode('test-password')).toString(),
        );
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        expect(body['bypassTwoFactor'], true);
        expect(body.containsKey('password'), false);
        await reply(request, {'success': true, 'token': 'pat'});
      };
      expect(
        await client.createPersonalToken(
          const AuthSession(token: 'session', userId: 'user'),
          'test',
          proof: TwoFactorProof.password('test-password'),
        ),
        'pat',
      );
    },
  );

  test('reports invalid confirmation without echoing server secrets', () async {
    handle = (request) => reply(request, {
      'errorType': 'totp-invalid',
      'error': 'sensitive-server-message',
      'details': {'method': 'email'},
    }, status: 400);
    try {
      await client.login(
        'student',
        'password',
        proof: const TwoFactorProof('email', '123456'),
      );
      fail('Expected a confirmation failure');
    } on AuthException catch (e) {
      expect(e.challenge?.invalid, true);
      expect(e.challenge?.method, 'email');
      expect(e.message, isNot(contains('sensitive-server-message')));
    }
  });

  test(
    'does not accept a login session when token creation is forbidden',
    () async {
      handle = (request) => reply(request, {
        'success': false,
        'errorType': 'error-forbidden',
      }, status: 403);
      await expectLater(
        client.createPersonalToken(
          const AuthSession(token: 'session', userId: 'user'),
          'test',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.kind,
            'kind',
            AuthError.forbidden,
          ),
        ),
      );
    },
  );

  test('does not follow redirects carrying authentication', () async {
    handle = (request) async {
      request.response.headers.set('Location', '/unexpected');
      expect(request.uri.path, '/api/v1/login');
      await reply(request, {}, status: 302);
    };
    await expectLater(
      client.login('student', 'password'),
      throwsA(
        isA<AuthException>().having((e) => e.kind, 'kind', AuthError.response),
      ),
    );
  });

  test('rejects a success response that has no personal token', () async {
    handle = (request) =>
        reply(request, {'success': true, 'authToken': 'temporary'});
    await expectLater(
      client.createPersonalToken(
        const AuthSession(token: 'session', userId: 'user'),
        'test',
      ),
      throwsA(
        isA<AuthException>().having((e) => e.kind, 'kind', AuthError.response),
      ),
    );
  });
}
