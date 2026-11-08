import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    show BitmapDescriptor;

/// How a stop pin is drawn.
///
/// A rider holding four bags needs to tell the stops apart at a glance, and
/// the one they have committed to has to stand out from the ones they have
/// only collected. The Maps SDK offers neither — `defaultMarkerWithHue` gives
/// colour but no number — so the pins are painted here.
enum StopPinStyle {
  /// Collected, not yet started. Amber on ink, matching the app.
  held(fill: Color(0xFFFFC107), label: Color(0xFF1F1F1F)),

  /// The one leg actually under way. Only ever one of these — the backend
  /// enforces it with a unique constraint.
  inTransit(fill: Color(0xFF00695C), label: Colors.white),

  /// Currently open in the sheet.
  selected(fill: Color(0xFF1F1F1F), label: Color(0xFFFFC107));

  const StopPinStyle({required this.fill, required this.label});

  final Color fill;
  final Color label;
}

/// Paints numbered map pins, and remembers them.
///
/// Rasterising is not free and the marker set is rebuilt on every poll, so a
/// pin is drawn once per (number, style) pair and reused. A rider carries a
/// handful of stops at a time, so the cache stays tiny.
class NumberedMarker {
  const NumberedMarker._();

  static final Map<String, BitmapDescriptor> _cache = {};

  /// Painted at this many device pixels, then handed to the SDK with a
  /// matching pixel ratio so it lands at roughly 40dp wide — big enough to
  /// read a number in, small enough that four do not cover the map.
  static const double _width = 108;
  static const double _height = 140;
  static const double _pixelRatio = 2.7;

  static Future<BitmapDescriptor> pin({
    required int number,
    required StopPinStyle style,
  }) async {
    final key = '$number:${style.name}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final descriptor = await _paint(number, style);
    _cache[key] = descriptor;
    return descriptor;
  }

  static Future<BitmapDescriptor> _paint(
    int number,
    StopPinStyle style,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    const radius = _width / 2;
    const centre = Offset(radius, radius);

    // Teardrop: a disc with a tail dropping to the point being marked, so
    // the pin's tip sits on the coordinate rather than its middle.
    final tail = Path()
      ..moveTo(radius - 26, radius + 30)
      ..lineTo(radius + 26, radius + 30)
      ..lineTo(radius, _height - 4)
      ..close();

    // White outline first, drawn wider underneath, so the pin reads against
    // both road tiles and dark satellite imagery.
    final outline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(tail, outline);
    canvas.drawCircle(centre, radius - 6, outline);

    final fill = Paint()..color = style.fill;
    canvas.drawPath(tail, fill);
    canvas.drawCircle(centre, radius - 6, fill);

    final painter = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          color: style.label,
          fontSize: 54,
          fontWeight: FontWeight.bold,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    painter.paint(
      canvas,
      Offset(radius - painter.width / 2, radius - painter.height / 2),
    );

    final image = await recorder
        .endRecording()
        .toImage(_width.round(), _height.round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    if (bytes == null) {
      // Nothing sensible to fall back to but the SDK's own pin. Losing the
      // number is far better than losing the marker.
      return BitmapDescriptor.defaultMarker;
    }

    return BitmapDescriptor.bytes(
      bytes.buffer.asUint8List(),
      imagePixelRatio: _pixelRatio,
    );
  }
}
