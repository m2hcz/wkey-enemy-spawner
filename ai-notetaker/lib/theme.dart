import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

class AppColors {
  static const accent = Color(0xFF5E7CFF);
  static const accent2 = Color(0xFF8C6BFF);
  static const record = Color(0xFFFF3B30);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accent2],
  );

  static Color bg(BuildContext c) =>
      CupertinoColors.systemGroupedBackground.resolveFrom(c);
  static Color card(BuildContext c) =>
      CupertinoColors.secondarySystemGroupedBackground.resolveFrom(c);
  static Color label(BuildContext c) => CupertinoColors.label.resolveFrom(c);
  static Color secondary(BuildContext c) =>
      CupertinoColors.secondaryLabel.resolveFrom(c);
  static Color tertiary(BuildContext c) =>
      CupertinoColors.tertiaryLabel.resolveFrom(c);
  static Color fill(BuildContext c) =>
      CupertinoColors.tertiarySystemFill.resolveFrom(c);
  static Color separator(BuildContext c) =>
      CupertinoColors.separator.resolveFrom(c);

  static bool dark(BuildContext c) =>
      CupertinoTheme.brightnessOf(c) == Brightness.dark;

  static List<BoxShadow> shadow(BuildContext c) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark(c) ? 0.5 : 0.12),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}

/// The app icon glyph: a rounded gradient tile with a small waveform.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.gradient,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(CupertinoIcons.waveform, color: Colors.white, size: size * 0.62),
    );
  }
}

/// iOS-style grouped section header / footer text.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.footer = false});
  final String text;
  final bool footer;

  @override
  Widget build(BuildContext context) => Text(
        footer ? text : text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          height: 1.3,
          fontWeight: FontWeight.w400,
          letterSpacing: footer ? 0 : 0.2,
          color: AppColors.secondary(context),
        ),
      );
}
