import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Uint8List, SystemUiOverlayStyle;

import 'pass_appearance.dart';
import 'ambient_background.dart';

class PassHome extends StatefulWidget {
  const PassHome({
    super.key,
    required this.appearance,
    required this.loading,
    required this.onRefresh,
    required this.onConnect,
    required this.onSettings,
    this.qr,
    this.expiresOn,
    this.error,
    this.reconnectRequired = false,
    this.backgroundPhoto,
  });

  final PassAppearance appearance;
  final bool loading;
  final Widget? qr;
  final DateTime? expiresOn;
  final String? error;
  final bool reconnectRequired;
  final Uint8List? backgroundPhoto;
  final VoidCallback onRefresh;
  final VoidCallback onConnect;
  final VoidCallback onSettings;

  @override
  State<PassHome> createState() => _PassHomeState();
}

class _PassHomeState extends State<PassHome> with WidgetsBindingObserver {
  Timer? _hintTimer;
  bool _showHints = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleHints();
  }

  void _scheduleHints() {
    _hintTimer?.cancel();
    _showHints = true;
    if (widget.qr != null && !widget.loading) {
      _hintTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showHints = false);
      });
    }
  }

  @override
  void didUpdateWidget(PassHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.qr != widget.qr || oldWidget.loading != widget.loading) {
      _scheduleHints();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(_scheduleHints);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hintTimer?.cancel();
    super.dispose();
  }

  String get _expiry {
    final date = widget.expiresOn;
    return date == null
        ? 'QR готов'
        : 'До ${date.day.toString().padLeft(2, '0')}.'
              '${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  void _showInfo() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'О пропуске',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                Text(
                  widget.qr == null ? 'Код пока не получен.' : _expiry,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'Нажмите на QR, чтобы открыть его на весь экран. '
                  'Если турникет не принимает код, обновите его кнопкой внизу.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Понятно'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final appearance = widget.appearance;
    final photo = appearance.backdrop == PassBackdrop.photo
        ? widget.backgroundPhoto
        : null;
    final background =
        appearance.backdrop == PassBackdrop.solid ||
            (appearance.backdrop == PassBackdrop.ambient &&
                appearance.ambientUseCustomBase)
        ? appearance.background
        : colors.surface;
    final hintColor = photo != null
        ? colors.onSurfaceVariant
        : ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? const Color(0xffd6d9e3)
        : const Color(0xff555c6b);
    final hintsVisible =
        _showHints ||
        widget.loading ||
        widget.qr == null ||
        MediaQuery.accessibleNavigationOf(context);
    final overlay =
        photo != null ||
            ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (photo != null) ...[
              Image.memory(
                photo,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
              ColoredBox(
                color: Colors.black.withValues(alpha: appearance.photoShade),
              ),
            ] else if (appearance.backdrop == PassBackdrop.ambient)
              AmbientBackground(
                base: background,
                accent: appearance.accent,
                enabled: appearance.ambientMotion,
                colors: appearance.ambientColors,
              )
            else if (appearance.backdrop == PassBackdrop.gradient)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.alphaBlend(
                        colors.primary.withValues(alpha: .14),
                        colors.surface,
                      ),
                      colors.surface,
                    ],
                  ),
                ),
              ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton.filledTonal(
                                      tooltip: 'Информация о пропуске',
                                      onPressed: _showInfo,
                                      style: IconButton.styleFrom(
                                        backgroundColor: colors.surfaceContainer
                                            .withValues(alpha: .9),
                                      ),
                                      icon: const Icon(
                                        Icons.info_outline_rounded,
                                        size: 22,
                                      ),
                                    ),
                                    IconButton.filledTonal(
                                      tooltip: 'Настройки пропуска',
                                      onPressed: widget.onSettings,
                                      style: IconButton.styleFrom(
                                        backgroundColor: colors.surfaceContainer
                                            .withValues(alpha: .9),
                                      ),
                                      icon: const Icon(
                                        Icons.tune_rounded,
                                        size: 22,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                const Spacer(),
                                Center(
                                  child: FractionallySizedBox(
                                    widthFactor: appearance.qrSize,
                                    child: AspectRatio(
                                      aspectRatio: 1,
                                      child: widget.qr == null
                                          ? Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                if (widget.loading)
                                                  const CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  )
                                                else
                                                  Icon(
                                                    Icons.qr_code_2_rounded,
                                                    size: 64,
                                                    color:
                                                        colors.onSurfaceVariant,
                                                  ),
                                                const SizedBox(height: 20),
                                                Text(
                                                  widget.loading
                                                      ? 'Получаем QR…'
                                                      : widget.reconnectRequired
                                                      ? 'Подключитесь к Rocket.Chat'
                                                      : 'Получите код перед проходом',
                                                  textAlign: TextAlign.center,
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: colors
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            )
                                          : Container(
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                              ),
                                              child: RepaintBoundary(
                                                child: widget.qr!,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                ExcludeSemantics(
                                  excluding: !hintsVisible,
                                  child: AnimatedOpacity(
                                    opacity: hintsVisible ? 1 : 0,
                                    duration:
                                        MediaQuery.disableAnimationsOf(context)
                                        ? Duration.zero
                                        : const Duration(milliseconds: 240),
                                    child: Column(
                                      children: [
                                        if (widget.qr != null &&
                                            (appearance.showExpiry ||
                                                widget.expiresOn == null))
                                          Text(
                                            widget.loading
                                                ? 'Обновляем QR…'
                                                : _expiry,
                                            textAlign: TextAlign.center,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color:
                                                      colors.onSurfaceVariant,
                                                  backgroundColor: photo != null
                                                      ? colors.surface
                                                      : null,
                                                ),
                                          ),
                                        const SizedBox(height: 8),
                                        Text(
                                          widget.qr == null
                                              ? ''
                                              : 'Нажмите, чтобы увеличить',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: hintColor,
                                                backgroundColor: photo != null
                                                    ? colors.surface
                                                    : null,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (widget.error != null) ...[
                                  const SizedBox(height: 20),
                                  Semantics(
                                    liveRegion: true,
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: colors.errorContainer,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        widget.error!,
                                        style: TextStyle(
                                          color: colors.onErrorContainer,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 24),
                                const Spacer(),
                                if (widget.qr == null)
                                  FilledButton.icon(
                                    onPressed: widget.loading
                                        ? null
                                        : widget.reconnectRequired
                                        ? widget.onConnect
                                        : widget.onRefresh,
                                    icon: Icon(
                                      widget.reconnectRequired
                                          ? Icons.login_rounded
                                          : Icons.refresh_rounded,
                                      size: 20,
                                    ),
                                    label: Text(
                                      widget.loading
                                          ? 'Получаем QR…'
                                          : widget.reconnectRequired
                                          ? 'Подключиться заново'
                                          : 'Получить QR',
                                    ),
                                  )
                                else
                                  Center(
                                    child: IconButton.filled(
                                      tooltip: 'Обновить QR',
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size.square(64),
                                        iconSize: 26,
                                      ),
                                      onPressed: widget.loading
                                          ? null
                                          : widget.onRefresh,
                                      icon: widget.loading
                                          ? const SizedBox.square(
                                              dimension: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.refresh_rounded),
                                    ),
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
          ],
        ),
      ),
    );
  }
}
