import '../../../components/codec/fap/api_version.dart';
import 'models/card.dart';
import 'models/manifest.dart';

enum CatalogAppState { install, update, open }

CatalogAppState catalogAppState({
  required AppCard card,
  required AppManifest? manifest,
  required (int major, int minor)? targetSdk,
  (int minMajor, int maxMajor)? apiWindow,
  bool ignoreSdkMismatch = false,
}) {
  if (manifest == null) return CatalogAppState.install;

  final cv = card.currentVersion;
  if (cv == null) return CatalogAppState.open;

  if (manifest.versionUid.isNotEmpty &&
      cv.id.isNotEmpty &&
      manifest.versionUid != cv.id) {
    return CatalogAppState.update;
  }

  final sdk = ignoreSdkMismatch ? null : parseApi(manifest.sdkApi);
  if (sdk != null && apiWindow != null) {
    if (sdk.$1 < apiWindow.$1 || sdk.$1 > apiWindow.$2) {
      return CatalogAppState.update;
    }
    if (targetSdk != null && sdk.$1 == targetSdk.$1 && targetSdk.$2 < sdk.$2) {
      return CatalogAppState.update;
    }
  } else if (sdk != null && targetSdk != null) {
    final (major, minor) = targetSdk;
    if (sdk.$1 != major || minor < sdk.$2) {
      return CatalogAppState.update;
    }
  }

  return CatalogAppState.open;
}
