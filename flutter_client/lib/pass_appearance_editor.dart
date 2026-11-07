import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ambient_background.dart';
import 'pass_appearance.dart';
import 'pass_color_picker.dart';

/// The mode is chosen explicitly. Editing a color never changes that mode.
class PassAppearanceEditor extends StatelessWidget {
  const PassAppearanceEditor({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onPreviewChanged,
  });

  final PassAppearance value;
  final ValueChanged<PassAppearance> onChanged;
  final ValueChanged<PassAppearance> onPreviewChanged;

  static const _matrix = [
    Color(0xff8df86b),
    Color(0xff0a5e2a),
    Color(0xff000000),
  ];

  bool get _glow => value.backdrop == PassBackdrop.ambient;

  Color _base(BuildContext context) =>
      value.backgroundFor(Theme.of(context).colorScheme.surface);

  Future<Color?> _pickColor(
    BuildContext context,
    Color color, {
    VoidCallback? onDelete,
  }) => showDialog<Color>(
    context: context,
    builder: (_) => Theme(
      data: Theme.of(context),
      child: PassColorDialog(color: color, onDelete: onDelete),
    ),
  );

  Future<void> _editColor(BuildContext context, int index) async {
    final result = await _pickColor(
      context,
      value.ambientColors[index],
      onDelete: value.ambientColors.length > 2
          ? () {
              if (!context.mounted) return;
              final colors = [...value.ambientColors]..removeAt(index);
              onChanged(value.copyWith(ambientColors: colors));
            }
          : null,
    );
    if (!context.mounted || result == null) return;
    final colors = [...value.ambientColors];
    colors[index] = result;
    onChanged(value.copyWith(ambientColors: colors));
  }

  Future<void> _addColor(BuildContext context) async {
    if (value.ambientColors.length >= 5) return;
    final result = await _pickColor(context, value.ambientColors.last);
    if (!context.mounted || result == null) return;
    onChanged(value.copyWith(ambientColors: [...value.ambientColors, result]));
  }

  Future<void> _changeColor(BuildContext context, {bool accent = false}) async {
    final result = await _pickColor(
      context,
      accent ? value.accent : _base(context),
    );
    if (!context.mounted || result == null) return;
    onChanged(
      accent
          ? value.copyWith(accent: result)
          : value.copyWith(background: result, ambientUseCustomBase: true),
    );
  }

  void _selectMode(BuildContext context, PassBackdrop mode) {
    if (value.backdrop == mode) return;
    onChanged(
      value.copyWith(
        backdrop: mode,
        background: _base(context),
        ambientUseCustomBase: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: _Preview(value: value, base: _base(context)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ModeButton(
                  label: 'Свечение',
                  icon: Icons.blur_on_rounded,
                  selected: _glow,
                  onTap: () => _selectMode(context, PassBackdrop.ambient),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModeButton(
                  label: 'Сплошной цвет',
                  icon: Icons.format_color_fill_rounded,
                  selected: !_glow,
                  onTap: () => _selectMode(context, PassBackdrop.solid),
                ),
              ),
            ],
          ),
        ),
        if (_glow) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Row(
              children: [
                const Expanded(child: Text('Интенсивность движения')),
                const SizedBox(width: 8),
                Text('${(value.ambientIntensity * 100).round()}%'),
              ],
            ),
          ),
          Slider(
            key: const ValueKey('ambient-intensity'),
            value: value.ambientIntensity,
            divisions: 20,
            semanticFormatterCallback: (v) =>
                v == 0 ? 'Без движения' : '${(v * 100).round()}%',
            onChanged: (next) =>
                onPreviewChanged(value.copyWith(ambientIntensity: next)),
            onChangeEnd: (next) =>
                onChanged(value.copyWith(ambientIntensity: next)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('Без движения', style: theme.textTheme.bodySmall),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Активное',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          if (MediaQuery.disableAnimationsOf(context))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Движение отключено в настройках устройства.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('Цвета свечения', style: theme.textTheme.bodyMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var i = 0; i < value.ambientColors.length; i++)
                  IconButton(
                    tooltip: 'Изменить цвет ${i + 1}',
                    onPressed: () => _editColor(context, i),
                    icon: _Swatch(value.ambientColors[i], size: 36),
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                  ),
                if (value.ambientColors.length < 5)
                  IconButton.outlined(
                    tooltip: 'Добавить цвет',
                    onPressed: () => _addColor(context),
                    icon: const Icon(Icons.add_rounded),
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Мягкая'),
                  selected:
                      !value.ambientUseCustomBase &&
                      listEquals(
                        value.ambientColors,
                        PassAppearance.defaultAmbientColors,
                      ),
                  onSelected: (_) => onChanged(
                    value.copyWith(
                      ambientColors: PassAppearance.defaultAmbientColors,
                      ambientUseCustomBase: false,
                    ),
                  ),
                ),
                ChoiceChip(
                  label: const Text('Матрица'),
                  selected:
                      value.ambientUseCustomBase &&
                      value.background == Colors.black &&
                      listEquals(value.ambientColors, _matrix),
                  onSelected: (_) => onChanged(
                    value.copyWith(
                      background: Colors.black,
                      ambientUseCustomBase: true,
                      ambientColors: _matrix,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else
          const SizedBox(height: 16),
        ListTile(
          title: const Text('Цвет фона'),
          subtitle: Text(
            _glow ? 'Основа под свечением' : 'Заливка всего экрана',
          ),
          trailing: _Swatch(_base(context)),
          onTap: () => _changeColor(context),
        ),
        ListTile(
          title: const Text('Цвет акцента'),
          subtitle: const Text('Кнопки и элементы управления'),
          trailing: _Swatch(value.accent),
          onTap: () => _changeColor(context, accent: true),
        ),
        const Divider(indent: 16, endIndent: 16, height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Тема меню'),
              DropdownButton<ThemeMode>(
                isExpanded: true,
                value: value.theme,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('Светлая'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    child: Text('Тёмная'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('Системная'),
                  ),
                ],
                onChanged: (mode) {
                  if (mode != null) onChanged(value.copyWith(theme: mode));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.value, required this.base});
  final PassAppearance value;
  final Color base;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Предпросмотр фона',
      image: true,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 168,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: base),
                if (value.backdrop == PassBackdrop.ambient)
                  AmbientBackground(
                    base: base,
                    enabled: value.ambientMotion,
                    intensity: value.ambientIntensity,
                    colors: value.ambientColors,
                  ),
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          'Предпросмотр',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.qr_code_2_rounded,
                      size: 64,
                      color: Colors.black,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.refresh_rounded,
                          size: 16,
                          color: colors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(80),
          padding: const EdgeInsets.all(12),
          backgroundColor: selected
              ? colors.primary.withValues(alpha: .1)
              : colors.surfaceContainer,
          foregroundColor: colors.onSurface,
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Column(
          children: [
            Icon(selected ? Icons.check_circle_rounded : icon, size: 24),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.color, {this.size = 28});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Theme.of(context).colorScheme.outline),
    ),
  );
}
