import 'package:flipperlib/flipperlib.dart' hide DateTime;

import '../logging.dart';

enum FirmwareCapability {
  subghzRpc(['doctor', 'rpc', 'subghz'], 3);

  const FirmwareCapability(this.path, this.minimum);

  final List<String> path;

  final int minimum;

  List<String> get candidateKeys => [
    path.join('_'),
    path.join('.'),
    'devinfo_${path.join('.')}',
    'devinfo_${path.join('_')}',
  ];
}

class FirmwareCapabilities {
  const FirmwareCapabilities._();

  static Future<bool> supports(
    FlipperClient client,
    FirmwareCapability capability,
  ) async {
    if (!client.isConnected) return false;

    var reported = level(client, capability);
    if (reported == null && !client.deviceInfoFetched) {
      try {
        await client.awaitDeviceInfo().timeout(const Duration(seconds: 15));
      } catch (e) {
        LogService.warn('[capability] device info unavailable: $e');
        return false;
      }
      reported = level(client, capability);
    }
    if (reported == null) {
      LogService.warn(
        '[capability] ${capability.name} not reported; looked for '
        '${capability.candidateKeys.join(", ")}',
      );
      return false;
    }
    return reported >= capability.minimum;
  }

  static int? level(FlipperClient client, FirmwareCapability capability) {
    final info = client.deviceInfoCache;
    for (final key in capability.candidateKeys) {
      final value = int.tryParse(info[key]?.trim() ?? '');
      if (value != null) return value;
    }
    return null;
  }
}
