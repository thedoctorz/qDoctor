import 'dart:async';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter_test/flutter_test.dart';
import 'package:doctormobile/components/archive/category.dart';
import 'package:doctormobile/pages/archive/map/controller.dart';
import 'package:doctormobile/services/archive/storage.dart';
import 'package:doctormobile/services/localization/l10n.dart';

class _FakeClient implements FlipperClient {
  _FakeClient({this.connected = true, this.name = 'Flipper'});

  final bool connected;
  final String? name;

  int listed = 0;
  int read = 0;

  @override
  bool get isConnected => connected;

  @override
  String? getName() => name;

  final _connection = StreamController<FlipperConnectionState>.broadcast();

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  Stream<Map<String, String>> get deviceInfoUpdates =>
      const Stream<Map<String, String>>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final member = invocation.memberName.toString();
    if (member.contains('storageList') || member.contains('storageRead')) {
      if (member.contains('storageList')) listed++;
      if (member.contains('storageRead')) read++;
      throw StateError('the map must not read the Flipper for pins');
    }
    return super.noSuchMethod(invocation);
  }

  Future<void> closeStreams() => _connection.close();
}

class _MemoryStorage extends ArchiveStorage {
  _MemoryStorage({this.deviceName, this.entries = const []});

  final String? deviceName;
  final List<LocalKeyEntry> entries;
  int lists = 0;

  @override
  Future<String?> readLastDeviceName() async => deviceName;

  @override
  Future<List<LocalKeyEntry>> listAll(
    String deviceName, {
    bool? includeSubfolders,
  }) async {
    lists++;
    return entries;
  }
}

String _geotagged({double lat = 48.8584, double lon = 2.2945}) =>
    'Filetype: Flipper SubGhz Key File\n'
    'Version: 1\n'
    'Frequency: 433920000\n'
    'Protocol: Princeton\n'
    'Bit: 24\n'
    'Key: 00 00 00 00 00 12 34 56\n'
    'Lat: $lat\n'
    'Lon: $lon\n';

const String _plain =
    'Filetype: Flipper SubGhz Key File\n'
    'Version: 1\n'
    'Protocol: Princeton\n'
    'Key: 00 00 00 00 00 65 43 21\n';

Future<({io.Directory dir, LocalKeyEntry entry})> _writeKey(
  String name,
  String contents,
) async {
  final dir = await io.Directory.systemTemp.createTemp('map-pins-');
  final file = io.File('${dir.path}/$name.sub');
  await file.writeAsString(contents);
  return (
    dir: dir,
    entry: LocalKeyEntry(
      name: name,
      category: ArchiveCategory.subghz,
      extension: 'sub',
      flipperDir: 'subghz',
      subFolder: '',
      path: file.path,
      size: await file.length(),
      mtime: DateTime.now(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unsynced files on the Flipper are not read; the map asks to sync instead',
    () async {
      final client = _FakeClient();
      final storage = _MemoryStorage(deviceName: 'Flipper');
      final controller = MapToolController(storage: storage, client: client);

      await controller.loadFiles();

      expect(controller.pins, isEmpty);
      expect(controller.needsArchiveSync, isTrue);
      expect(controller.syncHint, l10n.mapSyncToSeeLocations);
      expect(client.listed, 0);
      expect(client.read, 0);

      controller.dispose();
      await client.closeStreams();
    },
  );

  test('a geotagged file from the synced archive lands on the map', () async {
    final written = await _writeKey('gate', _geotagged());
    addTearDown(() => written.dir.delete(recursive: true));

    final client = _FakeClient();
    final controller = MapToolController(
      storage: _MemoryStorage(deviceName: 'Flipper', entries: [written.entry]),
      client: client,
    );

    await controller.loadFiles();

    expect(controller.pins, hasLength(1));
    final pin = controller.pins.single;
    expect(pin.name, 'gate');
    expect(pin.latitude, closeTo(48.8584, 0.0001));
    expect(pin.remotePath, '/ext/subghz/gate.sub');
    expect(controller.needsArchiveSync, isFalse);
    expect(controller.loadError, isNull);

    controller.dispose();
    await client.closeStreams();
  });

  test('a synced file with no coordinates is not a pin', () async {
    final written = await _writeKey('plain', _plain);
    addTearDown(() => written.dir.delete(recursive: true));

    final client = _FakeClient();
    final controller = MapToolController(
      storage: _MemoryStorage(deviceName: 'Flipper', entries: [written.entry]),
      client: client,
    );

    await controller.loadFiles();

    expect(controller.pins, isEmpty);
    expect(controller.needsArchiveSync, isFalse);

    controller.dispose();
    await client.closeStreams();
  });

  test('no known Flipper asks to connect and sync in Archive', () async {
    final client = _FakeClient(connected: false, name: null);
    final controller = MapToolController(
      storage: _MemoryStorage(),
      client: client,
    );

    await controller.loadFiles();

    expect(controller.pins, isEmpty);
    expect(controller.needsArchiveSync, isTrue);
    expect(controller.syncHint, l10n.mapNoSyncedFlipper);

    controller.dispose();
    await client.closeStreams();
  });

  test('overlapping loads read the archive once', () async {
    final client = _FakeClient();
    final storage = _MemoryStorage(deviceName: 'Flipper');
    final controller = MapToolController(storage: storage, client: client);

    await Future.wait([
      controller.loadFiles(),
      controller.loadFiles(),
      controller.loadFiles(),
    ]);

    expect(storage.lists, 1);

    controller.dispose();
    await client.closeStreams();
  });
}
