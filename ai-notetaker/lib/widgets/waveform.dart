import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// Live microphone level bars, newest on the right.
class Waveform extends StatelessWidget {
  const Waveform({super.key, required this.levels, this.active = true, this.height = 64});

  final List<double> levels;
  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _WavePainter(
          levels,
          active ? AppColors.accent : AppColors.tertiary(context),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.levels, this.color);

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final n = levels.length;
    final slot = size.width / n;
    final barW = slot * 0.55;
    final mid = size.height / 2;
    for (var i = 0; i < n; i++) {
      final v = levels[i];
      final h = (4 + v * (size.height - 4)).clamp(4.0, size.height);
      // Older bars fade out to the left.
      final alpha = 0.25 + 0.75 * (i / n);
      final paint = Paint()..color = color.withValues(alpha: alpha);
      final x = i * slot + (slot - barW) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - h / 2, barW, h),
          Radius.circular(barW / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}
