import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:flutter_test/flutter_test.dart';
import 'package:doctormobile/pages/tools/subghz/decode_raw/decode_raw_controller.dart';
import 'package:doctormobile/services/localization/l10n.dart';

class _FakeClient implements FlipperClient {
  _FakeClient({
    required this.subghzRpcLevel,
    this.answerDecodeRaw,
    this.fileContent,
    this.decodeFrames = const [],
  });

  final int? subghzRpcLevel;

  final Object? answerDecodeRaw;

  final String? fileContent;

  final List<Main> decodeFrames;

  final List<String> sent = [];
  final _connection = StreamController<FlipperConnectionState>.broadcast();
  late Map<String, String> _info = {
    'hardware.name': 'Flipper',
    if (subghzRpcLevel != null) 'doctor_rpc_subghz': '$subghzRpcLevel',
  };

  bool get sentDecodeRaw => sent.contains('subghzDecodeRawRequest');

  @override
  bool get isConnected => true;

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

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
    final frames = await callRpcFrames(
      request,
      timeout: timeout,
      priority: priority,
      onFrame: onFrame,
    );
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
    if (request.hasSubghzDecodeRawRequest()) {
      if (answerDecodeRaw != null) throw answerDecodeRaw!;
      for (final frame in decodeFrames) {
        onFrame?.call(frame);
      }
      return decodeFrames;
    }
    final body = fileContent;
    if (body == null) return const [];
    if (request.hasStorageStatRequest()) {
      return [
        Main(
          storageStatResponse: StatResponse(
            file: File(size: body.codeUnits.length),
          ),
        ),
      ];
    }
    if (request.hasStorageReadRequest()) {
      final frame = Main(
        storageReadResponse: ReadResponse(file: File(data: body.codeUnits)),
      );
      onFrame?.call(frame);
      return [frame];
    }
    return const [];
  }

  Future<void> closeStreams() => _connection.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('firmware without the Sub-GHz RPC is never sent a DecodeRaw', () async {
    final client = _FakeClient(subghzRpcLevel: null);
    final controller = DecodeRawController(client: client);

    await controller.decodeRemote('/ext/subghz/capture.sub');

    expect(client.sentDecodeRaw, isFalse);
    expect(controller.phase, DecodeRawPhase.idle);
    expect(controller.errorMessage, l10n.decodeRawNotImplemented);
    controller.dispose();
    await client.closeStreams();
  });

  test('a newer Sub-GHz RPC revision is still supported', () async {
    final client = _FakeClient(subghzRpcLevel: 9);
    final controller = DecodeRawController(client: client);

    await controller.decodeRemote('/ext/subghz/capture.sub');

    expect(client.sentDecodeRaw, isTrue);
    controller.dispose();
    await client.closeStreams();
  });

  test('firmware reporting the current revision is sent the tag', () async {
    final client = _FakeClient(subghzRpcLevel: 3);
    final controller = DecodeRawController(client: client);

    await controller.decodeRemote('/ext/subghz/capture.sub');

    expect(client.sentDecodeRaw, isTrue);
    controller.dispose();
    await client.closeStreams();
  });

  test(
    'supported firmware that answers NOT_IMPLEMENTED shows update copy',
    () async {
      final client = _FakeClient(
        subghzRpcLevel: 3,
        answerDecodeRaw: FlipperRpcNotImplementedException(
          Main(commandStatus: CommandStatus.ERROR_NOT_IMPLEMENTED),
        ),
      );
      final controller = DecodeRawController(client: client);

      await controller.decodeRemote('/ext/subghz/capture.sub');

      expect(client.sentDecodeRaw, isTrue);
      expect(controller.phase, DecodeRawPhase.idle);
      expect(controller.hits, isEmpty);
      expect(controller.errorMessage, l10n.decodeRawNotImplemented);
      controller.dispose();
      await client.closeStreams();
    },
  );

  group('capture preview', () {
    final pulses = <int>[
      for (var i = 0; i < 700; i++) ...[350, -350],
      -4000000,
    ];
    final file = StringBuffer()
      ..writeln('Filetype: Flipper SubGhz RAW File')
      ..writeln('Version: 1')
      ..writeln('Frequency: 433920000')
      ..writeln('Preset: FuriHalSubGhzPresetOok650Async')
      ..writeln('Protocol: RAW')
      ..writeln('RAW_Data: ${pulses.join(' ')}');

    test(
      'the whole capture is drawn before a single decode frame arrives',
      () async {
        final client = _FakeClient(
          subghzRpcLevel: 3,
          fileContent: file.toString(),
        );
        final controller = DecodeRawController(client: client);

        await controller.decodeRemote('/ext/subghz/capture.sub');

        expect(controller.capture.isEmpty, isFalse);
        expect(controller.capture.pulseCount, pulses.length);
        expect(controller.envelope.length, greaterThan(100));
        expect(controller.preparing, isFalse);

        final burst = controller.envelope.take(40);
        final silence = controller.envelope.skip(200);
        expect(burst.reduce((a, b) => a > b ? a : b), greaterThan(0.6));
        expect(silence.reduce((a, b) => a > b ? a : b), lessThan(0.2));

        controller.dispose();
        await client.closeStreams();
      },
    );

    test('the playhead follows time, not bytes', () async {
      final client = _FakeClient(
        subghzRpcLevel: 3,
        fileContent: file.toString(),
        decodeFrames: [
          Main(subghzDecodeRawResponse: DecodeRawResponse(percent: 50)),
        ],
      );
      final controller = DecodeRawController(client: client);

      await controller.decodeRemote('/ext/subghz/capture.sub');

      expect(controller.progress, 1.0);
      expect(controller.capture.timeAt(0.5), lessThan(0.25));

      controller.dispose();
      await client.closeStreams();
    });

    test('a capture that cannot be fetched still decodes', () async {
      final client = _FakeClient(subghzRpcLevel: 3);
      final controller = DecodeRawController(client: client);

      await controller.decodeRemote('/ext/subghz/capture.sub');

      expect(client.sentDecodeRaw, isTrue);
      expect(controller.capture.isEmpty, isTrue);
      expect(controller.phase, DecodeRawPhase.results);
      expect(controller.errorMessage, isNull);

      controller.dispose();
      await client.closeStreams();
    });
  });

  test('a cancelled decode keeps its hits and is not an error', () async {
    final client = _FakeClient(
      subghzRpcLevel: 3,
      answerDecodeRaw: FlipperRpcContinuousCommandInterruptedException(
        Main(commandStatus: CommandStatus.ERROR_CONTINUOUS_COMMAND_INTERRUPTED),
      ),
    );
    final controller = DecodeRawController(client: client);

    await controller.decodeRemote('/ext/subghz/capture.sub');

    expect(controller.phase, DecodeRawPhase.results);
    expect(controller.cancelled, isTrue);
    expect(controller.errorMessage, isNull);
    controller.dispose();
    await client.closeStreams();
  });
}
