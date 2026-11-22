import 'package:flutter/material.dart';

enum WidgetContent { logo, qr }

class WidgetAppearance {
  const WidgetAppearance({
    this.content = WidgetContent.logo,
    this.background = Colors.black,
    this.foreground = const Color(0xff8df86b),
  });

  final WidgetContent content;
  final Color background;
  final Color foreground;

  WidgetAppearance copyWith({
    WidgetContent? content,
    Color? background,
    Color? foreground,
  }) => WidgetAppearance(
    content: content ?? this.content,
    background: background?.withValues(alpha: 1) ?? this.background,
    foreground: foreground?.withValues(alpha: 1) ?? this.foreground,
  );

  Map<String, Object> toMessage() => {
    'content': content.name,
    'background': background.toARGB32(),
    'foreground': foreground.toARGB32(),
  };

  factory WidgetAppearance.fromMessage(Map<Object?, Object?>? value) {
    Color readColor(String key, Color fallback) {
      final number = value?[key];
      return number is int ? Color(number | 0xff000000) : fallback;
    }

    return WidgetAppearance(
      content: value?['content'] == 'qr'
          ? WidgetContent.qr
          : WidgetContent.logo,
      background: readColor('background', Colors.black),
      foreground: readColor('foreground', const Color(0xff8df86b)),
    );
  }

  Color get textColor =>
      background.computeLuminance() > .179 ? Colors.black : Colors.white;

  double get contrast {
    final a = background.computeLuminance();
    final b = foreground.computeLuminance();
    return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
  }

  /// Map the source's black modules and white quiet zone to the chosen colors.
  ColorFilter get qrFilter {
    final dark = foreground.toARGB32();
    final light = background.toARGB32();
    List<double> row(int shift) {
      final low = (dark >> shift) & 255;
      final high = (light >> shift) & 255;
      final scale = (high - low) / 255;
      return [scale * .299, scale * .587, scale * .114, 0, low.toDouble()];
    }

    return ColorFilter.matrix([
      ...row(16),
      ...row(8),
      ...row(0),
      0,
      0,
      0,
      0,
      255,
    ]);
  }
}
