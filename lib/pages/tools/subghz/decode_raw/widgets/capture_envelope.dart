import 'package:flutter/material.dart';

import '../../../../../theme/theme.dart';
import '../../widgets/signal_trace.dart';

class CaptureEnvelope extends StatelessWidget {
  const CaptureEnvelope({
    super.key,
    required this.envelope,
    required this.progress,
    required this.hitPositions,
    this.caption,
    this.height = SignalTrace.height,
    this.live = true,
    this.loading = false,
    this.loadingLabel,
  });

  final List<double> envelope;

  final double progress;

  final List<double> hitPositions;

  final String? caption;

  final double height;

  final bool live;

  final bool loading;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SignalTrace.frame(
      colors: colors,
      height: height,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _CapturePainter(
            envelope: envelope,
            progress: progress,
            hitPositions: hitPositions,
            live: live,
            trace: colors.accent,
            grid: colors.divider,
            cursor: colors.danger,
            hit: colors.success,
          ),
        ),
      ),
      overlays: [
        if (caption != null && !loading)
          Positioned(
            left: 8,
            top: 6,
            child: SignalTrace.chip(colors, caption!, colors.accent),
          ),
        if (live && !loading)
          Positioned(
            right: 8,
            top: 6,
            child: SignalTrace.chip(
              colors,
              '${(progress * 100).clamp(0, 100).round()}%',
              colors.danger,
            ),
          ),
        if (loading)
          Positioned.fill(
            child: ColoredBox(
              color: colors.card.withValues(alpha: 0.85),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(colors.accent),
                      ),
                    ),
                    if (loadingLabel != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        loadingLabel!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CapturePainter extends CustomPainter {
  _CapturePainter({
    required this.envelope,
    required this.progress,
    required this.hitPositions,
    required this.live,
    required this.trace,
    required this.grid,
    required this.cursor,
    required this.hit,
  });

  final List<double> envelope;
  final double progress;
  final List<double> hitPositions;
  final bool live;
  final Color trace;
  final Color grid;
  final Color cursor;
  final Color hit;

  static const double _tickStrip = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height - _tickStrip;
    SignalTrace.paintGrid(canvas, Size(size.width, baseline), grid);
    _paintEnvelope(canvas, size, baseline);
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );

    for (final position in hitPositions) {
      final x = (size.width * position.clamp(0.0, 1.0)).clamp(0.0, size.width);
      canvas.drawLine(
        Offset(x, baseline),
        Offset(x, baseline + 6),
        Paint()
          ..color = hit
          ..strokeWidth = 2,
      );
      canvas.drawCircle(Offset(x, baseline + 10), 2.5, Paint()..color = hit);
    }

    if (live) {
      final x = (size.width * progress.clamp(0.0, 1.0)).clamp(0.0, size.width);
      SignalTrace.paintCursor(canvas, size, x, baseline, cursor);
    }
  }

  void _paintEnvelope(Canvas canvas, Size size, double baseline) {
    if (envelope.length < 2 || size.width <= 0) return;

    final span = baseline * 0.88;
    final columns = size.width.ceil();
    final points = <Offset>[];

    for (var px = 0; px <= columns; px++) {
      final from = (px * envelope.length / (columns + 1)).floor();
      final to = ((px + 1) * envelope.length / (columns + 1)).ceil().clamp(
        from + 1,
        envelope.length,
      );
      var peak = 0.0;
      for (var i = from; i < to; i++) {
        if (envelope[i] > peak) peak = envelope[i];
      }
      points.add(
        Offset(
          size.width * px / columns,
          baseline - peak.clamp(0.0, 1.0) * span,
        ),
      );
    }

    SignalTrace.paintTrace(canvas, points, baseline, trace);
  }

  @override
  bool shouldRepaint(_CapturePainter old) =>
      old.progress != progress ||
      old.hitPositions.length != hitPositions.length ||
      old.live != live ||
      !identical(old.envelope, envelope);
}
