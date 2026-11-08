import 'api_client.dart';

/// `GET /api/constants/` — the single source of truth all three apps read,
/// so the delivery fee and service area are never hardcoded client-side.
class AppConstants {
  AppConstants({
    required this.deliveryFee,
    required this.serviceAreaCity,
    required this.serviceAreaRadiusKm,
    required this.serviceAreaCenterLat,
    required this.serviceAreaCenterLng,
  });

  final double deliveryFee;
  final String serviceAreaCity;
  final double serviceAreaRadiusKm;

  /// Centre of the delivery zone the backend geofences against. The map
  /// picker opens here and draws the radius around it.
  final double serviceAreaCenterLat;
  final double serviceAreaCenterLng;

  factory AppConstants.fromJson(Map<String, dynamic> json) {
    final area = json['service_area'];
    final areaMap = area is Map<String, dynamic> ? area : const {};
    return AppConstants(
      deliveryFee: _toDouble(json['delivery_fee']),
      serviceAreaCity: (areaMap['city'] ?? 'the service area') as String,
      serviceAreaRadiusKm: _toDouble(areaMap['radius_km']),
      serviceAreaCenterLat: _toDouble(areaMap['center_lat']),
      serviceAreaCenterLng: _toDouble(areaMap['center_lng']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}

class ConstantsService {
  ConstantsService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// The last good answer, kept only as a fallback.
  ///
  /// The store admin edits the delivery fee and service area at runtime, so
  /// every screen that opens re-reads them rather than trusting a value from
  /// app launch. The server recomputes the fee on placement regardless.
  static AppConstants? _lastGood;

  Future<AppConstants> fetch() async {
    try {
      final data = await _client.get('/api/constants/');
      if (data is! Map<String, dynamic>) {
        throw ApiException('Unexpected constants response from the server.');
      }
      return _lastGood = AppConstants.fromJson(data);
    } on ApiException {
      final fallback = _lastGood;
      if (fallback != null) return fallback;
      rethrow;
    }
  }
}
