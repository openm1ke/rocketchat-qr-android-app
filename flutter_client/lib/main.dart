import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'rocket_chat_client.dart';

void main() => runApp(const CampusPassApp());

class CampusPassApp extends StatelessWidget {
  const CampusPassApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Пропуск в кампус',
    theme: ThemeData(colorSchemeSeed: const Color(0xff006b58)),
    darkTheme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xff006b58),
    ),
    home: const PassScreen(),
  );
}

class PassScreen extends StatefulWidget {
  const PassScreen({super.key});

  @override
  State<PassScreen> createState() => _PassScreenState();
}

class _PassScreenState extends State<PassScreen> with WidgetsBindingObserver {
  static const _tokenKey = 'rocketchat_token';
  // Matches the existing Android client's provisional expiry policy.
  static const _lifetime = Duration(seconds: 30);
  final _storage = const FlutterSecureStorage();
  final _client = RocketChatClient();
  final _input = TextEditingController();
  String? _token;
  Uint8List? _image;
  DateTime? _expires;
  DateTime? _expiresOn;
  Timer? _expiryTimer;
  String? _error;
  bool _loading = true;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreToken());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiryTimer?.cancel();
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _expires != null &&
        !DateTime.now().isBefore(_expires!)) {
      _expire();
    }
  }

  Future<void> _restoreToken() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      if (!mounted) return;
      setState(() {
        _token = token;
        _loading = false;
      });
      if (token != null) await _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось прочитать сохранённый токен.';
      });
    }
  }

  Future<void> _saveToken() async {
    if (_loading) return;
    final token = _input.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Вставьте токен Rocket.Chat.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось сохранить токен.';
      });
      return;
    }
    if (!mounted) return;
    _input.clear();
    _expiryTimer?.cancel();
    setState(() {
      _token = token;
      _image = null;
      _expires = null;
      _expiresOn = null;
      _editing = false;
      _loading = false;
    });
    await _refresh();
  }

  void _expire() {
    _expiryTimer?.cancel();
    setState(() {
      _image = null;
      _expires = null;
      _expiresOn = null;
    });
  }

  Future<void> _refresh() async {
    final token = _token;
    if (_loading || token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pass = await _client.requestPass(token);
      final image = pass.image;
      final expires = pass.expiresOn ?? DateTime.now().add(_lifetime);
      final codec = await ui.instantiateImageCodec(image);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (!mounted) return;
      _expiryTimer?.cancel();
      final remaining = expires.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _expire();
        return;
      }
      setState(() {
        _image = image;
        _expires = expires;
        _expiresOn = pass.expiresOn;
      });
      _expiryTimer = Timer(remaining, _expire);
    } on PassException catch (failure) {
      if (!mounted) return;
      if (failure.kind == PassError.authorization) _expire();
      setState(
        () => _error = switch (failure.kind) {
          PassError.authorization =>
            'Rocket.Chat отклонил токен. Проверьте или замените его.',
          PassError.network =>
            'Нет соединения с Rocket.Chat. Проверьте сеть и повторите.',
          PassError.timeout =>
            'Rocket.Chat или бот не ответил вовремя. Повторите запрос.',
          PassError.bot => 'Rocket.Chat не смог выполнить команду бота.',
          PassError.response => 'В ответе бота не удалось прочитать QR-код.',
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Не удалось открыть изображение QR-кода.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = _editing || (_token == null && !_loading);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Пропуск в кампус'),
        actions: [
          if (_token != null && !_editing)
            IconButton(
              tooltip: 'Заменить токен',
              onPressed: _loading
                  ? null
                  : () => setState(() {
                      _editing = true;
                      _error = null;
                    }),
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.qr_code_2, size: 48, color: colors.primary),
                  const SizedBox(height: 16),
                  Text(
                    setup ? 'Подключите Rocket.Chat' : 'QR-код для входа',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (setup) ...[
                    const Text(
                      'Вставьте токен личного доступа из настроек Rocket.Chat.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _input,
                      enabled: !_loading,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Токен Rocket.Chat',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _saveToken(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loading ? null : _saveToken,
                      child: const Text('Сохранить и получить QR'),
                    ),
                    if (_token != null)
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => setState(() {
                                _input.clear();
                                _editing = false;
                                _error = null;
                              }),
                        child: const Text('Отмена'),
                      ),
                  ] else ...[
                    if (_image case final image?)
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(16),
                        child: Image.memory(
                          image,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.none,
                          semanticLabel: 'QR-код для турникета',
                        ),
                      )
                    else if (!_loading)
                      const Text(
                        'Получите новый код перед проходом.',
                        textAlign: TextAlign.center,
                      ),
                    if (_expiresOn case final date?) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Срок действия до ${date.day.toString().padLeft(2, '0')}.'
                        '${date.month.toString().padLeft(2, '0')}.${date.year}',
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_token != null) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loading ? null : _refresh,
                        child: Text(
                          _image == null ? 'Получить QR' : 'Обновить QR',
                        ),
                      ),
                    ],
                  ],
                  if (_loading) const LinearProgressIndicator(),
                  if (_error case final error?) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(error, style: TextStyle(color: colors.error)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
