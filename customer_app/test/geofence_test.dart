// The map picker shows the customer whether their pin is inside the delivery
// zone before they submit. That hint is only useful if it agrees with the
// check the server actually runs, so these expectations are reference values
// produced by the backend's own `core.geofence.haversine_km` — not by the
// Dart implementation under test.

import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/customer/map_picker_screen.dart';

void main() {
  // config/settings.py defaults: Kidapawan City, 8 km radius.
  const centreLat = 7.0083;
  const centreLng = 125.0894;

  double fromCentre(double lat, double lng) =>
      haversineKm(centreLat, centreLng, lat, lng);

  test('a pin on the service centre is zero km away', () {
    expect(fromCentre(centreLat, centreLng), 0);
  });

  test('matches the backend haversine to within a metre', () {
    // (point, kilometres) straight out of core/geofence.py.
    const cases = <List<double>>[
      [7.05, 125.12, 5.736230258350884],
      [7.2, 125.3, 31.53372356437127],
      [6.9, 125.0, 15.568933884973623],
      [14.5995, 120.9842, 955.6322328403904], // Manila
    ];

    for (final c in cases) {
      expect(
        fromCentre(c[0], c[1]),
        closeTo(c[2], 0.001),
        reason: 'distance to ${c[0]}, ${c[1]}',
      );
    }
  });

  test('the 8 km radius admits nearby points and rejects distant ones', () {
    const radiusKm = 8.0;

    expect(fromCentre(7.05, 125.12) <= radiusKm, isTrue);
    expect(fromCentre(7.2, 125.3) <= radiusKm, isFalse);
    expect(fromCentre(14.5995, 120.9842) <= radiusKm, isFalse);
  });

  test('distance is symmetric', () {
    expect(
      haversineKm(centreLat, centreLng, 7.05, 125.12),
      closeTo(haversineKm(7.05, 125.12, centreLat, centreLng), 1e-9),
    );
  });
}
