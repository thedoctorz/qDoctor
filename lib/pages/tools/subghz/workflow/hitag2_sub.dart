enum Hitag2Proto {
  fiatV1('Fiat V1'),
  fiatV2('Fiat V2'),
  renaultV1('Renault V1');

  const Hitag2Proto(this.wireName);

  final String wireName;
}

class Hitag2Signal {
  const Hitag2Signal({
    required this.proto,
    required this.uid,
    required this.btn,
    required this.cnt,
    required this.hop,
    this.frame,
  });

  final Hitag2Proto proto;
  final int uid;
  final int btn;
  final int cnt;
  final int hop;
  final List<int>? frame;

  Hitag2Signal withFrame(List<int>? frame) => Hitag2Signal(
    proto: proto,
    uid: uid,
    btn: btn,
    cnt: cnt,
    hop: hop,
    frame: frame,
  );
}

class Hitag2Sub {
  const Hitag2Sub._();

  static Hitag2Signal? parse(String content) {
    final fields = _flipperFields(content);
    final proto = _protocolKind(fields['Protocol']);
    if (proto == null) return null;

    var signal = _parseNamedFields(fields, proto);
    if (signal != null) {
      if (proto == Hitag2Proto.renaultV1) {
        final raw = parseRenaultV1Bytes(fields['Key'], fields['Key_2']);
        if (raw != null) signal = signal.withFrame(raw);
      }
      return signal;
    }

    return switch (proto) {
      Hitag2Proto.fiatV1 => _parseFiatRaw(fields['Raw'], proto),
      Hitag2Proto.fiatV2 => _parseFiatV2Raw(fields['Raw'], proto),
      Hitag2Proto.renaultV1 => _parseRenaultV1Frame(
        fields['Key'],
        fields['Key_2'],
        proto,
      ),
    };
  }

  static Hitag2Signal? _parseNamedFields(
    Map<String, String> fields,
    Hitag2Proto proto,
  ) {
    final uid = _u32(fields['Hitag2 UID']) ?? _u32(fields['Serial']);
    if (uid == null) return null;
    final hop = _u32(fields['Hop']);
    if (hop == null) return null;
    final cnt = _u32(fields['Cnt']);
    if (cnt == null) return null;

    final btn = _hellBtn(_u32(fields['Btn']) ?? 0, proto);
    final epoch = _u32(fields['Hitag2 Epoch']) ?? 0;

    final int fullCnt;
    if (proto == Hitag2Proto.renaultV1) {
      fullCnt = (((epoch & 0x3FFFF) << 10) | (cnt & 0x3FF)) & 0xFFFFFFFF;
    } else {
      fullCnt = cnt;
    }

    return Hitag2Signal(
      proto: proto,
      uid: uid,
      btn: btn,
      cnt: fullCnt,
      hop: hop,
      frame: proto == Hitag2Proto.renaultV1
          ? packRenaultV1Frame(
              uid: uid,
              btn: btn,
              cnt10: fullCnt & 0xFFFF,
              hop: hop,
            )
          : null,
    );
  }

  static Hitag2Signal? _parseFiatRaw(String? rawHex, Hitag2Proto proto) {
    final raw = _hexBytes(rawHex);
    if (raw == null || raw.length < 13) return null;
    final uid =
        ((raw[2] << 24) | (raw[3] << 16) | (raw[4] << 8) | raw[5]) & 0xFFFFFFFF;
    final btn = raw[6] >> 4;
    final cnt = ((raw[6] & 0x0F) << 6) | (raw[7] >> 2);
    final hop =
        (((raw[7] & 0x03) << 30) |
            (raw[8] << 22) |
            (raw[9] << 14) |
            (raw[10] << 6) |
            (raw[11] >> 2)) &
        0xFFFFFFFF;
    return Hitag2Signal(proto: proto, uid: uid, btn: btn, cnt: cnt, hop: hop);
  }

  static Hitag2Signal? _parseFiatV2Raw(String? rawHex, Hitag2Proto proto) {
    final raw = _hexBytes(rawHex);
    if (raw == null || raw.length < 14) return null;
    final uid =
        ((raw[2] << 24) | (raw[3] << 16) | (raw[4] << 8) | raw[5]) & 0xFFFFFFFF;
    final btn = _hellBtn(raw[7], proto);
    final isFCA = (raw[6] & 0xF0) == 0xD0;
    final int hop;
    final int cnt;
    if (isFCA) {
      hop =
          ((raw[10] << 24) | (raw[11] << 16) | (raw[12] << 8) | raw[13]) &
          0xFFFFFFFF;
      final rawCnt = (raw[8] << 6) | (raw[9] >> 2);
      cnt = (~rawCnt) & 0x3FFF;
    } else {
      hop =
          ((raw[9] << 24) | (raw[10] << 16) | (raw[11] << 8) | raw[12]) &
          0xFFFFFFFF;
      final rawCnt = ((raw[7] & 0x3F) << 5) | (raw[8] >> 3);
      cnt = (~rawCnt) & 0x7FF;
    }
    return Hitag2Signal(proto: proto, uid: uid, btn: btn, cnt: cnt, hop: hop);
  }

  static Hitag2Signal? _parseRenaultV1Frame(
    String? key,
    String? key2,
    Hitag2Proto proto,
  ) {
    final raw = parseRenaultV1Bytes(key, key2);
    if (raw == null) return null;
    final uid =
        ((raw[0] << 24) | (raw[1] << 16) | (raw[2] << 8) | raw[3]) & 0xFFFFFFFF;
    final btn = raw[4] >> 4;
    final cnt = ((raw[4] & 0x0F) << 6) | (raw[5] >> 2);
    final hop =
        (((raw[5] & 0x03) << 30) |
            (raw[6] << 22) |
            (raw[7] << 14) |
            (raw[8] << 6) |
            (raw[9] >> 2)) &
        0xFFFFFFFF;
    return Hitag2Signal(
      proto: proto,
      uid: uid,
      btn: btn,
      cnt: cnt,
      hop: hop,
      frame: raw.sublist(0, 11),
    );
  }

  static List<int>? parseRenaultV1Bytes(String? key, String? key2) {
    final keyBytes = _hexBytes(key);
    if (keyBytes == null || keyBytes.length < 8) return null;
    final key2Bytes = _hexBytes(key2);
    if (key2Bytes == null || key2Bytes.length < 3) return null;
    final raw = <int>[
      ...keyBytes.take(8),
      ...key2Bytes.sublist(key2Bytes.length - 3),
    ];
    if (raw.length < 11) return null;
    return raw.sublist(0, 11);
  }

  static List<int> packRenaultV1Frame({
    required int uid,
    required int btn,
    required int cnt10,
    required int hop,
    int tail = 2,
  }) {
    final raw = List<int>.filled(11, 0);
    raw[0] = (uid >> 24) & 0xFF;
    raw[1] = (uid >> 16) & 0xFF;
    raw[2] = (uid >> 8) & 0xFF;
    raw[3] = uid & 0xFF;
    raw[4] = (((btn & 0x0F) << 4) | ((cnt10 >> 6) & 0x0F)) & 0xFF;
    raw[5] = (((cnt10 & 0x3F) << 2) | ((hop >> 30) & 0x03)) & 0xFF;
    raw[6] = (hop >> 22) & 0xFF;
    raw[7] = (hop >> 14) & 0xFF;
    raw[8] = (hop >> 6) & 0xFF;
    raw[9] = (((hop << 2) & 0xFC) | (tail & 0x03)) & 0xFF;
    var xor = 0;
    for (var i = 0; i < 10; i++) {
      xor ^= raw[i];
    }
    raw[10] = xor & 0xFF;
    return raw;
  }

  static String patchingHitag2Key(String content, int key) {
    final bytes = List<int>.generate(6, (i) => (key >> (8 * (5 - i))) & 0xFF);
    final hex = bytes.map(_hex2).join(' ');
    final lines = content.split('\n');
    _upsert(lines, 'Hitag2 Key:', 'Hitag2 Key: $hex');
    _upsert(lines, 'Hitag2 Epoch:', 'Hitag2 Epoch: 0');
    _trimTrailingBlank(lines);
    return '${lines.join('\n')}\n';
  }

  static String patchingBcmSeed(String content, int seed) {
    final seedHex = List<int>.generate(
      4,
      (i) => (seed >> (8 * (3 - i))) & 0xFF,
    ).map(_hex2).join(' ');
    final lines = content.split('\n');
    _upsert(lines, 'Recovered:', 'Recovered: 01');
    _upsert(lines, 'Seed:', 'Seed: $seedHex');
    _trimTrailingBlank(lines);
    return '${lines.join('\n')}\n';
  }

  static bool hasRecoveredKey(String content) {
    final bytes = _hexBytes(_flipperFields(content)['Hitag2 Key']);
    if (bytes == null || bytes.length != 6) return false;
    return bytes.any((b) => b != 0);
  }

  static bool hasBcmSeed(String content) => recoveredFlag(content) == 1;

  static bool needsBcmSeed(String content) {
    final fields = _flipperFields(content);
    if (_protocolKind(fields['Protocol']) != Hitag2Proto.renaultV1) {
      return false;
    }
    return recoveredFlag(content) == 0 && !hasRecoveredKey(content);
  }

  static int recoveredFlag(String content) {
    final fields = _flipperFields(content);
    final bytes = _hexBytes(fields['Recovered']);
    if (bytes != null && bytes.isNotEmpty) return bytes.first;
    final value = _u32(fields['Recovered']);
    if (value != null) return value & 0xFF;
    return 0;
  }

  static bool isReadyToTransmit(String content) =>
      hasRecoveredKey(content) || hasBcmSeed(content);

  static int _hellBtn(int value, Hitag2Proto proto) {
    final btn = value & 0xFF;
    if (proto == Hitag2Proto.fiatV2 && btn > 0x0F) return btn >> 6;
    return btn;
  }

  static Hitag2Proto? _protocolKind(String? text) {
    if (text == null) return null;
    final t = text.toLowerCase();
    if (t.contains('fiat v2')) return Hitag2Proto.fiatV2;
    if (t.contains('fiat v1')) return Hitag2Proto.fiatV1;
    if (t.contains('renault v1')) return Hitag2Proto.renaultV1;
    return null;
  }

  static Map<String, String> _flipperFields(String content) {
    final fields = <String, String>{};
    for (final rawLine in content.split(RegExp(r'\r\n|\n'))) {
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

  static List<int>? _hexBytes(String? text) {
    if (text == null) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final out = <int>[];
    for (final token in trimmed.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final b = int.tryParse(token, radix: 16);
      if (b == null) return null;
      out.add(b & 0xFF);
    }
    return out.isEmpty ? null : out;
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

  static String _hex2(int b) =>
      (b & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0');

  static void _upsert(List<String> lines, String prefix, String value) {
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith(prefix)) {
        lines[i] = value;
        return;
      }
    }
    lines.add(value);
  }

  static void _trimTrailingBlank(List<String> lines) {
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
  }
}
