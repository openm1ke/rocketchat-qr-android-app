import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'pass_appearance.dart';
import 'pass_settings.dart';
import 'qr_transition.dart';
import 'rocket_chat_client.dart';

void main() => runApp(const CampusPassApp());

class CampusPassApp extends StatelessWidget {
  const CampusPassApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
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
  static const _appearanceKey = 'pass_appearance_v1';
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
  bool _expanded = false;
  PassAppearance _appearance = const PassAppearance();
  Uint8List? _backgroundPhoto;
  Future<void> _appearanceWrite = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreAppearance());
    unawaited(_restoreToken());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiryTimer?.cancel();
    if (_expanded) unawaited(_setScanBrightness(false));
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_expanded &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused)) {
      _toggleScanMode();
    }
    if (state == AppLifecycleState.resumed &&
        _expires != null &&
        !DateTime.now().isBefore(_expires!)) {
      _expire();
    }
  }

  Future<File> _photoFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/pass-background.jpg');
  }

  Future<void> _restoreAppearance() async {
    try {
      final value = PassAppearance.decode(
        await _storage.read(key: _appearanceKey),
      );
      if (!mounted) return;
      setState(() => _appearance = value);
      if (Platform.isAndroid) {
        final lost = await ImagePicker().retrieveLostData();
        final files = lost.files;
        if (mounted && files != null && files.isNotEmpty) {
          if (await _storeBackgroundPhoto(files.first) && mounted) {
            _saveAppearance(_appearance.copyWith(backdrop: PassBackdrop.photo));
            return;
          }
        }
      }
      if (value.backdrop == PassBackdrop.photo) {
        final photo = await (await _photoFile()).readAsBytes();
        if (mounted && identical(_appearance, value)) {
          setState(() => _backgroundPhoto = photo);
        }
      }
    } catch (error) {
      debugPrint('Unable to restore pass appearance: $error');
    }
  }

  void _saveAppearance(PassAppearance value) {
    setState(() => _appearance = value);
    _appearanceWrite = _appearanceWrite.then((_) async {
      try {
        await _storage.write(key: _appearanceKey, value: value.encode());
      } catch (error) {
        debugPrint('Unable to save pass appearance: $error');
      }
    });
  }

  Future<bool> _chooseBackgroundPhoto() async {
    final selected = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (selected == null) return false;
    return _storeBackgroundPhoto(selected);
  }

  Future<bool> _storeBackgroundPhoto(XFile selected) async {
    if (!mounted) return false;
    if (await selected.length() > 8 * 1024 * 1024) {
      throw const FormatException('Background photo is too large');
    }
    final photo = await selected.readAsBytes();
    final codec = await ui.instantiateImageCodec(photo, targetWidth: 1200);
    try {
      (await codec.getNextFrame()).image.dispose();
    } finally {
      codec.dispose();
    }
    final file = await _photoFile();
    final pending = await File('${file.path}.tmp')
        .writeAsBytes(photo, flush: true);
    await pending.rename(file.path);
    if (!mounted) return false;
    setState(() => _backgroundPhoto = photo);
    return true;
  }

  void _openSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (settingsContext) => PassSettings(
          appearance: _appearance,
          onChanged: _saveAppearance,
          onChoosePhoto: _chooseBackgroundPhoto,
          onEditToken: _token == null || _loading
              ? null
              : () {
                  Navigator.pop(settingsContext);
                  setState(() {
                    _editing = true;
                    _error = null;
                  });
                },
        ),
      ),
    );
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

  Future<void> _setScanBrightness(bool enabled) async {
    try {
      if (enabled) {
        if (!_appearance.boostBrightness) return;
        await ScreenBrightness.instance.setApplicationScreenBrightness(1);
      } else {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      }
    } catch (error) {
      debugPrint('Unable to change scan brightness: $error');
    }
  }

  void _toggleScanMode() {
    if (!_expanded && _image == null) return;
    if (_appearance.haptics) unawaited(HapticFeedback.selectionClick());
    setState(() => _expanded = !_expanded);
    unawaited(_setScanBrightness(_expanded));
  }

  void _expire() {
    if (_expanded) _toggleScanMode();
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
      if (!mounted) return;
      Object? decodeError;
      await precacheImage(
        MemoryImage(image),
        context,
        onError: (error, _) => decodeError = error,
      );
      if (decodeError case final error?) throw error;
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

  Widget _qrImage(Uint8List image, {bool expanded = false}) {
    return Semantics(
      button: true,
      hint: expanded ? 'Вернуться к пропуску' : 'Увеличить QR-код',
      child: GestureDetector(
        onTap: _toggleScanMode,
        child: QrTransition(image: image, loading: _loading),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_image case final image? when _expanded) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toggleScanMode();
        },
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FractionallySizedBox(
                  widthFactor: _appearance.scanSize,
                  heightFactor: _appearance.scanSize,
                  child: _qrImage(image, expanded: true),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final brightness = switch (_appearance.theme) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final colors = ColorScheme.fromSeed(
      seedColor: _appearance.accent,
      brightness: brightness,
    );
    return Theme(
      data: ThemeData(colorScheme: colors, useMaterial3: true),
      child: Builder(builder: _buildPass),
    );
  }

  Widget _buildPass(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final setup = _editing || (_token == null && !_loading);
    final custom = _appearance.backdrop;
    final photo = custom == PassBackdrop.photo ? _backgroundPhoto : null;
    final background = custom == PassBackdrop.solid
        ? _appearance.background
        : colors.brightness == Brightness.dark
        ? const Color(0xff101821)
        : const Color(0xffeaf1ef);
    final onBackground =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : const Color(0xff152520);

    return Scaffold(
      backgroundColor: background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (photo != null) ...[
            Image.memory(photo, fit: BoxFit.cover, excludeFromSemantics: true),
            ColoredBox(
              color: Colors.black.withValues(alpha: _appearance.photoShade),
            ),
          ] else if (custom != PassBackdrop.solid)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(.85, -.8),
                  radius: 1.15,
                  colors: [
                    Color.alphaBlend(
                      _appearance.accent.withValues(alpha: .24),
                      background,
                    ),
                    background,
                  ],
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(Icons.qr_code_2, color: colors.onPrimary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Пропуск в кампус',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: photo == null
                                  ? onBackground
                                  : Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Настройки пропуска',
                          onPressed: _editing ? null : _openSettings,
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  setup
                                      ? 'Подключите Rocket.Chat'
                                      : 'QR-код для входа',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (_image != null && !setup)
                                Icon(
                                  Icons.check_circle_outline,
                                  color: colors.primary,
                                  semanticLabel: 'QR готов',
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (setup)
                            ..._tokenForm()
                          else ...[
                            if (_image case final image?) ...[
                              FractionallySizedBox(
                                widthFactor: _appearance.qrSize,
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: _qrImage(image),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_appearance.showExpiry && _expiresOn != null)
                                Text(
                                  'Срок действия до ${_expiresOn!.day.toString().padLeft(2, '0')}.'
                                  '${_expiresOn!.month.toString().padLeft(2, '0')}.${_expiresOn!.year}',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              Text(
                                'Нажмите на QR, чтобы увеличить',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ] else if (!_loading)
                              const Text('Получите код перед проходом.'),
                            if (_token != null) ...[
                              const SizedBox(height: 14),
                              FilledButton.tonalIcon(
                                onPressed: _loading ? null : _refresh,
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(
                                  _image == null
                                      ? 'Получить QR'
                                      : 'Обновить QR',
                                ),
                              ),
                            ],
                          ],
                          if (_loading) ...[
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(),
                          ],
                          if (_error case final error?) ...[
                            const SizedBox(height: 12),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                error,
                                style: TextStyle(color: colors.error),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _tokenForm() => [
    const Text('Вставьте токен личного доступа из настроек Rocket.Chat.'),
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
  ];
}
