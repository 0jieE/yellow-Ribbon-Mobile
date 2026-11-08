/// Where the Django backend lives.
///
/// The default is the deployed backend, so a plain `flutter run` or a release
/// build reaches production with no flags. The previous default was a LAN
/// address that only worked from one desk — and a different one from the
/// rider app's, which meant the two apps could disagree about which server
/// they were talking to.
///
/// Point it somewhere else with a compile-time define — no code edit needed:
///
/// ```
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000
/// flutter build apk --debug --dart-define=API_BASE_URL=https://x.trycloudflare.com
/// ```
///
/// `10.0.2.2` is the Android emulator's alias for the host machine —
/// `127.0.0.1` inside the emulator is the emulator itself. On a physical
/// tablet use the laptop's LAN address, or a tunnel URL.
///
/// Overriding to plain `http://` only works in a debug build: the release
/// manifest has no cleartext exemption, by design.
class ApiConfig {
  const ApiConfig._();

  static const String _raw = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://yellow-ribbon-backend.onrender.com',
  );

  /// Base URL with any trailing slash removed, so paths can be concatenated
  /// without producing a double slash.
  static String get baseUrl {
    var value = _raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static Uri uri(String path, [Map<String, dynamic>? query]) {
    final normalised = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalised').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
    );
  }

  /// How long any single request may take before it is abandoned. A tunnel
  /// that has gone stale should surface as an error, not a spinner forever.
  static const Duration timeout = Duration(seconds: 20);

  /// Menu photos carry far more bytes than a JSON call, so uploads get their
  /// own, longer budget.
  static const Duration uploadTimeout = Duration(seconds: 60);
}
