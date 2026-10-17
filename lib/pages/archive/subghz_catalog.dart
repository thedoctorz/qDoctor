import '../../components/archive/category.dart';

const String subghzArchiveSyncHint =
    'Sync Sub-GHz in Archive to see captures from your Flipper.';

enum SubghzSyncFreshness { unknown, current, pending }

class SubghzArchiveFile {
  const SubghzArchiveFile({
    required this.keyId,
    required this.remotePath,
    required this.name,
    required this.size,
    required this.localPath,
  });

  final String keyId;
  final String remotePath;
  final String name;
  final int size;
  final String localPath;
}

class SubghzArchiveGap {
  const SubghzArchiveGap({
    required this.keyId,
    required this.remotePath,
    required this.name,
    required this.remoteSize,
    this.localPath,
  });

  final String keyId;
  final String remotePath;
  final String name;
  final int remoteSize;
  final String? localPath;
}

class SubghzSyncView {
  const SubghzSyncView({
    required this.freshness,
    required this.local,
    required this.gaps,
  });

  static const empty = SubghzSyncView(
    freshness: SubghzSyncFreshness.unknown,
    local: <SubghzArchiveFile>[],
    gaps: <SubghzArchiveGap>[],
  );

  final SubghzSyncFreshness freshness;
  final List<SubghzArchiveFile> local;
  final List<SubghzArchiveGap> gaps;
}

class SubghzRemotePath {
  const SubghzRemotePath({
    required this.category,
    required this.flipperDir,
    required this.subFolder,
    required this.name,
    required this.fileName,
  });

  final ArchiveCategory category;
  final String flipperDir;
  final String subFolder;
  final String name;
  final String fileName;

  static SubghzRemotePath? tryParse(String remotePath) {
    const prefix = '/ext/subghz/';
    if (!remotePath.startsWith(prefix)) return null;
    var rel = remotePath.substring(prefix.length);
    if (rel.isEmpty || rel.endsWith('/')) return null;

    var category = ArchiveCategory.subghz;
    var flipperDir = ArchiveCategory.subghz.flipperDir;
    if (rel == 'wardriving' || rel.startsWith('wardriving/')) {
      category = ArchiveCategory.wardriving;
      flipperDir = ArchiveCategory.wardriving.flipperDir;
      rel = rel.substring('wardriving'.length);
      if (rel.startsWith('/')) rel = rel.substring(1);
      if (rel.isEmpty) return null;
    }

    final slash = rel.lastIndexOf('/');
    final subFolder = slash < 0 ? '' : rel.substring(0, slash);
    final fileName = slash < 0 ? rel : rel.substring(slash + 1);
    if (!fileName.toLowerCase().endsWith('.sub')) return null;
    final name = fileName.substring(0, fileName.length - 4);
    if (name.isEmpty) return null;

    if (category == ArchiveCategory.subghz && subFolder.isNotEmpty) {
      final first = subFolder.split('/').first;
      if (ArchiveCategory.subghz.isIgnoredSubDir(first)) return null;
    }
    return SubghzRemotePath(
      category: category,
      flipperDir: flipperDir,
      subFolder: subFolder,
      name: name,
      fileName: fileName,
    );
  }
}

class ArchiveCatalog {
  ArchiveCatalog._();

  static final ArchiveCatalog instance = ArchiveCatalog._();

  Object? _owner;
  SubghzSyncView Function()? _read;
  bool Function()? _connected;
  Future<void> Function()? _warm;
  Future<void> Function({bool force})? _ensure;
  Future<void> Function({int? maxBytes})? _pull;
  Future<void> Function(String remotePath, List<int> bytes)? _mirror;

  bool get isAttached => _read != null;

  SubghzSyncView get view => _read?.call() ?? SubghzSyncView.empty;

  bool get isConnected => _connected?.call() ?? false;

  void attach({
    required Object owner,
    required SubghzSyncView Function() read,
    required bool Function() connected,
    required Future<void> Function() warm,
    required Future<void> Function({bool force}) ensure,
    required Future<void> Function({int? maxBytes}) pull,
    required Future<void> Function(String remotePath, List<int> bytes) mirror,
  }) {
    _owner = owner;
    _read = read;
    _connected = connected;
    _warm = warm;
    _ensure = ensure;
    _pull = pull;
    _mirror = mirror;
  }

  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _read = null;
    _connected = null;
    _warm = null;
    _ensure = null;
    _pull = null;
    _mirror = null;
  }

  Future<void> warmSubghzLocals() async {
    await _warm?.call();
  }

  Future<void> ensureSubghzVerified({bool force = false}) async {
    await _ensure?.call(force: force);
  }

  Future<void> pullSubghzGaps({int? maxBytes}) async {
    await _pull?.call(maxBytes: maxBytes);
  }

  Future<void> mirrorSubghzFile(String remotePath, List<int> bytes) async {
    await _mirror?.call(remotePath, bytes);
  }
}
