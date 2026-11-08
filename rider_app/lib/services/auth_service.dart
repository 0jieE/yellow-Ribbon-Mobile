import '../models/user_model.dart';
import 'api_client.dart';

/// Raised when a valid account signs in that is not a rider.
///
/// The credentials were correct, so this is not an authentication failure —
/// it is the wrong app for that account. The stored session is discarded
/// before this is thrown.
class NotARiderException extends ApiException {
  NotARiderException(this.role)
      : super(
          'That is a $role account. Please use the $role app.',
          statusCode: 403,
        );

  final String role;
}

class AuthService {
  AuthService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// `POST /api/auth/login/`
  ///
  /// SimpleJWT authenticates on `username`, not email — the Django user model
  /// leaves `USERNAME_FIELD` as the default.
  ///
  /// Every rider endpoint is guarded by `IsRiderUser`, so a non-rider account
  /// would sign in successfully and then be refused by each screen in turn.
  /// It is rejected here instead, and its tokens are not kept.
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

    final user = AppUser.fromJson(userJson);

    if (!user.isRider) {
      await _client.tokens.clear();
      throw NotARiderException(user.role);
    }

    await _client.tokens.saveTokens(access: access, refresh: refresh);
    await _client.tokens.saveUser(userJson);

    return user;
  }

  /// `GET /api/auth/me/` — the live profile, including the rider record.
  Future<AppUser> me() async {
    final data = await _client.get('/api/auth/me/');
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
