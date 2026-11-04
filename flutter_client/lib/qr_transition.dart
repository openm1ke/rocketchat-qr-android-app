import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Uint8List;

class QrTransition extends StatefulWidget {
  const QrTransition({super.key, required this.image, required this.loading});

  final Uint8List image;
  final bool loading;

  @override
  State<QrTransition> createState() => _QrTransitionState();
}

class _QrTransitionState extends State<QrTransition>
    with SingleTickerProviderStateMixin {
  late final _assembly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 580),
    value: 1,
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _assembly.value = 1;
  }

  @override
  void didUpdateWidget(QrTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.image, widget.image) && !_reduceMotion) {
      _assembly.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _assembly.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = Image.memory(
      widget.image,
      fit: BoxFit.contain,
      width: double.infinity,
      filterQuality: FilterQuality.none,
      excludeFromSemantics: true,
    );
    return AnimatedBuilder(
      animation: _assembly,
      child: image,
      builder: (context, child) {
        final ready = !widget.loading && _assembly.isCompleted;
        final assembling = !widget.loading && !ready && !_reduceMotion;
        final visibleImage = assembling
            ? ClipPath(clipper: _TileReveal(_assembly.value), child: child)
            : child!;
        return Semantics(
          label: ready ? 'QR-код для турникета' : 'QR-код обновляется',
          child: ClipRect(
            child: AnimatedOpacity(
              opacity: widget.loading ? .24 : 1,
              duration: _reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: ImageFiltered(
                enabled: widget.loading && !_reduceMotion,
                imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: visibleImage,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TileReveal extends CustomClipper<Path> {
  const _TileReveal(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    const tiles = 10;
    final side = math.min(size.width, size.height);
    final cell = side / tiles;
    final left = (size.width - side) / 2;
    final top = (size.height - side) / 2;
    final path = Path();
    for (var row = 0; row < tiles; row++) {
      for (var column = 0; column < tiles; column++) {
        final jitter = ((row * 17 + column * 31 + row * column * 7) % 23) / 22;
        final start = (row + column) / (2 * (tiles - 1)) * .42 + jitter * .28;
        final phase = ((progress - start) / .30).clamp(0.0, 1.0);
        if (phase == 0) continue;
        final extent = cell * Curves.easeOutCubic.transform(phase);
        path.addRect(
          Rect.fromCenter(
            center: Offset(
              left + (column + .5) * cell,
              top + (row + .5) * cell,
            ),
            width: extent,
            height: extent,
          ),
        );
      }
    }
    return path;
  }

  @override
  bool shouldReclip(_TileReveal oldClipper) => oldClipper.progress != progress;
}
