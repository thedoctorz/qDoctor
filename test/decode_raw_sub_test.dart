import 'package:flutter_test/flutter_test.dart';
import 'package:doctormobile/pages/tools/subghz/decode_raw/decode_raw_sub.dart';

void main() {
  group('DecodeRawSub.fields', () {
    test('parses FlipperFormat keys and ignores comments', () {
      const body = '''
Filetype: Flipper SubGhz Key File
Version: 1
# comment
Frequency: 433920000
Protocol: Princeton
Bit: 24
Key: 00 00 00 00 00 12 34 56
TE: 400
''';
      final f = DecodeRawSub.fields(body);
      expect(f['Filetype'], 'Flipper SubGhz Key File');
      expect(f['Protocol'], 'Princeton');
      expect(f['Key'], '00 00 00 00 00 12 34 56');
      expect(f['TE'], '400');
      expect(f.containsKey('#'), isFalse);
    });
  });

  group('DecodeRawSub.isRawHeader', () {
    test('matches Flipper SubGhz RAW Filetype', () {
      expect(
        DecodeRawSub.isRawHeader(
          'Filetype: Flipper SubGhz RAW File\nVersion: 1\n',
        ),
        isTrue,
      );
    });

    test('matches Protocol RAW', () {
      expect(
        DecodeRawSub.isRawHeader(
          'Filetype: Flipper SubGhz Key File\nProtocol: RAW\n',
        ),
        isTrue,
      );
    });

    test('rejects a decoded key file', () {
      expect(
        DecodeRawSub.isRawHeader(
          'Filetype: Flipper SubGhz Key File\nProtocol: Princeton\nKey: 01\n',
        ),
        isFalse,
      );
    });
  });

  group('DecodeRawSub.hitFromResponse', () {
    test('exposes protocol and key fields in the subtitle', () {
      const fmt = '''
Filetype: Flipper SubGhz Key File
Version: 1
Frequency: 433920000
Preset: FuriHalSubGhzPresetOok650Async
Protocol: Princeton
Bit: 24
Key: 00 00 00 00 00 12 34 56
TE: 400
''';
      final hit = DecodeRawSub.hitFromResponse(
        protocol: 'Princeton',
        flipperFormat: fmt,
      );
      expect(hit.protocol, 'Princeton');
      expect(hit.fields['Serial'], isNull);
      expect(hit.subtitle, contains('Key 00 00 00 00 00 12 34 56'));
      expect(hit.subtitle, contains('Bit 24'));
      expect(hit.subtitle, contains('TE 400'));
    });

    test('falls back to the Protocol field when the RPC name is empty', () {
      final hit = DecodeRawSub.hitFromResponse(
        protocol: '  ',
        flipperFormat: 'Protocol: Nice FloR-S\nSerial: 00AABB\nBtn: 1\n',
      );
      expect(hit.protocol, 'Nice FloR-S');
      expect(hit.subtitle, contains('Serial 00AABB'));
      expect(hit.subtitle, contains('Btn 1'));
    });
  });

  group('DecodeRawSub save naming', () {
    test('sourceStem strips path and .sub', () {
      expect(DecodeRawSub.sourceStem('/ext/subghz/capture.sub'), 'capture');
      expect(DecodeRawSub.sourceStem('garage.SUB'), 'garage');
      expect(DecodeRawSub.sourceStem(''), 'capture');
    });

    test('sanitizeProtocol keeps alphanumerics and collapses the rest', () {
      expect(DecodeRawSub.sanitizeProtocol('Princeton'), 'Princeton');
      expect(DecodeRawSub.sanitizeProtocol('Nice FloR-S'), 'Nice_FloR_S');
      expect(DecodeRawSub.sanitizeProtocol('???'), 'Unknown');
    });

    test('saveFileName is source_protocol_index.sub', () {
      expect(
        DecodeRawSub.saveFileName('capture', 'Princeton', 1),
        'capture_Princeton_1.sub',
      );
      expect(
        DecodeRawSub.saveFileName('gate', 'Nice FloR-S', 2),
        'gate_Nice_FloR_S_2.sub',
      );
    });
  });

  group('DecodeRawSub.isArchiveRaw', () {
    test('matches Protocol RAW or has_raw metadata', () {
      expect(DecodeRawSub.isArchiveRaw('RAW', null), isTrue);
      expect(DecodeRawSub.isArchiveRaw('raw', {'has_raw': '1'}), isTrue);
      expect(DecodeRawSub.isArchiveRaw('Princeton', {'has_raw': '1'}), isTrue);
      expect(DecodeRawSub.isArchiveRaw('Princeton', null), isFalse);
      expect(DecodeRawSub.isArchiveRaw('Princeton', {'has_raw': '0'}), isFalse);
    });
  });
}
