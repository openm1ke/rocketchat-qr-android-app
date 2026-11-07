import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pass_theme.dart';
import 'rocket_chat_auth.dart';
import 'token_guide.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    super.key,
    required this.onConnected,
    this.onCancel,
    this.authClient,
  });

  final Future<void> Function(String token) onConnected;
  final VoidCallback? onCancel;
  final RocketChatAuthClient? authClient;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _token = TextEditingController();
  final _code = TextEditingController();
  late final _auth = widget.authClient ?? RocketChatAuthClient();
  late final _tokenName =
      'Campus Pass · ${Platform.isIOS ? 'iPhone' : 'Android'} · '
      '${List.generate(6, (_) => Random.secure().nextInt(16).toRadixString(16)).join()}';
  AuthSession? _session;
  TwoFactorChallenge? _challenge;
  bool _manual = false;
  bool _busy = false;
  bool _showPassword = false;
  bool _emailSending = false;
  bool _emailCooldown = false;
  Timer? _emailTimer;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    final session = _session;
    if (session != null) unawaited(_auth.logout(session));
    _emailTimer?.cancel();
    _username.dispose();
    _password.dispose();
    _token.dispose();
    _code.dispose();
    super.dispose();
  }

  void _reset({required bool manual}) {
    _discardSession();
    _password.clear();
    _code.clear();
    _token.clear();
    _emailTimer?.cancel();
    setState(() {
      _manual = manual;
      _challenge = null;
      _error = null;
      _notice = null;
      _emailCooldown = false;
    });
  }

  void _discardSession() {
    final session = _session;
    _session = null;
    if (session != null) unawaited(_auth.logout(session));
  }

  TwoFactorProof? _proof() {
    final challenge = _challenge;
    if (challenge == null) return null;
    return challenge.method == 'password'
        ? TwoFactorProof.password(_code.text)
        : TwoFactorProof(challenge.method, _code.text.trim());
  }

  Future<void> _submit() async {
    if (_busy || _emailSending) return;
    if (_manual && _token.text.trim().isEmpty) {
      setState(() => _error = 'Вставьте токен Rocket.Chat.');
      return;
    }
    if (!_manual && (_username.text.trim().isEmpty || _password.text.isEmpty)) {
      setState(() => _error = 'Введите логин и пароль Rocket.Chat.');
      return;
    }
    if (!_manual && _challenge != null && _code.text.trim().isEmpty) {
      setState(
        () => _error = _challenge!.method == 'password'
            ? 'Введите пароль для подтверждения.'
            : 'Введите код подтверждения.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final password = _password.text;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (_manual) {
        await widget.onConnected(_token.text.trim());
        return;
      }
      final session =
          _session ??
          await _auth.login(_username.text.trim(), password, proof: _proof());
      if (!mounted) {
        unawaited(_auth.logout(session));
        return;
      }
      final alreadyAuthenticated = _session != null;
      _session = session;
      var proof = alreadyAuthenticated ? _proof() : null;
      String personalToken;
      try {
        personalToken = await _auth.createPersonalToken(
          session,
          _tokenName,
          proof: proof,
        );
      } on AuthException catch (error) {
        if (error.challenge?.method != 'password' ||
            error.challenge!.invalid ||
            proof != null) {
          rethrow;
        }
        // Confirm creation independently of the personal token's usage policy.
        proof = TwoFactorProof.password(password);
        personalToken = await _auth.createPersonalToken(
          session,
          _tokenName,
          proof: proof,
        );
      }
      _session = null;
      if (!mounted) {
        await _auth.removePersonalToken(session, _tokenName, proof: proof);
        unawaited(_auth.logout(session));
        return;
      }
      try {
        await widget.onConnected(personalToken);
      } catch (_) {
        await _auth.removePersonalToken(session, _tokenName, proof: proof);
        if (mounted) {
          _session = session;
        } else {
          unawaited(_auth.logout(session));
        }
        rethrow;
      }
      unawaited(_auth.logout(session));
      TextInput.finishAutofillContext(shouldSave: false);
    } on AuthException catch (error) {
      if (!mounted) return;
      final challenge = error.challenge;
      if (challenge == null) _discardSession();
      setState(() {
        if (challenge != null) {
          _challenge = challenge;
          _code.clear();
          _error = challenge.invalid
              ? 'Код не подошёл. Проверьте его и повторите.'
              : null;
          _notice = challenge.method == 'email' && challenge.codeGenerated
              ? 'Rocket.Chat отправил код на вашу почту.'
              : null;
        } else {
          _challenge = null;
          _code.clear();
          _error = error.message;
        }
      });
    } catch (_) {
      _discardSession();
      if (mounted) {
        setState(() {
          _challenge = null;
          _code.clear();
          _error = 'Не удалось сохранить подключение. Попробуйте ещё раз.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendEmail() async {
    if (_emailSending || _emailCooldown || _busy) return;
    setState(() {
      _emailSending = true;
      _error = null;
    });
    try {
      await _auth.sendEmailCode(_username.text.trim(), session: _session);
      if (!mounted) return;
      setState(() {
        _notice = 'Код отправлен на почту вашего аккаунта.';
        _emailCooldown = true;
      });
      _emailTimer = Timer(const Duration(seconds: 30), () {
        if (mounted) setState(() => _emailCooldown = false);
      });
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _emailSending = false);
    }
  }

  void _openGuide() {
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute(
            builder: (_) =>
                const TokenGuideScreen(doneLabel: 'Перейти к вводу токена'),
          ),
        )
        .then((_) {
          if (mounted && !_busy) _reset(manual: true);
        });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final challenge = _challenge;
    final locked = _busy || challenge != null;
    return PopScope(
      canPop: !_busy && !_emailSending && widget.onCancel == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy && !_emailSending) widget.onCancel?.call();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: widget.onCancel == null
              ? const CampusWordmark()
              : TextButton.icon(
                  onPressed: _busy ? null : widget.onCancel,
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  label: const Text('К пропуску'),
                ),
          actions: [
            IconButton(
              tooltip: 'Где взять токен?',
              onPressed: _busy ? null : _openGuide,
              icon: const Icon(Icons.help_outline_rounded),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                        child: AutofillGroup(
                          onDisposeAction: AutofillContextAction.cancel,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                challenge != null
                                    ? 'ПОДТВЕРЖДЕНИЕ ВХОДА'
                                    : 'ПОДКЛЮЧЕНИЕ',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  letterSpacing: 1,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                challenge != null
                                    ? 'Подтвердите\nподключение'
                                    : 'Пропуск.\nВсегда под рукой.',
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -1,
                                  height: 1.12,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _manual
                                    ? 'Вставьте личный токен из настроек Rocket.Chat.'
                                    : challenge != null
                                    ? 'Rocket.Chat просит подтвердить, что это вы.'
                                    : 'Войдите в Rocket.Chat Школы 21 один раз, чтобы получать QR прямо здесь.',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 32),
                              if (_manual) ...[
                                TextField(
                                  controller: _token,
                                  enabled: !_busy,
                                  obscureText: true,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Токен Rocket.Chat',
                                  ),
                                  onSubmitted: (_) => _submit(),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: _busy ? null : _openGuide,
                                    child: const Text('Где взять токен?'),
                                  ),
                                ),
                              ] else if (challenge == null) ...[
                                TextField(
                                  controller: _username,
                                  enabled: !locked,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  autofillHints: const [AutofillHints.username],
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Логин или почта Rocket.Chat',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _password,
                                  enabled: !locked,
                                  obscureText: !_showPassword,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  autofillHints: const [AutofillHints.password],
                                  decoration: InputDecoration(
                                    labelText: 'Пароль',
                                    suffixIcon: IconButton(
                                      tooltip: _showPassword
                                          ? 'Скрыть пароль'
                                          : 'Показать пароль',
                                      onPressed: () => setState(
                                        () => _showPassword = !_showPassword,
                                      ),
                                      icon: Icon(
                                        _showPassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (_) => _submit(),
                                ),
                              ] else ...[
                                Text(
                                  _username.text.trim(),
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 16),
                                if (challenge.availableMethods.length > 1) ...[
                                  DropdownButtonFormField<String>(
                                    initialValue: challenge.method,
                                    decoration: const InputDecoration(
                                      labelText: 'Способ подтверждения',
                                    ),
                                    items: challenge.availableMethods
                                        .map(
                                          (method) => DropdownMenuItem(
                                            value: method,
                                            child: Text(switch (method) {
                                              'email' => 'Код из письма',
                                              'totp' =>
                                                'Приложение-аутентификатор',
                                              _ => 'Пароль',
                                            }),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: _busy
                                        ? null
                                        : (method) {
                                            if (method == null) return;
                                            setState(() {
                                              _challenge = TwoFactorChallenge(
                                                method: method,
                                                availableMethods:
                                                    challenge.availableMethods,
                                              );
                                              _code.clear();
                                              _error = null;
                                              _notice = null;
                                            });
                                          },
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                TextField(
                                  key: ValueKey(
                                    'confirmation-${challenge.method}',
                                  ),
                                  controller: _code,
                                  enabled: !_busy,
                                  obscureText: challenge.method == 'password',
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  autofillHints: challenge.method == 'password'
                                      ? null
                                      : const [AutofillHints.oneTimeCode],
                                  keyboardType: challenge.method == 'password'
                                      ? TextInputType.visiblePassword
                                      : TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: switch (challenge.method) {
                                      'email' => 'Код из письма',
                                      'totp' => 'Код из аутентификатора',
                                      _ => 'Пароль Rocket.Chat',
                                    },
                                  ),
                                  onSubmitted: (_) => _submit(),
                                ),
                                if (challenge.method == 'email')
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed:
                                          _busy ||
                                              _emailSending ||
                                              _emailCooldown
                                          ? null
                                          : _sendEmail,
                                      child: Text(
                                        _emailSending
                                            ? 'Отправляем…'
                                            : _emailCooldown
                                            ? 'Код отправлен'
                                            : 'Отправить код на почту',
                                      ),
                                    ),
                                  ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _reset(manual: false),
                                    child: const Text('Другой аккаунт'),
                                  ),
                                ),
                              ],
                              if (_notice != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      _notice!,
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      _error!,
                                      style: TextStyle(color: colors.error),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 32),
                              const Spacer(),
                              FilledButton(
                                onPressed: _busy || _emailSending
                                    ? null
                                    : _submit,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_busy) ...[
                                      const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                    Flexible(
                                      child: Text(
                                        _busy
                                            ? 'Подключаем…'
                                            : _manual
                                            ? 'Сохранить и получить QR'
                                            : challenge != null
                                            ? 'Подтвердить'
                                            : 'Подключить Rocket.Chat',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: _busy || _emailSending
                                    ? null
                                    : () => _reset(manual: !_manual),
                                child: Text(
                                  _manual
                                      ? 'Войти по логину и паролю'
                                      : 'У меня есть токен',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 16,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Токен хранится в защищённом хранилище устройства.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
