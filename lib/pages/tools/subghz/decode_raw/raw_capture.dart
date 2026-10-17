import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

class RawCapture {
  const RawCapture({
    required this.envelope,
    required this.pulseCount,
    required this.durationMicros,
    required List<double> byteLadder,
    required List<double> timeLadder,
  }) : _byteLadder = byteLadder,
       _timeLadder = timeLadder;

  final List<double> envelope;

  final int pulseCount;
  final double durationMicros;

  final List<double> _byteLadder;
  final List<double> _timeLadder;

  static const int buckets = 480;

  static const int maxPulses = 2000000;

  bool get isEmpty => pulseCount == 0 || durationMicros <= 0;

  double timeAt(double byteFraction) {
    final target = byteFraction.clamp(0.0, 1.0);
    if (_byteLadder.length < 2) return target;
    if (target <= _byteLadder.first) return _timeLadder.first;
    if (target >= _byteLadder.last) return _timeLadder.last;

    var lo = 0;
    var hi = _byteLadder.length - 1;
    while (lo + 1 < hi) {
      final mid = (lo + hi) >> 1;
      if (_byteLadder[mid] <= target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = _byteLadder[hi] - _byteLadder[lo];
    if (span <= 0) return _timeLadder[lo];
    final t = (target - _byteLadder[lo]) / span;
    return _timeLadder[lo] + t * (_timeLadder[hi] - _timeLadder[lo]);
  }

  static const RawCapture empty = RawCapture(
    envelope: <double>[],
    pulseCount: 0,
    durationMicros: 0,
    byteLadder: <double>[],
    timeLadder: <double>[],
  );

  static Future<RawCapture> parseBytes(Uint8List bytes) {
    if (bytes.length <= isolateThresholdBytes) {
      return Future.value(_decode(bytes));
    }
    return Isolate.run(() => _decode(bytes));
  }

  static const int isolateThresholdBytes = 128 * 1024;

  static RawCapture _decode(Uint8List bytes) =>
      parse(utf8.decode(bytes, allowMalformed: true));

  static RawCapture parse(String content) {
    final pulses = <int>[];
    final byteAt = <int>[];

    var dataStart = -1;
    var offset = 0;
    final length = content.length;

    while (offset < length && pulses.length < maxPulses) {
      var lineEnd = content.indexOf('\n', offset);
      if (lineEnd < 0) lineEnd = length;
      final lineStart = offset;
      final line = content.substring(offset, lineEnd);
      offset = lineEnd + 1;

      final colon = line.indexOf(':');
      if (colon < 0) continue;
      if (line.substring(0, colon).trim() != 'RAW_Data') continue;
      if (dataStart < 0) dataStart = lineStart;

      _readValues(line, colon + 1, lineStart, pulses, byteAt);
    }

    if (pulses.isEmpty) return empty;
    if (dataStart < 0) dataStart = 0;

    final payloadBytes = math.max(1, length - dataStart);
    return _build(pulses, byteAt, dataStart, payloadBytes);
  }

  static void _readValues(
    String line,
    int from,
    int lineStart,
    List<int> pulses,
    List<int> byteAt,
  ) {
    var i = from;
    final end = line.length;
    while (i < end) {
      final ch = line.codeUnitAt(i);
      if (ch == 0x20 || ch == 0x09 || ch == 0x0D) {
        i++;
        continue;
      }
      final start = i;
      var negative = false;
      if (ch == 0x2D) {
        negative = true;
        i++;
      } else if (ch == 0x2B) {
        i++;
      }
      var value = 0;
      var digits = 0;
      while (i < end) {
        final digit = line.codeUnitAt(i) - 0x30;
        if (digit < 0 || digit > 9) break;
        value = value * 10 + digit;
        digits++;
        i++;
      }
      if (digits == 0) {
        while (i < end && line.codeUnitAt(i) != 0x20) {
          i++;
        }
        continue;
      }
      if (value == 0) continue;
      pulses.add(negative ? -value : value);
      byteAt.add(lineStart + start);
      if (pulses.length >= maxPulses) return;
    }
  }

  static RawCapture _build(
    List<int> pulses,
    List<int> byteAt,
    int dataStart,
    int payloadBytes,
  ) {
    final gate = _activityGate(pulses);

    var total = 0.0;
    for (final pulse in pulses) {
      total += pulse.abs();
    }
    if (total <= 0) return empty;

    final bucketSpan = total / buckets;
    final active = List<double>.filled(buckets, 0);
    final pairs = List<int>.filled(buckets, 0);
    final matched = List<int>.filled(buckets, 0);

    final byteLadder = <double>[0];
    final timeLadder = <double>[0];
    final ladderEvery = math.max(1, pulses.length ~/ buckets);

    var cursor = 0.0;
    var previous = 0.0;
    for (var i = 0; i < pulses.length; i++) {
      final duration = pulses[i].abs().toDouble();

      if (i % ladderEvery == 0) {
        byteLadder.add(
          ((byteAt[i] - dataStart) / payloadBytes).clamp(0.0, 1.0),
        );
        timeLadder.add((cursor / total).clamp(0.0, 1.0));
      }

      if (duration <= gate) _spread(active, cursor, duration, bucketSpan);

      if (previous > 0) {
        final bucket = (cursor / bucketSpan).floor().clamp(0, buckets - 1);
        pairs[bucket]++;
        final hi = math.max(previous, duration);
        final lo = math.min(previous, duration);
        if (hi <= lo * 1.25) matched[bucket]++;
      }
      previous = duration;

      cursor += duration;
    }
    byteLadder.add(1);
    timeLadder.add(1);

    final raw = List<double>.filled(buckets, 0);
    for (var i = 0; i < buckets; i++) {
      final duty = (active[i] / bucketSpan).clamp(0.0, 1.0);
      final regularity = pairs[i] == 0 ? 1.0 : matched[i] / pairs[i];
      raw[i] = duty * (0.35 + 0.65 * regularity);
    }

    return RawCapture(
      envelope: _normalize(raw),
      pulseCount: pulses.length,
      durationMicros: total,
      byteLadder: byteLadder,
      timeLadder: timeLadder,
    );
  }

  static void _spread(
    List<double> active,
    double at,
    double duration,
    double bucketSpan,
  ) {
    var index = (at / bucketSpan).floor();
    if (index < 0) index = 0;
    var position = at;
    var edge = (index + 1) * bucketSpan;
    var remaining = duration;

    while (remaining > 0 && index < buckets) {
      final room = edge - position;
      if (room > remaining) {
        active[index] += remaining;
        return;
      }
      if (room > 0) {
        active[index] += room;
        remaining -= room;
      }
      index++;
      position = edge;
      edge = (index + 1) * bucketSpan;
    }
  }

  static double _activityGate(List<int> pulses) {
    const sampleMax = 4096;
    final step = math.max(1, pulses.length ~/ sampleMax);
    final sample = <int>[];
    for (var i = 0; i < pulses.length; i += step) {
      sample.add(pulses[i].abs());
    }
    sample.sort();
    final median = sample[sample.length ~/ 2].toDouble();
    return (median * 8).clamp(400.0, 20000.0);
  }

  static List<double> _normalize(List<double> raw) {
    final sorted = [...raw]..sort();
    final low = sorted[(sorted.length * 0.05).floor()];
    final high =
        sorted[(sorted.length * 0.98).floor().clamp(0, sorted.length - 1)];
    final span = high - low;
    if (span < 0.08) return raw;
    return [for (final value in raw) ((value - low) / span).clamp(0.0, 1.0)];
  }
}
