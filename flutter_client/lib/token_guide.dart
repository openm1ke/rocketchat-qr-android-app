import 'package:flutter/material.dart';

class TokenGuideScreen extends StatefulWidget {
  const TokenGuideScreen({super.key, this.doneLabel = 'Готово'});

  final String doneLabel;

  @override
  State<TokenGuideScreen> createState() => _TokenGuideScreenState();
}

class _TokenGuideScreenState extends State<TokenGuideScreen> {
  static const _steps = [
    (
      title: 'Откройте настройки аккаунта',
      description:
          'Откройте Rocket.Chat на компьютере. Нажмите на свой аватар '
          'в левом верхнем углу и выберите «Настройки».',
      image: 'assets/token_guide/rocket1.png',
      imageLabel:
          'Меню аккаунта Rocket.Chat: пункт «Настройки» выделен рамкой.',
    ),
    (
      title: 'Создайте личный токен',
      description:
          'Перейдите в «Токены для личного доступа». Укажите название, '
          'например «Пропуск в кампус», и нажмите «Добавить». '
          'Если Rocket.Chat попросит подтверждение, введите пароль или код 2FA.',
      image: 'assets/token_guide/rocket2.png',
      imageLabel: 'Раздел «Токены для личного доступа» и кнопка «Добавить» в Rocket.Chat.',
    ),
    (
      title: 'Скопируйте токен в приложение',
      description:
          'Скопируйте значение после слова «Токен» и вставьте его в поле '
          'подключения. ID пользователя вводить не нужно. '
          'Затем нажмите «Сохранить и получить QR».',
      image: 'assets/token_guide/rocket3.png',
      imageLabel: 'Окно созданного токена Rocket.Chat. Значение токена на примере скрыто.',
    ),
  ];

  final _pages = PageController();
  int _step = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _openImage(BuildContext context, String path, String label) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xff15161a),
          appBar: AppBar(
            backgroundColor: const Color(0xff15161a),
            foregroundColor: Colors.white,
            title: const Text('Скриншот Rocket.Chat'),
          ),
          body: SafeArea(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(child: Image.asset(path, semanticLabel: label)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff325cf4),
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: dark ? const Color(0xff91a9ff) : const Color(0xff325cf4),
          onPrimary: dark ? const Color(0xff14265d) : Colors.white,
          surface: dark ? const Color(0xff15161a) : const Color(0xfff7f8fa),
          onSurface: dark ? const Color(0xfff5f6f8) : const Color(0xff191b22),
        );
    return Theme(
      data: ThemeData(colorScheme: colors, useMaterial3: true),
      child: Scaffold(
        appBar: AppBar(title: const Text('Где взять токен')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: Row(
                      children: [
                        for (var i = 0; i < _steps.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: Semantics(
                              label: 'Шаг ${i + 1} из ${_steps.length}',
                              selected: i == _step,
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2),
                                  color: i <= _step
                                      ? colors.primary
                                      : colors.outlineVariant,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: _steps.length,
                      onPageChanged: (value) => setState(() => _step = value),
                      itemBuilder: (context, index) {
                        final step = _steps[index];
                        final text = Theme.of(context).textTheme;
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                          children: [
                            Text(
                              'НА КОМПЬЮТЕРЕ · ШАГ ${index + 1} ИЗ 3',
                              style: text.labelMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                                letterSpacing: .8,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Semantics(
                              header: true,
                              child: Text(
                                step.title,
                                style: text.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(step.description, style: text.bodyLarge),
                            const SizedBox(height: 24),
                            Semantics(
                              button: true,
                              label: 'Увеличить скриншот. ${step.imageLabel}',
                              child: Material(
                                color: const Color(0xff24262e),
                                borderRadius: BorderRadius.circular(16),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => _openImage(
                                    context,
                                    step.image,
                                    step.imageLabel,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Image.asset(
                                      step.image,
                                      height: index == 0 ? 260 : null,
                                      fit: BoxFit.contain,
                                      excludeFromSemantics: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Нажмите на скриншот, чтобы увеличить',
                              style: text.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              index == 2
                                  ? 'Rocket.Chat показывает токен только один раз. '
                                        'Не отправляйте его другим людям.'
                                  : 'Интерфейс показан на примере настольного '
                                        'Rocket.Chat. Названия пунктов могут '
                                        'отличаться в вашей версии.',
                              style: text.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Row(
                      children: [
                        if (_step > 0) ...[
                          IconButton.outlined(
                            tooltip: 'Предыдущий шаг',
                            onPressed: () => _goTo(_step - 1),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            onPressed: _step == _steps.length - 1
                                ? () => Navigator.pop(context)
                                : () => _goTo(_step + 1),
                            child: Text(
                              _step == _steps.length - 1
                                  ? widget.doneLabel
                                  : 'Далее',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
