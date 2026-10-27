import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter_test/flutter_test.dart';
import 'package:doctormobile/pages/tools/subghz/workflow/hitag2_engine.dart';
import 'package:doctormobile/pages/tools/subghz/workflow/hitag2_workflow_controller.dart';

class _OfflineClient implements FlipperClient {
  @override
  bool get isConnected => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEngine extends DoctorHitag2Engine {
  _FakeEngine({Hitag2Result? completeWith}) : _completeWith = completeWith;

  final Hitag2Result? _completeWith;
  final result = Completer<Hitag2Result>();
  final progress = StreamController<Hitag2Progress>.broadcast();
  int cancels = 0;

  @override
  Hitag2RecoverHandle start({required Hitag2Request request}) {
    final pending = _completeWith;
    if (pending != null) {
      result.complete(pending);
    }
    return Hitag2RecoverHandle.forTest(
      result: result.future,
      progress: progress.stream,
      cancel: () => cancels++,
    );
  }
}

Hitag2WorkflowController _controller(
  _FakeEngine engine, {
  Duration? stallTimeout,
}) {
  final c =
      Hitag2WorkflowController(
          client: _OfflineClient(),
          engine: engine,
          stallTimeout: stallTimeout,
        )
        ..uidHex = '12345678'
        ..hopHex = 'ABCDEF01'
        ..cntHex = '1';
  return c;
}

void main() {
  group('Hitag2Diag.describe', () {
    test('a working GPU that finds a key reads as GPU, found', () {
      final diag = Hitag2Diag.gpuInitOk | Hitag2Diag.found;
      expect(Hitag2Diag.describe(diag), 'GPU, found');
    });

    test('the Android stall case reads as GPU stalled, CPU, found', () {
      final diag =
          Hitag2Diag.gpuInitOk | Hitag2Diag.gpuFault | Hitag2Diag.found;
      expect(Hitag2Diag.describe(diag), 'GPU stalled→CPU, found');
    });

    test('no usable GPU reads as CPU', () {
      expect(
        Hitag2Diag.describe(Hitag2Diag.cpuFallback | Hitag2Diag.found),
        'CPU, found',
      );
    });
  });

  test('a finished run surfaces the engine diag label', () async {
    final engine = _FakeEngine(
      completeWith: Hitag2Result.found(
        0x1122334455,
        diag: Hitag2Diag.gpuInitOk | Hitag2Diag.gpuFault | Hitag2Diag.found,
      ),
    );
    final controller = _controller(engine);
    addTearDown(controller.dispose);

    await controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, Hitag2WorkflowState.finished);
    expect(controller.result?.key, 0x1122334455);
    expect(controller.diagLabel, 'GPU stalled→CPU, found');
    expect(controller.errorMessage, isNull);
  });

  test('a run that never progresses trips the stall watchdog', () async {
    final engine = _FakeEngine(); // result never completes, no progress
    final controller = _controller(
      engine,
      stallTimeout: const Duration(milliseconds: 300),
    );
    addTearDown(controller.dispose);

    await controller.start();
    expect(controller.state, Hitag2WorkflowState.calculating);

    await Future<void>.delayed(const Duration(milliseconds: 900));

    expect(
      controller.state,
      Hitag2WorkflowState.finished,
      reason: 'the watchdog must end a wedged run',
    );
    expect(controller.errorMessage, contains('stalled'));
    expect(engine.cancels, greaterThan(0), reason: 'it must cancel the run');
  });

  test('progress keeps the watchdog from tripping', () async {
    final engine = _FakeEngine();
    final controller = _controller(
      engine,
      stallTimeout: const Duration(milliseconds: 300),
    );
    addTearDown(controller.dispose);

    await controller.start();

    for (var i = 1; i <= 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      engine.progress.add(Hitag2Progress(i * 10, i));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      controller.state,
      Hitag2WorkflowState.calculating,
      reason: 'a run that is making progress must not be killed',
    );
    expect(engine.cancels, 0);

    engine.result.complete(
      Hitag2Result.found(0x42, diag: Hitag2Diag.gpuInitOk | Hitag2Diag.found),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, Hitag2WorkflowState.finished);
    expect(controller.result?.key, 0x42);
  });
}
