import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';

class SignalTrace {
  const SignalTrace._();

  static const double height = 160;

  static const double cornerRadius = 12;
  static const double strokeWidth = 1.6;
  static const double fillAlpha = 0.16;

  static const int gridLines = 6;

  static const int batchMs = 40;

  static const int sampleIntervalMs = 20;

  static Widget frame({
    required QAppColors colors,
    required Widget child,
    List<Widget> overlays = const [],
    double height = SignalTrace.height,
  }) => Container(
    height: height,
    decoration: BoxDecoration(
      color: colors.card,
      borderRadius: BorderRadius.circular(cornerRadius),
      border: Border.all(color: colors.divider),
    ),
    clipBehavior: Clip.antiAlias,
    child: overlays.isEmpty
        ? child
        : Stack(
            children: [
              Positioned.fill(child: child),
              ...overlays,
            ],
          ),
  );

  static Widget chip(QAppColors colors, String text, Color accent) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: colors.background.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: accent.withValues(alpha: 0.5)),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: accent,
      ),
    ),
  );

  static void paintGrid(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 0; i < gridLines; i++) {
      final y = size.height * i / (gridLines - 1);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  static void paintTrace(
    Canvas canvas,
    List<Offset> points,
    double baseline,
    Color color,
  ) {
    if (points.length < 2) return;

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    final fill = Path()
      ..moveTo(points.first.dx, baseline)
      ..lineTo(points.first.dx, points.first.dy);

    for (var i = 1; i < points.length; i++) {
      line.lineTo(points[i].dx, points[i].dy);
      fill.lineTo(points[i].dx, points[i].dy);
    }
    fill
      ..lineTo(points.last.dx, baseline)
      ..close();

    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: fillAlpha));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  static void paintCursor(
    Canvas canvas,
    Size size,
    double x,
    double baseline,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4;
    for (var y = 0.0; y < baseline; y += 6) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, (y + 3).clamp(0.0, baseline)),
        paint,
      );
    }
    canvas.drawRect(
      Rect.fromCenter(center: Offset(x, 3), width: 9, height: 6),
      Paint()..color = color,
    );
  }
}
