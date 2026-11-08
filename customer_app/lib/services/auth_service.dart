import '../models/user_model.dart';
import 'api_client.dart';

/// Registration, login and the cached profile.
class AuthService {
  AuthService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// `POST /api/auth/login/`
  ///
  /// SimpleJWT authenticates on `username`, not email — the Django user model
  /// leaves `USERNAME_FIELD` as the default. Stores both tokens plus the role
  /// flags that come back alongside them.
  Future<AppUser> login({
    required String username,
    required String password,
  }) async {
    final data = await _client.post(
      '/api/auth/login/',
      body: {'username': username, 'password': password},
      authenticated: false,
    );

    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected login response from the server.');
    }

    final access = data['access'] as String?;
    final refresh = data['refresh'] as String?;
    if (access == null || refresh == null) {
      throw ApiException('The server did not return a usable session.');
    }

    final userJson = data['user'];
    if (userJson is! Map<String, dynamic>) {
      throw ApiException('The server did not return a user profile.');
    }

    await _client.tokens.saveTokens(access: access, refresh: refresh);
    await _client.tokens.saveUser(userJson);

    return AppUser.fromJson(userJson);
  }

  /// `POST /api/auth/register/` — customer self-registration.
  ///
  /// Returns the created user but no tokens: the endpoint answers 201 with a
  /// profile only, so the caller logs in afterwards to obtain a session.
  Future<AppUser> register({
    required String username,
    required String password,
    required String passwordConfirm,
    String firstName = '',
    String lastName = '',
    String phone = '',
  }) async {
    final data = await _client.post(
      '/api/auth/register/',
      body: {
        'username': username,
        'password': password,
        'password_confirm': passwordConfirm,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
      },
      authenticated: false,
    );

    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected registration response from the server.');
    }
    return AppUser.fromJson(data);
  }

  /// `GET /api/auth/me/` — the live profile, including the saved default
  /// address and its coordinates.
  Future<AppUser> me() async {
    final data = await _client.get('/api/auth/me/');
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected profile response from the server.');
    }
    await _client.tokens.saveUser(data);
    return AppUser.fromJson(data);
  }

  /// `PATCH /api/auth/me/`
  ///
  /// `MeSerializer` accepts `first_name`, `last_name`, `phone`, and
  /// the customer profile as a nested write. `username` is read-only, and
  /// there is no password field — changing a password needs an endpoint the
  /// backend does not currently expose.
  ///
  /// Only the arguments supplied are sent, so a partial edit cannot blank a
  /// field it did not touch.
  Future<AppUser> updateProfile({
    String? firstName,
    String? lastName,
    String? phone,
    String? defaultAddress,
    String? defaultLatitude,
    String? defaultLongitude,
  }) async {
    final customer = <String, dynamic>{
      'default_address': ?defaultAddress,
      'default_latitude': ?defaultLatitude,
      'default_longitude': ?defaultLongitude,
    };

    final data = await _client.patch(
      '/api/auth/me/',
      body: <String, dynamic>{
        'first_name': ?firstName,
        'last_name': ?lastName,
        'phone': ?phone,
        if (customer.isNotEmpty) 'customer': customer,
      },
    );

    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected profile response from the server.');
    }

    await _client.tokens.saveUser(data);
    return AppUser.fromJson(data);
  }

  /// The profile cached at login, for deciding the landing screen without a
  /// network call. Null when logged out.
  Future<AppUser?> cachedUser() async {
    final json = await _client.tokens.readUser();
    return json == null ? null : AppUser.fromJson(json);
  }

  Future<bool> hasSession() => _client.tokens.hasSession();

  /// `POST /api/auth/logout/` drops the device's FCM registration. The JWT
  /// itself stays valid until it expires, so the stored copy is discarded
  /// locally whether or not the call succeeds.
  ///
  /// The server deletes EVERY token the user has when no `fcm_token` is
  /// sent — which would silence the same account on any other phone. So
  /// this device's token is always named, and with none there is nothing
  /// of ours to drop and the call is skipped.
  Future<void> logout({String? fcmToken}) async {
    try {
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await _client.post(
          '/api/auth/logout/',
          body: {'fcm_token': fcmToken},
        );
      }
    } on ApiException {
      // Logging out must work offline and with an already-dead token.
    }
    await _client.tokens.clear();
  }
}
