import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/foundation.dart';

import '../../../archive/subghz_catalog.dart';
import '../subghz_archive_source.dart';
import 'doctor_psa_engine.dart';
import 'psa_sub.dart';
import 'writeback_target.dart';

enum PsaWorkflowState { input, calculating, finished }

class PsaCaptureRef {
  const PsaCaptureRef({
    required this.path,
    required this.name,
    required this.size,
    required this.signal,
  });

  final String path;
  final String name;
  final int size;
  final PsaSignal signal;

  String get keyHint => signal.key1
      .take(3)
      .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
      .join();
}

class _KeyFile {
  const _KeyFile(this.path, this.name, this.size, {required this.localPath});
  final String path;
  final String name;
  final int size;
  final String localPath;
}

class PsaWorkflowController extends ChangeNotifier {
  PsaWorkflowController({FlipperClient? client, DoctorPsaEngine? engine})
    : _client = client ?? FlipperOneClient().get(),
      _engine = engine ?? DoctorPsaEngine();

  final FlipperClient _client;
  final DoctorPsaEngine _engine;

  static const int _maxKeyFileBytes = 16 * 1024;

  PsaWorkflowState _state = PsaWorkflowState.input;
  PsaWorkflowState get state => _state;

  double _progress = 0;
  double get progress => _progress;

  Duration _elapsed = Duration.zero;
  Duration get elapsed => _elapsed;

  PsaRecovered? _recovered;
  PsaRecovered? get recovered => _recovered;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _writeBackDone = false;
  bool get writeBackDone => _writeBackDone;

  bool _writingBack = false;
  bool get writingBack => _writingBack;

  String? _writtenPath;
  String? get writtenPath => _writtenPath;

  String key1Hex = '';
  String key2Hex = '';

  String? _loadedContent;
  String? _sourcePath;
  String? _localFileName;
  bool _loaded = false;
  bool get hasLoadedCapture => _loaded;

  final List<PsaCaptureRef> _captures = [];
  String? selectedPath;
  bool _listing = false;
  bool get listing => _listing;
  int _listDone = 0;
  int get listDone => _listDone;
  int _listTotal = 0;
  int get listTotal => _listTotal;
  double get listProgress => _listTotal == 0 ? 0 : _listDone / _listTotal;

  List<PsaCaptureRef> get captures => List.unmodifiable(_captures);

  final Map<String, PsaCaptureRef> _hits = {};
  final Set<String> _misses = {};
  final Map<String, String> _localByRemote = {};

  PsaRecoverHandle? _handle;
  StreamSubscription<PsaProgress>? _progressSub;
  Timer? _ticker;
  DateTime? _startedAt;
  bool _disposed = false;

  bool get isCalculating => _state == PsaWorkflowState.calculating;
  bool get hasResult =>
      _state == PsaWorkflowState.finished && _recovered != null;
  bool get notFound =>
      _state == PsaWorkflowState.finished && _recovered == null;
  bool get isConnected => _client.isConnected;
  bool get gpuAccelerated =>
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isAndroid ||
      Platform.isWindows;

  bool get canStart => _keys() != null;
  bool get canWriteBack =>
      hasResult &&
      _loadedContent != null &&
      (_sourcePath != null || _localFileName != null);

  String get elapsedLabel => _fmt(_elapsed);

  String? get etaLabel {
    if (_state != PsaWorkflowState.calculating) return null;
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

  ({List<int> key1, List<int> key2})? _keys() {
    final k1 = PsaSub.readKeyBytes(key1Hex);
    final k2 = PsaSub.readKeyBytes(key2Hex);
    if (k1 == null || k2 == null) return null;
    return (key1: k1, key2: k2);
  }

  void loadSampleVector() {
    final s = psaEncodeMode36(serial: 0x12, button: 1, counter: 0x10, crc: 0);
    key1Hex = _hex(s.key1);
    key2Hex = _hex(s.key2);
    _clearLoaded();
    _resetRun();
    _state = PsaWorkflowState.input;
    notifyListeners();
  }

  void manualEdited() {
    final content = _loadedContent;
    final signal = content == null ? null : PsaSub.parse(content);
    final keys = _keys();
    if (signal != null &&
        (keys == null ||
            !listEquals(keys.key1, signal.key1) ||
            !listEquals(keys.key2, signal.key2))) {
      _clearLoaded();
    }
    notifyListeners();
  }

  void selectCapture(String path) {
    selectedPath = selectedPath == path ? null : path;
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
      int pri(String n) => n.toLowerCase().contains('psa') ? 0 : 1;
      final pa = pri(a.name), pb = pri(b.name);
      return pa != pb ? pa.compareTo(pb) : a.name.compareTo(b.name);
    });
    return out;
  }

  Future<void> _syncCaptures(SubghzSyncView view) async {
    final files = _candidateFiles(view);
    final wanted = {for (final f in files) '${f.path}|${f.size}'};
    _captures.removeWhere((c) => !wanted.contains('${c.path}|${c.size}'));
    final selected = selectedPath;
    if (selected != null && !files.any((f) => f.path == selected)) {
      selectedPath = null;
    }
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

  Future<PsaCaptureRef?> _parseCandidate(_KeyFile f) async {
    try {
      final bytes = await File(f.localPath).readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      final signal = PsaSub.parse(content);
      if (signal == null) return null;
      if (!PsaSub.needsBruteforce(content)) return null;
      return PsaCaptureRef(
        path: f.path,
        name: f.name,
        size: f.size,
        signal: signal,
      );
    } catch (_) {
      return null;
    }
  }

  bool applyLocalCapture(String content, {String fileName = 'recovered.sub'}) {
    final signal = PsaSub.parse(content);
    if (signal == null) {
      _errorMessage = 'Not a PSA capture.';
      notifyListeners();
      return false;
    }
    key1Hex = _hex(signal.key1);
    key2Hex = _hex(signal.key2);
    _clearLoaded();
    _loadedContent = content;
    _localFileName = fileName;
    _loaded = true;
    _errorMessage = null;
    _resetRun();
    _state = PsaWorkflowState.input;
    notifyListeners();
    return true;
  }

  Future<void> loadSelected() async {
    final path = selectedPath;
    if (path == null) return;
    _errorMessage = null;
    try {
      final content = await _readContent(path);
      final signal = PsaSub.parse(content);
      if (signal == null) {
        _errorMessage = 'Not a PSA capture.';
        notifyListeners();
        return;
      }
      key1Hex = _hex(signal.key1);
      key2Hex = _hex(signal.key2);
      _clearLoaded();
      _loadedContent = content;
      _sourcePath = path;
      _loaded = true;
      _resetRun();
      _state = PsaWorkflowState.input;
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

  void start() {
    final keys = _keys();
    if (keys == null) {
      _errorMessage = 'Enter Key and Key_2 (16 hex digits each).';
      notifyListeners();
      return;
    }
    _progressSub?.cancel();
    _handle?.cancel();

    _resetRun();
    _state = PsaWorkflowState.calculating;
    _startedAt = DateTime.now();
    _startTicker();
    notifyListeners();

    final handle = _engine.start(key1: keys.key1, key2: keys.key2);
    _handle = handle;
    _progressSub = handle.progress.listen((p) {
      if (_disposed) return;
      _progress = p.percent.clamp(0, 100) / 100.0;
      notifyListeners();
    });
    handle.result.then(
      (res) {
        if (_disposed) return;
        if (_state != PsaWorkflowState.calculating) return;
        if (res.found) {
          _recovered = PsaRecovered(
            serial: res.serial,
            counter: res.counter,
            button: res.button,
            type: res.type,
            crc: res.crc,
            seed: res.seed,
          );
        }
        _syncElapsed();
        _stopTicker();
        _state = PsaWorkflowState.finished;
        notifyListeners();
      },
      onError: (Object e, StackTrace _) {
        if (_disposed) return;
        _stopTicker();
        _errorMessage = e.toString();
        _state = PsaWorkflowState.finished;
        notifyListeners();
      },
    );
  }

  void cancel() {
    _handle?.cancel();
    _stopTicker();
    if (_state == PsaWorkflowState.calculating) {
      _state = PsaWorkflowState.finished;
      notifyListeners();
    }
  }

  void reset() {
    _handle?.cancel();
    _handle = null;
    _stopTicker();
    _resetRun();
    _clearLoaded();
    _state = PsaWorkflowState.input;
    notifyListeners();
  }

  Future<void> writeBack() async {
    final content = _loadedContent;
    final rec = _recovered;
    if (content == null || rec == null || !canWriteBack || _writingBack) {
      return;
    }
    if (!_client.isConnected) {
      _errorMessage = 'Connect the Flipper to write the result back.';
      notifyListeners();
      return;
    }
    _errorMessage = null;
    _writingBack = true;
    notifyListeners();
    try {
      final path =
          _sourcePath ??
          await resolveLocalWriteBackPath(
            _client,
            fileName: _localFileName ?? 'recovered.sub',
            content: content,
          );
      final patched = PsaSub.patching(content, rec);
      final bytes = utf8.encode(patched);
      await _client.storageWriteChunked(path, bytes);
      await SubghzArchiveSource.mirror(path, bytes);
      _loadedContent = patched;
      _sourcePath = path;
      _localFileName = null;
      _writtenPath = path;
      _captures.removeWhere((c) => c.path == path);
      _hits.removeWhere((k, _) => k.startsWith('$path|'));
      _writeBackDone = true;
    } catch (e) {
      _errorMessage = 'Write-back failed: $e';
    } finally {
      _writingBack = false;
    }
    notifyListeners();
  }

  static String _hex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
      .join();

  void _clearLoaded() {
    _loaded = false;
    _loadedContent = null;
    _sourcePath = null;
    _localFileName = null;
  }

  void _resetRun() {
    _recovered = null;
    _errorMessage = null;
    _writeBackDone = false;
    _writtenPath = null;
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
