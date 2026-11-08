import '../models/rider_model.dart';
import 'api_client.dart';

class RiderAdminService {
  RiderAdminService({ApiClient? client})
      : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// `GET /api/admin/riders/` — every rider, ordered by username.
  Future<List<Rider>> fetchAll() => _list('/api/admin/riders/');

  /// `GET /api/admin/riders/available/` — on duty, active account, and not
  /// already mid-delivery. This is what populates the assignment picker.
  Future<List<Rider>> fetchAvailable() =>
      _list('/api/admin/riders/available/');

  Future<List<Rider>> _list(String path) async {
    final data = await _client.get(path);
    final rows = data is Map<String, dynamic> ? data['results'] : data;
    if (rows is! List) {
      throw ApiException('Unexpected riders response from the server.');
    }
    return rows.whereType<Map<String, dynamic>>().map(Rider.fromJson).toList();
  }

  /// `POST /api/admin/riders/`
  ///
  /// The only way a rider account comes into existence — riders cannot self
  /// register, and `/api/auth/register/` creates customers only. The role
  /// flags are set server-side, never taken from this body.
  ///
  /// `username` and `password` are required; the password goes
  /// through Django's validators, so a weak one comes back as a field error.
  /// `is_available` starts false — the rider goes on duty from their own app.
  Future<Rider> create({
    required String username,
    required String password,
    String firstName = '',
    String lastName = '',
    String phone = '',
    String vehicleType = '',
    String plateNumber = '',
  }) async {
    final data = await _client.post(
      '/api/admin/riders/',
      body: {
        'username': username,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'vehicle_type': vehicleType,
        'plate_number': plateNumber,
      },
    );

    return _one(data);
  }

  /// `PATCH /api/admin/riders/{id}/`
  ///
  /// Covers both halves of the account — the User row and the Rider profile —
  /// in one call. Only the fields passed are sent, because the endpoint is a
  /// partial update and a null would be written as a blank.
  ///
  /// `username` is deliberately absent: it is what the rider signs in with,
  /// and the server does not accept it here. `is_available` is the rider's own
  /// on-duty toggle, not the admin's.
  Future<Rider> update(
    int riderId, {
    String? firstName,
    String? lastName,
    String? phone,
    String? vehicleType,
    String? plateNumber,
  }) async {
    // `key: ?value` drops the entry when the value is null, which is what
    // keeps an unspecified field out of the PATCH body entirely rather than
    // sending null and having it stored as a blank.
    final body = <String, dynamic>{
      'first_name': ?firstName,
      'last_name': ?lastName,
      'phone': ?phone,
      'vehicle_type': ?vehicleType,
      'plate_number': ?plateNumber,
    };

    final data = await _client.patch('/api/admin/riders/$riderId/', body: body);
    return _one(data);
  }

  /// `POST /api/admin/riders/{id}/set-password/`
  ///
  /// The only way back in for a locked-out rider — there is no self-service
  /// reset. Django's validators run against the target user, so a password
  /// resembling their own name or email comes back as `fields.password`.
  ///
  /// Answers with `{"detail": "..."}`, not a rider, so nothing is returned.
  Future<void> setPassword(int riderId, String password) async {
    await _client.post(
      '/api/admin/riders/$riderId/set-password/',
      body: {'password': password},
    );
  }

  /// `PATCH /api/admin/riders/{id}/deactivate/`
  ///
  /// Explicit rather than a toggle, so a retried request cannot switch the
  /// account back on. Never a delete: a rider is referenced by every delivery
  /// they ever made.
  ///
  /// Refuses with a 400 naming the orders when the rider is still carrying
  /// work — the caller should show that sentence rather than a generic error.
  Future<Rider> setActive(int riderId, bool isActive) async {
    final data = await _client.patch(
      '/api/admin/riders/$riderId/deactivate/',
      body: {'is_active': isActive},
    );
    return _one(data);
  }

  /// `GET /api/admin/riders/{id}/`
  Future<Rider> fetchOne(int riderId) async =>
      _one(await _client.get('/api/admin/riders/$riderId/'));

  Rider _one(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected rider response from the server.');
    }
    return Rider.fromJson(data);
  }
}
