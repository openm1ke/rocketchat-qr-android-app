import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pass_appearance.dart';

/// A small adaptation of SignMoment's gradient atmosphere. Only the backdrop
/// repaints; no video, image decoding, blur layers, or widget rebuild per frame.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({
    super.key,
    required this.base,
    required this.enabled,
    this.intensity = .5,
    this.colors = PassAppearance.defaultAmbientColors,
  });

  final Color base;
  final bool enabled;
  final double intensity;
  final List<Color> colors;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _clock = AnimationController(vsync: this, duration: _duration)
    ..addListener(_tick);
  final _phase = ValueNotifier<double>(.17);
  bool _allowed = false;
  bool _active = true;

  Duration get _duration => Duration(
    milliseconds: (60000 - widget.intensity.clamp(0, 1) * 48000).round(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  void _tick() {
    // Quantization also caps painting on displays running at 60/90/120 Hz.
    final frames = _duration.inMilliseconds / 1000 * 24;
    _phase.value = (_clock.value * frames).floor() / frames;
  }

  void _sync() {
    if (widget.enabled && widget.intensity > 0 && _allowed && _active) {
      if (!_clock.isAnimating) _clock.repeat();
    } else {
      _clock.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _allowed =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(AmbientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intensity != widget.intensity) {
      _clock.duration = _duration;
      if (_clock.isAnimating) _clock.repeat(period: _duration);
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _AmbientPainter(
            _phase,
            base: widget.base,
            intensity: widget.intensity,
            colors: widget.colors,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(
    this.phase, {
    required this.base,
    required this.intensity,
    required this.colors,
  }) : super(repaint: phase);

  final ValueNotifier<double> phase;
  final Color base;
  final double intensity;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final dark = base.computeLuminance() < .2;
    final t = phase.value * math.pi * 2;
    final travel = .4 + intensity.clamp(0, 1) * 1.2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var i = 0; i < colors.length; i++) {
      final x = (i.isEven ? -.05 : 1.05) + math.sin(t + i * 1.8) * .18 * travel;
      final y =
          .12 +
          i / (colors.length - 1) * .8 +
          math.cos(t * 2 + i) * .12 * travel;
      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(math.sin(t + i) * .3 * travel);
      canvas.scale(size.width * .85, size.height * .46);
      const field = Rect.fromLTWH(-1, -1, 2, 2);
      canvas.drawRect(
        field,
        Paint()
          ..shader = RadialGradient(
            colors: [
              colors[i].withValues(alpha: dark ? .24 : .13),
              colors[i].withValues(alpha: 0),
            ],
          ).createShader(field),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AmbientPainter oldDelegate) =>
      oldDelegate.base != base ||
      oldDelegate.intensity != intensity ||
      oldDelegate.colors != colors ||
      oldDelegate.phase != phase;
}
