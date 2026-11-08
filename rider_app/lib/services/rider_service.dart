import '../models/dashboard_model.dart';
import 'api_client.dart';

class RiderService {
  RiderService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// `GET /api/rider/dashboard/` — assigned count, completed count, earnings.
  Future<RiderDashboard> fetchDashboard() async {
    final data = await _client.get('/api/rider/dashboard/');
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected dashboard response from the server.');
    }
    return RiderDashboard.fromJson(data);
  }

  /// `PATCH /api/rider/availability/` — the on-duty toggle that drives
  /// `GET /api/admin/riders/available/`.
  Future<bool> setAvailability(bool isAvailable) async {
    final data = await _client.patch(
      '/api/rider/availability/',
      body: {'is_available': isAvailable},
    );
    if (data is Map<String, dynamic> && data['is_available'] is bool) {
      return data['is_available'] as bool;
    }
    // The server echoes the stored value; fall back to what was requested.
    return isAvailable;
  }

  /// `POST /api/rider/location/` — body `{"lat": ..., "lng": ...}`, answered
  /// with 204.
  ///
  /// Deliberately the cheapest call in the system: it overwrites the rider's
  /// coordinates rather than appending a row, and writes no status log. Do
  /// not add work to this path — it fires every few seconds.
  Future<void> pingLocation({
    required double latitude,
    required double longitude,
  }) async {
    await _client.post(
      '/api/rider/location/',
      body: {'lat': latitude, 'lng': longitude},
    );
  }
}
