// Tests for decoding `route_polyline`.
//
// The empty case is the important one: the backend writes the polyline only
// when a delivery goes in_transit, and the model column defaults to "" — so
// "no route yet" arrives as an empty string, not null, for most of an order's
// life. That must render a map without a route, never an error.

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import 'package:rider_app/utils/route_path.dart';

void main() {
  // Google's own reference example from the encoded polyline spec.
  const encoded = r'_p~iF~ps|U_ulLnnqC_mqNvxq`@';

  group('decode', () {
    test('decodes the reference polyline to its three points', () {
      final points = RoutePath.decode(encoded);

      expect(points, hasLength(3));
      expect(points[0].latitude, closeTo(38.5, 0.0001));
      expect(points[0].longitude, closeTo(-120.2, 0.0001));
      expect(points[1].latitude, closeTo(40.7, 0.0001));
      expect(points[1].longitude, closeTo(-120.95, 0.0001));
      expect(points[2].latitude, closeTo(43.252, 0.0001));
      expect(points[2].longitude, closeTo(-126.453, 0.0001));
    });

    test('an absent route is empty, not an error', () {
      // "" is what the TextField default sends; null guards a missing key.
      expect(RoutePath.decode(''), isEmpty);
      expect(RoutePath.decode('   '), isEmpty);
      expect(RoutePath.decode(null), isEmpty);
    });
  });

  group('distanceKm', () {
    test('is zero for a route that cannot be measured', () {
      expect(RoutePath.distanceKm(const []), 0);
      expect(RoutePath.distanceKm([const LatLng(7.0, 125.0)]), 0);
    });

    test('sums the legs rather than measuring end to end', () {
      // A dog-leg: south then east. Straight-line would be shorter than the
      // path actually driven, which is the whole reason for summing.
      const a = LatLng(7.0000, 125.0000);
      const b = LatLng(7.0100, 125.0000);
      const c = LatLng(7.0100, 125.0100);

      final along = RoutePath.distanceKm(const [a, b, c]);
      final direct = RoutePath.distanceKm(const [a, c]);

      expect(along, greaterThan(direct));
      // ~1.11 km per 0.01° of latitude, twice over.
      expect(along, closeTo(2.22, 0.05));
    });
  });

  group('raisePin', () {
    // Davao, roughly where the service area sits.
    const stop = LatLng(7.0731, 125.6128);

    test('moves the target south so the pin rides up the screen', () {
      final target = RoutePath.raisePin(stop, byPixels: 120, zoom: 16);

      // South, not north. Getting this backwards would drop the pin behind
      // the sheet — the exact bug it exists to avoid — and it cannot be
      // checked without a device, so it is pinned here.
      expect(target.latitude, lessThan(stop.latitude));
      expect(target.longitude, stop.longitude);
    });

    test('shifts by the right amount for the zoom', () {
      // At zoom 16 the world is 256·2^16 px across, so a pixel is about
      // 2.14e-5 degrees; 120 of them is a shade over 0.00255.
      final target = RoutePath.raisePin(stop, byPixels: 120, zoom: 16);

      expect(stop.latitude - target.latitude, closeTo(0.002554, 1e-5));
    });

    test('a wider zoom moves the target further', () {
      final close = RoutePath.raisePin(stop, byPixels: 120, zoom: 16);
      final wide = RoutePath.raisePin(stop, byPixels: 120, zoom: 14);

      // Zoomed out, a pixel covers more ground, so the same nudge in pixels
      // is a bigger nudge in degrees.
      expect(
        stop.latitude - wide.latitude,
        greaterThan(stop.latitude - close.latitude),
      );
    });

    test('a negative shift pushes the pin down instead', () {
      final target = RoutePath.raisePin(stop, byPixels: -120, zoom: 16);

      expect(target.latitude, greaterThan(stop.latitude));
    });

    test('a shift too small to see is left alone', () {
      // Guards the case where the anchor already matches the padded centre.
      expect(RoutePath.raisePin(stop, byPixels: 0, zoom: 16), stop);
      expect(RoutePath.raisePin(stop, byPixels: 0.4, zoom: 16), stop);
    });
  });

  group('bounds', () {
    test('covers every point given', () {
      final bounds = RoutePath.bounds(const [
        LatLng(7.00, 125.00),
        LatLng(7.05, 125.10),
        LatLng(6.98, 125.02),
      ]);

      expect(bounds, isNotNull);
      expect(bounds!.southwest.latitude, closeTo(6.98, 1e-9));
      expect(bounds.southwest.longitude, closeTo(125.00, 1e-9));
      expect(bounds.northeast.latitude, closeTo(7.05, 1e-9));
      expect(bounds.northeast.longitude, closeTo(125.10, 1e-9));
    });

    test('returns null when there is nothing to frame', () {
      // Empty, and a box too small for the SDK to zoom to — callers centre
      // on a single point instead.
      expect(RoutePath.bounds(const []), isNull);
      expect(
        RoutePath.bounds(const [
          LatLng(7.0, 125.0),
          LatLng(7.0, 125.0),
        ]),
        isNull,
      );
    });
  });
}
