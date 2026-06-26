import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Simple donut progress chart for the Aggregate Result viz.
/// Shows `percent` (0–100) filled in [color], with [trackColor] for the rest.
class Donut extends StatelessWidget {
  const Donut({
    super.key,
    required this.percent,
    this.size = 56,
    this.strokeWidth = 8,
    Color? color,
    Color? trackColor,
  })  : color = color ?? AppColors.success,
        trackColor = trackColor ?? AppColors.successBorder;

  final double percent;
  final double size;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(
          percent: percent.clamp(0, 100).toDouble(),
          color: color,
          trackColor: trackColor,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.percent,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double percent;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweep = 2 * pi * (percent / 100);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweep,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.percent != percent || old.color != color;
}
