import 'package:flutter/material.dart';

class PassColorDialog extends StatefulWidget {
  const PassColorDialog({super.key, required this.color, this.onDelete});
  final Color color;
  final VoidCallback? onDelete;

  @override
  State<PassColorDialog> createState() => _PassColorDialogState();
}

class _PassColorDialogState extends State<PassColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.color);
  void _select(HSVColor value) => setState(() => _hsv = value);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Выберите цвет'),
    content: SizedBox(
      width: 280,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 160,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  void select(Offset position) => _select(
                    _hsv
                        .withSaturation(
                          (position.dx / constraints.maxWidth).clamp(0.0, 1.0),
                        )
                        .withValue((1 - position.dy / 160).clamp(0.0, 1.0)),
                  );
                  return Semantics(
                    label: 'Насыщенность и яркость цвета',
                    child: GestureDetector(
                      key: const ValueKey('color-sv'),
                      behavior: HitTestBehavior.opaque,
                      onPanDown: (details) => select(details.localPosition),
                      onPanUpdate: (details) => select(details.localPosition),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white,
                                      HSVColor.fromAHSV(
                                        1,
                                        _hsv.hue,
                                        1,
                                        1,
                                      ).toColor(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Colors.black],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: _hsv.saturation * constraints.maxWidth - 8,
                              top: (1 - _hsv.value) * 160 - 8,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black54,
                                      blurRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Оттенок',
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(
                        colors: [
                          Colors.red,
                          Colors.yellow,
                          Color(0xff00ff00),
                          Colors.cyan,
                          Colors.blue,
                          Color(0xffff00ff),
                          Colors.red,
                        ],
                      ),
                    ),
                  ),
                  Slider(
                    key: const ValueKey('color-hue'),
                    value: _hsv.hue,
                    min: 0,
                    max: 360,
                    activeColor: Colors.transparent,
                    inactiveColor: Colors.transparent,
                    thumbColor: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
                    semanticFormatterCallback: (value) => '${value.round()}°',
                    onChanged: (value) => _select(_hsv.withHue(value)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _hsv.toColor(),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Выбранный цвет'),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: [
                for (final color in const [
                  Color(0xff000000),
                  Color(0xff0a5e2a),
                  Color(0xff8df86b),
                  Color(0xff325cf4),
                  Color(0xffffffff),
                ])
                  IconButton(
                    tooltip: switch (color.toARGB32()) {
                      0xff000000 => 'Чёрный',
                      0xff0a5e2a => 'Тёмно-зелёный',
                      0xff8df86b => 'Светло-зелёный',
                      0xff325cf4 => 'Синий',
                      _ => 'Белый',
                    },
                    onPressed: () => _select(HSVColor.fromColor(color)),
                    icon: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onDelete != null)
            TextButton.icon(
              onPressed: () {
                widget.onDelete!();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.remove_circle_outline_rounded),
              label: const Text('Удалить этот цвет'),
            ),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(44, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, _hsv.toColor()),
                  child: const Text('Применить'),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
