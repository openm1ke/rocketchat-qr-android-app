import 'package:flutter/material.dart';

import 'pass_appearance.dart';
import 'pass_color_picker.dart';
import 'pass_theme.dart';
import 'token_guide.dart';
import 'request_log_screen.dart';

class PassSettings extends StatefulWidget {
  const PassSettings({
    super.key,
    required this.appearance,
    required this.onChanged,
    required this.onChoosePhoto,
    this.onEditToken,
  });

  final PassAppearance appearance;
  final ValueChanged<PassAppearance> onChanged;
  final Future<bool> Function() onChoosePhoto;
  final VoidCallback? onEditToken;

  @override
  State<PassSettings> createState() => _PassSettingsState();
}

class _PassSettingsState extends State<PassSettings> {
  late PassAppearance _value = widget.appearance;
  bool _pickingPhoto = false;

  void _change(PassAppearance value, {bool save = true}) {
    setState(() => _value = value);
    if (save) widget.onChanged(value);
  }

  Future<void> _choosePhoto() async {
    setState(() => _pickingPhoto = true);
    try {
      if (await widget.onChoosePhoto() && mounted) {
        _change(_value.copyWith(backdrop: PassBackdrop.photo));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть фотографию.')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<Color?> _pickColor(Color color) => showDialog<Color>(
    context: context,
    builder: (_) => Theme(
      data: _theme,
      child: PassColorDialog(color: color),
    ),
  );

  Future<void> _chooseColor({required bool isAccent}) async {
    final result = await _pickColor(
      isAccent ? _value.accent : _value.background,
    );
    if (!mounted || result == null) return;
    _change(
      isAccent
          ? _value.copyWith(accent: result)
          : _value.copyWith(
              background: result,
              backdrop: PassBackdrop.solid,
              ambientUseCustomBase: true,
            ),
    );
  }

  Color get _ambientBase => _value.ambientUseCustomBase
      ? _value.background
      : _theme.colorScheme.surface;

  Future<void> _chooseAmbientBase() async {
    final result = await _pickColor(_ambientBase);
    if (!mounted || result == null) return;
    _change(_value.copyWith(background: result, ambientUseCustomBase: true));
  }

  Future<void> _editAmbientColor(int index) async {
    final result = await _pickColor(_value.ambientColors[index]);
    if (!mounted || result == null) return;
    final colors = [..._value.ambientColors];
    colors[index] = result;
    _change(_value.copyWith(ambientColors: colors));
  }

  Future<void> _addAmbientColor() async {
    if (_value.ambientColors.length >= 5) return;
    final result = await _pickColor(_value.ambientColors.last);
    if (!mounted || result == null) return;
    _change(_value.copyWith(ambientColors: [..._value.ambientColors, result]));
  }

  String _hex(Color color) =>
      '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Widget _section(String title, List<Widget> children) {
    final theme = _theme;
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          Semantics(
            container: true,
            explicitChildNodes: true,
            child: Material(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String title,
    double value,
    double min,
    double max,
    PassAppearance Function(double) update,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(title)),
              Text('${(value * 100).round()}%'),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) * 20).round(),
            onChanged: (next) => _change(update(next), save: false),
            onChangeEnd: (next) => _change(update(next)),
          ),
        ],
      ),
    );
  }

  ThemeData get _theme {
    final brightness = switch (_value.theme) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    return passTheme(brightness: brightness, accent: _value.accent);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _theme,
      child: Scaffold(
        appBar: AppBar(title: const Text('Настройки пропуска')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              _section('Главное', [
                _slider(
                  'Размер QR',
                  _value.qrSize,
                  .65,
                  1,
                  (v) => _value.copyWith(qrSize: v),
                ),
                SwitchListTile(
                  title: const Text('Показывать срок действия'),
                  value: _value.showExpiry,
                  onChanged: (v) => _change(_value.copyWith(showExpiry: v)),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_outlined),
                  title: const Text('Выбрать фото для фона'),
                  subtitle: _value.backdrop == PassBackdrop.photo
                      ? const Text('Сейчас используется фото')
                      : null,
                  trailing: _pickingPhoto
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _pickingPhoto ? null : _choosePhoto,
                ),
              ]),
              _section('Оформление', [
                if (_value.backdrop != PassBackdrop.ambient)
                  ListTile(
                    title: const Text('Живой фон'),
                    leading: const Icon(Icons.blur_on_rounded),
                    onTap: () => _change(
                      _value.copyWith(backdrop: PassBackdrop.ambient),
                    ),
                  ),
                ListTile(
                  title: const Text('Тема'),
                  trailing: DropdownButton<ThemeMode>(
                    value: _value.theme,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('Тёмная'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('Светлая'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('Как в системе'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) _change(_value.copyWith(theme: v));
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Цвет акцента'),
                  trailing: _Swatch(_value.accent),
                  onTap: () => _chooseColor(isAccent: true),
                ),
                ListTile(
                  title: const Text('Однотонный фон'),
                  trailing: _Swatch(_value.background),
                  onTap: () => _chooseColor(isAccent: false),
                ),
                if (_value.backdrop != PassBackdrop.gradient)
                  ListTile(
                    title: const Text('Вернуть градиент'),
                    leading: const Icon(Icons.gradient_outlined),
                    onTap: () => _change(
                      _value.copyWith(backdrop: PassBackdrop.gradient),
                    ),
                  ),
                if (_value.backdrop != PassBackdrop.plain)
                  ListTile(
                    title: const Text('Стандартный фон'),
                    leading: const Icon(Icons.crop_square_rounded),
                    onTap: () =>
                        _change(_value.copyWith(backdrop: PassBackdrop.plain)),
                  ),
                if (_value.backdrop == PassBackdrop.photo)
                  _slider(
                    'Затемнение фото',
                    _value.photoShade,
                    .2,
                    .85,
                    (v) => _value.copyWith(photoShade: v),
                  ),
              ]),
              if (_value.backdrop == PassBackdrop.ambient)
                _section('Цвета живого фона', [
                  SwitchListTile(
                    title: const Text('Движение фона'),
                    subtitle: const Text(
                      'Перетекающий градиент, до 24 кадров/с',
                    ),
                    value: _value.ambientMotion,
                    onChanged: (value) =>
                        _change(_value.copyWith(ambientMotion: value)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.terminal_rounded),
                    title: const Text('Матрица'),
                    subtitle: const Text(
                      'Чёрный, тёмно-зелёный, светло-зелёный',
                    ),
                    onTap: () => _change(
                      _value.copyWith(
                        background: const Color(0xff000000),
                        ambientUseCustomBase: true,
                        ambientColors: const [
                          Color(0xff8df86b),
                          Color(0xff0a5e2a),
                          Color(0xff000000),
                        ],
                      ),
                    ),
                  ),
                  ListTile(
                    leading: _Swatch(_ambientBase),
                    title: const Text('Цвет основы'),
                    subtitle: Text(
                      '${_hex(_ambientBase)} · общий с однотонным фоном',
                    ),
                    onTap: _chooseAmbientBase,
                  ),
                  for (var i = 0; i < _value.ambientColors.length; i++)
                    ListTile(
                      leading: _Swatch(_value.ambientColors[i]),
                      title: Text('Цвет ${i + 1}'),
                      subtitle: Text(_hex(_value.ambientColors[i])),
                      onTap: () => _editAmbientColor(i),
                      trailing: IconButton(
                        tooltip: 'Удалить цвет ${i + 1}',
                        onPressed: _value.ambientColors.length <= 2
                            ? null
                            : () {
                                final colors = [..._value.ambientColors]
                                  ..removeAt(i);
                                _change(_value.copyWith(ambientColors: colors));
                              },
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add_rounded),
                    title: const Text('Добавить цвет'),
                    subtitle: Text(
                      '${_value.ambientColors.length} из 5 · выберите свой оттенок',
                    ),
                    enabled: _value.ambientColors.length < 5,
                    onTap: _value.ambientColors.length >= 5
                        ? null
                        : _addAmbientColor,
                  ),
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('Вернуть нейтральную палитру'),
                    onTap: () => _change(
                      _value.copyWith(
                        ambientColors: PassAppearance.defaultAmbientColors,
                        ambientUseCustomBase: false,
                      ),
                    ),
                  ),
                ]),
              _section('Сканирование', [
                _slider(
                  'Размер в режиме сканирования',
                  _value.scanSize,
                  .75,
                  1,
                  (v) => _value.copyWith(scanSize: v),
                ),
                SwitchListTile(
                  title: const Text('Повышать яркость'),
                  value: _value.boostBrightness,
                  onChanged: (v) =>
                      _change(_value.copyWith(boostBrightness: v)),
                ),
                SwitchListTile(
                  title: const Text('Отклик при нажатии на QR'),
                  value: _value.haptics,
                  onChanged: (v) => _change(_value.copyWith(haptics: v)),
                ),
              ]),
              _section('Аккаунт и сброс', [
                ListTile(
                  leading: const Icon(Icons.help_outline_rounded),
                  title: const Text('Где взять токен?'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const TokenGuideScreen()),
                  ),
                ),
                if (widget.onEditToken != null)
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: const Text('Подключение Rocket.Chat'),
                    subtitle: const Text('Войти заново или заменить токен'),
                    onTap: widget.onEditToken,
                  ),
                ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('Сбросить оформление'),
                  onTap: () => _change(const PassAppearance()),
                ),
              ]),
              _section('Для разработчиков', [
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Журнал запросов'),
                  subtitle: const Text(
                    'HTTP, WebSocket и результаты подключения',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          Theme(data: _theme, child: const RequestLogScreen()),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Theme.of(context).colorScheme.outline),
    ),
  );
}
