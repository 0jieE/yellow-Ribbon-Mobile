import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:http/http.dart' as http;

/// One driving leg as OSRM measured it.
///
/// Deliberately an *estimate*. The committed route is the one the backend
/// writes from the Google Routes API when a delivery goes `in_transit`; this
/// is only there to help the rider decide which stop to do next.
class RoutePreview {
  const RoutePreview({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.polyline,
  });

  final double distanceMeters;
  final double durationSeconds;

  /// Google-format encoded polyline — the same encoding `route_polyline`
  /// uses, so `RoutePath.decode` handles both.
  final String polyline;

  String get distanceLabel => distanceMeters < 1000
      ? "${distanceMeters.round()} m"
      : "${(distanceMeters / 1000).toStringAsFixed(1)} km";

  String get durationLabel {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 1) return "under a minute";
    if (minutes < 60) return "$minutes min";
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? "$hours hr" : "$hours hr $rest min";
  }
}

/// Previews a leg from the rider's current position to a stop, using the
/// public OSRM demo server.
///
/// Why not the backend: the ETA the backend computes is a committed
/// origin-to-destination leg written once, when the delivery starts. A rider
/// holding four bags wants to compare stops *before* committing to one, and
/// there is no endpoint for that. OSRM answers it client-side without
/// spending Google Routes quota on a number nobody has agreed to yet.
///
/// The demo server is a courtesy service with no SLA. Every failure mode —
/// down, rate-limited, no route, malformed — resolves to null, and the caller
/// shows the stop without distance and duration. It is never an error state.
class OsrmService {
  OsrmService({http.Client? client}) : _client = client ?? http.Client();

  static final OsrmService instance = OsrmService();

  final http.Client _client;

  static const _host = 'router.project-osrm.org';

  /// The OSRM usage policy requires a real, identifying User-Agent, and
  /// blocks clients that omit one or impersonate a browser. This names the
  /// app and the project so the operators can find us if we misbehave.
  static const _userAgent =
      'YellowRibbonRiderApp/1.0 (Flutter; capstone delivery project; '
      'https://github.com/jayarlopez1264-spec/yellowribbonpizza)';

  /// The demo server asks for no more than about one request a second. A tap
  /// on a marker is well inside that, but the timeout keeps a slow reply from
  /// leaving the sheet spinning.
  static const _timeout = Duration(seconds: 12);

  /// Previews are cached per delivery, keyed on the stop, so tapping between
  /// four markers costs four requests rather than one per tap.
  final Map<int, _CachedLeg> _cache = {};

  /// How far the rider may move before a cached leg is re-measured.
  ///
  /// The cache is keyed on the delivery, but the *origin* is the rider, and
  /// they are moving. Without this, a preview measured at the store would
  /// still claim 3.2 km after the rider had driven most of it. 250 m is short
  /// enough that the number stays honest and long enough that shuffling
  /// between markers at one spot never re-requests.
  static const double _staleAfterMetres = 250;

  /// Distance, duration and shape for the leg, or null when OSRM could not
  /// answer. Never throws.
  Future<RoutePreview?> previewLeg({
    required int deliveryId,
    required LatLng from,
    required LatLng to,
  }) async {
    final cached = _cache[deliveryId];
    if (cached != null && !cached.isStaleFrom(from)) return cached.preview;

    final uri = Uri.https(
      _host,
      // OSRM takes lng,lat — the opposite order to everything else here.
      '/route/v1/driving/'
          '${from.longitude},${from.latitude};'
          '${to.longitude},${to.latitude}',
      const {'overview': 'full', 'geometries': 'polyline'},
    );

    try {
      final response = await _client
          .get(uri, headers: const {
            'User-Agent': _userAgent,
            'Accept': 'application/json',
          })
          .timeout(_timeout);

      if (response.statusCode != 200) {
        _log('HTTP ${response.statusCode} for delivery $deliveryId');
        return null;
      }

      final preview = _parse(response.body);
      if (preview == null) return null;

      _cache[deliveryId] = _CachedLeg(preview: preview, origin: from);
      return preview;
    } on TimeoutException {
      _log('timed out for delivery $deliveryId');
      return null;
    } on SocketException {
      _log('no connection for delivery $deliveryId');
      return null;
    } on http.ClientException catch (e) {
      _log('client error for delivery $deliveryId: ${e.message}');
      return null;
    }
  }

  RoutePreview? _parse(String body) {
    dynamic data;
    try {
      data = jsonDecode(body);
    } on FormatException {
      _log('unparseable response body');
      return null;
    }

    if (data is! Map) return null;

    // OSRM answers 200 with code "NoRoute" when the points cannot be joined
    // by road — an island, or a coordinate that landed in the sea.
    final code = data['code'];
    if (code != 'Ok') {
      _log('OSRM answered code=$code');
      return null;
    }

    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) return null;

    final route = routes.first;
    if (route is! Map) return null;

    final geometry = route['geometry'];
    if (geometry is! String || geometry.isEmpty) return null;

    return RoutePreview(
      distanceMeters: _toDouble(route['distance']),
      durationSeconds: _toDouble(route['duration']),
      polyline: geometry,
    );
  }

  /// Drops a cached leg. Called once a delivery starts for real, because the
  /// backend's committed route supersedes the estimate.
  void forget(int deliveryId) => _cache.remove(deliveryId);

  /// Clears everything — used on logout so one rider's legs are not shown to
  /// the next person to sign in on a shared handset.
  void clear() => _cache.clear();

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  void _log(String message) => debugPrint('[OSRM] $message');
}

class _CachedLeg {
  const _CachedLeg({required this.preview, required this.origin});

  final RoutePreview preview;

  /// Where the rider was when this was measured.
  final LatLng origin;

  bool isStaleFrom(LatLng now) =>
      _metresBetween(origin, now) > OsrmService._staleAfterMetres;

  /// Equirectangular approximation — accurate well past the few hundred
  /// metres this is comparing, and it avoids the trig of a full haversine on
  /// a check that runs on every marker tap.
  static double _metresBetween(LatLng a, LatLng b) {
    const metresPerDegreeLat = 111320.0;

    final dLat = (b.latitude - a.latitude) * metresPerDegreeLat;
    // A degree of longitude shrinks towards the poles; without this the
    // check would over-report east-west movement.
    final dLng = (b.longitude - a.longitude) *
        metresPerDegreeLat *
        math.cos(a.latitude * math.pi / 180.0);

    return math.sqrt(dLat * dLat + dLng * dLng);
  }
}
