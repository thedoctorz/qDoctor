import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../../mifare/mifare_native.dart' show openNativeLibrary;

class PsaEngineResult {
  const PsaEngineResult._({
    required this.found,
    required this.serial,
    required this.counter,
    required this.button,
    required this.type,
    required this.crc,
    required this.seed,
  });

  const PsaEngineResult.notFound()
    : found = false,
      serial = 0,
      counter = 0,
      button = 0,
      type = 0,
      crc = 0,
      seed = 0;

  const PsaEngineResult.recovered({
    required int serial,
    required int counter,
    required int button,
    required int type,
    required int crc,
    required int seed,
  }) : this._(
         found: true,
         serial: serial,
         counter: counter,
         button: button,
         type: type,
         crc: crc,
         seed: seed,
       );

  final bool found;
  final int serial;
  final int counter;
  final int button;
  final int type;
  final int crc;
  final int seed;
}

class PsaProgress {
  const PsaProgress(this.percent, this.done);
  final int percent;
  final int done;
}

class PsaRecoverHandle {
  PsaRecoverHandle._(this._result, this._progress, this._cancel);

  final Future<PsaEngineResult> _result;
  final StreamController<PsaProgress> _progress;
  final void Function() _cancel;

  Future<PsaEngineResult> get result => _result;
  Stream<PsaProgress> get progress => _progress.stream;
  void cancel() => _cancel();
}

typedef _Native = Int32 Function(
  Pointer<Uint8> key1,
  Pointer<Uint8> key2,
  Pointer<Uint8> outButton,
  Pointer<Uint32> outSerial,
  Pointer<Uint32> outCounter,
  Pointer<Uint16> outCrc,
  Pointer<Uint32> outSeed,
  Pointer<Uint8> outType,
  Pointer<Int32> found,
  Pointer<Uint64> progressOut,
  Pointer<Int32> cancel,
);
typedef _Dart = int Function(
  Pointer<Uint8> key1,
  Pointer<Uint8> key2,
  Pointer<Uint8> outButton,
  Pointer<Uint32> outSerial,
  Pointer<Uint32> outCounter,
  Pointer<Uint16> outCrc,
  Pointer<Uint32> outSeed,
  Pointer<Uint8> outType,
  Pointer<Int32> found,
  Pointer<Uint64> progressOut,
  Pointer<Int32> cancel,
);

class DoctorPsaEngine {
  PsaRecoverHandle start({required List<int> key1, required List<int> key2}) {
    final cancel = calloc<Int32>();
    final progressCell = calloc<Uint64>();
    final progressController = StreamController<PsaProgress>.broadcast();

    var closed = false;
    var lastPacked = -1;
    final timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (closed) return;
      final packed = progressCell.value;
      if (packed == lastPacked) return;
      lastPacked = packed;
      final pct = (packed >> 56) & 0xFF;
      final done = packed & 0x00FFFFFFFFFFFFFF;
      if (!progressController.isClosed) {
        progressController.add(PsaProgress(pct, done));
      }
    });

    final payload = _Payload(
      key1: List<int>.from(key1),
      key2: List<int>.from(key2),
      cancelAddress: cancel.address,
      progressAddress: progressCell.address,
    );

    final Future<PsaEngineResult> runFuture = _spawn(payload);
    final result = runFuture.whenComplete(() {
      closed = true;
      timer.cancel();
      calloc.free(cancel);
      calloc.free(progressCell);
      if (!progressController.isClosed) progressController.close();
    });

    return PsaRecoverHandle._(result, progressController, () {
      if (closed) return;
      cancel.value = 1;
    });
  }

  static Future<void> _inflight = Future.value();

  static Future<PsaEngineResult> _spawn(_Payload p) async {
    final previous = _inflight;
    final gate = Completer<void>();
    _inflight = gate.future;
    try {
      await previous;
    } catch (_) {}
    try {
      return await Isolate.run(() => _runInIsolate(p));
    } finally {
      gate.complete();
    }
  }

  static PsaEngineResult _runInIsolate(_Payload p) {
    final library = openNativeLibrary('doctor_subghz');
    final run = library.lookupFunction<_Native, _Dart>('doctor_psa_recover');

    final cancel = Pointer<Int32>.fromAddress(p.cancelAddress);
    final progressOut = Pointer<Uint64>.fromAddress(p.progressAddress);
    final k1 = calloc<Uint8>(8);
    final k2 = calloc<Uint8>(8);
    final outButton = calloc<Uint8>();
    final outSerial = calloc<Uint32>();
    final outCounter = calloc<Uint32>();
    final outCrc = calloc<Uint16>();
    final outSeed = calloc<Uint32>();
    final outType = calloc<Uint8>();
    final found = calloc<Int32>();
    try {
      k1.asTypedList(8).setAll(0, p.key1);
      k2.asTypedList(8).setAll(0, p.key2);
      final rc = run(
        k1,
        k2,
        outButton,
        outSerial,
        outCounter,
        outCrc,
        outSeed,
        outType,
        found,
        progressOut,
        cancel,
      );
      if (rc == 1 && found.value != 0) {
        return PsaEngineResult.recovered(
          serial: outSerial.value,
          counter: outCounter.value,
          button: outButton.value,
          type: outType.value,
          crc: outCrc.value,
          seed: outSeed.value,
        );
      }
      return const PsaEngineResult.notFound();
    } finally {
      calloc.free(k1);
      calloc.free(k2);
      calloc.free(outButton);
      calloc.free(outSerial);
      calloc.free(outCounter);
      calloc.free(outCrc);
      calloc.free(outSeed);
      calloc.free(outType);
      calloc.free(found);
    }
  }
}

class _Payload {
  const _Payload({
    required this.key1,
    required this.key2,
    required this.cancelAddress,
    required this.progressAddress,
  });

  final List<int> key1;
  final List<int> key2;
  final int cancelAddress;
  final int progressAddress;
}

typedef _EncNative = Void Function(
  Uint32 serial,
  Uint8 button,
  Uint32 counter,
  Uint16 crc,
  Pointer<Uint8> outKey1,
  Pointer<Uint8> outKey2,
);
typedef _EncDart = void Function(
  int serial,
  int button,
  int counter,
  int crc,
  Pointer<Uint8> outKey1,
  Pointer<Uint8> outKey2,
);

({List<int> key1, List<int> key2}) psaEncodeMode36({
  required int serial,
  required int button,
  required int counter,
  required int crc,
}) {
  final lib = openNativeLibrary('doctor_subghz');
  final fn = lib.lookupFunction<_EncNative, _EncDart>(
    'doctor_psa_encode_mode36',
  );
  final k1 = calloc<Uint8>(8);
  final k2 = calloc<Uint8>(8);
  try {
    fn(serial, button, counter, crc, k1, k2);
    return (
      key1: List<int>.from(k1.asTypedList(8)),
      key2: List<int>.from(k2.asTypedList(8)),
    );
  } finally {
    calloc.free(k1);
    calloc.free(k2);
  }
}
