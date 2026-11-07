import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'request_log.dart';

enum AuthError { credentials, forbidden, rateLimit, network, timeout, response }

class TwoFactorChallenge {
  const TwoFactorChallenge({
    required this.method,
    this.invalid = false,
    this.codeGenerated = false,
    this.availableMethods = const [],
  });

  final String method;
  final bool invalid;
  final bool codeGenerated;
  final List<String> availableMethods;
}

class AuthException implements Exception {
  const AuthException(this.kind, {this.challenge});
  final AuthError kind;
  final TwoFactorChallenge? challenge;

  String get message => switch (kind) {
    AuthError.credentials =>
      'Не удалось войти. Проверьте логин и пароль Rocket.Chat.',
    AuthError.forbidden =>
      'Сервер не разрешил создать персональный токен. '
          'Подключитесь с готовым токеном — инструкция доступна ниже.',
    AuthError.rateLimit =>
      'Слишком много попыток. Подождите немного и повторите.',
    AuthError.network => 'Нет соединения с Rocket.Chat. Проверьте интернет.',
    AuthError.timeout => 'Rocket.Chat не ответил вовремя. Попробуйте ещё раз.',
    AuthError.response =>
      'Не удалось обработать ответ Rocket.Chat. Попробуйте вход по токену.',
  };
}

class AuthSession {
  const AuthSession({required this.token, required this.userId});
  final String token;
  final String userId;
}

class TwoFactorProof {
  const TwoFactorProof(this.method, this.code);
  factory TwoFactorProof.password(String password) => TwoFactorProof(
    'password',
    sha256.convert(utf8.encode(password)).toString(),
  );
  final String method;
  final String code;
}

class RocketChatAuthClient {
  RocketChatAuthClient({Uri? origin})
    : origin = origin ?? Uri.parse('https://rocketchat-student.21-school.ru');

  final Uri origin;

  Future<AuthSession> login(
    String username,
    String password, {
    TwoFactorProof? proof,
  }) async {
    final data = await _post(
      'login',
      {
        'user': username,
        'password': password,
        if (proof != null && proof.method != 'password') 'code': proof.code,
      },
      proof: proof,
      signingIn: true,
    );
    final result = data['data'];
    if (result is! Map ||
        result['authToken'] is! String ||
        result['userId'] is! String ||
        (result['authToken'] as String).isEmpty ||
        (result['userId'] as String).isEmpty) {
      throw const AuthException(AuthError.response);
    }
    return AuthSession(token: result['authToken'], userId: result['userId']);
  }

  Future<String> createPersonalToken(
    AuthSession session,
    String name, {
    TwoFactorProof? proof,
  }) async {
    final data = await _post(
      'users.generatePersonalAccessToken',
      {'tokenName': name, 'bypassTwoFactor': true},
      session: session,
      proof: proof,
    );
    final token = data['token'];
    if (token is! String || token.isEmpty || data['success'] != true) {
      throw const AuthException(AuthError.response);
    }
    return token;
  }

  Future<void> sendEmailCode(String username, {AuthSession? session}) async {
    await _post('users.2fa.sendEmailCode', {
      'emailOrUsername': username,
    }, session: session);
  }

  Future<bool> removePersonalToken(
    AuthSession session,
    String name, {
    TwoFactorProof? proof,
  }) async {
    try {
      await _post(
        'users.removePersonalAccessToken',
        {'tokenName': name},
        session: session,
        proof: proof,
      );
      return true;
    } on AuthException {
      return false;
    }
  }

  Future<void> logout(AuthSession session) async {
    try {
      await _post('logout', const {}, session: session);
    } on AuthException {
      // Session cleanup must not discard a successfully saved personal token.
    }
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, Object?> body, {
    AuthSession? session,
    TwoFactorProof? proof,
    bool signingIn = false,
  }) async {
    final loopback = InternetAddress.tryParse(origin.host)?.isLoopback ?? false;
    if (origin.userInfo.isNotEmpty ||
        (origin.scheme != 'https' && !(origin.scheme == 'http' && loopback))) {
      throw const AuthException(AuthError.network);
    }
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final timer = Stopwatch()..start();
    final trace = RequestLog.instance.beginHttp(
      origin.resolve('/api/v1/$endpoint'),
      'POST',
      headers: {
        'Content-Type': 'application/json',
        if (session != null) 'X-Auth-Token': session.token,
        if (session != null) 'X-User-Id': session.userId,
        if (proof != null) 'X-2fa-Method': proof.method,
        if (proof != null) 'X-2fa-Code': proof.code,
      },
      body: body,
    );
    int? traceStatus;
    Object? traceResponse;
    void finish({String? failure, bool challenge = false}) =>
        RequestLog.instance.endHttp(
          trace,
          statusCode: traceStatus,
          response: traceResponse,
          failure: failure,
          challenge: challenge,
          durationMs: timer.elapsedMilliseconds,
        );
    try {
      return await (() async {
        final request = await http.postUrl(origin.resolve('/api/v1/$endpoint'));
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        if (session != null) {
          request.headers.set('X-Auth-Token', session.token);
          request.headers.set('X-User-Id', session.userId);
        }
        if (proof != null) {
          request.headers.set('X-2fa-Method', proof.method);
          request.headers.set('X-2fa-Code', proof.code);
        }
        request.add(utf8.encode(jsonEncode(body)));
        final response = await request.close();
        traceStatus = response.statusCode;
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          bytes.add(chunk);
          if (bytes.length > 512 * 1024) {
            throw const AuthException(AuthError.response);
          }
        }
        traceResponse = {
          'bytes': bytes.length,
          'Content-Type': response.headers.contentType?.toString(),
        };
        if (response.statusCode == 429) {
          throw const AuthException(AuthError.rateLimit);
        }
        final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
        if (decoded is! Map<String, dynamic>) {
          throw const AuthException(AuthError.response);
        }
        traceResponse = decoded;
        final type = '${decoded['errorType'] ?? decoded['error'] ?? ''}';
        if (type.contains('totp-required') || type.contains('totp-invalid')) {
          final details = decoded['details'];
          final method = details is Map ? details['method'] : null;
          if (method != 'email' && method != 'totp' && method != 'password') {
            throw const AuthException(AuthError.response);
          }
          final methods = details is Map ? details['availableMethods'] : null;
          throw AuthException(
            AuthError.credentials,
            challenge: TwoFactorChallenge(
              method: method,
              invalid: type.contains('totp-invalid'),
              codeGenerated: details is Map && details['codeGenerated'] == true,
              availableMethods: methods is List
                  ? methods
                        .whereType<String>()
                        .where(
                          (m) => m == 'email' || m == 'totp' || m == 'password',
                        )
                        .toList()
                  : const [],
            ),
          );
        }
        if (response.statusCode < 200 ||
            response.statusCode >= 300 ||
            decoded['success'] == false ||
            decoded['status'] == 'error') {
          throw AuthException(
            signingIn &&
                    (response.statusCode == 401 || response.statusCode == 403)
                ? AuthError.credentials
                : response.statusCode == 401 ||
                      response.statusCode == 403 ||
                      type.contains('not-authorized') ||
                      type.contains('forbidden')
                ? AuthError.forbidden
                : AuthError.response,
          );
        }
        finish();
        return decoded;
      })().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      finish(failure: 'timeout');
      throw const AuthException(AuthError.timeout);
    } on IOException {
      finish(failure: 'network');
      throw const AuthException(AuthError.network);
    } on FormatException {
      finish(failure: 'invalid-json');
      throw const AuthException(AuthError.response);
    } on AuthException catch (failure) {
      final expectedChallenge =
          failure.challenge != null && !failure.challenge!.invalid;
      finish(
        failure: expectedChallenge ? null : failure.kind.name,
        challenge: expectedChallenge,
      );
      rethrow;
    } finally {
      timer.stop();
      http.close(force: true);
    }
  }
}
