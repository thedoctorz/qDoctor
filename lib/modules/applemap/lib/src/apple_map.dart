import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'types.dart';

/// Drives one live [AppleMap]. Handed to the caller by
/// [AppleMap.onMapCreated] and valid until that widget goes away.
class AppleMapController {
  AppleMapController._(this._channel);

  final MethodChannel _channel;
  bool _disposed = false;

  /// Points the map at [camera]. Silently ignored once the widget is gone.
  Future<void> moveCamera(AppleMapCamera camera, {bool animated = true}) =>
      _invoke('moveCamera', {...camera.toMap(), 'animated': animated});

  /// Where the map is looking right now, straight from MapKit.
  ///
  /// [AppleMap.onCameraMoved] is the cheaper way to track this; use it when
  /// there is a reason to distrust the last reported value.
  Future<AppleMapCamera?> camera() async {
    if (_disposed) return null;
    try {
      return AppleMapCamera.fromMap(
        await _channel.invokeMethod<Object?>('camera'),
      );
    } on PlatformException catch (error) {
      debugPrint('[AppleMap] camera failed: $error');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      debugPrint('[AppleMap] $method failed: $error');
    } on MissingPluginException {
      // The view went away between the call and its delivery.
    }
  }

  void _dispose() => _disposed = true;
}

/// The system map, as a Flutter widget.
///
/// MapKit on iOS: no API key, no tile server, no account, and the map people
/// already know from every other app on the phone. It draws the basemap, the
/// system location dot and a set of image annotations — everything else is an
/// ordinary Flutter widget stacked on top.
///
/// Only iOS has an implementation. [AppleMap.isSupported] says so, and callers
/// are expected to check it and fall back rather than have this throw.
class AppleMap extends StatefulWidget {
  const AppleMap({
    super.key,
    required this.initialCamera,
    required this.style,
    required this.images,
    required this.annotations,
    this.dark = false,
    this.showsUserLocation = false,
    this.onMapCreated,
    this.onCameraMoved,
    this.onAnnotationTap,
    this.onMapTap,
  });

  /// True on platforms where this widget draws a real map.
  static bool get isSupported => Platform.isIOS;

  /// Where the map opens. Later moves go through [AppleMapController]; a
  /// change to this value after the map exists is ignored, exactly as an
  /// initial value should be.
  final AppleMapCamera initialCamera;

  final AppleMapStyle style;

  /// Whether to render the basemap in its dark variant.
  final bool dark;

  /// Annotation artwork by key. Pushed to the platform before the annotations
  /// that name it, so a caller cannot get the order wrong.
  final AppleMapImages images;

  final List<AppleMapAnnotation> annotations;

  /// Draws the system location dot, with its own heading and accuracy ring.
  final bool showsUserLocation;

  final void Function(AppleMapController controller)? onMapCreated;

  /// Fires whenever the map settles somewhere new. `byGesture` is true only
  /// when the user moved it, not when [AppleMapController.moveCamera] did.
  final void Function(AppleMapCamera camera, bool byGesture)? onCameraMoved;

  final void Function(String id)? onAnnotationTap;

  /// A tap on the basemap, away from any annotation.
  final void Function(double latitude, double longitude)? onMapTap;

  @override
  State<AppleMap> createState() => _AppleMapState();
}

class _AppleMapState extends State<AppleMap> {
  MethodChannel? _channel;
  AppleMapController? _controller;
  List<AppleMapAnnotation> _pushedAnnotations = const [];
  Set<String> _pushedImageKeys = const {};

  @override
  void didUpdateWidget(AppleMap old) {
    super.didUpdateWidget(old);
    if (_channel == null) return;
    if (widget.style != old.style || widget.dark != old.dark) _pushStyle();
    if (widget.showsUserLocation != old.showsUserLocation) {
      unawaited(
        _controller?._invoke('setShowsUserLocation', {
          'value': widget.showsUserLocation,
        }),
      );
    }
    _pushImages();
    _pushAnnotations();
  }

  @override
  void dispose() {
    _controller?._dispose();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('applemap/view/$id');
    channel.setMethodCallHandler(_onPlatformCall);
    _channel = channel;
    final controller = AppleMapController._(channel);
    _controller = controller;
    _pushImages();
    _pushAnnotations();
    widget.onMapCreated?.call(controller);
  }

  Future<void> _onPlatformCall(MethodCall call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'onCameraMoved':
        final camera = AppleMapCamera.fromMap(args);
        if (camera == null) return;
        final gesture = args is Map && args['gesture'] == true;
        widget.onCameraMoved?.call(camera, gesture);
      case 'onAnnotationTap':
        final id = args is Map ? args['id'] : null;
        if (id is String) widget.onAnnotationTap?.call(id);
      case 'onMapTap':
        if (args is! Map) return;
        final latitude = args['latitude'];
        final longitude = args['longitude'];
        if (latitude is! num || longitude is! num) return;
        widget.onMapTap?.call(latitude.toDouble(), longitude.toDouble());
    }
  }

  void _pushStyle() => unawaited(
    _controller?._invoke('setStyle', {
      'style': widget.style.name,
      'dark': widget.dark,
    }),
  );

  /// Only ever grows the platform's cache, and only with keys it does not
  /// already hold. Artwork is generated from the theme and the pin category,
  /// so the same handful of keys serve the whole session.
  void _pushImages() {
    final missing = <String, Uint8List>{
      for (final entry in widget.images.entries)
        if (!_pushedImageKeys.contains(entry.key)) entry.key: entry.value,
    };
    if (missing.isEmpty) return;
    _pushedImageKeys = {..._pushedImageKeys, ...missing.keys};
    unawaited(_controller?._invoke('setImages', {'images': missing}));
  }

  void _pushAnnotations() {
    if (listEquals(_pushedAnnotations, widget.annotations)) return;
    _pushedAnnotations = List.unmodifiable(widget.annotations);
    unawaited(
      _controller?._invoke('setAnnotations', {
        'annotations': [
          for (final annotation in widget.annotations) annotation.toMap(),
        ],
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AppleMap.isSupported) return const SizedBox.shrink();
    return UiKitView(
      viewType: 'applemap/view',
      creationParams: <String, Object?>{
        'camera': widget.initialCamera.toMap(),
        'style': widget.style.name,
        'dark': widget.dark,
        'showsUserLocation': widget.showsUserLocation,
      },
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onPlatformViewCreated,
      // Without this the map loses pans and pinches to Flutter's gesture
      // arena, and reads as a picture of a map rather than a map.
      gestureRecognizers: const {
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
    );
  }
}
