import 'package:flutter/material.dart';

ThemeData passTheme({
  Brightness brightness = Brightness.light,
  Color accent = const Color(0xff325cf4),
}) {
  final dark = brightness == Brightness.dark;
  final primary = dark ? Color.lerp(accent, Colors.white, .45)! : accent;
  const darkInk = Color(0xff111318);
  final lightContrast = 1.05 / (primary.computeLuminance() + .05);
  final darkContrast =
      (primary.computeLuminance() + .05) / (darkInk.computeLuminance() + .05);
  final colors = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: primary,
        onPrimary: lightContrast >= darkContrast ? Colors.white : darkInk,
        surface: dark ? const Color(0xff17191e) : const Color(0xfff5f6f8),
        onSurface: dark ? const Color(0xfff3f4f6) : const Color(0xff191b22),
        onSurfaceVariant: dark
            ? const Color(0xffafb5c2)
            : const Color(0xff656b78),
        surfaceContainer: dark ? const Color(0xff22252c) : Colors.white,
        outlineVariant: dark
            ? const Color(0xff343840)
            : const Color(0xffe3e6ec),
      );
  final base = ThemeData(colorScheme: colors, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: colors.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainer,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class CampusWordmark extends StatelessWidget {
  const CampusWordmark({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.qr_code_scanner_rounded,
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(width: 8),
      const Text(
        'CAMPUS',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    ],
  );
}
