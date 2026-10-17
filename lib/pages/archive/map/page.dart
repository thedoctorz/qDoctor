import '../../../services/localization/l10n.dart';

import 'dart:async';
import 'dart:io' show HttpClient, HttpException, SocketException;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:applemap/applemap.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/io_client.dart';
import 'package:http/retry.dart';
import 'package:latlong2/latlong.dart';

import '../../../theme/theme.dart';
import '../../../components/notification.dart';
import 'controller.dart';
import 'data/settings.dart';
import 'native/marker_images.dart';
import '../../../components/navigation.dart';
import '../../../components/archive/models/pin.dart';
import '../../../components/filelist/empty_view.dart';
import '../../../app/nav_bar.dart';

part 'widgets/circle_button.dart';
part 'widgets/panel.dart';
part 'widgets/sheet.dart';

class FlipperMapPage extends StatefulWidget {
  const FlipperMapPage({super.key, this.focusPinPath, this.pickLocationFor});

  final String? focusPinPath;
  final MapPickTarget? pickLocationFor;

  @override
  State<FlipperMapPage> createState() => _FlipperMapPageState();
}

enum _MapMode { browse, pick }

class _FlipperMapPageState extends State<FlipperMapPage> {
  late final MapToolController _controller;
  final MapSettings _settings = MapSettings.instance;
  final MapController _mapController = MapController();
  MapPin? _selectedPin;
  bool _initialCentered = false;
  bool _centeredOnPinsOnly = false;
  bool _userMovedMap = false;
  bool _initialPinSelected = false;
  bool _mapReady = false;
  bool _saving = false;
  String? _failedTemplate;
  Timer? _tileQuietTimer;
  int _tileFailures = 0;
  String? _noticeKey;
  QNotificationHandle? _notice;

  static const Duration _tileGracePeriod = Duration(seconds: 6);
  final Stopwatch _openedAt = Stopwatch();

  bool _panelOpen = true;

  // TileLayer builds a NetworkTileProvider — and with it a fresh HTTP client
  // and connection pool — inside its constructor. This page rebuilds on every
  // position fix, so a per-build provider meant no keep-alive at all and a new
  // TLS handshake per tile. One provider per tile source instead; the outgoing
  // TileLayer state disposes it when the source (and so the layer key) changes.
  String? _tileSource;
  NetworkTileProvider? _tileProvider;

  _MapMode _mode = _MapMode.browse;
  MapPickTarget? _pickTarget;
  late final bool _openedInPickMode;

  AppleMapController? _systemMap;

  AppleMapCamera? _systemCamera;
  final MapMarkerImages _markers = MapMarkerImages.instance;
  bool _markerWorkPending = false;

  @override
  void initState() {
    super.initState();
    _openedAt.start();
    _controller = MapToolController()..addListener(_onChanged);
    _settings.addListener(_onChanged);
    unawaited(_settings.load());
    _openedInPickMode = widget.pickLocationFor != null;
    if (_openedInPickMode) {
      _mode = _MapMode.pick;
      _pickTarget = widget.pickLocationFor;
    }
    _controller.initialize();
  }

  @override
  void dispose() {
    _notice?.close();
    _tileQuietTimer?.cancel();
    _settings.removeListener(_onChanged);
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    _maybeSelectInitialPin();
    if (_settings.useSystemMap == (_systemMap == null) && _mapReady) {
      _systemMap = null;
      _systemCamera = null;
      _mapReady = !_settings.useSystemMap;
    }
    setState(() {});
    _maybeAutoCenter();
    _maybeFollowUser();
  }

  void _maybeAutoCenter() {
    if (!_mapReady) return;
    if (_mode == _MapMode.pick) {
      if (_initialCentered) return;
      final target = _pickTarget;
      if (target?.initialLatitude != null && target?.initialLongitude != null) {
        _initialCentered = true;
        _moveCamera(
          LatLng(target!.initialLatitude!, target.initialLongitude!),
          17,
        );
        return;
      }
      final p = _controller.userPosition;
      if (p != null) {
        _initialCentered = true;
        _moveCamera(LatLng(p.latitude, p.longitude), 17);
      }
      return;
    }

    final selected = _selectedPin;
    if (selected != null) {
      if (_initialCentered) return;
      _initialCentered = true;
      _centeredOnPinsOnly = false;
      _moveCamera(LatLng(selected.latitude, selected.longitude), 17);
      return;
    }

    final p = _controller.userPosition;
    if (p != null) {
      // Pins are read from disk long before the first fix arrives, so the
      // fallback below normally claims the initial centring and the map never
      // moves to the user on its own. Treat that framing as provisional and
      // upgrade to the real position once it lands — unless the map has been
      // panned by hand in the meantime.
      if (_initialCentered && !(_centeredOnPinsOnly && !_userMovedMap)) return;
      _initialCentered = true;
      _centeredOnPinsOnly = false;
      _moveCamera(LatLng(p.latitude, p.longitude), 16);
      return;
    }

    if (_initialCentered) return;
    if (_controller.pins.isNotEmpty) {
      _initialCentered = true;
      _centeredOnPinsOnly = true;
      final first = _controller.pins.first;
      _moveCamera(LatLng(first.latitude, first.longitude), 14);
    }
  }

  void _maybeFollowUser() {
    if (!_settings.autoCenter ||
        !_mapReady ||
        _mode != _MapMode.browse ||
        !_initialCentered) {
      return;
    }
    final target = _activeTarget();
    if (target == null) return;
    _moveCamera(target, _cameraZoom);
  }

  void _moveCamera(LatLng target, double zoom) {
    if (!_mapReady) return;
    final system = _systemMap;
    if (system != null) {
      _systemCamera = AppleMapCamera(
        latitude: target.latitude,
        longitude: target.longitude,
        zoom: zoom,
      );
      unawaited(system.moveCamera(_systemCamera!));
      return;
    }
    _mapController.move(target, zoom);
  }

  LatLng get _cameraCenter {
    final camera = _systemCamera;
    if (_systemMap != null && camera != null) {
      return LatLng(camera.latitude, camera.longitude);
    }
    if (_systemMap != null) return _initialCenter();
    return _mapController.camera.center;
  }

  double get _cameraZoom {
    final camera = _systemCamera;
    if (_systemMap != null) return camera?.zoom ?? _initialZoom();
    return _mapController.camera.zoom;
  }

  LatLng? _activeTarget() {
    if (_settings.trackDevice) {
      final d = _controller.devicePosition;
      if (d != null && d.hasFix) return LatLng(d.latitude, d.longitude);
    }
    final p = _controller.userPosition;
    if (p == null) return null;
    return LatLng(p.latitude, p.longitude);
  }

  void _maybeSelectInitialPin() {
    final path = widget.focusPinPath;
    if (_initialPinSelected || path == null || path.isEmpty) return;
    for (final pin in _controller.pins) {
      if (pin.path == path || pin.id == path) {
        _selectedPin = pin;
        _initialPinSelected = true;
        break;
      }
    }
  }

  /// Following is one mode with two targets, not two switches: [MapSettings]
  /// stores "follow" in `autoCenter` and "the target is the Flipper" in
  /// `trackDevice`. So exactly one of the two buttons can read as active, and
  /// tapping the active one stops following altogether.
  bool get _followingMe => _settings.autoCenter && !_settings.trackDevice;

  bool get _followingDevice => _settings.autoCenter && _settings.trackDevice;

  void _stopFollowing() {
    _settings.setAutoCenter(false);
    _settings.setTrackDevice(false);
  }

  void _toggleAutoCenter() {
    if (_followingMe) {
      _stopFollowing();
      return;
    }
    _settings.setTrackDevice(false);
    _settings.setAutoCenter(true);
    _centerOnTarget();
  }

  void _toggleTrackDevice() {
    if (_followingDevice) {
      _stopFollowing();
      return;
    }
    _settings.setTrackDevice(true);
    _settings.setAutoCenter(true);
    _centerOnTarget();
  }

  void _centerOnTarget() {
    final target = _activeTarget();
    if (target == null) {
      _controller.requestLocation();
      return;
    }
    _moveCamera(target, 17);
  }

  void _selectPin(MapPin pin) {
    if (_mode == _MapMode.pick) return;
    setState(() {
      _selectedPin = pin;
    });
    _moveCamera(LatLng(pin.latitude, pin.longitude), 17);
  }

  void _enterEditModeFor(MapPin pin) {
    setState(() {
      _mode = _MapMode.pick;
      _pickTarget = MapPickTarget(
        localPath: pin.path,
        remotePath: pin.remotePath,
        displayName: pin.name,
        initialLatitude: pin.latitude,
        initialLongitude: pin.longitude,
      );
      _selectedPin = null;
    });
    _moveCamera(LatLng(pin.latitude, pin.longitude), 17);
  }

  void _exitPickMode() {
    if (_openedInPickMode) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _mode = _MapMode.browse;
      _pickTarget = null;
    });
  }

  Future<void> _savePickedLocation() async {
    final target = _pickTarget;
    if (target == null || _saving) return;
    setState(() => _saving = true);
    final center = _cameraCenter;
    final ok = await _controller.writeCoordinates(
      localPath: target.localPath,
      remotePath: target.remotePath,
      latitude: center.latitude,
      longitude: center.longitude,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      context.showNotification(
        context.l10n.mapSaveLocationFailed,
        type: QNotificationType.error,
      );
      return;
    }
    final savedPath = target.localPath;
    if (_openedInPickMode) {
      Navigator.of(context).maybePop(true);
      return;
    }
    setState(() {
      _mode = _MapMode.browse;
      _pickTarget = null;
    });
    for (final p in _controller.pins) {
      if (p.path == savedPath) {
        setState(() => _selectedPin = p);
        _moveCamera(LatLng(p.latitude, p.longitude), 17);
        break;
      }
    }
    context.showNotification(
      context.l10n.mapLocationSaved,
      type: QNotificationType.good,
    );
  }

  @override
  Widget build(BuildContext context) {
    final firmwareColors = context.appColors;
    final effectiveDark = _settings.darkFor(firmwareColors.isDark);
    final mapColors = _resolveMapColors(firmwareColors, effectiveDark);

    final colorScheme =
        (effectiveDark ? const ColorScheme.dark() : const ColorScheme.light())
            .copyWith(
              primary: mapColors.accent,
              onPrimary: mapColors.onAccent,
              secondary: mapColors.info,
              surface: mapColors.card,
              onSurface: mapColors.textPrimary,
              error: mapColors.danger,
            );

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: mapColors.background,
        colorScheme: colorScheme,
        extensions: [mapColors],
      ),
      child: Builder(
        builder: (ctx) {
          final colors = ctx.appColors;
          return LayoutBuilder(
            builder: (_, constraints) {
              final wide = constraints.maxWidth >= 720;
              return Scaffold(
                backgroundColor: colors.background,
                body: wide
                    ? _buildDesktopLayout(colors)
                    : _buildMobileLayout(colors),
              );
            },
          );
        },
      ),
    );
  }

  static QAppColors _resolveMapColors(QAppColors current, bool dark) {
    if (dark == current.isDark) return current;
    return QAppColors.build(
      dark ? Brightness.dark : Brightness.light,
      current.accent,
    );
  }

  /// True while the browse mode has nothing to draw but a status screen.
  Widget? _buildBrowseGuard(QAppColors colors) {
    if (_mode != _MapMode.browse) return null;
    if (_controller.loading && _controller.pins.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    final loadError = _controller.loadError;
    if (loadError != null && _controller.pins.isEmpty) {
      return ArchiveEmptyView(
        icon: Icons.map_outlined,
        title: context.l10n.mapNoPins,
        subtitle: loadError,
        actionLabel: context.l10n.mapTryAgain,
        onAction: _controller.refresh,
      );
    }
    if (_controller.needsArchiveSync && _controller.pins.isEmpty) {
      return ArchiveEmptyView(
        icon: Icons.map_outlined,
        title: context.l10n.mapNoPins,
        subtitle: _controller.syncHint ?? context.l10n.mapSyncToSeeLocations,
        actionLabel: context.l10n.mapOpenArchive,
        onAction: _openArchive,
      );
    }
    return null;
  }

  Widget _withDismiss(Widget guard, QAppColors colors) {
    final canDismiss = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    if (!canDismiss) return guard;
    return Stack(
      children: [
        guard,
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Align(
              alignment: Alignment.topLeft,
              child: _MapControl(
                colors: colors,
                icon: Icons.arrow_back,
                tooltip: context.l10n.commonClose,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openArchive() {
    requestRootTab(FlipperRootTab.archive);
    Navigator.of(context).maybePop();
  }

  Widget _buildDesktopLayout(QAppColors colors) {
    final guard = _buildBrowseGuard(colors);
    if (guard != null) return _withDismiss(guard, colors);
    final picking = _mode == _MapMode.pick;
    final showPanel = _panelOpen && !picking;

    return Stack(
      children: [
        _buildMapStack(
          colors,
          desktopMode: true,
          leftInset: showPanel ? kMapPanelWidth + 24 : 0,
        ),
        if (showPanel)
          Positioned(
            left: 12,
            top: kMapControl + 24,
            bottom: 12,
            width: kMapPanelWidth,
            child: Material(
              color: colors.card,
              elevation: 6,
              shadowColor: Colors.black38,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: _MapPanel(
                pins: _sortedPins(),
                selected: _selectedPin,
                controller: _controller,
                colors: colors,
                onSelect: _selectPin,
                onClose: () => setState(() => _selectedPin = null),
                onEdit: _selectedPin != null
                    ? () => _enterEditModeFor(_selectedPin!)
                    : null,
                onCopyCoords: () => context.showNotification(
                  context.l10n.mapCoordinatesCopied,
                  type: QNotificationType.good,
                ),
              ),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: picking
              ? _buildPickControls(colors)
              : _buildBrowseControls(colors, withPanelToggle: true),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(QAppColors colors) {
    final guard = _buildBrowseGuard(colors);
    if (guard != null) {
      return _withDismiss(guard, colors);
    }
    final picking = _mode == _MapMode.pick;
    return Stack(
      children: [
        _buildMapStack(colors, desktopMode: false),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Align(
              alignment: Alignment.topCenter,
              child: picking
                  ? _buildPickControls(colors)
                  : _buildBrowseControls(colors),
            ),
          ),
        ),
        if (!picking)
          Positioned.fill(
            child: _MapSheet(
              pins: _sortedPins(),
              selected: _selectedPin,
              controller: _controller,
              colors: colors,
              onSelect: _selectPin,
              onClose: () => setState(() => _selectedPin = null),
              onEdit: _selectedPin != null
                  ? () => _enterEditModeFor(_selectedPin!)
                  : null,
              onCopyCoords: () => context.showNotification(
                context.l10n.mapCoordinatesCopied,
                type: QNotificationType.good,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBrowseControls(
    QAppColors colors, {
    bool withPanelToggle = false,
  }) {
    final canDismiss = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return Row(
      children: [
        if (canDismiss) ...[
          _MapControl(
            colors: colors,
            icon: Icons.arrow_back,
            tooltip: context.l10n.commonClose,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          if (withPanelToggle) const SizedBox(width: 8),
        ],
        if (withPanelToggle)
          _MapControl(
            colors: colors,
            icon: _panelOpen
                ? Icons.menu_open_rounded
                : Icons.format_list_bulleted_rounded,
            tooltip: context.l10n.mapTitle,
            active: _panelOpen,
            onTap: () => setState(() => _panelOpen = !_panelOpen),
          ),
        const Spacer(),
        ..._mapControls(colors),
      ],
    );
  }

  /// The control group both hosts share, so a button never means one thing on
  /// the phone and another on the desktop.
  List<Widget> _mapControls(QAppColors colors) {
    return [
      _MapControl(
        colors: colors,
        icon: Icons.place,
        label: '${_controller.pins.length}',
        onTap: null,
      ),
      const SizedBox(width: 8),
      _MapControl(
        colors: colors,
        icon: Icons.my_location,
        tooltip: context.l10n.mapAutoCenter,
        active: _followingMe,
        onTap: _toggleAutoCenter,
      ),
      const SizedBox(width: 8),
      _MapControl(
        colors: colors,
        icon: Icons.settings_remote,
        tooltip: _controller.devicePosition != null
            ? context.l10n.mapTrackFlipper
            : context.l10n.mapNoDeviceLocation,
        active: _followingDevice,
        onTap: _controller.devicePosition == null ? null : _toggleTrackDevice,
      ),
      const SizedBox(width: 8),
      _MapControl(
        colors: colors,
        icon: Icons.refresh,
        tooltip: context.l10n.mapReloadFiles,
        onTap: _controller.loading ? null : _controller.refresh,
      ),
      const SizedBox(width: 8),
      _MapControl(
        colors: colors,
        icon: Icons.settings,
        tooltip: context.l10n.mapSettingsEntry,
        onTap: () => openRoute(context, AppRoute.mapSettings),
      ),
    ];
  }

  Widget _buildPickControls(QAppColors colors) {
    return Row(
      children: [
        _MapControl(
          colors: colors,
          icon: Icons.close,
          tooltip: context.l10n.commonCancel,
          onTap: _saving ? null : _exitPickMode,
        ),
        const Spacer(),
        _MapControl(
          colors: colors,
          icon: Icons.check,
          label: context.l10n.mapSaveLocation,
          active: true,
          onTap: _saving ? null : _savePickedLocation,
        ),
      ],
    );
  }

  // Shared map Stack used by both mobile and desktop layouts
  Widget _buildMapStack(
    QAppColors colors, {
    required bool desktopMode,
    double leftInset = 0,
  }) {
    final picking = _mode == _MapMode.pick;
    // There is no app bar on either host: the floating controls own the top
    // strip, the sheet or the side panel owns the rest, and everything else is
    // inset past them.
    final sheet = (desktopMode || picking)
        ? 0.0
        : kMapSheetThin + MediaQuery.viewPaddingOf(context).bottom;
    final tiles = _settings.resolve(dark: colors.isDark);
    if (_failedTemplate != null && _failedTemplate != tiles.urlTemplate) {
      _failedTemplate = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncNotice(tiles));

    final system = _settings.useSystemMap;
    return Stack(
      children: [
        if (system)
          _buildSystemMap(colors, picking)
        else
          _buildTileMap(colors, tiles, picking),
        if (picking) Positioned.fill(child: _buildPickOverlay(colors)),

        if (!system && tiles.attribution.isNotEmpty)
          Positioned(
            left: leftInset + 6,
            bottom: sheet + 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.card.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: Text(
                  tiles.attribution,
                  style: TextStyle(color: colors.textMuted, fontSize: 9.5),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSystemMap(QAppColors colors, bool picking) {
    final annotations = _buildAnnotations(
      colors,
      hidePinId: picking ? _pickTarget?.localPath : null,
    );
    _ensureMarkerImages(annotations.requests);

    final start = _initialCenter();
    return AppleMap(
      initialCamera: AppleMapCamera(
        latitude: start.latitude,
        longitude: start.longitude,
        zoom: _initialZoom(),
      ),
      style: _settings.systemStyle,
      dark: colors.isDark,
      images: _markers.images,
      annotations: annotations.annotations,
      showsUserLocation:
          _controller.locationStatus == MapLocationStatus.granted,
      onMapCreated: (controller) {
        _systemMap = controller;
        _mapReady = true;
        _maybeAutoCenter();
      },
      onCameraMoved: (camera, byGesture) {
        _systemCamera = camera;
        if (!byGesture) return;
        _userMovedMap = true;
        if (!_settings.autoCenter && !_settings.trackDevice) return;
        _stopFollowing();
      },
      onAnnotationTap: (id) {
        for (final pin in _controller.pins) {
          if (pin.id != id) continue;
          _selectPin(pin);
          return;
        }
      },
      onMapTap: picking ? null : (_, _) => setState(() => _selectedPin = null),
    );
  }

  Widget _buildTileMap(QAppColors colors, MapTileConfig tiles, bool picking) {
    return FlutterMap(
      key: const ValueKey('tiles'),
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _initialCenter(),
        initialZoom: _initialZoom(),
        maxZoom: tiles.maxZoom,
        minZoom: 2,
        backgroundColor: colors.isDark
            ? const Color(0xFF1A1A1A)
            : const Color(0xFFFFFFFF),
        onMapReady: () {
          _mapReady = true;
          _maybeAutoCenter();
        },
        onPositionChanged: (_, hasGesture) {
          if (!hasGesture) return;
          _userMovedMap = true;
          if (!_settings.autoCenter && !_settings.trackDevice) return;
          _stopFollowing();
        },
        onTap: picking ? null : (_, _) => setState(() => _selectedPin = null),
      ),
      children: [
        TileLayer(
          key: ValueKey(tiles.urlTemplate),
          tileProvider: _providerFor(tiles.urlTemplate),
          urlTemplate: tiles.urlTemplate,
          errorTileCallback: (_, _, _) => _reportTileFailure(tiles),
          subdomains: tiles.subdomains,
          userAgentPackageName: 'com.doctormobile.app',
          maxZoom: tiles.maxZoom,
          retinaMode:
              tiles.retina &&
              _settings.retina &&
              RetinaMode.isHighDensity(context),
        ),
        MarkerLayer(
          markers: _buildMarkers(
            colors,
            hidePinId: picking ? _pickTarget?.localPath : null,
          ),
        ),
      ],
    );
  }

  /// Everything the map has to say goes through the one app-wide notification:
  /// the missing-key and dead-source notices, and the pick-mode hint. Keyed so
  /// a rebuild does not re-raise a notice that is already up.
  void _syncNotice(MapTileConfig tiles) {
    if (!mounted) return;
    final tileNotices = !_settings.useSystemMap;

    final String? key;
    String message = '';
    var type = QNotificationType.warning;
    VoidCallback? onTap;
    var duration = const Duration(seconds: 3);

    if (_mode == _MapMode.pick) {
      key = 'pick';
      message = context.l10n.mapDragHint;
      type = QNotificationType.info;
    } else if (tileNotices && tiles.missingKey) {
      key = 'key';
      message = context.l10n.mapNeedsKeyTap;
      onTap = () => openRoute(context, AppRoute.mapSettings);
      duration = Duration.zero;
    } else if (tileNotices && _failedTemplate == tiles.urlTemplate) {
      key = 'dead:${tiles.urlTemplate}';
      message = context.l10n.mapSourceNotAnswering(tiles.label);
      onTap = () => openRoute(context, AppRoute.mapSettings);
      duration = Duration.zero;
    } else {
      key = null;
    }

    if (key == _noticeKey) return;
    _noticeKey = key;
    _notice?.close();
    _notice = null;
    if (key == null) return;

    _notice = context.showNotification(
      message,
      type: type,
      duration: duration,
      onTap: onTap,
    );
  }

  NetworkTileProvider _providerFor(String template) {
    if (_tileSource != template || _tileProvider == null) {
      _tileSource = template;
      // Dart's HttpClient leaves maxConnectionsPerHost unbounded, so one pan
      // fires a hundred simultaneous TLS handshakes and the tile CDN drops the
      // overflow mid-handshake. Measured against this network: ~33 parallel
      // connections get through, the rest time out. Six per host, reused.
      _tileProvider = NetworkTileProvider(
        httpClient: RetryClient(
          IOClient(
            HttpClient()
              ..maxConnectionsPerHost = 6
              ..idleTimeout = const Duration(seconds: 30)
              ..connectionTimeout = const Duration(seconds: 15),
          ),
          retries: 3,
          when: (response) =>
              response.statusCode == 429 || response.statusCode >= 500,
          whenError: (error, _) =>
              error is SocketException ||
              error is HttpException ||
              error is TimeoutException,
          delay: (attempt) => Duration(
            milliseconds:
                (400 * math.pow(2, attempt)).round() + _jitter.nextInt(250),
          ),
        ),
      );
    }
    return _tileProvider!;
  }

  static final math.Random _jitter = math.Random();

  /// A single dropped tile means nothing — one stalled connection out of a
  /// screenful. The notice is for a source that has actually stopped answering,
  /// so it needs a run of failures to appear and clears itself once tiles start
  /// arriving again (a quiet spell with no new errors).
  void _reportTileFailure(MapTileConfig tiles) {
    if (_openedAt.elapsed < _tileGracePeriod) return;

    _tileFailures++;
    _tileQuietTimer?.cancel();
    _tileQuietTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      _tileFailures = 0;
      if (_failedTemplate == null) return;
      setState(() => _failedTemplate = null);
    });

    if (_tileFailures < 16 || _failedTemplate == tiles.urlTemplate) return;
    _failedTemplate = tiles.urlTemplate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  List<MapPin> _sortedPins() {
    final sorted = [..._controller.pins];
    sorted.sort((a, b) => a.category.index.compareTo(b.category.index));
    return sorted;
  }

  Widget _buildPickOverlay(QAppColors colors) {
    return IgnorePointer(
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: Icon(Icons.location_on, size: 44, color: colors.accent),
            ),
          ),
          Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  LatLng _initialCenter() {
    if (_mode == _MapMode.pick) {
      final target = _pickTarget;
      if (target?.initialLatitude != null && target?.initialLongitude != null) {
        return LatLng(target!.initialLatitude!, target.initialLongitude!);
      }
      final p = _controller.userPosition;
      if (p != null) return LatLng(p.latitude, p.longitude);
      return const LatLng(20, 0);
    }
    final selected = _selectedPin;
    if (selected != null) return LatLng(selected.latitude, selected.longitude);
    final p = _controller.userPosition;
    if (p != null) return LatLng(p.latitude, p.longitude);
    if (_controller.pins.isNotEmpty) {
      final first = _controller.pins.first;
      return LatLng(first.latitude, first.longitude);
    }
    return const LatLng(20, 0);
  }

  double _initialZoom() {
    if (_mode == _MapMode.pick) return 17;
    if (_selectedPin != null) return 17;
    if (_controller.userPosition != null) return 16;
    if (_controller.pins.isNotEmpty) return 14;
    return 2;
  }

  ({List<AppleMapAnnotation> annotations, List<MapMarkerRequest> requests})
  _buildAnnotations(QAppColors colors, {String? hidePinId}) {
    final annotations = <AppleMapAnnotation>[];
    final requests = <MapMarkerRequest>[];

    final device = _controller.devicePosition;
    if (device != null && device.hasFix) {
      const glyph = Icons.gps_fixed;
      final request = MapMarkerRequest.icon(icon: glyph, color: colors.info);
      requests.add(request);
      annotations.add(
        AppleMapAnnotation(
          id: '__device__',
          latitude: device.latitude,
          longitude: device.longitude,
          imageKey: request.key,
          zIndex: 100,
        ),
      );
    }

    final visiblePins = hidePinId == null
        ? _controller.pins
        : _controller.pins.where((pin) => pin.path != hidePinId).toList();
    for (final entry in _spreadOverlappingPins(visiblePins).entries) {
      final pin = entry.key;
      final selected = _selectedPin?.id == pin.id;
      final request = MapMarkerRequest.asset(
        asset: _assetForPin(pin),
        color: pin.category.color,
        selected: selected,
      );
      requests.add(request);
      annotations.add(
        AppleMapAnnotation(
          id: pin.id,
          latitude: entry.value.latitude,
          longitude: entry.value.longitude,
          imageKey: request.key,
          zIndex: selected ? 50 : 0,
        ),
      );
    }

    return (annotations: annotations, requests: requests);
  }

  void _ensureMarkerImages(List<MapMarkerRequest> requests) {
    if (_markerWorkPending) return;
    final missing = requests
        .where((request) => !_markers.images.containsKey(request.key))
        .toList();
    if (missing.isEmpty) return;

    _markerWorkPending = true;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    unawaited(
      _markers.ensure(missing, pixelRatio: pixelRatio).then((produced) {
        _markerWorkPending = false;
        if (produced && mounted) setState(() {});
      }),
    );
  }

  List<Marker> _buildMarkers(QAppColors colors, {String? hidePinId}) {
    final list = <Marker>[];
    final p = _controller.userPosition;
    if (p != null) {
      final bearing = _controller.userBearingDegrees ?? 0;
      list.add(
        Marker(
          point: LatLng(p.latitude, p.longitude),
          width: 34,
          height: 34,
          child: Container(
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4),
              ],
            ),
            child: Transform.rotate(
              angle: bearing * 3.1415926 / 180,
              child: const Icon(
                Icons.navigation,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      );
    }
    final device = _controller.devicePosition;
    if (device != null && device.hasFix) {
      list.add(
        Marker(
          point: LatLng(device.latitude, device.longitude),
          width: 34,
          height: 34,
          child: Container(
            decoration: BoxDecoration(
              color: colors.info,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4),
              ],
            ),
            child: const Icon(Icons.gps_fixed, color: Colors.white, size: 18),
          ),
        ),
      );
    }
    final visiblePins = hidePinId == null
        ? _controller.pins
        : _controller.pins.where((pin) => pin.path != hidePinId).toList();
    final markerPoints = _spreadOverlappingPins(visiblePins);
    for (final entry in markerPoints.entries) {
      final pin = entry.key;
      final selected = _selectedPin?.id == pin.id;
      final pinColor = pin.category.color;
      list.add(
        Marker(
          point: entry.value,
          width: 42,
          height: 42,
          child: GestureDetector(
            onTap: () => _selectPin(pin),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: pinColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? Colors.white : pinColor,
                  width: selected ? 3 : 2,
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: SvgPicture.asset(
                  _assetForPin(pin),
                  fit: BoxFit.contain,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return list;
  }

  Map<MapPin, LatLng> _spreadOverlappingPins(List<MapPin> pins) {
    final points = <MapPin, LatLng>{};
    final groups = <String, List<MapPin>>{};
    for (final pin in pins) {
      final key =
          '${pin.latitude.toStringAsFixed(5)}:${pin.longitude.toStringAsFixed(5)}';
      groups.putIfAbsent(key, () => <MapPin>[]).add(pin);
    }
    for (final group in groups.values) {
      if (group.length == 1) {
        final pin = group.first;
        points[pin] = LatLng(pin.latitude, pin.longitude);
        continue;
      }
      final centerLat =
          group.map((p) => p.latitude).reduce((a, b) => a + b) / group.length;
      final centerLon =
          group.map((p) => p.longitude).reduce((a, b) => a + b) / group.length;
      final radiusMeters = 10.0 + group.length.clamp(0, 8) * 2.0;
      for (var i = 0; i < group.length; i++) {
        final pin = group[i];
        final angle = (2 * 3.1415926 * i / group.length) - (3.1415926 / 2);
        points[pin] = _offsetLatLng(centerLat, centerLon, radiusMeters, angle);
      }
    }
    return points;
  }

  static LatLng _offsetLatLng(
    double latitude,
    double longitude,
    double meters,
    double angle,
  ) {
    const metersPerDegreeLatitude = 111320.0;
    final latRad = latitude * 3.1415926 / 180;
    final metersPerDegreeLongitude =
        metersPerDegreeLatitude * math.cos(latRad).abs().clamp(0.01, 1.0);
    final latOffset = math.sin(angle) * meters / metersPerDegreeLatitude;
    final lonOffset = math.cos(angle) * meters / metersPerDegreeLongitude;
    return LatLng(latitude + latOffset, longitude + lonOffset);
  }

  static String _assetForPin(MapPin pin) {
    return switch (pin.extension) {
      'sub' => 'assets/ic/fileformat/sub.svg',
      'nfc' => 'assets/ic/fileformat/nfc.svg',
      'rfid' => 'assets/ic/fileformat/rfid.svg',
      'ibtn' => 'assets/ic/fileformat/ibutton.svg',
      _ => pin.category.asset,
    };
  }
}
