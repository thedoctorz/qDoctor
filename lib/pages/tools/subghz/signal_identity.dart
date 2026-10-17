class SubGhzSignalIdentity {
  const SubGhzSignalIdentity._();

  static const String _absent = '-';

  static String of(Map<String, String> fields, {required String fallback}) {
    final protocol = fields['Protocol']?.trim();
    if (protocol == null || protocol.isEmpty) return fallback;

    final counter = _uint(fields['Cnt']) ?? _uint(fields['RawCnt']);
    if (counter != null) {
      return [
        protocol,
        'c$counter',
        's${_uint(fields['Serial']) ?? _absent}',
        'b${_uint(fields['Btn']) ?? _absent}',
        't${_uint(fields['Type']) ?? _absent}',
      ].join('|');
    }

    final key = _hex(fields['Key']);
    if (key == null) return fallback;
    final key2 = _hex(fields['Key_2']) ?? _hex(fields['Key2']);
    return [protocol, 'k$key', 'j${key2 ?? _absent}'].join('|');
  }

  static int? _uint(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    return int.tryParse(value);
  }

  static String? _hex(String? raw) {
    final value = raw?.replaceAll(RegExp(r'[\s]'), '').toUpperCase();
    if (value == null || value.isEmpty) return null;
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(value)) return null;
    final trimmed = value.replaceFirst(RegExp(r'^0+(?=.)'), '');
    return trimmed;
  }
}
