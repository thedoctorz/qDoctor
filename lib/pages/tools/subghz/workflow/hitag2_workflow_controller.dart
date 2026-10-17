import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/foundation.dart';

import '../../../archive/subghz_catalog.dart';
import '../subghz_archive_source.dart';
import 'hitag2_engine.dart';
import 'hitag2_sub.dart';
import 'writeback_target.dart';

enum Hitag2WorkflowState { input, calculating, finished }

class Hitag2CaptureRef {
  const Hitag2CaptureRef({
    required this.path,
    required this.name,
    required this.size,
    required this.signal,
  });

  final String path;
  final String name;
  final int size;
  final Hitag2Signal signal;

  int get uid => signal.uid;
  Hitag2Proto get proto => signal.proto;
}

class _KeyFile {
  const _KeyFile(this.path, this.name, this.size, {required this.localPath});
  final String path;
  final String name;
  final int size;
  final String localPath;
}

class Hitag2WorkflowController extends ChangeNotifier {
  Hitag2WorkflowController({FlipperClient? client, DoctorHitag2Engine? engine})
    : _client = client ?? FlipperOneClient().get(),
      _engine = engine ?? DoctorHitag2Engine();

  final FlipperClient _client;
  final DoctorHitag2Engine _engine;

  static const int _maxKeyFileBytes = 16 * 1024;

  Hitag2WorkflowState _state = Hitag2WorkflowState.input;
  Hitag2WorkflowState get state => _state;

  double _progress = 0;
  double get progress => _progress;

  Duration _elapsed = Duration.zero;
  Duration get elapsed => _elapsed;

  Hitag2Result? _result;
  Hitag2Result? get result => _result;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _writeBackDone = false;
  bool get writeBackDone => _writeBackDone;

  bool _writingBack = false;
  bool get writingBack => _writingBack;

  final List<String> _writtenPaths = [];
  List<String> get writtenPaths => List.unmodifiable(_writtenPaths);

  List<int>? _frame;
  String _phase = '';
  int? _seed;
  String? _method;
  double? _recoveredAtProgress;

  String uidHex = '';
  String btnHex = '2';
  String hopHex = '';
  String cntHex = '';
  String hop2Hex = '';
  String cnt2Hex = '';
  String btn2Hex = '';

  Hitag2Proto? _loadedProto;
  Hitag2Proto? get loadedProto => _loadedProto;

  static const String _sampleSource = 'sample';
  static const String _localPrefix = 'local:';
  final List<String> _sourcePaths = [];
  final Map<String, String> _sourceContent = {};
  final Map<String, String> _localFileNames = {};
  int? _loadedUid;

  final List<Hitag2CaptureRef> _captures = [];
  final List<String> selectedPaths = [];
  bool _listing = false;
  bool get listing => _listing;
  int _listDone = 0;
  int get listDone => _listDone;
  int _listTotal = 0;
  int get listTotal => _listTotal;
  double get listProgress => _listTotal == 0 ? 0 : _listDone / _listTotal;

  final Map<String, Hitag2CaptureRef> _hits = {};
  final Set<String> _misses = {};
  final Map<String, String> _localByRemote = {};

  Hitag2RecoverHandle? _handle;
  StreamSubscription<Hitag2Progress>? _progressSub;
  Timer? _ticker;
  DateTime? _startedAt;
  bool _disposed = false;

  bool get isCalculating => _state == Hitag2WorkflowState.calculating;
  bool get hasResult =>
      _state == Hitag2WorkflowState.finished &&
      (_result?.found == true || _seed != null);
  bool get notFound => _state == Hitag2WorkflowState.finished && !hasResult;
  bool get isConnected => _client.isConnected;

  bool get gpuAccelerated =>
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isAndroid ||
      Platform.isWindows;

  bool get canStart => _makeRequest() != null;

  bool get canWriteBack =>
      hasResult && _sourcePaths.any((p) => p != _sampleSource);

  List<Hitag2CaptureRef> get listedCaptures {
    if (selectedPaths.isEmpty) return List.unmodifiable(_captures);
    Hitag2CaptureRef? first;
    for (final c in _captures) {
      if (c.path == selectedPaths.first) {
        first = c;
        break;
      }
    }
    if (first == null) return List.unmodifiable(_captures);
    final uid = first.uid;
    return _captures.where((c) => c.uid == uid).toList(growable: false);
  }

  String? get recoveredKeyHex {
    final key = _result?.key;
    if (key == null) return null;
    return List<int>.generate(
      6,
      (i) => (key >> (8 * (5 - i))) & 0xFF,
    ).map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');
  }

  String? get recoveredSeedHex =>
      _seed?.toRadixString(16).toUpperCase().padLeft(8, '0');

  String get phaseLabel =>
      _phase == 'bcm' ? 'Trying Bruteforce…' : 'Recovering Key…';
  bool get isBcmPhase => _phase == 'bcm';

  String? get methodLabel => _method;

  String? get recoveredAtPercentLabel {
    final p = _recoveredAtProgress;
    return p == null ? null : (p * 100).round().toString();
  }

  String get elapsedLabel => _fmt(_elapsed);

  String? get etaLabel {
    if (_state != Hitag2WorkflowState.calculating) return null;
    if (_progress < 0.03 || _progress >= 1 || _elapsed.inMilliseconds <= 0) {
      return null;
    }
    final remainingMs = _elapsed.inMilliseconds * (1 - _progress) / _progress;
    return _fmt(Duration(milliseconds: remainingMs.round()));
  }

  static String _fmt(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '${s}s';
    return '${s ~/ 60}m ${(s % 60).toString().padLeft(2, '0')}s';
  }

  void loadSampleVector() {
    _clearLoaded();
    uidHex = '13E9EC28';
    hopHex = '7AFCC042';
    cntHex = '231';
    btnHex = '2';
    hop2Hex = '7AB0EC32';
    cnt2Hex = '232';
    btn2Hex = '2';
    _resetRun();
    _state = Hitag2WorkflowState.input;
    notifyListeners();
  }

  void loadBcmSampleVector() {
    const sample =
        'Protocol: Renault V1\n'
        'Key: CA 61 54 2A 13 3B FC DB\n'
        'Key_2: 50 02 88\n';
    final signal = Hitag2Sub.parse(sample);
    if (signal == null) return;
    _clearLoaded();
    _applySignal(signal, second: null);
    _loadedProto = signal.proto;
    _loadedUid = signal.uid;
    _sourcePaths.add(_sampleSource);
    _sourceContent[_sampleSource] = sample;
    _resetRun();
    _state = Hitag2WorkflowState.input;
    notifyListeners();
  }

  void manualEdited() {
    final loaded = _loadedUid;
    if (loaded != null && _hex32(uidHex) != loaded) _clearLoaded();
    notifyListeners();
  }

  void toggleSelected(String path) {
    if (selectedPaths.contains(path)) {
      selectedPaths.remove(path);
    } else if (selectedPaths.length < 2) {
      selectedPaths.add(path);
    }
    notifyListeners();
  }

  void clearSelection() {
    selectedPaths.clear();
    notifyListeners();
  }

  Future<void> refreshCaptures({bool forceReload = false}) async {
    if (_listing) return;
    _listing = true;
    _errorMessage = null;
    _captures.clear();
    _listDone = 0;
    _listTotal = 0;
    if (forceReload) {
      _hits.clear();
      _misses.clear();
    }
    notifyListeners();
    try {
      if (!SubghzArchiveSource.available) {
        _errorMessage = subghzArchiveSyncHint;
        return;
      }
      await SubghzArchiveSource.showLocalsThenGaps(
        force: forceReload,
        pullMaxBytes: _maxKeyFileBytes,
        consume: _syncCaptures,
      );
      if (_captures.isEmpty &&
          _errorMessage == null &&
          !SubghzArchiveSource.connected &&
          SubghzArchiveSource.view.local.isEmpty) {
        _errorMessage = subghzArchiveSyncHint;
      }
    } catch (e) {
      _errorMessage = 'Listing failed: $e';
    } finally {
      _listing = false;
      notifyListeners();
    }
  }

  List<_KeyFile> _candidateFiles(SubghzSyncView view) {
    final skip = {for (final gap in view.gaps) gap.remotePath};
    final out = <_KeyFile>[];
    for (final file in view.local) {
      if (file.size <= 0 || file.size > _maxKeyFileBytes) continue;
      if (skip.contains(file.remotePath)) continue;
      out.add(
        _KeyFile(
          file.remotePath,
          file.name,
          file.size,
          localPath: file.localPath,
        ),
      );
    }
    out.sort((a, b) {
      int pri(String n) {
        final l = n.toLowerCase();
        return (l.contains('fiat') || l.contains('renault')) ? 0 : 1;
      }

      final pa = pri(a.name), pb = pri(b.name);
      return pa != pb ? pa.compareTo(pb) : a.name.compareTo(b.name);
    });
    return out;
  }

  Future<void> _syncCaptures(SubghzSyncView view) async {
    final files = _candidateFiles(view);
    final wanted = {for (final f in files) '${f.path}|${f.size}'};
    _captures.removeWhere((c) => !wanted.contains('${c.path}|${c.size}'));
    selectedPaths.removeWhere((p) => !files.any((f) => f.path == p));
    final pending = <_KeyFile>[];
    for (final f in files) {
      _localByRemote[f.path] = f.localPath;
      final key = '${f.path}|${f.size}';
      final cached = _hits[key];
      if (cached != null) {
        if (!_captures.any(
          (c) => c.path == cached.path && c.size == cached.size,
        )) {
          _captures.add(cached);
        }
        continue;
      }
      if (_misses.contains(key)) continue;
      pending.add(f);
    }
    _listTotal = files.length;
    _listDone = files.length - pending.length;
    _captures.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
    for (final f in pending) {
      final key = '${f.path}|${f.size}';
      final ref = await _parseCandidate(f);
      if (ref != null) {
        _hits[key] = ref;
        _captures.add(ref);
      } else {
        _misses.add(key);
      }
      _captures.sort((a, b) => a.name.compareTo(b.name));
      _listDone++;
      notifyListeners();
    }
  }

  Future<Hitag2CaptureRef?> _parseCandidate(_KeyFile f) async {
    try {
      final bytes = await File(f.localPath).readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      final signal = Hitag2Sub.parse(content);
      if (signal == null) return null;
      if (Hitag2Sub.isReadyToTransmit(content)) return null;
      return Hitag2CaptureRef(
        path: f.path,
        name: f.name,
        size: f.size,
        signal: signal,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> loadSelected() async {
    if (selectedPaths.isEmpty) return;
    _errorMessage = null;
    final firstPath = selectedPaths.first;
    final secondPath = selectedPaths.length > 1 ? selectedPaths[1] : null;
    try {
      final c1 = await _readContent(firstPath);
      final s1 = Hitag2Sub.parse(c1);
      if (s1 == null) {
        _errorMessage = 'First capture is not a Hitag2 file.';
        notifyListeners();
        return;
      }
      _clearLoaded();
      _sourcePaths.add(firstPath);
      _sourceContent[firstPath] = c1;

      Hitag2Signal? s2;
      if (secondPath != null) {
        final c2 = await _readContent(secondPath);
        s2 = Hitag2Sub.parse(c2);
        if (s2 == null) {
          _errorMessage = 'Second capture is not a Hitag2 file.';
          notifyListeners();
          return;
        }
        if (s2.proto != s1.proto) {
          _errorMessage =
              'Pick two captures of the same protocol (${s1.proto.wireName}).';
          notifyListeners();
          return;
        }
        if (s2.uid != s1.uid) {
          _errorMessage = 'The two captures have different UIDs.';
          notifyListeners();
          return;
        }
        _sourcePaths.add(secondPath);
        _sourceContent[secondPath] = c2;
      }
      _applySignal(s1, second: s2);
      _loadedProto = s1.proto;
      _loadedUid = s1.uid;
      _resetRun();
      _state = Hitag2WorkflowState.input;
    } catch (e) {
      _errorMessage = 'Read failed: $e';
    }
    notifyListeners();
  }

  Future<String> _readContent(String path) async {
    final local = _localByRemote[path];
    if (local != null) {
      return File(local).readAsString();
    }
    final bytes = await _client.storageReadChunked(path);
    return utf8.decode(bytes, allowMalformed: true);
  }

  bool applyLocalCapture(String content, {String fileName = 'recovered.sub'}) {
    final signal = Hitag2Sub.parse(content);
    if (signal == null) {
      _errorMessage = 'Not a Hitag2 file.';
      notifyListeners();
      return false;
    }
    if (hopHex.trim().isEmpty) {
      _clearLoaded();
      _applySignal(signal);
      _loadedProto = signal.proto;
      _loadedUid = signal.uid;
      _addLocalSource(fileName, content);
      _errorMessage = null;
      _resetRun();
      _state = Hitag2WorkflowState.input;
      notifyListeners();
      return true;
    }
    if (hop2Hex.trim().isNotEmpty) {
      _errorMessage = 'Both captures are already filled.';
      notifyListeners();
      return false;
    }
    if (_loadedProto != null && signal.proto != _loadedProto) {
      _errorMessage =
          'Pick two captures of the same protocol (${_loadedProto!.wireName}).';
      notifyListeners();
      return false;
    }
    final uid = _hex32(uidHex);
    if (uid != null && signal.uid != uid) {
      _errorMessage = 'The two captures have different UIDs.';
      notifyListeners();
      return false;
    }
    hop2Hex = signal.hop.toRadixString(16).toUpperCase();
    cnt2Hex = signal.cnt.toRadixString(16).toUpperCase();
    btn2Hex = signal.btn.toRadixString(16).toUpperCase();
    _loadedProto ??= signal.proto;
    _loadedUid ??= signal.uid;
    if (uidHex.trim().isEmpty) {
      uidHex = signal.uid.toRadixString(16).toUpperCase();
    }
    _addLocalSource(fileName, content);
    _errorMessage = null;
    _resetRun();
    notifyListeners();
    return true;
  }

  void _addLocalSource(String fileName, String content) {
    final key = '$_localPrefix${_localFileNames.length}';
    _localFileNames[key] = fileName;
    _sourcePaths.add(key);
    _sourceContent[key] = content;
  }

  void _applySignal(Hitag2Signal s, {Hitag2Signal? second}) {
    _frame = s.frame;
    uidHex = s.uid.toRadixString(16).toUpperCase();
    btnHex = s.btn.toRadixString(16).toUpperCase();
    hopHex = s.hop.toRadixString(16).toUpperCase();
    cntHex = s.cnt.toRadixString(16).toUpperCase();
    if (second != null) {
      hop2Hex = second.hop.toRadixString(16).toUpperCase();
      cnt2Hex = second.cnt.toRadixString(16).toUpperCase();
      btn2Hex = second.btn.toRadixString(16).toUpperCase();
    } else {
      hop2Hex = '';
      cnt2Hex = '';
      btn2Hex = '';
    }
  }

  Hitag2Request? _makeRequest() {
    final uid = _hex32(uidHex);
    final hop = _hex32(hopHex);
    final cnt = _hex32(cntHex);
    if (uid == null || hop == null || cnt == null) return null;
    final btn = _hex8(btnHex) ?? 2;
    final hop2 = _hex32(hop2Hex);
    final cnt2 = _hex32(cnt2Hex);
    final hasSecond = hop2 != null && cnt2 != null;
    return Hitag2Request(
      uid: uid,
      hop: hop,
      cnt: cnt,
      btn: btn,
      hop2: hop2 ?? 0,
      cnt2: cnt2 ?? 0,
      btn2: _hex8(btn2Hex) ?? btn,
      hasSecond: hasSecond,
    );
  }

  Future<void> start() async {
    final req = _makeRequest();
    if (req == null) {
      _errorMessage = 'Enter UID, Hop and Counter (hex).';
      notifyListeners();
      return;
    }
    unawaited(_progressSub?.cancel());
    _handle?.cancel();

    _resetRun();
    _state = Hitag2WorkflowState.calculating;
    _startedAt = DateTime.now();
    _startTicker();

    final frame = _frame;
    if (frame != null &&
        frame.length == 11 &&
        _loadedProto == Hitag2Proto.renaultV1) {
      _phase = 'bcm';
      notifyListeners();
      final seed = await hitag2BcmRecover(frame);
      if (_disposed || _state != Hitag2WorkflowState.calculating) return;
      if (seed != null) {
        _seed = seed;
        _method = 'BCM Bruteforce';
        _syncElapsed();
        _stopTicker();
        _state = Hitag2WorkflowState.finished;
        notifyListeners();
        if (canWriteBack &&
            _client.isConnected &&
            !_sourcePaths.any((p) => p.startsWith(_localPrefix))) {
          unawaited(writeBack());
        }
        return;
      }
    }

    _phase = 'hell';
    notifyListeners();
    final handle = _engine.start(request: req);
    _handle = handle;
    _progressSub = handle.progress.listen((p) {
      if (_disposed) return;
      _progress = p.percent.clamp(0, 100) / 100.0;
      notifyListeners();
    });
    unawaited(
      handle.result.then(
        (res) {
          if (_disposed) return;
          if (_state != Hitag2WorkflowState.calculating) return;
          _result = res;
          if (res.found) {
            _method = 'Hitag2Hell';
            _recoveredAtProgress = _progress;
          }
          _syncElapsed();
          _stopTicker();
          _state = Hitag2WorkflowState.finished;
          notifyListeners();
        },
        onError: (Object e, StackTrace _) {
          if (_disposed) return;
          _stopTicker();
          _errorMessage = e.toString();
          _state = Hitag2WorkflowState.finished;
          notifyListeners();
        },
      ),
    );
  }

  void cancel() {
    _handle?.cancel();
    _stopTicker();
    if (_state == Hitag2WorkflowState.calculating) {
      _state = Hitag2WorkflowState.finished;
      notifyListeners();
    }
  }

  void reset() {
    _handle?.cancel();
    _handle = null;
    _stopTicker();
    _resetRun();
    _state = Hitag2WorkflowState.input;
    notifyListeners();
  }

  Future<void> writeBack() async {
    final key = _result?.key;
    final seed = _seed;
    if ((key == null && seed == null) || !canWriteBack || _writingBack) return;
    if (!_client.isConnected) {
      _errorMessage = 'Connect the Flipper to write the result back.';
      notifyListeners();
      return;
    }
    _errorMessage = null;
    _writingBack = true;
    notifyListeners();
    try {
      for (var i = 0; i < _sourcePaths.length; i++) {
        final source = _sourcePaths[i];
        if (source == _sampleSource) continue;
        final content = _sourceContent[source] ?? await _readContent(source);
        final path = source.startsWith(_localPrefix)
            ? await resolveLocalWriteBackPath(
                _client,
                fileName: _localFileNames[source] ?? 'recovered.sub',
                content: content,
              )
            : source;
        final patched = seed != null
            ? Hitag2Sub.patchingBcmSeed(content, seed)
            : Hitag2Sub.patchingHitag2Key(content, key!);
        final bytes = utf8.encode(patched);
        await _client.storageWriteChunked(path, bytes);
        await SubghzArchiveSource.mirror(path, bytes);
        if (path != source) {
          _sourcePaths[i] = path;
          _sourceContent.remove(source);
          _localFileNames.remove(source);
        }
        _sourceContent[path] = patched;
        if (!_writtenPaths.contains(path)) _writtenPaths.add(path);
        _captures.removeWhere((c) => c.path == path);
        _hits.removeWhere((k, _) => k.startsWith('$path|'));
      }
      _writeBackDone = true;
    } catch (e) {
      _errorMessage = 'Write-back failed: $e';
    } finally {
      _writingBack = false;
    }
    notifyListeners();
  }

  void _clearLoaded() {
    _loadedProto = null;
    _loadedUid = null;
    _frame = null;
    _sourcePaths.clear();
    _sourceContent.clear();
    _localFileNames.clear();
  }

  void _resetRun() {
    _result = null;
    _errorMessage = null;
    _writeBackDone = false;
    _writtenPaths.clear();
    _seed = null;
    _method = null;
    _recoveredAtProgress = null;
    _phase = '';
    _progress = 0;
    _elapsed = Duration.zero;
    _startedAt = null;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _syncElapsed();
      notifyListeners();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _syncElapsed() {
    final started = _startedAt;
    if (started != null) _elapsed = DateTime.now().difference(started);
  }

  static int? _hex32(String text) {
    var v = text.trim();
    if (v.startsWith('0x') || v.startsWith('0X')) v = v.substring(2);
    if (v.isEmpty) return null;
    return int.tryParse(v, radix: 16);
  }

  static int? _hex8(String text) {
    final v = _hex32(text);
    return v == null ? null : v & 0xFF;
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _handle?.cancel();
    _progressSub?.cancel();
    _stopTicker();
    super.dispose();
  }
}
