import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctormobile/services/connection/firmware_capability.dart';

class _FakeClient implements FlipperClient {
  _FakeClient(this._info, {this.connected = true, this.fetched = true});

  final Map<String, String> _info;
  final bool connected;
  final bool fetched;

  @override
  bool get isConnected => connected;

  @override
  bool get deviceInfoFetched => fetched;

  @override
  Map<String, String> get deviceInfoCache => _info;

  @override
  Future<Map<String, String>> awaitDeviceInfo() async => _info;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const capability = FirmwareCapability.subghzRpc;

  group('key spelling', () {
    test('the RPC spelling is underscore separated', () {
      expect(capability.candidateKeys.first, 'doctor_rpc_subghz');
    });

    for (final key in const [
      'doctor_rpc_subghz',
      'doctor.rpc.subghz',
      'devinfo_doctor.rpc.subghz',
      'devinfo_doctor_rpc_subghz',
    ]) {
      test('$key resolves', () {
        final client = _FakeClient({key: '1'});
        expect(FirmwareCapabilities.level(client, capability), 1);
      });
    }

    test('an unrelated key does not', () {
      final client = _FakeClient({'doctor_rpc_nfc': '1'});
      expect(FirmwareCapabilities.level(client, capability), isNull);
    });
  });

  group('supports', () {
    test('the app minimum tracks the firmware DOCTOR_RPC_SUBGHZ_VERSION', () {
      expect(capability.minimum, 3);
    });

    test('firmware that does not report the key is unsupported', () async {
      final client = _FakeClient({'hardware_name': 'Flipper'});
      expect(await FirmwareCapabilities.supports(client, capability), isFalse);
    });

    test('a revision below the minimum is unsupported', () async {
      final client = _FakeClient({
        'doctor_rpc_subghz': '${capability.minimum - 1}',
      });
      expect(await FirmwareCapabilities.supports(client, capability), isFalse);
    });

    test('the minimum revision is supported', () async {
      final client = _FakeClient({
        'doctor_rpc_subghz': '${capability.minimum}',
      });
      expect(await FirmwareCapabilities.supports(client, capability), isTrue);
    });

    test('a newer revision is still supported', () async {
      final client = _FakeClient({
        'doctor_rpc_subghz': '${capability.minimum + 6}',
      });
      expect(await FirmwareCapabilities.supports(client, capability), isTrue);
    });

    test('a value that is not a number is treated as absent', () async {
      final client = _FakeClient({'doctor_rpc_subghz': 'yes'});
      expect(await FirmwareCapabilities.supports(client, capability), isFalse);
    });

    test('nothing is claimed while disconnected', () async {
      final client = _FakeClient({
        'doctor_rpc_subghz': '${capability.minimum}',
      }, connected: false);
      expect(await FirmwareCapabilities.supports(client, capability), isFalse);
    });

    test('an unfetched snapshot is awaited before answering', () async {
      final client = _FakeClient({
        'doctor_rpc_subghz': '${capability.minimum}',
      }, fetched: false);
      expect(await FirmwareCapabilities.supports(client, capability), isTrue);
    });
  });
}
