import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../../mifare/mifare_native.dart' show openNativeLibrary;

class Hitag2Request {
  const Hitag2Request({
    required this.uid,
    required this.hop,
    required this.cnt,
    this.btn = 2,
    this.hop2 = 0,
    this.cnt2 = 0,
    this.btn2 = 0,
    this.hasSecond = false,
  });

  final int uid;
  final int hop;
  final int cnt;
  final int btn;
  final int hop2;
  final int cnt2;
  final int btn2;
  final bool hasSecond;
}

class Hitag2Result {
  const Hitag2Result.found(int this.key);
  const Hitag2Result.notFound() : key = null;

  final int? key;

  bool get found => key != null;
}

class Hitag2Progress {
  const Hitag2Progress(this.percent, this.done);
  final int percent;
  final int done;
}

class Hitag2RecoverHandle {
  Hitag2RecoverHandle._(this._result, this._progress, this._cancel);

  final Future<Hitag2Result> _result;
  final StreamController<Hitag2Progress> _progress;
  final void Function() _cancel;

  Future<Hitag2Result> get result => _result;
  Stream<Hitag2Progress> get progress => _progress.stream;
  void cancel() => _cancel();
}

typedef _Native = Int32 Function(
  Uint32 hop,
  Uint32 uid,
  Uint32 cnt,
  Uint8 btn,
  Uint32 hop2,
  Uint32 cnt2,
  Uint8 btn2,
  Int32 hasSecond,
  Pointer<Uint64> outKey,
  Pointer<Int32> found,
  Pointer<Uint64> progressOut,
  Pointer<Int32> cancel,
);
typedef _Dart = int Function(
  int hop,
  int uid,
  int cnt,
  int btn,
  int hop2,
  int cnt2,
  int btn2,
  int hasSecond,
  Pointer<Uint64> outKey,
  Pointer<Int32> found,
  Pointer<Uint64> progressOut,
  Pointer<Int32> cancel,
);

class DoctorHitag2Engine {
  Hitag2RecoverHandle start({required Hitag2Request request}) {
    final cancel = calloc<Int32>();
    final progressCell = calloc<Uint64>();
    final progressController = StreamController<Hitag2Progress>.broadcast();

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
        progressController.add(Hitag2Progress(pct, done));
      }
    });

    final payload = _Payload(
      hop: request.hop,
      uid: request.uid,
      cnt: request.cnt,
      btn: request.btn,
      hop2: request.hop2,
      cnt2: request.cnt2,
      btn2: request.btn2,
      hasSecond: request.hasSecond ? 1 : 0,
      cancelAddress: cancel.address,
      progressAddress: progressCell.address,
    );

    final Future<Hitag2Result> runFuture = _spawn(payload);
    final result = runFuture.whenComplete(() {
      closed = true;
      timer.cancel();
      calloc.free(cancel);
      calloc.free(progressCell);
      if (!progressController.isClosed) progressController.close();
    });

    return Hitag2RecoverHandle._(result, progressController, () {
      if (closed) return;
      cancel.value = 1;
    });
  }

  static Future<void> _inflight = Future.value();

  static Future<Hitag2Result> _spawn(_Payload p) async {
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

  static Hitag2Result _runInIsolate(_Payload p) {
    final library = openNativeLibrary('doctor_subghz');
    final run = library.lookupFunction<_Native, _Dart>(
      'doctor_hitag2hell_recover',
    );

    final cancel = Pointer<Int32>.fromAddress(p.cancelAddress);
    final progressOut = Pointer<Uint64>.fromAddress(p.progressAddress);
    final outKey = calloc<Uint64>();
    final found = calloc<Int32>();
    try {
      final rc = run(
        p.hop,
        p.uid,
        p.cnt,
        p.btn,
        p.hop2,
        p.cnt2,
        p.btn2,
        p.hasSecond,
        outKey,
        found,
        progressOut,
        cancel,
      );
      if (rc == 1 && found.value != 0) {
        return Hitag2Result.found(outKey.value);
      }
      return const Hitag2Result.notFound();
    } finally {
      calloc.free(outKey);
      calloc.free(found);
    }
  }
}

class _Payload {
  const _Payload({
    required this.hop,
    required this.uid,
    required this.cnt,
    required this.btn,
    required this.hop2,
    required this.cnt2,
    required this.btn2,
    required this.hasSecond,
    required this.cancelAddress,
    required this.progressAddress,
  });

  final int hop;
  final int uid;
  final int cnt;
  final int btn;
  final int hop2;
  final int cnt2;
  final int btn2;
  final int hasSecond;
  final int cancelAddress;
  final int progressAddress;
}

typedef _BcmNative = Int32 Function(
  Pointer<Uint8> frame,
  Pointer<Uint32> outSeed,
  Pointer<Int32> found,
);
typedef _BcmDart = int Function(
  Pointer<Uint8> frame,
  Pointer<Uint32> outSeed,
  Pointer<Int32> found,
);

Future<int?> hitag2BcmRecover(List<int> frame) =>
    Isolate.run(() => _hitag2Bcm(frame));

int? _hitag2Bcm(List<int> frame) {
  final lib = openNativeLibrary('doctor_subghz');
  final fn = lib.lookupFunction<_BcmNative, _BcmDart>(
    'doctor_hitag2_bcm_recover',
  );
  final f = calloc<Uint8>(11);
  final seed = calloc<Uint32>();
  final found = calloc<Int32>();
  try {
    final src = frame.length >= 11
        ? frame.sublist(0, 11)
        : [...frame, ...List<int>.filled(11 - frame.length, 0)];
    f.asTypedList(11).setAll(0, src);
    final rc = fn(f, seed, found);
    return (rc == 1 && found.value != 0) ? seed.value : null;
  } finally {
    calloc.free(f);
    calloc.free(seed);
    calloc.free(found);
  }
}
