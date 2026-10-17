import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:applemap/applemap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../services/logging.dart';

class MapMarkerImages {
  MapMarkerImages._();

  static final MapMarkerImages instance = MapMarkerImages._();

  static const double pinSize = 42;

  final Map<String, Uint8List> _images = {};
  final Map<String, Future<void>> _pending = {};

  AppleMapImages get images => Map.unmodifiable(_images);

  static String keyFor({
    required String glyph,
    required Color color,
    required bool selected,
  }) => '$glyph|${color.toARGB32().toRadixString(16)}|$selected';

  Future<bool> ensure(
    Iterable<MapMarkerRequest> requests, {
    required double pixelRatio,
  }) async {
    final work = <Future<void>>[];
    for (final request in requests) {
      final key = request.key;
      if (_images.containsKey(key)) continue;
      work.add(
        _pending.putIfAbsent(
          key,
          () => _build(key, request, pixelRatio).whenComplete(() {
            _pending.remove(key);
          }),
        ),
      );
    }
    if (work.isEmpty) return false;
    await Future.wait(work);
    return true;
  }

  Future<void> _build(
    String key,
    MapMarkerRequest request,
    double pixelRatio,
  ) async {
    try {
      final bytes = await _paint(request, pixelRatio);
      if (bytes != null) _images[key] = bytes;
    } catch (e) {
      LogService.warn('[Map] marker artwork failed for ${request.glyph}: $e');
    }
  }

  Future<Uint8List?> _paint(MapMarkerRequest request, double pixelRatio) async {
    final asset = request.asset;
    final glyph = asset == null
        ? null
        : await vg.loadPicture(SvgAssetLoader(asset), null);
    try {
      final side = pinSize * pixelRatio;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final centre = Offset(side / 2, side / 2);
      final radius = side / 2 - 2 * pixelRatio;

      canvas.drawCircle(
        centre.translate(0, 1 * pixelRatio),
        radius,
        Paint()
          ..color = const Color(0x61000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 * pixelRatio),
      );
      canvas.drawCircle(centre, radius, Paint()..color = request.color);
      if (request.selected) {
        canvas.drawCircle(
          centre,
          radius - 1.5 * pixelRatio,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * pixelRatio,
        );
      }

      final box = side - 8 * pixelRatio * 2;
      if (glyph != null) {
        final scale = glyph.size.isEmpty ? 1.0 : box / glyph.size.longestSide;
        canvas
          ..saveLayer(
            Rect.fromLTWH(0, 0, side, side),
            Paint()
              ..colorFilter = const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
          )
          ..translate(
            (side - glyph.size.width * scale) / 2,
            (side - glyph.size.height * scale) / 2,
          )
          ..scale(scale)
          ..drawPicture(glyph.picture)
          ..restore();
      } else if (request.icon != null) {
        _paintIcon(canvas, request.icon!, box, side);
      }

      final picture = recorder.endRecording();
      try {
        final image = await picture.toImage(side.ceil(), side.ceil());
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          return data?.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      glyph?.picture.dispose();
    }
  }

  void _paintIcon(Canvas canvas, IconData icon, double box, double side) {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: box,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
          height: 1,
        ),
      ),
    )..layout();
    painter.paint(
      canvas,
      Offset((side - painter.width) / 2, (side - painter.height) / 2),
    );
    painter.dispose();
  }
}

class MapMarkerRequest {
  const MapMarkerRequest.asset({
    required String this.asset,
    required this.color,
    this.selected = false,
  }) : icon = null;

  const MapMarkerRequest.icon({
    required IconData this.icon,
    required this.color,
    this.selected = false,
  }) : asset = null;

  final String? asset;
  final IconData? icon;
  final Color color;
  final bool selected;

  String get glyph => asset ?? 'icon:${icon!.codePoint}';

  String get key =>
      MapMarkerImages.keyFor(glyph: glyph, color: color, selected: selected);
}
