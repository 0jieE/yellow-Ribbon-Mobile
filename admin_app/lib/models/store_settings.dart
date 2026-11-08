/// `GET/PATCH /api/admin/store-settings/` — the store's runtime settings.
///
/// These used to be environment variables on the server, so changing the
/// delivery fee meant a redeploy. Now the admin edits them here and the next
/// `/api/constants/` read, order placement and geofence check pick them up.
/// Orders keep the fee they were placed with.
///
/// Decimals arrive as strings and are sent back as strings, exactly as typed,
/// so the server's DecimalField does the rounding — never a double.
class StoreSettings {
  StoreSettings({
    required this.deliveryFee,
    required this.deliveryFeePerKm,
    required this.deliveryFeeMode,
    required this.serviceAreaCity,
    required this.serviceAreaCenterLat,
    required this.serviceAreaCenterLng,
    required this.serviceAreaRadiusKm,
    required this.paymongoFeePercent,
    required this.paymongoFeeFixed,
    required this.mayaFeePercent,
    required this.mayaFeeFixed,
    this.updatedAt,
  });

  /// The flat fee, or the base fee when a per-km rate is set.
  final String deliveryFee;

  /// Added per km of straight-line distance from the store. "0.00" = flat.
  final String deliveryFeePerKm;

  /// Read-only: `flat` or `per_km`, derived from [deliveryFeePerKm].
  final String deliveryFeeMode;

  final String serviceAreaCity;
  final String serviceAreaCenterLat;
  final String serviceAreaCenterLng;
  final String serviceAreaRadiusKm;

  /// What each gateway keeps per online payment. Used to work out what
  /// actually reaches the store in the payments report.
  final String paymongoFeePercent;
  final String paymongoFeeFixed;
  final String mayaFeePercent;
  final String mayaFeeFixed;

  final DateTime? updatedAt;

  bool get isPerKm => deliveryFeeMode == 'per_km';

  factory StoreSettings.fromJson(Map<String, dynamic> json) => StoreSettings(
        deliveryFee: _str(json['delivery_fee']),
        deliveryFeePerKm: _str(json['delivery_fee_per_km']),
        deliveryFeeMode: _str(json['delivery_fee_mode'], fallback: 'flat'),
        serviceAreaCity: _str(json['service_area_city']),
        serviceAreaCenterLat: _str(json['service_area_center_lat']),
        serviceAreaCenterLng: _str(json['service_area_center_lng']),
        serviceAreaRadiusKm: _str(json['service_area_radius_km']),
        paymongoFeePercent: _str(json['paymongo_fee_percent']),
        paymongoFeeFixed: _str(json['paymongo_fee_fixed']),
        mayaFeePercent: _str(json['maya_fee_percent']),
        mayaFeeFixed: _str(json['maya_fee_fixed']),
        updatedAt: DateTime.tryParse('${json['updated_at']}'),
      );
}

String _str(dynamic value, {String fallback = ''}) =>
    value == null ? fallback : '$value';
