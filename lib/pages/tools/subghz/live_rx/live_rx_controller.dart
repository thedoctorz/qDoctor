import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/foundation.dart';

import '../../../../services/connection/firmware_capability.dart';
import '../../../../services/localization/l10n.dart';
import '../decode_raw/decode_raw_sub.dart';
import '../signal_identity.dart';
import '../subghz_key_store.dart';
import '../widgets/signal_trace.dart';

enum LiveRxPhase { idle, starting, running, stopping }

class LiveRssi {
  const LiveRssi({
    required this.tick,
    required this.latest,
    required this.noiseFloor,
  });

  final int tick;

  final int? latest;
  final int noiseFloor;
}

enum SubGhzIgnore {
  reversRb2(2048),
  alarms(4096),
  sensors(8192),
  princeton(16384),
  niceFlorS(32768);

  const SubGhzIgnore(this.flag);

  final int flag;
}

class LiveRxSignal {
  LiveRxSignal({
    required this.protocol,
    required this.flipperFormat,
    required this.frequency,
    required this.rssi,
    required this.transmittable,
    required this.pulses,
    required this.firstSeen,
  }) : lastSeen = firstSeen,
       fields = DecodeRawSub.fields(flipperFormat);

  final String protocol;
  final String flipperFormat;
  final int frequency;
  final bool transmittable;
  final Map<String, String> fields;
  final DateTime firstSeen;

  int rssi;
  List<int> pulses;
  DateTime lastSeen;
  int repeats = 1;
  String? savedPath;

  bool get saved => savedPath != null;

  String get subtitle {
    final parts = <String>[];
    for (final key in const ['Key', 'Serial', 'Btn', 'Bit', 'Cnt', 'TE']) {
      final v = fields[key];
      if (v != null && v.isNotEmpty) parts.add('$key $v');
    }
    return parts.join('  ·  ');
  }

  late final String dedupKey = SubGhzSignalIdentity.of(
    fields,
    fallback: flipperFormat,
  );
}

class LiveRxController extends ChangeNotifier {
  LiveRxController({FlipperClient? client})
    : _client = client ?? FlipperOneClient().get() {
    _connSub = _client.connectionStream.listen((_) => _onConnectionChanged());
  }

  static const int rssiWindowSize = 300;

  static const int rssiIntervalMs = SignalTrace.sampleIntervalMs;

  final FlipperClient _client;
  StreamSubscription<FlipperConnectionState>? _connSub;
  StreamSubscription<SubGhzRxUpdate>? _eventSub;
  bool _disposed = false;

  LiveRxPhase _phase = LiveRxPhase.idle;
  LiveRxPhase get phase => _phase;
  bool get running => _phase == LiveRxPhase.running;
  bool get busy =>
      _phase == LiveRxPhase.starting || _phase == LiveRxPhase.stopping;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _transmitting = false;
  bool get transmitting => _transmitting;

  bool _retuning = false;
  bool get retuning => _retuning;

  List<int> frequencies = const [];
  List<int> hopperFrequencies = const [];
  List<String> presets = const [];
  bool settingsLoaded = false;

  static const String _defaultPreset = 'AM650';

  int frequency = 433920000;
  String preset = '';
  String presetB = '';
  bool hopping = false;
  bool modulationHopping = false;

  bool? externalRadio;
  bool capturePulses = false;
  bool sound = false;
  Set<SubGhzIgnore> ignored = const {};

  bool autosave = false;

  int get ignoreFilter => ignored.fold(0, (mask, ignore) => mask | ignore.flag);

  RadioDevice get _radioDevice => switch (externalRadio) {
    true => RadioDevice.RADIO_DEVICE_EXTERNAL,
    false => RadioDevice.RADIO_DEVICE_INTERNAL,
    null => RadioDevice.RADIO_DEVICE_AUTO,
  };

  bool usingExternalRadio = false;

  bool thresholdEnabled = false;

  int threshold = -95;

  final List<int> rssi = [];

  final ValueNotifier<LiveRssi> live = ValueNotifier<LiveRssi>(
    const LiveRssi(tick: 0, latest: null, noiseFloor: -100),
  );

  int noiseFloor = -100;
  int _liveFrequency = 433920000;
  int get liveFrequency => _liveFrequency;
  String deviceName = '';
  bool txAllowed = false;

  final List<LiveRxSignal> signals = [];
  final Map<String, LiveRxSignal> _byKey = {};

  bool get isConnected => _client.isConnected;
  bool get canStart => _client.isConnected && _phase == LiveRxPhase.idle;

  int get latestRssi => rssi.isEmpty ? -127 : rssi.last;

  bool _loadingSettings = false;
  bool get loadingSettings => _loadingSettings;

  Future<void> loadSettings() async {
    if (settingsLoaded || _loadingSettings || !_client.isConnected) return;
    _loadingSettings = true;
    _notify();
    try {
      await _loadSettings();
    } finally {
      _loadingSettings = false;
      _notify();
    }
  }

  Future<void> _loadSettings() async {
    if (!await FirmwareCapabilities.supports(
      _client,
      FirmwareCapability.subghzRpc,
    )) {
      if (_disposed) return;
      _fail(l10n.subghzRxNotImplemented);
      return;
    }
    try {
      final settings = await _client.subghzSettings();
      if (_disposed) return;
      frequencies = List<int>.unmodifiable(settings.frequencies);
      hopperFrequencies = List<int>.unmodifiable(settings.hopperFrequencies);
      presets = List<String>.unmodifiable(settings.presets);
      settingsLoaded = frequencies.isNotEmpty && presets.isNotEmpty;

      if (!frequencies.contains(frequency)) {
        frequency =
            settings.defaultFrequency != 0 &&
                frequencies.contains(settings.defaultFrequency)
            ? settings.defaultFrequency
            : (frequencies.isNotEmpty ? frequencies.first : frequency);
      }
      if (!presets.contains(preset)) {
        preset = presets.contains(_defaultPreset)
            ? _defaultPreset
            : (presets.isNotEmpty ? presets.first : preset);
      }
      if (!presets.contains(presetB)) {
        presetB = presets.length > 1 ? presets[1] : preset;
      }
      _errorMessage = null;
    } catch (e) {
      _fail(l10n.subghzRxFailed(e.toString()));
      return;
    }
    _notify();
  }

  Future<void> setFrequency(int hz) async {
    if (frequency == hz) return;
    frequency = hz;
    await applyConfig();
  }

  Future<void> setPreset(String name) async {
    if (preset == name) return;
    preset = name;
    await applyConfig();
  }

  void resetConfig() {
    hopping = false;
    modulationHopping = false;
    capturePulses = false;
    sound = false;
    autosave = false;
    ignored = const {};
    thresholdEnabled = false;
    threshold = -95;
    if (presets.isNotEmpty) {
      preset = presets.contains(_defaultPreset)
          ? _defaultPreset
          : presets.first;
      presetB = presets.firstWhere((p) => p != preset, orElse: () => preset);
    }
    _notify();
  }

  Future<void> start() async {
    if (_phase != LiveRxPhase.idle) return;
    if (!_client.isConnected) {
      _fail(l10n.decodeRawConnectFirst);
      return;
    }
    _phase = LiveRxPhase.starting;
    _errorMessage = null;
    _notify();

    if (!await FirmwareCapabilities.supports(
      _client,
      FirmwareCapability.subghzRpc,
    )) {
      if (_disposed) return;
      _phase = LiveRxPhase.idle;
      _fail(l10n.subghzRxNotImplemented);
      return;
    }

    _eventSub ??= _client.subghzRxEvents.listen(_onEvent);

    try {
      final state = await _client.subghzRxStart(
        RxStartRequest(
          frequency: frequency,
          rssiIntervalMs: rssiIntervalMs,
          preset: preset,
          presetB: presetB,
          hopping: hopping,
          hopFrequencies: hopping ? hopperFrequencies : const [],
          modulationHopping: modulationHopping,
          capturePulses: capturePulses,
          sound: sound,
          ignoreFilter: ignoreFilter,
          device: _radioDevice,
        ),
      );
      if (_disposed) return;
      _applyState(state);
      _phase = LiveRxPhase.running;
      rssi.clear();
    } on FlipperRpcBusyException {
      _phase = LiveRxPhase.idle;
      _fail(l10n.subghzRxBusy);
      return;
    } on FlipperRpcNotImplementedException {
      _phase = LiveRxPhase.idle;
      _fail(
        externalRadio == true
            ? l10n.subghzRxNoDevice
            : l10n.subghzRxNotImplemented,
      );
      return;
    } catch (e) {
      _phase = LiveRxPhase.idle;
      _fail(l10n.subghzRxFailed(e.toString()));
      return;
    }
    _notify();
  }

  Future<void> stop() async {
    if (_phase != LiveRxPhase.running) return;
    _phase = LiveRxPhase.stopping;
    _notify();
    try {
      await _client.subghzRxStop();
    } catch (e) {
      _errorMessage = l10n.subghzRxFailed(e.toString());
    }
    await _eventSub?.cancel();
    _eventSub = null;
    if (_disposed) return;
    _phase = LiveRxPhase.idle;
    _notify();
  }

  Future<void> applyConfig() async {
    if (_phase != LiveRxPhase.running) {
      _notify();
      return;
    }
    _retuning = true;
    _notify();
    try {
      final state = await _client.subghzRxConfig(
        RxConfigRequest(
          frequency: frequency,
          preset: preset,
          presetB: presetB,
          hopping: hopping,
          hopFrequencies: hopping ? hopperFrequencies : const [],
          modulationHopping: modulationHopping,
          capturePulses: capturePulses,
          sound: sound,
          ignoreFilter: ignoreFilter,
        ),
      );
      if (_disposed) return;
      _applyState(state);
      rssi.clear();
    } catch (e) {
      _errorMessage = l10n.subghzRxFailed(e.toString());
    }
    _retuning = false;
    _notify();
  }

  Future<({String? error, int frequency})> transmit(LiveRxSignal signal) async {
    if (_transmitting) {
      return (error: null, frequency: 0);
    }
    if (!signal.transmittable) {
      return (error: l10n.subghzRxTransmitUnsupported, frequency: 0);
    }
    _transmitting = true;
    _notify();
    try {
      final response = await _client.subghzTx(
        TxRequest(
          flipperFormat: signal.flipperFormat,
          repeat: 3,
          device: _radioDevice,
        ),
      );
      return (
        error: null,
        frequency: response.frequency != 0
            ? response.frequency
            : signal.frequency,
      );
    } on FlipperRpcInvalidParametersException {
      return (error: l10n.subghzRxTransmitForbidden, frequency: 0);
    } catch (e) {
      return (error: l10n.subghzRxTransmitFailed(e.toString()), frequency: 0);
    } finally {
      _transmitting = false;
      _notify();
    }
  }

  Future<String?> save(LiveRxSignal signal) async {
    if (!_client.isConnected) return l10n.decodeRawConnectFirst;
    try {
      final stem =
          '${DecodeRawSub.sanitizeProtocol(signal.protocol)}_'
          '${signal.frequency ~/ 1000000}';
      final path = await SubGhzKeyStore.write(
        _client,
        stem,
        signal.flipperFormat,
      );
      signal.savedPath = path;
      _notify();
      return null;
    } catch (e) {
      return l10n.decodeRawSaveFailed(e.toString());
    }
  }

  void setThreshold(int value) {
    if (!thresholdEnabled) return;
    threshold = value.clamp(-127, 0);
    _notify();
  }

  void clearSignals() {
    signals.clear();
    _byKey.clear();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    live.dispose();
    unawaited(_eventSub?.cancel());
    unawaited(_connSub?.cancel());
    _eventSub = null;
    _connSub = null;
    if (_phase == LiveRxPhase.running && _client.isConnected) {
      unawaited(_client.subghzRxStop().catchError((_) {}));
    }
    super.dispose();
  }

  void _onEvent(SubGhzRxUpdate update) {
    if (_disposed) return;
    switch (update) {
      case SubGhzRxRssi(:final samples, :final frequency, :final noiseFloor):
        final hopped = frequency != 0 && frequency != _liveFrequency;
        if (frequency != 0) _liveFrequency = frequency;
        this.noiseFloor = noiseFloor;
        rssi.addAll(samples);
        if (rssi.length > rssiWindowSize) {
          rssi.removeRange(0, rssi.length - rssiWindowSize);
        }
        live.value = LiveRssi(
          tick: live.value.tick + 1,
          latest: rssi.isEmpty ? null : rssi.last,
          noiseFloor: noiseFloor,
        );
        if (hopped) _notify();
        return;
      case SubGhzRxHit hit:
        _addHit(hit);
      case SubGhzRxStopped():
        final expected = _phase == LiveRxPhase.stopping;
        _phase = LiveRxPhase.idle;
        if (!expected) _errorMessage = l10n.subghzRxStoppedByDevice;
        unawaited(_eventSub?.cancel());
        _eventSub = null;
    }
    _notify();
  }

  void _addHit(SubGhzRxHit hit) {
    if (thresholdEnabled && hit.rssi < threshold) return;

    final signal = LiveRxSignal(
      protocol: hit.protocol.isEmpty ? 'Unknown' : hit.protocol,
      flipperFormat: hit.flipperFormat,
      frequency: hit.frequency,
      rssi: hit.rssi,
      transmittable: hit.transmittable,
      pulses: hit.pulses,
      firstSeen: DateTime.now(),
    );

    final existing = _byKey[signal.dedupKey];
    if (existing != null) {
      existing.repeats++;
      existing.rssi = hit.rssi;
      existing.lastSeen = DateTime.now();
      if (hit.pulses.isNotEmpty) existing.pulses = hit.pulses;
      signals.remove(existing);
      signals.insert(0, existing);
      return;
    }

    _byKey[signal.dedupKey] = signal;
    signals.insert(0, signal);
    if (autosave) unawaited(save(signal));
  }

  void _applyState(RxStateResponse state) {
    if (state.frequency != 0) _liveFrequency = state.frequency;
    if (state.preset.isNotEmpty) preset = state.preset;
    hopping = state.hopping;
    usingExternalRadio = state.device == RadioDevice.RADIO_DEVICE_EXTERNAL;
    txAllowed = state.txAllowed;
    deviceName = state.deviceName;
    modulationHopping = state.modulationHopping;
    if (state.presetB.isNotEmpty) presetB = state.presetB;
    sound = state.sound;
    ignored = {
      for (final ignore in SubGhzIgnore.values)
        if (state.ignoreFilter & ignore.flag != 0) ignore,
    };
  }

  void _onConnectionChanged() {
    if (_disposed) return;
    if (_client.isConnected && !settingsLoaded) {
      unawaited(loadSettings());
    }
    if (!_client.isConnected && _phase != LiveRxPhase.idle) {
      _phase = LiveRxPhase.idle;
      _errorMessage = l10n.decodeRawConnectionLost;
      unawaited(_eventSub?.cancel());
      _eventSub = null;
    }
    _notify();
  }

  void _fail(String message) {
    _errorMessage = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
