import 'dart:io';

import 'api_client.dart';

/// Registers this handset's FCM token with the backend so pushes can reach it.
///
/// `DeviceToken` is keyed on the token, not on (user, token): if another
/// account signs in on this phone the registration moves to them rather than
/// leaving the previous user receiving notifications here.
class DeviceTokenService {
  DeviceTokenService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// `POST /api/device-tokens/` — needs the JWT, so call it after login.
  ///
  /// Field names match `DeviceTokenSerializer`: `fcm_token` (required) and
  /// `platform` (optional, and one of the `DevicePlatform` choices). Returns
  /// the created row, so the caller can log the DeviceToken id it produced.
  Future<dynamic> register(String fcmToken) {
    return _client.post(
      '/api/device-tokens/',
      body: {
        'fcm_token': fcmToken,
        'platform': Platform.isIOS ? 'ios' : 'android',
      },
    );
  }

  /// `DELETE /api/device-tokens/`
  ///
  /// Passing the token drops this device only. Omitting it would drop every
  /// device on the account, which is not what logging out of one phone means.
  Future<void> unregister(String fcmToken) async {
    await _client.delete(
      '/api/device-tokens/',
      body: {'fcm_token': fcmToken},
    );
  }
}
