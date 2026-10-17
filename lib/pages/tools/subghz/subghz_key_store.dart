import 'dart:convert';

import 'package:flipperlib/flipperlib.dart' hide DateTime;

import 'decode_raw/decode_raw_sub.dart';
import '../../archive/subghz_catalog.dart';

class SubGhzKeyStore {
  const SubGhzKeyStore._();

  static const String dir = '/ext/subghz';

  static Future<String> write(
    FlipperClient client,
    String stem,
    String flipperFormat,
  ) async {
    final path = await uniquePath(client, DecodeRawSub.sourceStem(stem));
    final bytes = utf8.encode(flipperFormat);
    await client.storageWriteChunked(path, bytes);
    await ArchiveCatalog.instance.mirrorSubghzFile(path, bytes);
    return path;
  }

  static Future<String> uniquePath(
    FlipperClient client,
    String stem, {
    String directory = dir,
  }) async {
    var index = 1;
    while (true) {
      final fileName = index == 1 ? '$stem.sub' : '${stem}_$index.sub';
      final path = '$directory/$fileName';
      if (!await exists(client, path)) return path;
      index++;
    }
  }

  static Future<bool> exists(FlipperClient client, String path) async {
    try {
      await client.storageStat(StatRequest(path: path));
      return true;
    } on FlipperRpcStorageNotExistException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
