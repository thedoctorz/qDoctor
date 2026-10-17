import 'dart:io' show File;

import 'package:flipperlib/flipperlib.dart' hide File;

import '../../../archive/subghz_catalog.dart';

const _subghzRoot = '/ext/subghz';

Future<String> resolveLocalWriteBackPath(
  FlipperClient client, {
  required String fileName,
  required String content,
}) async {
  final catalog = ArchiveCatalog.instance;
  if (catalog.isAttached) {
    await catalog.warmSubghzLocals();
    for (final file in catalog.view.local) {
      if (file.name != fileName) continue;
      try {
        if (await File(file.localPath).readAsString() == content) {
          return file.remotePath;
        }
      } catch (_) {}
    }
  }

  var name = fileName.split('/').last.trim();
  if (name.isEmpty) name = 'recovered.sub';
  final dot = name.toLowerCase().lastIndexOf('.sub');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  for (var i = 0; i < 100; i++) {
    final candidate = switch (i) {
      0 => '$_subghzRoot/$stem.sub',
      1 => '$_subghzRoot/${stem}_recovered.sub',
      _ => '$_subghzRoot/${stem}_recovered_$i.sub',
    };
    if (!await _exists(client, candidate)) return candidate;
  }
  throw StateError('No free file name for "$stem" in $_subghzRoot');
}

Future<bool> _exists(FlipperClient client, String path) async {
  try {
    await client.storageStat(StatRequest(path: path));
    return true;
  } on FlipperRpcStorageNotExistException {
    return false;
  }
}
