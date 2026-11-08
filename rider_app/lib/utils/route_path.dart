import 'dart:math' as math;

import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    show LatLng, LatLngBounds;

/// Helpers for the `route_polyline` the backend stores on a delivery.
///
/// The value is Google's encoded polyline, written when a delivery goes
/// `in_transit` and empty before that — which is the normal state for most of
/// an order's life, not an error.
class RoutePath {
  const RoutePath._();

  static const _earthRadiusKm = 6371.0088;

  /// The closest the camera is allowed to sit out.
  ///
  /// Fitting a whole route can zoom far enough out that street names stop
  /// rendering, which is useless for finding a door. Anything wider than this
  /// is clamped; the zoom controls are on, so pulling back is one tap away.
  static const double minZoom = 16;

  /// Middle of a bounding box, for re-centring after a clamp.
  static LatLng centreOf(LatLngBounds bounds) => LatLng(
        (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
        (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
      );

  /// A camera target that renders [point] [byPixels] higher up the screen
  /// than it would sit if it were the target itself.
  ///
  /// Used to keep a tapped stop clear of the sheet covering the bottom of the
  /// map. Done as an offset target rather than by inflating the map's
  /// `padding`, because padding also decides where the SDK draws the zoom and
  /// my-location buttons — padding far enough to lift the pin would push
  /// those behind the sheet.
  ///
  /// Only present in the rider app: customer_app has no multi-stop map.
  static LatLng raisePin(
    LatLng point, {
    required double byPixels,
    required double zoom,
  }) {
    if (byPixels.abs() < 1) return point;

    // Web Mercator: the world is 256·2^zoom logical pixels across, and a
    // degree of latitude covers fewer pixels the further north you are.
    final degreesPerPixel = 360 /
        (256 * math.pow(2, zoom)) *
        math.cos(point.latitude * math.pi / 180);

    // Moving the camera target south lifts a fixed point up the screen.
    return LatLng(
      point.latitude - byPixels * degreesPerPixel,
      point.longitude,
    );
  }

  /// Decodes the encoded polyline into map points.
  ///
  /// Returns an empty list for null, empty, or unparseable input, so callers
  /// can treat "no route yet" and "bad data" the same way — neither should
  /// break the map.
  static List<LatLng> decode(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) return const [];

    try {
      return PolylinePoints.decodePolyline(encoded)
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList(growable: false);
    } on Exception {
      return const [];
    }
  }

  /// Road distance along the decoded route, in kilometres.
  ///
  /// Summed from the polyline rather than read from the API: the Routes
  /// response carries `distanceMeters`, but the backend does not persist it,
  /// so it never reaches the apps. Because the polyline follows the road this
  /// is road distance, not straight-line — accurate to within the resolution
  /// of the encoded path.
  static double distanceKm(List<LatLng> points) {
    if (points.length < 2) return 0;

    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += _haversineKm(points[i - 1], points[i]);
    }
    return total;
  }

  static double _haversineKm(LatLng a, LatLng b) {
    double toRadians(double degrees) => degrees * math.pi / 180.0;

    final phi1 = toRadians(a.latitude);
    final phi2 = toRadians(b.latitude);
    final dPhi = toRadians(b.latitude - a.latitude);
    final dLambda = toRadians(b.longitude - a.longitude);

    final h = math.pow(math.sin(dPhi / 2), 2) +
        math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(dLambda / 2), 2);

    return 2 * _earthRadiusKm * math.asin(math.sqrt(h));
  }

  /// A box covering every point given, or null when there is nothing to fit.
  ///
  /// Returns null for a box too small to zoom to — the SDK will not animate
  /// to a zero-area bounds — so callers can fall back to centring instead.
  static LatLngBounds? bounds(Iterable<LatLng> points) {
    if (points.isEmpty) return null;

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    if ((maxLat - minLat).abs() < 0.0005 &&
        (maxLng - minLng).abs() < 0.0005) {
      return null;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }
}
