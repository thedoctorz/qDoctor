import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/foundation.dart';

import '../../../../services/connection/firmware_capability.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../services/logging.dart';
import '../../../archive/subghz_catalog.dart';
import '../signal_identity.dart';
import '../subghz_archive_source.dart';
import 'decode_raw_sub.dart';
import 'raw_capture.dart';

enum DecodeRawPhase { idle, decoding, results }

class DecodeRawListedFile {
  const DecodeRawListedFile({
    required this.path,
    required this.name,
    required this.size,
  });

  final String path;
  final String name;
  final int size;
}

class DecodeRawHitItem {
  DecodeRawHitItem(this.view, {this.position = 0});

  final DecodeRawHitView view;

  final double position;

  String? savedPath;
  bool get saved => savedPath != null;
}

class DecodeRawController extends ChangeNotifier {
  DecodeRawController({FlipperClient? client})
    : _client = client ?? FlipperOneClient().get() {
    _connSub = _client.connectionStream.listen((_) => _onConnectionChanged());
  }

  final FlipperClient _client;
  StreamSubscription<FlipperConnectionState>? _connSub;
  bool _disposed = false;

  static const int headerSniffMaxBytes = 4096;

  DecodeRawPhase _phase = DecodeRawPhase.idle;
  DecodeRawPhase get phase => _phase;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  double _progress = 0;
  double get progress => _progress;

  RawCapture capture = RawCapture.empty;

  bool _preparing = false;
  bool get preparing => _preparing;

  double _fetchProgress = 0;
  double get fetchProgress => _fetchProgress;

  bool _parsing = false;
  bool get parsing => _parsing;

  List<double> get envelope =>
      capture.isEmpty ? _fallbackView : capture.envelope;

  double get cursor => capture.isEmpty ? _progress : capture.timeAt(_progress);

  List<double> get hitMarks => [
    for (final hit in hits)
      capture.isEmpty ? hit.position : capture.timeAt(hit.position),
  ];

  final List<double> _fallback = List<double>.filled(RawCapture.buckets, 0);
  List<double> _fallbackView = const [];
  double _fallbackPeak = 0;

  static const int maxFetchBytes = 4 * 1024 * 1024;

  int _hitCount = 0;
  int get hitCount => _hitCount;

  String? _sourcePath;
  String? get sourcePath => _sourcePath;
  String _sourceStem = 'capture';
  String get sourceStem => _sourceStem;

  String? _uploadedPath;
  String? get uploadedPath => _uploadedPath;

  bool _cancelling = false;
  bool get cancelling => _cancelling;

  bool _cancelled = false;
  bool get cancelled => _cancelled;

  final List<DecodeRawListedFile> listed = [];
  final Map<String, String> _localByRemote = {};
  final Set<String> _listedPaths = {};
  bool _listing = false;
  bool get listing => _listing;
  int listDone = 0;
  int listTotal = 0;
  double get listProgress => listTotal == 0 ? 0 : listDone / listTotal;

  final List<DecodeRawHitItem> hits = [];

  final Set<String> _seen = {};

  int get unsavedCount => hits.where((h) => !h.saved).length;

  bool get isConnected => _client.isConnected;
  bool get isDecoding => _phase == DecodeRawPhase.decoding;
  bool get canDecode => _client.isConnected && !isDecoding;

  Future<void> refreshRawFiles({bool force = false}) async {
    if (_listing) return;
    _listing = true;
    _errorMessage = null;
    listed.clear();
    _listedPaths.clear();
    _localByRemote.clear();
    listDone = 0;
    listTotal = 0;
    _notify();
    try {
      if (!SubghzArchiveSource.available) {
        _errorMessage = l10n.decodeRawSyncArchive;
        return;
      }
      await SubghzArchiveSource.showLocalsThenGaps(
        force: force,
        pullMaxBytes: headerSniffMaxBytes,
        consume: _consumeArchive,
      );
      if (listed.isEmpty &&
          _errorMessage == null &&
          !SubghzArchiveSource.connected &&
          SubghzArchiveSource.view.local.isEmpty) {
        _errorMessage = l10n.decodeRawSyncArchive;
      }
    } catch (e) {
      _errorMessage = l10n.decodeRawListingFailed(e.toString());
    } finally {
      _listing = false;
      _notify();
    }
  }

  Future<void> _consumeArchive(SubghzSyncView view) async {
    final pendingSmall = {
      for (final gap in view.gaps)
        if (gap.remoteSize <= headerSniffMaxBytes) gap.remotePath,
    };
    final sniff = <({String path, String name, int size, String local})>[];
    for (final file in view.local) {
      if (file.size <= 0 || pendingSmall.contains(file.remotePath)) continue;
      _localByRemote[file.remotePath] = file.localPath;
      if (_listedPaths.contains(file.remotePath)) continue;
      if (file.size > headerSniffMaxBytes) {
        _addListed(
          DecodeRawListedFile(
            path: file.remotePath,
            name: file.name,
            size: file.size,
          ),
        );
      } else {
        sniff.add((
          path: file.remotePath,
          name: file.name,
          size: file.size,
          local: file.localPath,
        ));
      }
    }
    for (final gap in view.gaps) {
      if (gap.remoteSize <= headerSniffMaxBytes) continue;
      if (_listedPaths.contains(gap.remotePath)) continue;
      _addListed(
        DecodeRawListedFile(
          path: gap.remotePath,
          name: gap.name,
          size: gap.remoteSize,
        ),
      );
    }
    listTotal = listed.length + sniff.length;
    listDone = listed.length;
    listed.sort((a, b) => a.name.compareTo(b.name));
    _notify();
    for (final file in sniff) {
      if (_disposed) return;
      if (await _isRawLocal(file.local)) {
        _addListed(
          DecodeRawListedFile(
            path: file.path,
            name: file.name,
            size: file.size,
          ),
        );
      }
      listDone++;
      listed.sort((a, b) => a.name.compareTo(b.name));
      _notify();
    }
  }

  void _addListed(DecodeRawListedFile file) {
    if (!_listedPaths.add(file.path)) return;
    listed.add(file);
  }

  Future<bool> _isRawLocal(String localPath) async {
    try {
      final bytes = await io.File(localPath).readAsBytes();
      final head = bytes.length > headerSniffMaxBytes
          ? bytes.sublist(0, headerSniffMaxBytes)
          : bytes;
      return DecodeRawSub.isRawHeader(utf8.decode(head, allowMalformed: true));
    } catch (_) {
      return false;
    }
  }

  Future<void> decodeRemote(String path, {String? name}) async {
    if (!await _ready()) return;
    _sourcePath = path;
    _uploadedPath = null;
    _sourceStem = DecodeRawSub.sourceStem(name ?? path);
    final local = _localByRemote[path];
    Uint8List? content;
    if (local != null) {
      try {
        final file = io.File(local);
        final length = await file.length();
        if (length <= maxFetchBytes) content = await file.readAsBytes();
      } catch (_) {}
    }
    await _runDecode(path, content: content);
  }

  Future<void> decodeLocal(Uint8List bytes, String fileName) async {
    if (!await _ready()) return;
    final text = utf8.decode(
      bytes.length > headerSniffMaxBytes
          ? bytes.sublist(0, headerSniffMaxBytes)
          : bytes,
      allowMalformed: true,
    );
    if (!DecodeRawSub.isRawHeader(text)) {
      _errorMessage = l10n.decodeRawInvalidFile;
      _notify();
      return;
    }
    var name = fileName;
    if (!name.toLowerCase().endsWith('.sub')) name = '$name.sub';
    final remote = await _uniquePath(
      '/ext/subghz',
      DecodeRawSub.sourceStem(name),
    );
    try {
      await _client.storageWriteChunked(remote, bytes);
      await SubghzArchiveSource.mirror(remote, bytes);
    } catch (e) {
      _errorMessage = l10n.decodeRawUploadFailed(e.toString());
      _notify();
      return;
    }
    _sourcePath = remote;
    _uploadedPath = remote;
    _sourceStem = DecodeRawSub.sourceStem(name);
    await _runDecode(remote, content: bytes);
  }

  Future<void> cancelDecode() async {
    if (!isDecoding || _cancelling) return;
    _cancelling = true;
    _notify();
    try {
      await _client.decodeRawStop();
    } catch (e) {
      _cancelling = false;
      _notify();
    }
  }

  Future<void> saveHit(DecodeRawHitItem item) async {
    if (!_client.isConnected) {
      _errorMessage = l10n.decodeRawConnectFirst;
      _notify();
      return;
    }
    try {
      final path = await _writeHit(item);
      item.savedPath = path;
      _notify();
    } catch (e) {
      _errorMessage = l10n.decodeRawSaveFailed(e.toString());
      _notify();
    }
  }

  Future<int> saveAll() async {
    var n = 0;
    for (final item in hits) {
      if (_disposed) break;
      if (item.saved) continue;
      try {
        item.savedPath = await _writeHit(item);
        n++;
        _notify();
      } catch (e) {
        _errorMessage = l10n.decodeRawSaveFailed(e.toString());
        _notify();
        break;
      }
    }
    return n;
  }

  void reset() {
    _phase = DecodeRawPhase.idle;
    _errorMessage = null;
    _progress = 0;
    _hitCount = 0;
    _cancelling = false;
    _cancelled = false;
    _uploadedPath = null;
    capture = RawCapture.empty;
    _clearFallback();
    hits.clear();
    _seen.clear();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_connSub?.cancel());
    _connSub = null;
    super.dispose();
  }

  void _onConnectionChanged() {
    if (_disposed) return;
    if (!_client.isConnected && _phase == DecodeRawPhase.decoding) {
      _errorMessage = l10n.decodeRawConnectionLost;
      _phase = hits.isEmpty ? DecodeRawPhase.idle : DecodeRawPhase.results;
    }
    _notify();
  }

  Future<bool> _ready() async {
    if (!_client.isConnected) {
      _errorMessage = l10n.decodeRawConnectFirst;
      _notify();
      return false;
    }
    final supported = await FirmwareCapabilities.supports(
      _client,
      FirmwareCapability.subghzRpc,
    );
    if (_disposed) return false;
    if (!supported) {
      _errorMessage = l10n.decodeRawNotImplemented;
      _notify();
      return false;
    }
    return true;
  }

  Future<void> _runDecode(String path, {Uint8List? content}) async {
    _phase = DecodeRawPhase.decoding;
    _errorMessage = null;
    _progress = 0;
    _hitCount = 0;
    _cancelling = false;
    _cancelled = false;
    hits.clear();
    _seen.clear();
    capture = RawCapture.empty;
    _clearFallback();
    _notify();

    await _prepareCapture(path, content);
    if (_disposed || _phase != DecodeRawPhase.decoding) return;

    try {
      await _client.decodeRaw(
        DecodeRawRequest(path: path),
        onProgress: (p, slice) {
          _progress = p;
          if (capture.isEmpty) _addFallbackSlice(p, slice);
          _notify();
        },
        onHit: (resp) {
          final view = DecodeRawSub.hitFromResponse(
            protocol: resp.protocol,
            flipperFormat: resp.flipperFormat,
          );
          final identity = SubGhzSignalIdentity.of(
            view.fields,
            fallback: view.flipperFormat,
          );
          if (!_seen.add(identity)) return;
          hits.add(
            DecodeRawHitItem(
              view,
              position: (resp.percent / 100).clamp(0.0, 1.0),
            ),
          );
          _hitCount = hits.length;
          _notify();
        },
      );
      _progress = 1;
      _phase = DecodeRawPhase.results;
    } on FlipperRpcContinuousCommandInterruptedException {
      _cancelled = true;
      _phase = DecodeRawPhase.results;
    } on FlipperRpcNotImplementedException {
      _errorMessage = l10n.decodeRawNotImplemented;
      _phase = DecodeRawPhase.idle;
    } catch (e) {
      _errorMessage = l10n.decodeRawFailed(e.toString());
      _phase = hits.isEmpty ? DecodeRawPhase.idle : DecodeRawPhase.results;
    }
    _cancelling = false;
    _notify();
  }

  Future<void> _prepareCapture(String path, Uint8List? content) async {
    _preparing = true;
    _fetchProgress = 0;
    _parsing = false;
    _notify();
    try {
      var bytes = content;
      if (bytes == null) {
        final size = await _sizeOf(path);
        if (size > maxFetchBytes) return;
        final read = await _client.storageReadChunked(
          path,
          expectedSize: size,
          onProgress: (p) {
            if (_disposed) return;
            _fetchProgress = p;
            _notify();
          },
        );
        if (_disposed) return;
        bytes = Uint8List.fromList(read);
      }
      _parsing = true;
      _notify();
      final parsed = await RawCapture.parseBytes(bytes);
      if (_disposed) return;
      if (!parsed.isEmpty) capture = parsed;
    } catch (e) {
      LogService.warn('[DecodeRaw] capture preview unavailable: $e');
    } finally {
      _preparing = false;
      _parsing = false;
      _notify();
    }
  }

  Future<int> _sizeOf(String path) async {
    for (final file in listed) {
      if (file.path == path) return file.size;
    }
    try {
      final stat = await _client.storageStat(StatRequest(path: path));
      return stat.firstOrNull?.file.size ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void _clearFallback() {
    _fallback.fillRange(0, _fallback.length, 0);
    _fallbackView = const [];
    _fallbackPeak = 0;
  }

  void _addFallbackSlice(double at, int value) {
    final index = (at * (RawCapture.buckets - 1)).round().clamp(
      0,
      RawCapture.buckets - 1,
    );
    _fallback[index] = value.toDouble();
    if (value > _fallbackPeak) _fallbackPeak = value.toDouble();
    if (_fallbackPeak <= 0) return;
    _fallbackView = [
      for (final slice in _fallback) (slice / _fallbackPeak).clamp(0.0, 1.0),
    ];
  }

  Future<String> _writeHit(DecodeRawHitItem item) async {
    final name = DecodeRawSub.saveFileName(
      _sourceStem,
      item.view.protocol,
      hits.indexOf(item) + 1,
    );
    final path = await _uniquePath(
      '/ext/subghz',
      DecodeRawSub.sourceStem(name),
    );
    final encoded = utf8.encode(item.view.flipperFormat);
    await _client.storageWriteChunked(path, encoded);
    await SubghzArchiveSource.mirror(path, encoded);
    return path;
  }

  Future<String> _uniquePath(String dir, String stem) async {
    var index = 1;
    while (true) {
      final fileName = index == 1 ? '$stem.sub' : '${stem}_$index.sub';
      final path = '$dir/$fileName';
      if (!await _exists(path)) return path;
      index++;
    }
  }

  Future<bool> _exists(String path) async {
    try {
      await _client.storageStat(StatRequest(path: path));
      return true;
    } on FlipperRpcStorageNotExistException {
      return false;
    } catch (_) {
      return false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
