import 'dart:convert';

import 'package:flutter/material.dart';

enum PassBackdrop { ambient, plain, gradient, solid, photo }

class PassAppearance {
  static const defaultAmbientColors = [
    Color(0xff325cf4),
    Color(0xffc091b7),
    Color(0xffe7a36d),
  ];
  const PassAppearance({
    this.theme = ThemeMode.light,
    this.accent = const Color(0xff325cf4),
    this.background = const Color(0xfff5f6f8),
    this.backdrop = PassBackdrop.ambient,
    this.ambientIntensity = .5,
    this.ambientColors = defaultAmbientColors,
    this.ambientUseCustomBase = false,
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

  /// Zero keeps the glow still; higher values increase speed and travel.
  final double ambientIntensity;
  bool get ambientMotion => ambientIntensity > 0;
  final List<Color> ambientColors;
  final bool ambientUseCustomBase;
  Color backgroundFor(Color themedSurface) =>
      ambientUseCustomBase ? background : themedSurface;
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
    double? ambientIntensity,
    List<Color>? ambientColors,
    bool? ambientUseCustomBase,
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
    ambientIntensity: (ambientIntensity ?? this.ambientIntensity).clamp(0, 1),
    ambientColors: ambientColors == null
        ? this.ambientColors
        : List.unmodifiable(ambientColors),
    ambientUseCustomBase: ambientUseCustomBase ?? this.ambientUseCustomBase,
    qrSize: qrSize ?? this.qrSize,
    scanSize: scanSize ?? this.scanSize,
    photoShade: photoShade ?? this.photoShade,
    showExpiry: showExpiry ?? this.showExpiry,
    boostBrightness: boostBrightness ?? this.boostBrightness,
    haptics: haptics ?? this.haptics,
  );

  String encode() => jsonEncode({
    'version': 5,
    'theme': theme.name,
    'accent': accent.toARGB32(),
    'background': background.toARGB32(),
    'backdrop': backdrop.name,
    'ambientIntensity': ambientIntensity,
    'ambientColors': ambientColors.map((color) => color.toARGB32()).toList(),
    'ambientUseCustomBase': ambientUseCustomBase,
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
      final currentDesign = [2, 3, 4, 5].contains(version);
      final palette = data['ambientColors'];
      final oldBackdrop = data['backdrop'];
      final motion = data['ambientIntensity'];
      return PassAppearance(
        theme: currentDesign
            ? ThemeMode.values.byName(data['theme'] as String)
            : defaults.theme,
        accent: currentDesign ? Color(data['accent'] as int) : defaults.accent,
        background: currentDesign
            ? Color(data['background'] as int)
            : defaults.background,
        backdrop:
            !currentDesign ||
                oldBackdrop == 'ambient' ||
                oldBackdrop == 'gradient' ||
                (version == 2 && oldBackdrop == 'plain')
            ? PassBackdrop.ambient
            : PassBackdrop.solid,
        ambientIntensity: motion is num && motion.isFinite
            ? motion.toDouble().clamp(0, 1)
            : data['ambientMotion'] == false
            ? 0
            : defaults.ambientIntensity,
        ambientColors:
            palette is List &&
                palette.length >= 2 &&
                palette.length <= 5 &&
                palette.every((color) => color is int)
            ? List.unmodifiable(palette.map((color) => Color(color as int)))
            : defaultAmbientColors,
        ambientUseCustomBase:
            (version != 5 && oldBackdrop == 'solid') ||
            (data['ambientUseCustomBase'] as bool? ?? false),
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
