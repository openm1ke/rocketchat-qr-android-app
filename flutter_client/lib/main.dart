import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'connection_screen.dart';
import 'pass_appearance.dart';
import 'pass_home.dart';
import 'pass_theme.dart';
import 'pass_settings.dart';
import 'qr_transition.dart';
import 'rocket_chat_client.dart';
import 'request_log.dart';

void main() => runApp(const CampusPassApp());

class CampusPassApp extends StatelessWidget {
  const CampusPassApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Пропуск в кампус',
    theme: passTheme(),
    darkTheme: passTheme(brightness: Brightness.dark),
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
  String? _token;
  Uint8List? _image;
  DateTime? _expires;
  DateTime? _expiresOn;
  Timer? _expiryTimer;
  String? _error;
  bool _loading = true;
  bool _editing = false;
  bool _expanded = false;
  bool _reconnectRequired = false;
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

  Future<void> _saveConnection(String token) async {
    // Commit only the personal/manual token. The login session never reaches storage.
    try {
      await _storage.write(key: _tokenKey, value: token);
      RequestLog.instance.credentialSaved(success: true);
    } catch (_) {
      RequestLog.instance.credentialSaved(success: false);
      rethrow;
    }
    if (!mounted) return;
    _expiryTimer?.cancel();
    setState(() {
      _token = token;
      _image = null;
      _expires = null;
      _expiresOn = null;
      _editing = false;
      _reconnectRequired = false;
      _error = null;
      _loading = false;
    });
    unawaited(_refresh());
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
        _reconnectRequired = false;
      });
      _expiryTimer = Timer(remaining, _expire);
    } on PassException catch (failure) {
      if (!mounted) return;
      if (failure.kind == PassError.authorization) {
        _expire();
        _reconnectRequired = true;
      }
      setState(
        () => _error = switch (failure.kind) {
          PassError.authorization => 'Подключение к Rocket.Chat больше не действует. Подключитесь заново.',
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
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark,
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
        ),
      );
    }

    final brightness = switch (_appearance.theme) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    return Theme(
      data: passTheme(brightness: brightness, accent: _appearance.accent),
      child: Builder(
        builder: (context) {
          if (_editing || (_token == null && !_loading)) {
            return ConnectionScreen(
              onConnected: _saveConnection,
              onCancel: _token == null
                  ? null
                  : () => setState(() => _editing = false),
            );
          }
          return PassHome(
            appearance: _appearance,
            loading: _loading,
            qr: _image == null ? null : _qrImage(_image!),
            expiresOn: _expiresOn,
            error: _error,
            reconnectRequired: _reconnectRequired,
            backgroundPhoto: _backgroundPhoto,
            onRefresh: _refresh,
            onConnect: () => setState(() {
              _editing = true;
              _error = null;
            }),
            onSettings: _openSettings,
          );
        },
      ),
    );
  }
}
