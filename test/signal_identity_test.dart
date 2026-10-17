import 'package:flutter_test/flutter_test.dart';
import 'package:doctormobile/pages/tools/subghz/decode_raw/decode_raw_sub.dart';
import 'package:doctormobile/pages/tools/subghz/signal_identity.dart';

String _identity(String keyFile) =>
    SubGhzSignalIdentity.of(DecodeRawSub.fields(keyFile), fallback: keyFile);

String _mercedes({int cnt = 42, int btn = 2, String crc = '0A'}) =>
    '''
Filetype: Flipper SubGhz Key File
Version: 1
Frequency: 433920000
Preset: FM20K
Protocol: Mercedes
Bit: 64
Key: 00 00 00 00 12 34 56 78
Serial: 305419896
Btn: $btn
Cnt: $cnt
CRC: $crc
''';

void main() {
  group('a counter protocol', () {
    test('repeats of one press are one signal, whatever else wobbles', () {
      expect(_identity(_mercedes()), _identity(_mercedes(crc: 'FF')));
    });

    test('the next press is a different signal', () {
      expect(
        _identity(_mercedes(cnt: 42)),
        isNot(_identity(_mercedes(cnt: 43))),
      );
    });

    test('another button at the same count is a different signal', () {
      expect(_identity(_mercedes(btn: 2)), isNot(_identity(_mercedes(btn: 4))));
    });

    test('a missing field is not the same as a zero one', () {
      const base = '''
Protocol: Test
Key: 00 00 00 00 00 00 00 01
Cnt: 7
''';
      const withBtn = '''
Protocol: Test
Key: 00 00 00 00 00 00 00 01
Cnt: 7
Btn: 0
''';
      expect(_identity(base), isNot(_identity(withBtn)));
    });

    test('RawCnt stands in when there is no Cnt', () {
      const a = 'Protocol: Test\nKey: 00 01\nRawCnt: 3\n';
      const b = 'Protocol: Test\nKey: 00 02\nRawCnt: 3\n';
      expect(_identity(a), _identity(b));
    });
  });

  group('a static protocol', () {
    test('the same key is the same signal', () {
      const a = 'Protocol: Princeton\nBit: 24\nKey: 00 00 00 00 00 12 34 56\n';
      const b =
          'Protocol: Princeton\nBit: 24\nKey: 00 00 00 00 00 12 34 56\nTE: 401\n';
      expect(_identity(a), _identity(b));
    });

    test('a different key is a different signal', () {
      const a = 'Protocol: Princeton\nKey: 00 00 00 00 00 12 34 56\n';
      const b = 'Protocol: Princeton\nKey: 00 00 00 00 00 12 34 57\n';
      expect(_identity(a), isNot(_identity(b)));
    });

    test('leading zeroes are formatting, not data', () {
      const padded = 'Protocol: P\nKey: 00 00 00 00 00 00 12 34\n';
      const bare = 'Protocol: P\nKey: 12 34\n';
      expect(_identity(padded), _identity(bare));
    });

    test('Key_2 separates two signals that share a Key', () {
      const a = 'Protocol: P\nKey: 00 11\nKey_2: 00 22\n';
      const b = 'Protocol: P\nKey: 00 11\nKey_2: 00 33\n';
      const none = 'Protocol: P\nKey: 00 11\n';
      expect(_identity(a), isNot(_identity(b)));
      expect(_identity(a), isNot(_identity(none)));
    });

    test('Key2 is read where Key_2 is absent', () {
      const underscore = 'Protocol: P\nKey: 00 11\nKey_2: 00 22\n';
      const plain = 'Protocol: P\nKey: 00 11\nKey2: 00 22\n';
      expect(_identity(underscore), _identity(plain));
    });

    test('a different protocol with the same key is a different signal', () {
      const a = 'Protocol: Princeton\nKey: 00 11\n';
      const b = 'Protocol: CAME\nKey: 00 11\n';
      expect(_identity(a), isNot(_identity(b)));
    });
  });

  group('when the Flipper would refuse to judge', () {
    test('no protocol falls back, so only identical files collapse', () {
      const a = 'Key: 00 11\n';
      const b = 'Key: 00 11\nBit: 8\n';
      expect(_identity(a), a);
      expect(_identity(a), isNot(_identity(b)));
    });

    test('no counter and no key falls back', () {
      const only = 'Protocol: Weird\nBit: 12\n';
      expect(_identity(only), only);
    });

    test('an unparseable key falls back rather than matching everything', () {
      const a = 'Protocol: P\nKey: nonsense\n';
      const b = 'Protocol: P\nKey: also nonsense\n';
      expect(_identity(a), isNot(_identity(b)));
    });
  });
}
