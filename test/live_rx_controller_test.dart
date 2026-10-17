import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:doctormobile/pages/tools/subghz/live_rx/live_rx_controller.dart';
import 'package:doctormobile/services/localization/l10n.dart';

class _FakeClient implements FlipperClient {
  _FakeClient({this.subghzRpcLevel = 3});

  final int? subghzRpcLevel;

  final List<String> sent = [];
  final _connection = StreamController<FlipperConnectionState>.broadcast();
  final _broadcast = StreamController<Main>.broadcast();
  late Map<String, String> _info = {
    'hardware.name': 'Flipper',
    if (subghzRpcLevel != null) 'doctor_rpc_subghz': '$subghzRpcLevel',
  };

  bool get sentRxStart => sent.contains('subghzRxStartRequest');

  void push(RxEvent event) => _broadcast.add(Main(subghzRxEvent: event));

  bool connected = true;

  @override
  bool get isConnected => connected;

  void dropLink() {
    connected = false;
    _connection.add(
      const FlipperConnectionState(
        mode: FlipperMode.rpc,
        device: null,
        connected: false,
      ),
    );
  }

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  Stream<Main> get broadcastStream => _broadcast.stream;

  @override
  Map<String, String> get deviceInfoCache => _info;

  @override
  bool get deviceInfoFetched => true;

  @override
  Future<Map<String, String>> awaitDeviceInfo() async => _info;

  @override
  void publishDeviceInfoPatch(Map<String, String> patch) {
    _info = {..._info, ...patch};
  }

  @override
  Future<FlipperRpcBatch<T>> callRpc<T extends GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
  }) async {
    final frames = await callRpcFrames(request, timeout: timeout);
    return FlipperRpcBatch<T>(
      commandId: 1,
      request: request,
      frames: frames,
      items: [for (final frame in frames) ?pick(frame)],
    );
  }

  @override
  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
    bool retainFrames = true,
    bool interleavable = false,
    bool pipelined = true,
  }) async {
    sent.add(request.whichContent().name);
    if (request.hasSubghzSettingsRequest()) {
      return [
        Main(
          subghzSettingsResponse: SettingsResponse(
            frequencies: const [315000000, 433920000, 868350000],
            hopperFrequencies: const [315000000, 433920000],
            presets: const ['AM270', 'AM650', 'FM238', 'MyCustom'],
            defaultFrequency: 433920000,
          ),
        ),
      ];
    }
    if (request.hasSubghzRxStartRequest()) {
      return [
        Main(
          subghzRxStateResponse: RxStateResponse(
            running: true,
            frequency: request.subghzRxStartRequest.frequency,
            preset: request.subghzRxStartRequest.preset,
            deviceName: 'cc1101_int',
            txAllowed: true,
          ),
        ),
      ];
    }
    return const [];
  }

  Future<void> closeStreams() async {
    await _connection.close();
    await _broadcast.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String keyFile({required String key, String protocol = 'Princeton'}) =>
    'Filetype: Flipper SubGhz Key File\n'
    'Version: 1\n'
    'Frequency: 433920000\n'
    'Preset: FuriHalSubGhzPresetOok650Async\n'
    'Protocol: $protocol\n'
    'Bit: 24\n'
    'Key: $key\n';

RxEvent hitEvent(String flipperFormat, {int rssi = -50, String? protocol}) =>
    RxEvent(
      type: RxEventType.RX_EVENT_HIT,
      protocol: protocol ?? 'Princeton',
      flipperFormat: flipperFormat,
      frequency: 433920000,
      rssi: rssi,
      transmittable: true,
    );

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('radio config', () {
    test('nothing is offered before the device tables are read', () {
      final controller = LiveRxController(client: _FakeClient());
      expect(controller.presets, isEmpty);
      expect(controller.frequencies, isEmpty);
      expect(controller.settingsLoaded, isFalse);
      controller.dispose();
    });

    test('the tables come from the device, custom presets included', () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);

      await controller.loadSettings();

      expect(controller.presets, contains('MyCustom'));
      expect(controller.frequencies, contains(868350000));
      expect(controller.hopperFrequencies, hasLength(2));
      expect(controller.settingsLoaded, isTrue);
      controller.dispose();
      await client.closeStreams();
    });

    test('a preset the device does not have is replaced, not sent', () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client)
        ..preset = 'FuriHalSubGhzPresetOok650Async';

      await controller.loadSettings();

      expect(controller.presets, contains(controller.preset));
      expect(controller.preset, isNot('FuriHalSubGhzPresetOok650Async'));
      controller.dispose();
      await client.closeStreams();
    });

    test('AM650 is chosen at launch, not the first table entry', () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);

      await controller.loadSettings();

      expect(controller.presets.first, 'AM270');
      expect(controller.preset, 'AM650');
      controller.dispose();
      await client.closeStreams();
    });

    test('reset goes back to AM650 with a different partner preset', () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);
      await controller.loadSettings();
      controller.preset = 'FM238';

      controller.resetConfig();

      expect(controller.preset, 'AM650');
      expect(controller.presetB, isNot(controller.preset));
      controller.dispose();
      await client.closeStreams();
    });

    test(
      'a frequency the device does not have falls back to its default',
      () async {
        final client = _FakeClient();
        final controller = LiveRxController(client: client)..frequency = 1;

        await controller.loadSettings();

        expect(controller.frequency, 433920000);
        controller.dispose();
        await client.closeStreams();
      },
    );

    test('the settings query only goes to the wire once', () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);

      await controller.loadSettings();
      await controller.loadSettings();

      expect(client.sent.where((c) => c == 'subghzSettingsRequest').length, 1);
      controller.dispose();
      await client.closeStreams();
    });

    test('ignore selections become the SubGhzProtocolFlag bitmask', () {
      final controller = LiveRxController(client: _FakeClient())
        ..ignored = {SubGhzIgnore.princeton, SubGhzIgnore.alarms};
      expect(controller.ignoreFilter, 16384 | 4096);
      controller.dispose();
    });

    test('reset clears the filters and toggles', () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);
      await controller.loadSettings();
      controller
        ..ignored = {SubGhzIgnore.sensors}
        ..sound = true
        ..hopping = true;

      controller.resetConfig();

      expect(controller.ignored, isEmpty);
      expect(controller.sound, isFalse);
      expect(controller.hopping, isFalse);
      expect(controller.presets, contains(controller.preset));
      controller.dispose();
      await client.closeStreams();
    });
  });

  group('firmware gate', () {
    test('firmware without the Sub-GHz RPC is never sent an RxStart', () async {
      final client = _FakeClient(subghzRpcLevel: null);
      final controller = LiveRxController(client: client);

      await controller.start();

      expect(client.sentRxStart, isFalse);
      expect(controller.phase, LiveRxPhase.idle);
      expect(controller.errorMessage, l10n.subghzRxNotImplemented);
      controller.dispose();
      await client.closeStreams();
    });

    test(
      'a reporting firmware starts and takes back the state it applied',
      () async {
        final client = _FakeClient();
        final controller = LiveRxController(client: client)
          ..frequency = 315000000;

        await controller.start();

        expect(client.sentRxStart, isTrue);
        expect(controller.phase, LiveRxPhase.running);
        expect(controller.liveFrequency, 315000000);
        expect(controller.deviceName, 'cc1101_int');
        controller.dispose();
        await client.closeStreams();
      },
    );
  });

  group('signal list', () {
    test(
      'an identical press collapses into one row with a repeat count',
      () async {
        final client = _FakeClient();
        final controller = LiveRxController(client: client);
        await controller.start();

        final body = keyFile(key: '00FFAA55');
        client.push(hitEvent(body));
        client.push(hitEvent(body));
        client.push(hitEvent(body));
        await settle();

        expect(controller.signals, hasLength(1));
        expect(controller.signals.single.repeats, 3);
        controller.dispose();
        await client.closeStreams();
      },
    );

    test('one press stays one row when a decoder recomputes a field', () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);
      await controller.start();

      String press(String crc) =>
          '${keyFile(key: '00FFAA55', protocol: 'Mercedes')}'
          'Serial: 305419896\n'
          'Btn: 2\n'
          'Cnt: 42\n'
          'CRC: $crc\n';

      client.push(hitEvent(press('0A'), protocol: 'Mercedes'));
      client.push(hitEvent(press('B7'), protocol: 'Mercedes'));
      client.push(hitEvent(press('3C'), protocol: 'Mercedes'));
      await settle();

      expect(controller.signals, hasLength(1));
      expect(controller.signals.single.repeats, 3);
      controller.dispose();
      await client.closeStreams();
    });

    test('a rolling counter is a different signal, not a repeat', () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);
      await controller.start();

      client.push(hitEvent('${keyFile(key: '01')}Cnt: 0001\n'));
      client.push(hitEvent('${keyFile(key: '01')}Cnt: 0002\n'));
      await settle();

      expect(controller.signals, hasLength(2));
      controller.dispose();
      await client.closeStreams();
    });

    test('the newest press is moved to the top of the list', () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);
      await controller.start();

      final first = keyFile(key: 'AAAA');
      final second = keyFile(key: 'BBBB');
      client.push(hitEvent(first));
      client.push(hitEvent(second));
      client.push(hitEvent(first));
      await settle();

      expect(controller.signals.first.fields['Key'], 'AAAA');
      expect(controller.signals.first.repeats, 2);
      controller.dispose();
      await client.closeStreams();
    });

    test('nothing is filtered until the threshold is turned on', () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);
      await controller.start();
      expect(controller.thresholdEnabled, isFalse);

      client.push(hitEvent(keyFile(key: 'FAINT'), rssi: -120));
      await settle();

      expect(controller.signals, hasLength(1));
      controller.dispose();
      await client.closeStreams();
    });

    test('the threshold only moves while it is enabled', () async {
      final controller = LiveRxController(client: _FakeClient());
      final original = controller.threshold;
      controller.setThreshold(-40);
      expect(controller.threshold, original);

      controller.thresholdEnabled = true;
      controller.setThreshold(-40);
      expect(controller.threshold, -40);
      controller.dispose();
    });

    test('an enabled threshold drops hits below it', () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);
      await controller.start();
      controller.thresholdEnabled = true;
      controller.setThreshold(-80);

      client.push(hitEvent(keyFile(key: 'FAINT'), rssi: -95));
      client.push(hitEvent(keyFile(key: 'LOUD'), rssi: -40));
      await settle();

      expect(controller.signals, hasLength(1));
      expect(controller.signals.single.fields['Key'], 'LOUD');
      controller.dispose();
      await client.closeStreams();
    });

    test('clearing empties the list and forgets the dedup keys', () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);
      await controller.start();

      final body = keyFile(key: 'CAFE');
      client.push(hitEvent(body));
      await settle();
      controller.clearSignals();
      client.push(hitEvent(body));
      await settle();

      expect(controller.signals, hasLength(1));
      expect(controller.signals.single.repeats, 1);
      controller.dispose();
      await client.closeStreams();
    });

    test(
      'a protocol with no encoder is listed but not transmittable',
      () async {
        final client = _FakeClient();
        final controller = LiveRxController(client: client);
        await controller.start();

        client.push(
          RxEvent(
            type: RxEventType.RX_EVENT_HIT,
            protocol: 'Weather',
            flipperFormat: keyFile(key: '01', protocol: 'Weather'),
            frequency: 433920000,
            rssi: -55,
            transmittable: false,
          ),
        );
        await settle();

        expect(controller.signals.single.transmittable, isFalse);
        final result = await controller.transmit(controller.signals.single);
        expect(result.error, l10n.subghzRxTransmitUnsupported);
        controller.dispose();
        await client.closeStreams();
      },
    );
  });

  group('rssi', () {
    test('samples above 127 are read back as negative dBm', () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);
      await controller.start();

      client.push(
        RxEvent(
          type: RxEventType.RX_EVENT_RSSI,
          rssiSamples: [256 - 70, 256 - 100],
          frequency: 433920000,
          noiseFloor: -98,
        ),
      );
      await settle();

      expect(controller.rssi, [-70, -100]);
      expect(controller.noiseFloor, -98);
      controller.dispose();
      await client.closeStreams();
    });

    test(
      'a batch republishes the readouts without rebuilding the page',
      () async {
        final client = _FakeClient();
        final controller = LiveRxController(client: client);
        await controller.start();

        var pageRebuilds = 0;
        var traceRepaints = 0;
        controller.addListener(() => pageRebuilds++);
        controller.live.addListener(() => traceRepaints++);

        for (var batch = 0; batch < 5; batch++) {
          client.push(
            RxEvent(
              type: RxEventType.RX_EVENT_RSSI,
              rssiSamples: [256 - 80, 256 - 82],
              frequency: 433920000,
              noiseFloor: -96,
            ),
          );
        }
        await settle();

        expect(traceRepaints, 5);
        expect(pageRebuilds, 0);
        expect(controller.live.value.latest, -82);
        expect(controller.live.value.noiseFloor, -96);
        expect(controller.live.value.tick, 5);

        controller.dispose();
        await client.closeStreams();
      },
    );

    test('hopping to another frequency does rebuild the page', () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);
      await controller.start();

      var pageRebuilds = 0;
      controller.addListener(() => pageRebuilds++);

      client.push(
        RxEvent(
          type: RxEventType.RX_EVENT_RSSI,
          rssiSamples: [256 - 80],
          frequency: 868350000,
          noiseFloor: -96,
        ),
      );
      await settle();

      expect(controller.liveFrequency, 868350000);
      expect(pageRebuilds, 1);

      controller.dispose();
      await client.closeStreams();
    });

    test(
      'the window is bounded so a long session cannot grow forever',
      () async {
        final client = _FakeClient();
        final controller = LiveRxController(client: client);
        await controller.start();

        for (var batch = 0; batch < 20; batch++) {
          client.push(
            RxEvent(
              type: RxEventType.RX_EVENT_RSSI,
              rssiSamples: List<int>.filled(64, 200),
              frequency: 433920000,
            ),
          );
        }
        await settle();

        expect(controller.rssi, hasLength(LiveRxController.rssiWindowSize));
        controller.dispose();
        await client.closeStreams();
      },
    );
  });

  test(
    'a session the firmware drops leaves the page idle and says so',
    () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);
      await controller.start();

      client.push(RxEvent(type: RxEventType.RX_EVENT_STOPPED));
      await settle();

      expect(controller.phase, LiveRxPhase.idle);
      expect(controller.errorMessage, l10n.subghzRxStoppedByDevice);
      controller.dispose();
      await client.closeStreams();
    },
  );

  test(
    'losing the link stops the session rather than freezing the trace',
    () async {
      final client = _FakeClient();
      final controller = LiveRxController(client: client);
      await controller.start();
      expect(controller.phase, LiveRxPhase.running);

      client.dropLink();
      await settle();

      expect(controller.phase, LiveRxPhase.idle);
      controller.dispose();
      await client.closeStreams();
    },
  );
}
