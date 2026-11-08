import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the JWT pair and the role flags that came back with it.
///
/// Tokens go in the platform keystore rather than SharedPreferences — an
/// access token is a bearer credential and should not sit in plaintext.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _kAccess = 'jwt_access';
  static const _kRefresh = 'jwt_refresh';
  static const _kUser = 'auth_user';

  Future<String?> readAccessToken() => _storage.read(key: _kAccess);

  Future<String?> readRefreshToken() => _storage.read(key: _kRefresh);

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  /// Called after a refresh, which returns a new access token only —
  /// the refresh token itself is not rotated by SimpleJWT here.
  Future<void> saveAccessToken(String access) =>
      _storage.write(key: _kAccess, value: access);

  /// The `user` object from the login response, holding `is_customer`,
  /// `is_rider`, `is_admin` and `role`. Cached so [HomeRouter] can decide
  /// where to land without a network round trip on every cold start.
  Future<void> saveUser(Map<String, dynamic> user) =>
      _storage.write(key: _kUser, value: jsonEncode(user));

  Future<Map<String, dynamic>?> readUser() async {
    final raw = await _storage.read(key: _kUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      // Corrupt entry is not worth crashing over; treat it as logged out.
      return null;
    }
  }

  Future<bool> hasSession() async {
    final access = await readAccessToken();
    return access != null && access.isNotEmpty;
  }

  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kUser);
  }
}
