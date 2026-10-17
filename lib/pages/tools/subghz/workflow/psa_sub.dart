class PsaSignal {
  const PsaSignal({required this.key1, required this.key2});

  final List<int> key1;
  final List<int> key2;
}

class PsaRecovered {
  const PsaRecovered({
    required this.serial,
    required this.counter,
    required this.button,
    required this.type,
    this.crc,
    this.seed,
  });

  final int serial;
  final int counter;
  final int button;
  final int type;
  final int? crc;
  final int? seed;
}

class PsaSub {
  const PsaSub._();

  static PsaSignal? parse(String content) {
    final fields = _flipperFields(content);
    if (!_protocolIsPsa(fields['Protocol'])) return null;
    final key1 = readKeyBytes(fields['Key']);
    if (key1 == null) return null;
    final key2 = readKeyBytes(fields['Key_2']) ?? readKeyBytes(fields['Key2']);
    if (key2 == null) return null;
    return PsaSignal(key1: key1, key2: key2);
  }

  static bool needsBruteforce(String content) =>
      parse(content) != null && !hasSerial(content);

  static bool hasSerial(String content) =>
      _u32(_flipperFields(content)['Serial']) != null;

  static String patching(String content, PsaRecovered r) {
    final lines = content.split('\n');
    _upsert(lines, 'Serial:', 'Serial: ${r.serial}');
    _upsert(lines, 'Btn:', 'Btn: ${r.button}');
    _upsert(lines, 'Cnt:', 'Cnt: ${r.counter}');
    _upsert(lines, 'Type:', 'Type: ${r.type}');
    if (r.crc != null) _upsert(lines, 'CRC:', 'CRC: ${r.crc}');
    if (r.seed != null) _upsert(lines, 'Seed:', 'Seed: ${r.seed}');
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return '${lines.join('\n')}\n';
  }

  static List<int>? readKeyBytes(String? text) {
    if (text == null || text.isEmpty) return null;
    final buf = StringBuffer();
    for (final ch in text.split('')) {
      if (_isSpace(ch)) continue;
      if (!_isHexDigit(ch)) break;
      buf.write(ch);
      if (buf.length == 16) break;
    }
    var hex = buf.toString();
    if (hex.isEmpty) return null;
    if (hex.length < 16) hex = hex.padLeft(16, '0');
    if (hex.length != 16) return null;
    final out = <int>[];
    for (var i = 0; i < 16; i += 2) {
      final b = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (b == null) return null;
      out.add(b);
    }
    return out;
  }

  static bool _protocolIsPsa(String? text) =>
      text != null && text.toLowerCase().contains('psa');

  static Map<String, String> _flipperFields(String content) {
    final fields = <String, String>{};
    for (final rawLine in content.split(RegExp(r'\r\n|\r|\n'))) {
      final line = rawLine.trim();
      if (line.startsWith('#')) continue;
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final key = line.substring(0, colon).trim();
      if (key.isEmpty) continue;
      fields[key] = line.substring(colon + 1).trim();
    }
    return fields;
  }

  static int? _u32(String? text) {
    if (text == null) return null;
    final v = text.trim();
    if (v.isEmpty) return null;
    if (v.startsWith('0x') || v.startsWith('0X')) {
      return int.tryParse(v.substring(2), radix: 16);
    }
    return int.tryParse(v);
  }

  static void _upsert(List<String> lines, String prefix, String value) {
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith(prefix)) {
        lines[i] = value;
        return;
      }
    }
    lines.add(value);
  }

  static bool _isSpace(String ch) => ch.trim().isEmpty;

  static bool _isHexDigit(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x46) ||
        (c >= 0x61 && c <= 0x66);
  }
}
