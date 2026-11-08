// Tests for the OSRM route preview.
//
// Two things matter here. First, that a failing demo server never becomes an
// error the rider sees — every broken shape has to resolve to null so the
// stop's details still render. Second, that the cache does its job: the OSRM
// usage policy asks for restraint, and a rider shuffling between four markers
// must not fire a request per tap.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:rider_app/services/osrm_service.dart';

/// A well-formed answer for a 3.2 km, 8 minute leg.
String _okBody({double distance = 3200, double duration = 480}) => jsonEncode({
      'code': 'Ok',
      'routes': [
        {
          'geometry': r'_p~iF~ps|U_ulLnnqC_mqNvxq`@',
          'distance': distance,
          'duration': duration,
          'legs': <dynamic>[],
        }
      ],
      'waypoints': <dynamic>[],
    });

const _from = LatLng(7.0731, 125.6128);
const _to = LatLng(7.0900, 125.6200);

void main() {
  group('previewLeg', () {
    test('reads distance, duration and shape out of the response', () async {
      final service = OsrmService(
        client: MockClient((_) async => http.Response(_okBody(), 200)),
      );

      final preview = await service.previewLeg(
        deliveryId: 1,
        from: _from,
        to: _to,
      );

      expect(preview, isNotNull);
      expect(preview!.distanceMeters, 3200);
      expect(preview.durationSeconds, 480);
      expect(preview.polyline, isNotEmpty);
    });

    test('identifies itself, as the OSRM usage policy requires', () async {
      String? agent;
      Uri? requested;

      final service = OsrmService(
        client: MockClient((request) async {
          agent = request.headers['User-Agent'];
          requested = request.url;
          return http.Response(_okBody(), 200);
        }),
      );

      await service.previewLeg(deliveryId: 1, from: _from, to: _to);

      expect(agent, isNotNull);
      expect(agent, contains('YellowRibbonRiderApp'));

      // OSRM takes lng,lat — the opposite order to the rest of the app, and
      // getting it backwards would silently route from the wrong hemisphere.
      expect(
        requested!.path,
        '/route/v1/driving/125.6128,7.0731;125.62,7.09',
      );
      expect(requested!.queryParameters['geometries'], 'polyline');
      expect(requested!.queryParameters['overview'], 'full');
    });

    test('a leg that cannot be measured is null, never an error', () async {
      // Everything the demo server does on a bad day.
      final failures = <String, http.Response>{
        'rate limited': http.Response('Too many requests', 429),
        'server error': http.Response('', 500),
        'no route between the points':
            http.Response(jsonEncode({'code': 'NoRoute'}), 200),
        'empty route list':
            http.Response(jsonEncode({'code': 'Ok', 'routes': []}), 200),
        'no geometry': http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              {'distance': 100, 'duration': 60}
            ],
          }),
          200,
        ),
        'html from a proxy': http.Response('<html>502</html>', 200),
      };

      for (final entry in failures.entries) {
        final service = OsrmService(
          client: MockClient((_) async => entry.value),
        );

        expect(
          await service.previewLeg(deliveryId: 1, from: _from, to: _to),
          isNull,
          reason: entry.key,
        );
      }
    });
  });

  group('caching', () {
    test('tapping the same marker again does not re-request', () async {
      var calls = 0;
      final service = OsrmService(
        client: MockClient((_) async {
          calls++;
          return http.Response(_okBody(), 200);
        }),
      );

      for (var i = 0; i < 4; i++) {
        await service.previewLeg(deliveryId: 7, from: _from, to: _to);
      }

      expect(calls, 1);
    });

    test('each stop is cached separately', () async {
      var calls = 0;
      final service = OsrmService(
        client: MockClient((_) async {
          calls++;
          return http.Response(_okBody(), 200);
        }),
      );

      await service.previewLeg(deliveryId: 1, from: _from, to: _to);
      await service.previewLeg(deliveryId: 2, from: _from, to: _to);
      await service.previewLeg(deliveryId: 1, from: _from, to: _to);

      expect(calls, 2);
    });

    test('shuffling on the spot reuses the cached leg', () async {
      var calls = 0;
      final service = OsrmService(
        client: MockClient((_) async {
          calls++;
          return http.Response(_okBody(), 200);
        }),
      );

      await service.previewLeg(deliveryId: 1, from: _from, to: _to);
      // Roughly 55 m away — a rider standing next to their bike, or GPS
      // jitter. Not worth a second request.
      await service.previewLeg(
        deliveryId: 1,
        from: const LatLng(7.07355, 125.6128),
        to: _to,
      );

      expect(calls, 1);
    });

    test('riding away from the cached origin re-measures the leg', () async {
      var calls = 0;
      final service = OsrmService(
        client: MockClient((_) async {
          calls++;
          return http.Response(_okBody(), 200);
        }),
      );

      await service.previewLeg(deliveryId: 1, from: _from, to: _to);
      // About 1.1 km on. A preview measured back at the store would still
      // claim the full distance, which is the bug this guards.
      await service.previewLeg(
        deliveryId: 1,
        from: const LatLng(7.0831, 125.6128),
        to: _to,
      );

      expect(calls, 2);
    });

    test('starting a delivery drops its superseded estimate', () async {
      var calls = 0;
      final service = OsrmService(
        client: MockClient((_) async {
          calls++;
          return http.Response(_okBody(), 200);
        }),
      );

      await service.previewLeg(deliveryId: 1, from: _from, to: _to);
      service.forget(1);
      await service.previewLeg(deliveryId: 1, from: _from, to: _to);

      expect(calls, 2);
    });

    test('clear empties everything, for a shared handset', () async {
      var calls = 0;
      final service = OsrmService(
        client: MockClient((_) async {
          calls++;
          return http.Response(_okBody(), 200);
        }),
      );

      await service.previewLeg(deliveryId: 1, from: _from, to: _to);
      await service.previewLeg(deliveryId: 2, from: _from, to: _to);
      service.clear();
      await service.previewLeg(deliveryId: 1, from: _from, to: _to);

      expect(calls, 3);
    });
  });

  group('labels', () {
    test('distance switches to metres under a kilometre', () {
      expect(
        const RoutePreview(
          distanceMeters: 640,
          durationSeconds: 0,
          polyline: '',
        ).distanceLabel,
        '640 m',
      );
      expect(
        const RoutePreview(
          distanceMeters: 3240,
          durationSeconds: 0,
          polyline: '',
        ).distanceLabel,
        '3.2 km',
      );
    });

    test('duration reads as a rider would say it', () {
      String label(double seconds) => RoutePreview(
            distanceMeters: 0,
            durationSeconds: seconds,
            polyline: '',
          ).durationLabel;

      expect(label(20), 'under a minute');
      expect(label(480), '8 min');
      expect(label(3600), '1 hr');
      expect(label(4500), '1 hr 15 min');
    });
  });
}
