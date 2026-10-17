import '../../archive/subghz_catalog.dart';

class SubghzArchiveSource {
  const SubghzArchiveSource._();

  static bool get available => ArchiveCatalog.instance.isAttached;

  static bool get connected => ArchiveCatalog.instance.isConnected;

  static SubghzSyncView get view => ArchiveCatalog.instance.view;

  static Future<void> showLocalsThenGaps({
    required bool force,
    required int? pullMaxBytes,
    required Future<void> Function(SubghzSyncView view) consume,
  }) async {
    final catalog = ArchiveCatalog.instance;
    if (!catalog.isAttached) return;
    await catalog.warmSubghzLocals();
    await consume(catalog.view);
    if (!catalog.isConnected) return;
    final freshness = catalog.view.freshness;
    if (!force && freshness == SubghzSyncFreshness.current) return;
    if (force || freshness == SubghzSyncFreshness.unknown) {
      await catalog.ensureSubghzVerified(force: force);
    }
    if (pullMaxBytes != null) {
      await catalog.pullSubghzGaps(maxBytes: pullMaxBytes);
    }
    await consume(catalog.view);
  }

  static Future<void> mirror(String remotePath, List<int> bytes) {
    return ArchiveCatalog.instance.mirrorSubghzFile(remotePath, bytes);
  }
}
