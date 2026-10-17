const String kSubGhzRawFileType = 'Flipper SubGhz RAW File';

class DecodeRawHitView {
  const DecodeRawHitView({
    required this.protocol,
    required this.flipperFormat,
    required this.fields,
  });

  final String protocol;
  final String flipperFormat;
  final Map<String, String> fields;

  String get subtitle {
    final parts = <String>[];
    for (final key in const [
      'Key',
      'Serial',
      'Btn',
      'Bit',
      'TE',
      'Hop',
      'Cnt',
      'Key_2',
    ]) {
      final v = fields[key];
      if (v != null && v.isNotEmpty) parts.add('$key $v');
    }
    return parts.join('  ·  ');
  }
}

class DecodeRawSub {
  const DecodeRawSub._();

  static Map<String, String> fields(String content) {
    final out = <String, String>{};
    for (final rawLine in content.split(RegExp(r'\r\n|\r|\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final key = line.substring(0, colon).trim();
      if (key.isEmpty) continue;
      out[key] = line.substring(colon + 1).trim();
    }
    return out;
  }

  static bool isRawHeader(String content) {
    final f = fields(content);
    final type = f['Filetype'] ?? '';
    if (type.contains(kSubGhzRawFileType)) return true;
    return (f['Protocol'] ?? '').toUpperCase() == 'RAW';
  }

  static DecodeRawHitView hitFromResponse({
    required String protocol,
    required String flipperFormat,
  }) {
    final f = fields(flipperFormat);
    final name = protocol.trim().isNotEmpty
        ? protocol.trim()
        : (f['Protocol'] ?? 'Unknown');
    return DecodeRawHitView(
      protocol: name,
      flipperFormat: flipperFormat,
      fields: f,
    );
  }

  static String sourceStem(String pathOrName) {
    var name = pathOrName.replaceAll('\\', '/').split('/').last;
    if (name.toLowerCase().endsWith('.sub')) {
      name = name.substring(0, name.length - 4);
    }
    return name.isEmpty ? 'capture' : name;
  }

  static String sanitizeProtocol(String protocol) {
    final buf = StringBuffer();
    for (final unit in protocol.codeUnits) {
      final isAlnum =
          (unit >= 48 && unit <= 57) ||
          (unit >= 65 && unit <= 90) ||
          (unit >= 97 && unit <= 122);
      if (isAlnum) {
        buf.writeCharCode(unit);
      } else if (buf.isNotEmpty) {
        final s = buf.toString();
        if (!s.endsWith('_')) buf.write('_');
      }
    }
    var out = buf.toString();
    while (out.endsWith('_')) {
      out = out.substring(0, out.length - 1);
    }
    return out.isEmpty ? 'Unknown' : out;
  }

  static String saveFileName(String sourceStem, String protocol, int index) {
    return '${sourceStem}_${sanitizeProtocol(protocol)}_$index.sub';
  }

  static bool isArchiveRaw(String? protocol, Map<String, String>? meta) {
    if ((protocol ?? '').toUpperCase() == 'RAW') return true;
    return meta?['has_raw'] == '1';
  }
}
