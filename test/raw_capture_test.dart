import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:doctormobile/pages/tools/subghz/decode_raw/raw_capture.dart';

List<int> _burst(int count, int te) => [
  for (var i = 0; i < count; i++) ...[te, -te],
];

String _file(List<int> pulses, {int perLine = 32}) {
  final buffer = StringBuffer()
    ..writeln('Filetype: Flipper SubGhz RAW File')
    ..writeln('Version: 1')
    ..writeln('Frequency: 433920000')
    ..writeln('Preset: FuriHalSubGhzPresetOok650Async')
    ..writeln('Protocol: RAW');
  for (var i = 0; i < pulses.length; i += perLine) {
    final end = i + perLine > pulses.length ? pulses.length : i + perLine;
    buffer.writeln('RAW_Data: ${pulses.sublist(i, end).join(' ')}');
  }
  return buffer.toString();
}

void main() {
  group('RawCapture.parse', () {
    test('returns empty for a file with no RAW_Data', () {
      final capture = RawCapture.parse(
        'Filetype: Flipper SubGhz Key File\nProtocol: Princeton\nTE: 400\n',
      );
      expect(capture.isEmpty, isTrue);
      expect(capture.pulseCount, 0);
    });

    test('counts every pulse and sums the capture duration', () {
      final capture = RawCapture.parse(_file([100, -200, 300, -400]));
      expect(capture.pulseCount, 4);
      expect(capture.durationMicros, 1000);
    });

    test('ignores zero-valued samples, which carry no time', () {
      final capture = RawCapture.parse(_file([100, 0, -200]));
      expect(capture.pulseCount, 2);
      expect(capture.durationMicros, 300);
    });

    test('reads values split across several RAW_Data lines', () {
      final capture = RawCapture.parse(_file(_burst(64, 350), perLine: 8));
      expect(capture.pulseCount, 128);
    });

    test('a burst stands up and the gap after it sits at the floor', () {
      final pulses = [..._burst(200, 350), -140000];
      final capture = RawCapture.parse(_file(pulses));

      final half = RawCapture.buckets ~/ 2;
      final burst = capture.envelope.sublist(0, half - 8);
      final gap = capture.envelope.sublist(half + 8);

      expect(burst.reduce((a, b) => a < b ? a : b), greaterThan(0.6));
      expect(gap.reduce((a, b) => a > b ? a : b), lessThan(0.2));
    });

    test(
      'irregular noise reads lower than a regular burst of the same duty',
      () {
        final random = <int>[];
        var seed = 7;
        for (var i = 0; i < 400; i++) {
          seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
          final span = 40 + seed % 400;
          random.add(i.isEven ? span : -span);
        }
        final regular = _burst(200, 220);

        final noise = RawCapture.parse(_file(random));
        final signal = RawCapture.parse(_file(regular));

        double mean(List<double> values) =>
            values.reduce((a, b) => a + b) / values.length;

        expect(mean(noise.envelope), lessThan(mean(signal.envelope)));
      },
    );

    test('envelope stays inside 0..1', () {
      final capture = RawCapture.parse(
        _file([..._burst(120, 400), -50000, ..._burst(120, 400)]),
      );
      for (final value in capture.envelope) {
        expect(value, inInclusiveRange(0, 1));
      }
      expect(capture.envelope.length, RawCapture.buckets);
    });
  });

  group('RawCapture.parseBytes', () {
    test('a small capture parses inline and matches parse()', () async {
      final text = _file(_burst(40, 350));
      final bytes = Uint8List.fromList(utf8.encode(text));
      expect(bytes.length, lessThan(RawCapture.isolateThresholdBytes));

      final viaBytes = await RawCapture.parseBytes(bytes);
      final direct = RawCapture.parse(text);
      expect(viaBytes.pulseCount, direct.pulseCount);
      expect(viaBytes.durationMicros, direct.durationMicros);
      expect(viaBytes.envelope, direct.envelope);
    });

    test('a capture past the threshold crosses an isolate intact', () async {
      final text = _file(_burst(40000, 350));
      final bytes = Uint8List.fromList(utf8.encode(text));
      expect(bytes.length, greaterThan(RawCapture.isolateThresholdBytes));

      final viaBytes = await RawCapture.parseBytes(bytes);
      expect(viaBytes.pulseCount, 80000);
      expect(viaBytes.envelope, RawCapture.parse(text).envelope);
      expect(viaBytes.timeAt(0.5), closeTo(0.5, 0.05));
    });
  });

  group('RawCapture.timeAt', () {
    test('maps the ends onto the ends', () {
      final capture = RawCapture.parse(_file(_burst(200, 350)));
      expect(capture.timeAt(0), closeTo(0, 0.01));
      expect(capture.timeAt(1), closeTo(1, 0.01));
    });

    test('is monotonic', () {
      final capture = RawCapture.parse(
        _file([..._burst(100, 350), -80000, ..._burst(100, 350)]),
      );
      var previous = -1.0;
      for (var i = 0; i <= 20; i++) {
        final value = capture.timeAt(i / 20);
        expect(value, greaterThanOrEqualTo(previous));
        previous = value;
      }
    });

    test('a long gap takes more of the trace than it does of the file', () {
      final capture = RawCapture.parse(
        _file([..._burst(20, 350), -56000, ..._burst(20, 350)]),
      );
      expect(capture.timeAt(0.5), lessThan(0.5));
    });

    test('clamps out-of-range input', () {
      final capture = RawCapture.parse(_file(_burst(20, 350)));
      expect(capture.timeAt(-2), closeTo(0, 0.01));
      expect(capture.timeAt(4), closeTo(1, 0.01));
    });

    test('an unparsed capture maps through unchanged', () {
      expect(RawCapture.empty.timeAt(0.42), 0.42);
    });
  });
}
