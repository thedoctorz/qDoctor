import 'package:applemap/applemap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctormobile/pages/archive/map/data/settings.dart';

void main() {
  group('AppleMapCamera', () {
    test('serializes the three fields the platform reads', () {
      const camera = AppleMapCamera(
        latitude: 48.8584,
        longitude: 2.2945,
        zoom: 16.5,
      );
      expect(camera.toMap(), {
        'latitude': 48.8584,
        'longitude': 2.2945,
        'zoom': 16.5,
      });
    });

    test('round-trips through its own map', () {
      const camera = AppleMapCamera(latitude: -33.8, longitude: 151.2, zoom: 9);
      expect(AppleMapCamera.fromMap(camera.toMap()), camera);
    });

    test('accepts the ints the platform channel may hand back', () {
      final camera = AppleMapCamera.fromMap({
        'latitude': 48,
        'longitude': 2,
        'zoom': 16,
      });
      expect(camera, isNotNull);
      expect(camera!.latitude, 48.0);
      expect(camera.zoom, 16.0);
    });

    test('rejects anything that is not a camera', () {
      expect(AppleMapCamera.fromMap(null), isNull);
      expect(AppleMapCamera.fromMap('nope'), isNull);
      expect(AppleMapCamera.fromMap({'latitude': 1, 'longitude': 2}), isNull);
    });
  });

  group('AppleMapAnnotation', () {
    test('carries an image key rather than the image', () {
      const annotation = AppleMapAnnotation(
        id: 'pin-1',
        latitude: 1.5,
        longitude: -2.5,
        imageKey: 'assets/ic/fileformat/sub.svg|ff00ff00|true',
        zIndex: 50,
      );
      expect(annotation.toMap(), {
        'id': 'pin-1',
        'latitude': 1.5,
        'longitude': -2.5,
        'imageKey': 'assets/ic/fileformat/sub.svg|ff00ff00|true',
        'zIndex': 50,
      });
    });

    test('compares by value, so an unchanged list is not re-sent', () {
      const a = AppleMapAnnotation(
        id: 'p',
        latitude: 1,
        longitude: 2,
        imageKey: 'k',
      );
      const b = AppleMapAnnotation(
        id: 'p',
        latitude: 1,
        longitude: 2,
        imageKey: 'k',
      );
      const selected = AppleMapAnnotation(
        id: 'p',
        latitude: 1,
        longitude: 2,
        imageKey: 'k:selected',
      );
      expect(a, b);
      expect(a, isNot(selected));
    });
  });

  group('AppleMapStyle', () {
    test('parses its own names', () {
      for (final style in AppleMapStyle.values) {
        expect(AppleMapStyle.parse(style.name), style);
      }
    });

    test('falls back to standard for anything else', () {
      expect(AppleMapStyle.parse(null), AppleMapStyle.standard);
      expect(AppleMapStyle.parse('terrain'), AppleMapStyle.standard);
    });
  });

  group('MapEngine', () {
    test('parses its own names', () {
      expect(MapEngine.parse('system'), MapEngine.system);
      expect(MapEngine.parse('tiles'), MapEngine.tiles);
    });

    test('an unset or unknown preference follows what the platform has', () {
      final expected = MapEngine.systemAvailable
          ? MapEngine.system
          : MapEngine.tiles;
      expect(MapEngine.parse(null), expected);
      expect(MapEngine.parse('mapbox'), expected);
    });

    test('the system map is only ever offered where it exists', () {
      expect(MapEngine.systemAvailable, AppleMap.isSupported);
    });
  });
}
