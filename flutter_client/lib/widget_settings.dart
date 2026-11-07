import 'dart:async';

import 'package:flutter/material.dart';

import 'home_screen_widgets.dart';

class HomeWidgetSettings extends StatefulWidget {
  const HomeWidgetSettings({
    super.key,
    required this.widgets,
    required this.onSync,
  });

  final HomeScreenWidgets widgets;
  final Future<bool> Function() onSync;

  @override
  State<HomeWidgetSettings> createState() => _HomeWidgetSettingsState();
}

class _HomeWidgetSettingsState extends State<HomeWidgetSettings>
    with WidgetsBindingObserver {
  WidgetCapabilities _capabilities = const WidgetCapabilities();
  WidgetPass? _pass;
  bool _busy = true;
  String? _error;
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_reload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiry?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final capabilities = await widget.widgets.capabilities();
      final pass = capabilities.supported ? await widget.widgets.read() : null;
      if (!mounted) return;
      _expiry?.cancel();
      if (pass != null) {
        _expiry = Timer(pass.expiresAt.difference(DateTime.now()), () {
          if (mounted) setState(() => _pass = null);
        });
      }
      setState(() {
        _capabilities = capabilities;
        _pass = pass;
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Не удалось прочитать данные виджета. Повторите попытку.';
        });
      }
    }
  }

  Future<void> _perform() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_capabilities.platform == 'android' &&
          !_capabilities.overlayAllowed) {
        await widget.widgets.requestOverlayPermission();
      } else {
        if (!await widget.onSync()) {
          throw StateError('Widget synchronisation failed');
        }
        if (_capabilities.platform == 'android' && _capabilities.pinSupported) {
          if (!await widget.widgets.requestPin()) {
            throw StateError('Launcher did not accept the pin request');
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Содержимое виджета обновлено')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Не удалось выполнить действие. Повторите попытку.',
        );
      }
    } finally {
      await _reload();
    }
  }

  Widget _step(int number, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(radius: 14, child: Text('$number')),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final android = _capabilities.platform == 'android';
    final pass = _pass;
    final title = android ? 'QR поверх рабочего стола' : 'Крупный QR на экране';
    final button = android && !_capabilities.overlayAllowed
        ? 'Разрешить показ поверх экрана'
        : android && _capabilities.pinSupported
        ? 'Добавить виджет'
        : 'Обновить виджет';
    return Scaffold(
      appBar: AppBar(title: const Text('Виджет рабочего стола')),
      bottomNavigationBar: _capabilities.supported
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: FilledButton.icon(
                onPressed: _busy ? null : _perform,
                icon: Icon(
                  android && !_capabilities.overlayAllowed
                      ? Icons.layers_outlined
                      : Icons.add_to_home_screen,
                ),
                label: Text(button, textAlign: TextAlign.center),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            android
                ? 'Нажмите на виджет — QR появится в отдельном окне поверх '
                      'рабочего стола. Основной экран приложения не откроется.'
                : 'Большой виджет сразу показывает QR. Нажатие на него '
                      'оставляет вас на рабочем столе.',
          ),
          const SizedBox(height: 24),
          Text('Предпросмотр', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 224,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: pass == null
                  ? Column(
                      children: [
                        const Icon(Icons.qr_code_2_rounded, size: 64),
                        const SizedBox(height: 12),
                        Text(
                          _busy
                              ? 'Загружаем…'
                              : 'Сначала получите QR в приложении',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        ColoredBox(
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Image.memory(
                                pass.image,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Последний полученный QR',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 24),
          if (!_busy && !_capabilities.supported)
            const Text(
              'Виджеты доступны на Android и на iPhone с iOS 17 или новее.',
            )
          else if (android) ...[
            _step(
              1,
              'Разрешите показ поверх других приложений. '
              'Это нужно только для отдельного окна QR.',
            ),
            _step(
              2,
              _capabilities.pinSupported
                  ? 'Нажмите «Добавить виджет» и подтвердите добавление на рабочий стол.'
                  : 'Зажмите рабочий стол → Виджеты → Пропуск в кампус.',
            ),
            _step(
              3,
              'Нажмите на QR в виджете. Закройте увеличенный код крестиком '
              'или нажатием на фон.',
            ),
          ] else ...[
            _step(1, 'Зажмите свободное место на рабочем столе iPhone.'),
            _step(2, 'Выберите «Изменить» → «Добавить виджет».'),
            _step(
              3,
              'Найдите Campus Pass и добавьте большой виджет «QR-пропуск».',
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Виджет обновляется после получения нового кода в приложении. '
            'Если код истёк, получите новый в приложении.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: colors.error)),
          ],
        ],
      ),
    );
  }
}
