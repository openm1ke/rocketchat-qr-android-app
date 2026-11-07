import 'package:campus_pass/connection_screen.dart';
import 'package:campus_pass/pass_theme.dart';
import 'package:campus_pass/rocket_chat_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TestAuthClient extends RocketChatAuthClient {
  TestAuthClient(this.method);
  final String method;
  int logins = 0;
  int logouts = 0;
  int removals = 0;
  bool denyNext = false;
  TwoFactorProof? confirmedWith;

  @override
  Future<AuthSession> login(
    String username,
    String password, {
    TwoFactorProof? proof,
  }) async {
    logins++;
    return const AuthSession(token: 'temporary', userId: 'user');
  }

  @override
  Future<String> createPersonalToken(
    AuthSession session,
    String name, {
    TwoFactorProof? proof,
  }) async {
    if (denyNext) {
      denyNext = false;
      throw const AuthException(AuthError.forbidden);
    }
    if (proof == null) {
      throw AuthException(
        AuthError.credentials,
        challenge: TwoFactorChallenge(method: method),
      );
    }
    confirmedWith = proof;
    return 'permanent';
  }

  @override
  Future<void> logout(AuthSession session) async {
    logouts++;
  }

  @override
  Future<bool> removePersonalToken(
    AuthSession session,
    String name, {
    TwoFactorProof? proof,
  }) async {
    removals++;
    return true;
  }
}

void main() {
  Future<void> enterCredentials(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Логин или почта Rocket.Chat'),
      'student',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Пароль'),
      'password',
    );
    await tester.ensureVisible(find.text('Подключить Rocket.Chat'));
    await tester.tap(find.text('Подключить Rocket.Chat'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a rejected token exchange ends the session before another login',
    (tester) async {
      final auth = TestAuthClient('password')..denyNext = true;
      String? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: passTheme(),
          home: ConnectionScreen(
            authClient: auth,
            onConnected: (token) async => saved = token,
          ),
        ),
      );
      await enterCredentials(tester);
      expect(saved, isNull);
      expect(auth.logouts, 1);
      await enterCredentials(tester);
      expect(auth.logins, 2);
      expect(saved, 'permanent');
    },
  );

  testWidgets('saves only a PAT after server-requested password confirmation', (
    tester,
  ) async {
    final auth = TestAuthClient('password');
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: passTheme(),
        home: ConnectionScreen(
          authClient: auth,
          onConnected: (token) async => saved = token,
        ),
      ),
    );
    await enterCredentials(tester);
    expect(saved, 'permanent');
    expect(auth.confirmedWith?.method, 'password');
    expect(auth.confirmedWith?.code, isNot('password'));
    expect(auth.logouts, 1);
  });

  testWidgets('asks for a code and continues the existing login session', (
    tester,
  ) async {
    final auth = TestAuthClient('totp');
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: passTheme(),
        home: ConnectionScreen(
          authClient: auth,
          onConnected: (token) async => saved = token,
        ),
      ),
    );
    await enterCredentials(tester);
    expect(saved, isNull);
    expect(find.byKey(const ValueKey('confirmation-totp')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('confirmation-totp')),
      '123456',
    );
    await tester.ensureVisible(find.text('Подтвердить'));
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    expect(saved, 'permanent');
    expect(auth.logins, 1);
    expect(auth.confirmedWith?.code, '123456');
  });

  testWidgets('revokes a newly created PAT when secure storage fails', (
    tester,
  ) async {
    final auth = TestAuthClient('password');
    await tester.pumpWidget(
      MaterialApp(
        theme: passTheme(),
        home: ConnectionScreen(
          authClient: auth,
          onConnected: (_) async => throw StateError('storage unavailable'),
        ),
      ),
    );
    await enterCredentials(tester);
    expect(auth.removals, 1);
    expect(
      find.text('Не удалось сохранить подключение. Попробуйте ещё раз.'),
      findsOneWidget,
    );
  });
}
