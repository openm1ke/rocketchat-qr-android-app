import 'package:flutter/material.dart';

import 'pass_appearance.dart';
import 'pass_appearance_editor.dart';
import 'pass_theme.dart';
import 'token_guide.dart';
import 'request_log_screen.dart';

class PassSettings extends StatefulWidget {
  const PassSettings({
    super.key,
    required this.appearance,
    required this.onChanged,
    this.onEditToken,
  });

  final PassAppearance appearance;
  final ValueChanged<PassAppearance> onChanged;
  final VoidCallback? onEditToken;

  @override
  State<PassSettings> createState() => _PassSettingsState();
}

class _PassSettingsState extends State<PassSettings> {
  late PassAppearance _value = widget.appearance;

  void _change(PassAppearance value, {bool save = true}) {
    setState(() => _value = value);
    if (save) widget.onChanged(value);
  }

  Widget _section(String title, List<Widget> children) {
    final theme = _theme;
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
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
              _section('Оформление', [
                PassAppearanceEditor(
                  value: _value,
                  onChanged: _change,
                  onPreviewChanged: (value) => _change(value, save: false),
                ),
              ]),
              _section('Пропуск', [
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
