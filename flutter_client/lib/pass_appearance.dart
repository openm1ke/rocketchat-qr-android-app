import 'dart:convert';

import 'package:flutter/material.dart';

enum PassBackdrop { gradient, solid, photo }

class PassAppearance {
  const PassAppearance({
    this.theme = ThemeMode.dark,
    this.accent = const Color(0xff78f1bd),
    this.background = const Color(0xff101821),
    this.backdrop = PassBackdrop.gradient,
    this.qrSize = .9,
    this.scanSize = 1,
    this.photoShade = .55,
    this.showExpiry = true,
    this.boostBrightness = true,
    this.haptics = true,
  });

  final ThemeMode theme;
  final Color accent;
  final Color background;
  final PassBackdrop backdrop;
  final double qrSize;
  final double scanSize;
  final double photoShade;
  final bool showExpiry;
  final bool boostBrightness;
  final bool haptics;

  PassAppearance copyWith({
    ThemeMode? theme,
    Color? accent,
    Color? background,
    PassBackdrop? backdrop,
    double? qrSize,
    double? scanSize,
    double? photoShade,
    bool? showExpiry,
    bool? boostBrightness,
    bool? haptics,
  }) => PassAppearance(
    theme: theme ?? this.theme,
    accent: accent ?? this.accent,
    background: background ?? this.background,
    backdrop: backdrop ?? this.backdrop,
    qrSize: qrSize ?? this.qrSize,
    scanSize: scanSize ?? this.scanSize,
    photoShade: photoShade ?? this.photoShade,
    showExpiry: showExpiry ?? this.showExpiry,
    boostBrightness: boostBrightness ?? this.boostBrightness,
    haptics: haptics ?? this.haptics,
  );

  String encode() => jsonEncode({
    'theme': theme.name,
    'accent': accent.toARGB32(),
    'background': background.toARGB32(),
    'backdrop': backdrop.name,
    'qrSize': qrSize,
    'scanSize': scanSize,
    'photoShade': photoShade,
    'showExpiry': showExpiry,
    'boostBrightness': boostBrightness,
    'haptics': haptics,
  });

  static PassAppearance decode(String? value) {
    const defaults = PassAppearance();
    if (value == null) return defaults;
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      return PassAppearance(
        theme: ThemeMode.values.byName(data['theme'] as String),
        accent: Color(data['accent'] as int),
        background: Color(data['background'] as int),
        backdrop: PassBackdrop.values.byName(data['backdrop'] as String),
        qrSize: (data['qrSize'] as num).toDouble().clamp(.65, 1),
        scanSize: (data['scanSize'] as num).toDouble().clamp(.75, 1),
        photoShade: (data['photoShade'] as num).toDouble().clamp(.2, .85),
        showExpiry: data['showExpiry'] as bool,
        boostBrightness: data['boostBrightness'] as bool,
        haptics: data['haptics'] as bool,
      );
    } on Object {
      return defaults;
    }
  }
}
