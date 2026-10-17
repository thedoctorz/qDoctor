/// The system map on Apple platforms, as a Flutter widget.
///
/// MapKit is part of iOS: there is no API key, no tile server and no account
/// behind it, and it is the map people already know from everything else on
/// the phone. This wraps it thinly — basemap, annotations, camera and the
/// system location dot — and leaves everything above it to Flutter.
library;

export 'src/apple_map.dart' show AppleMap, AppleMapController;
export 'src/types.dart'
    show AppleMapAnnotation, AppleMapCamera, AppleMapImages, AppleMapStyle;
