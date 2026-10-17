import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';

const int kPulseLevelBit = 0x80000000;
const int kPulseDurationMask = 0x7FFFFFFF;

class PulseTrainView extends StatefulWidget {
  const PulseTrainView({super.key, required this.pulses, this.height = 132});

  final List<int> pulses;
  final double height;

  static const double detailScale = 3;

  @override
  State<PulseTrainView> createState() => _PulseTrainViewState();
}

class _PulseTrainViewState extends State<PulseTrainView> {
  final TransformationController _transform = TransformationController();
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  void _onTransform() {
    final scale = _transform.value.getMaxScaleOnAxis();
    final wasDetail = _scale >= PulseTrainView.detailScale;
    final isDetail = scale >= PulseTrainView.detailScale;
    _scale = scale;
    if (wasDetail != isDetail) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = context.l10n;
    if (widget.pulses.isEmpty) return const SizedBox.shrink();

    final total = widget.pulses.fold<int>(
      0,
      (sum, p) => sum + (p & kPulseDurationMask),
    );
    final detail = _scale >= PulseTrainView.detailScale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) => InteractiveViewer(
              transformationController: _transform,
              constrained: true,
              scaleEnabled: true,
              panEnabled: true,
              minScale: 1,
              maxScale: 60,
              child: CustomPaint(
                size: Size(constraints.maxWidth, widget.height),
                painter: _BurstPainter(
                  pulses: widget.pulses,
                  totalUs: total,
                  detail: detail,
                  line: colors.accent,
                  grid: colors.divider,
                  label: colors.textMuted,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${(total / 1000).toStringAsFixed(1)} ms  ·  '
          '${widget.pulses.length} edges  ·  '
          '${detail ? s.subghzRxPulseDetail : s.subghzRxPulseZoomHint}',
          style: TextStyle(fontSize: 11, color: colors.textMuted),
        ),
      ],
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.pulses,
    required this.totalUs,
    required this.detail,
    required this.line,
    required this.grid,
    required this.label,
  });

  final List<int> pulses;
  final int totalUs;
  final bool detail;
  final Color line;
  final Color grid;
  final Color label;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalUs <= 0) return;
    final baseline = size.height - 10;
    final scale = size.width / totalUs;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final tickUs = totalUs > 20000 ? 5000 : 1000;
    for (var us = 0; us <= totalUs; us += tickUs) {
      final x = us * scale;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    if (detail) {
      _paintEdges(canvas, size, scale, baseline);
    } else {
      _paintEnvelope(canvas, size, baseline);
    }
  }

  void _paintEnvelope(Canvas canvas, Size size, double baseline) {
    final columns = size.width.ceil();
    if (columns <= 0) return;
    final usPerColumn = totalUs / columns;
    final high = List<double>.filled(columns, 0);

    var cursor = 0.0;
    for (final pulse in pulses) {
      final duration = (pulse & kPulseDurationMask).toDouble();
      if ((pulse & kPulseLevelBit) != 0) {
        var remaining = duration;
        var at = cursor;
        while (remaining > 0) {
          final column = (at / usPerColumn).floor();
          if (column >= columns) break;
          final columnEnd = (column + 1) * usPerColumn;
          final slice = (columnEnd - at).clamp(0.0, remaining);
          high[column] += slice;
          at += slice;
          remaining -= slice;
          if (slice <= 0) break;
        }
      }
      cursor += duration;
    }

    final bars = Paint()..color = line;
    final span = baseline - 6;
    for (var x = 0; x < columns; x++) {
      final duty = (high[x] / usPerColumn).clamp(0.0, 1.0);
      if (duty <= 0) continue;
      final barHeight = (duty * span).clamp(1.0, span);
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), baseline - barHeight, 1, barHeight),
        bars,
      );
    }

    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      Paint()
        ..color = label
        ..strokeWidth = 1,
    );
  }

  void _paintEdges(Canvas canvas, Size size, double scale, double baseline) {
    final top = size.height * 0.25;
    final bottom = baseline - 4;

    final path = Path();
    var x = 0.0;
    var first = true;
    for (final pulse in pulses) {
      final level = (pulse & kPulseLevelBit) != 0;
      final y = level ? top : bottom;
      final width = (pulse & kPulseDurationMask) * scale;
      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
      path.lineTo(x + width, y);
      x += width;
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.pulses != pulses || old.detail != detail || old.line != line;
}
