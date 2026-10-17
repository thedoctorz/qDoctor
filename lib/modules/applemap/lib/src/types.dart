import 'dart:typed_data';

/// Where the map is looking. Zoom is the web-mercator tile zoom every other
/// map in this app is expressed in; the native side converts it to a MapKit
/// span so callers never have to think in metres.
class AppleMapCamera {
  const AppleMapCamera({
    required this.latitude,
    required this.longitude,
    required this.zoom,
  });

  final double latitude;
  final double longitude;
  final double zoom;

  Map<String, Object?> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
    'zoom': zoom,
  };

  static AppleMapCamera? fromMap(Object? value) {
    if (value is! Map) return null;
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    final zoom = value['zoom'];
    if (latitude is! num || longitude is! num || zoom is! num) return null;
    return AppleMapCamera(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      zoom: zoom.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppleMapCamera &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(latitude, longitude, zoom);
}

/// The basemap MapKit draws. These are the map types the system offers; there
/// is no styling beyond them, which is rather the point of using it.
enum AppleMapStyle {
  standard,

  /// Standard with the colour turned down, so overlaid pins carry the screen.
  muted,
  satellite,
  hybrid;

  static AppleMapStyle parse(String? raw) => AppleMapStyle.values.firstWhere(
    (value) => value.name == raw,
    orElse: () => AppleMapStyle.standard,
  );
}

/// One pin. [imageKey] names artwork registered through [AppleMap.images]
/// rather than carrying it, so moving or reselecting a pin costs a string.
class AppleMapAnnotation {
  const AppleMapAnnotation({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.imageKey,
    this.zIndex = 0,
  });

  final String id;
  final double latitude;
  final double longitude;
  final String imageKey;
  final int zIndex;

  Map<String, Object?> toMap() => {
    'id': id,
    'latitude': latitude,
    'longitude': longitude,
    'imageKey': imageKey,
    'zIndex': zIndex,
  };

  @override
  bool operator ==(Object other) =>
      other is AppleMapAnnotation &&
      other.id == id &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.imageKey == imageKey &&
      other.zIndex == zIndex;

  @override
  int get hashCode => Object.hash(id, latitude, longitude, imageKey, zIndex);
}

/// Artwork for annotations, keyed by the name [AppleMapAnnotation.imageKey]
/// refers to. PNG bytes at the device's own pixel ratio.
typedef AppleMapImages = Map<String, Uint8List>;
