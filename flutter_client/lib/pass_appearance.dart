import 'dart:convert';

import 'package:flutter/material.dart';

enum PassBackdrop { ambient, plain, gradient, solid, photo }

class PassAppearance {
  const PassAppearance({
    this.theme = ThemeMode.light,
    this.accent = const Color(0xff325cf4),
    this.background = const Color(0xfff5f6f8),
    this.backdrop = PassBackdrop.ambient,
    this.ambientMotion = true,
    this.qrSize = 1,
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
  final bool ambientMotion;
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
    bool? ambientMotion,
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
    ambientMotion: ambientMotion ?? this.ambientMotion,
    qrSize: qrSize ?? this.qrSize,
    scanSize: scanSize ?? this.scanSize,
    photoShade: photoShade ?? this.photoShade,
    showExpiry: showExpiry ?? this.showExpiry,
    boostBrightness: boostBrightness ?? this.boostBrightness,
    haptics: haptics ?? this.haptics,
  );

  String encode() => jsonEncode({
    'version': 3,
    'theme': theme.name,
    'accent': accent.toARGB32(),
    'background': background.toARGB32(),
    'backdrop': backdrop.name,
    'ambientMotion': ambientMotion,
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
      final version = data['version'];
      final currentDesign = version == 2 || version == 3;
      return PassAppearance(
        theme: currentDesign
            ? ThemeMode.values.byName(data['theme'] as String)
            : defaults.theme,
        accent: currentDesign ? Color(data['accent'] as int) : defaults.accent,
        background: currentDesign
            ? Color(data['background'] as int)
            : defaults.background,
        backdrop: version == 2 && data['backdrop'] == 'plain'
            ? PassBackdrop.ambient
            : currentDesign
            ? PassBackdrop.values.byName(data['backdrop'] as String)
            : defaults.backdrop,
        ambientMotion: data['ambientMotion'] as bool? ?? true,
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
