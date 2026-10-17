import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../../services/localization/l10n.dart';
import '../../../../../theme/theme.dart';
import '../../widgets/signal_trace.dart';
import '../live_rx_controller.dart';

class RssiWaveform extends StatefulWidget {
  const RssiWaveform({
    super.key,
    required this.samples,
    required this.live,
    required this.threshold,
    required this.thresholdEnabled,
    required this.onThresholdChanged,
    required this.running,
    this.retuning = false,
    this.height = SignalTrace.height,
    this.windowSize = 300,
    this.sampleIntervalMs = 20,
  });

  final ValueListenable<LiveRssi> live;

  final List<int> samples;
  final int threshold;

  final bool thresholdEnabled;

  final ValueChanged<int> onThresholdChanged;

  final bool running;

  final bool retuning;
  final double height;
  final int windowSize;
  final int sampleIntervalMs;

  static const int minDbm = -120;
  static const int maxDbm = -10;

  @override
  State<RssiWaveform> createState() => _RssiWaveformState();
}

class _RssiWaveformState extends State<RssiWaveform>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  final ValueNotifier<double> _drawnNotifier = ValueNotifier<double>(0);
  double get _drawn => _drawnNotifier.value;
  set _drawn(double value) => _drawnNotifier.value = value;

  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.running) _ticker.start();
  }

  @override
  void didUpdateWidget(RssiWaveform old) {
    super.didUpdateWidget(old);
    if (widget.running && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!widget.running && _ticker.isActive) {
      _ticker.stop();
    }
    if (widget.samples.length < _drawn) {
      _drawn = widget.samples.length.toDouble();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _drawnNotifier.dispose();
    super.dispose();
  }

  double get _maxLag =>
      (SignalTrace.batchMs / widget.sampleIntervalMs.clamp(1, 1000))
          .clamp(2, 8)
          .toDouble();

  void _onTick(Duration elapsed) {
    final total = widget.samples.length.toDouble();
    if (_last == Duration.zero) {
      _last = elapsed;
      return;
    }
    final dt = (elapsed - _last).inMicroseconds / 1000.0;
    _last = elapsed;

    var behind = total - _drawn;
    if (behind <= 0) return;

    if (behind > _maxLag) {
      _drawn = total - _maxLag;
      behind = _maxLag;
    }

    final perMs = 1 / widget.sampleIntervalMs.clamp(1, 1000);
    final advance = dt * perMs * (1 + behind);
    _drawn = (_drawn + advance).clamp(0, total);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = context.l10n;

    final animating = TickerMode.valuesOf(context).enabled && widget.running;
    if (!animating) _drawn = widget.samples.length.toDouble();

    return SignalTrace.frame(
      colors: colors,
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          void handleDrag(Offset local) {
            final ratio = (local.dy / constraints.maxHeight).clamp(0.0, 1.0);
            widget.onThresholdChanged(
              (RssiWaveform.maxDbm -
                      ratio * (RssiWaveform.maxDbm - RssiWaveform.minDbm))
                  .round(),
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: widget.thresholdEnabled
                ? (d) => handleDrag(d.localPosition)
                : null,
            onVerticalDragUpdate: widget.thresholdEnabled
                ? (d) => handleDrag(d.localPosition)
                : null,
            onTapDown: widget.thresholdEnabled
                ? (d) => handleDrag(d.localPosition)
                : null,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _RssiPainter(
                        drawn: _drawnNotifier,
                        live: widget.live,
                        samples: widget.samples,
                        animating: animating,
                        windowSize: widget.windowSize,
                        threshold: widget.thresholdEnabled
                            ? widget.threshold
                            : null,
                        trace: colors.accent,
                        grid: colors.divider,
                        floorColor: colors.info,
                        thresholdColor: colors.danger,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  top: 6,
                  child: ValueListenableBuilder<LiveRssi>(
                    valueListenable: widget.live,
                    builder: (_, live, _) => SignalTrace.chip(
                      colors,
                      live.latest == null ? '—' : '${live.latest} dBm',
                      colors.accent,
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 6,
                  child: Row(
                    children: [
                      ValueListenableBuilder<LiveRssi>(
                        valueListenable: widget.live,
                        builder: (_, live, _) => SignalTrace.chip(
                          colors,
                          s.subghzRxNoiseFloor(live.noiseFloor),
                          colors.info,
                        ),
                      ),
                      if (widget.thresholdEnabled) ...[
                        const SizedBox(width: 6),
                        SignalTrace.chip(
                          colors,
                          s.subghzRxThreshold(widget.threshold),
                          colors.danger,
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.retuning)
                  Positioned.fill(
                    child: ColoredBox(
                      color: colors.background.withValues(alpha: 0.6),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  colors.accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              s.subghzRxRetuning,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RssiPainter extends CustomPainter {
  _RssiPainter({
    required this.drawn,
    required this.live,
    required this.samples,
    required this.animating,
    required this.windowSize,
    required this.threshold,
    required this.trace,
    required this.grid,
    required this.floorColor,
    required this.thresholdColor,
  }) : super(repaint: Listenable.merge([drawn, live]));

  final List<int> samples;

  final ValueNotifier<double> drawn;

  final bool animating;
  final int windowSize;

  final ValueListenable<LiveRssi> live;

  final int? threshold;
  final Color trace;
  final Color grid;
  final Color floorColor;
  final Color thresholdColor;

  double _y(num dbm, double height) {
    final clamped = dbm.clamp(RssiWaveform.minDbm, RssiWaveform.maxDbm);
    final ratio =
        (RssiWaveform.maxDbm - clamped) /
        (RssiWaveform.maxDbm - RssiWaveform.minDbm);
    return ratio * height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final visible = animating ? drawn.value : samples.length.toDouble();
    SignalTrace.paintGrid(canvas, size, grid);

    final count = visible.floor().clamp(0, samples.length);
    if (count > 1) {
      final step = size.width / windowSize;
      final fraction = visible - count;
      final endX = size.width - (1 - fraction) * step;
      final startX = endX - (count - 1) * step;

      SignalTrace.paintTrace(
        canvas,
        [
          for (var i = 0; i < count; i++)
            Offset(startX + i * step, _y(samples[i], size.height)),
        ],
        size.height,
        trace,
      );
    }

    _line(canvas, size, live.value.noiseFloor, floorColor, dashed: true);
    final limit = threshold;
    if (limit != null) {
      _line(canvas, size, limit, thresholdColor, dashed: false);
    }
  }

  void _line(
    Canvas canvas,
    Size size,
    int dbm,
    Color color, {
    required bool dashed,
  }) {
    final y = _y(dbm, size.height);
    final paint = Paint()
      ..color = color
      ..strokeWidth = dashed ? 1 : 1.6;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      canvas.drawCircle(Offset(size.width - 6, y), 5, paint);
      return;
    }
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, y), Offset(x + 4, y), paint);
    }
  }

  @override
  bool shouldRepaint(_RssiPainter old) =>
      old.animating != animating ||
      old.threshold != threshold ||
      old.samples.length != samples.length;
}
