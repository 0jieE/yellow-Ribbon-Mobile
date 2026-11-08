import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'token_storage.dart';

/// A failed API call, carrying the message Django sent.
///
/// The backend answers every error as `{"error": "..."}` with field detail
/// under `fields`, so [message] is always something showable to the admin.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.fields});

  final String message;
  final int? statusCode;
  final Map<String, dynamic>? fields;

  @override
  String toString() => message;
}

/// The refresh token was missing, expired or rejected. The caller should
/// send the admin back to the login screen.
class SessionExpiredException extends ApiException {
  SessionExpiredException([
    super.message = 'Your session has expired. Please log in again.',
  ]) : super(statusCode: 401);
}

/// Talks to the Django backend.
///
/// Responsibilities:
///  - prefix every path with the configured base URL
///  - attach `Authorization: Bearer <access>` when a session exists
///  - on a 401, refresh the access token once and replay the original request
///  - turn transport and HTTP errors into [ApiException] with a readable message
class ApiClient {
  ApiClient({http.Client? client, TokenStorage? tokens})
      : _client = client ?? http.Client(),
        _tokens = tokens ?? TokenStorage();

  /// Shared instance used by the services. Tests construct their own with a
  /// mock [http.Client].
  static final ApiClient instance = ApiClient();

  final http.Client _client;
  final TokenStorage _tokens;

  TokenStorage get tokens => _tokens;

  /// Invoked when the refresh token is no longer usable, so the UI can bounce
  /// to the login screen from wherever it happens to be.
  void Function()? onSessionExpired;

  /// In-flight refresh, shared by every request that 401s at the same time.
  /// Without this, a screen firing several calls at once would send several
  /// refreshes and all but one would race.
  Future<String?>? _refreshInFlight;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _sendJson('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body, bool authenticated = true}) =>
      _sendJson('POST', path, body: body, authenticated: authenticated);

  Future<dynamic> patch(String path, {Object? body}) =>
      _sendJson('PATCH', path, body: body);

  Future<dynamic> delete(String path, {Object? body}) =>
      _sendJson('DELETE', path, body: body);

  /// Multipart upload — used for menu photos on both create and update.
  ///
  /// The request is rebuilt for each attempt rather than reused: a
  /// [http.MultipartRequest] streams its file, and a sent one cannot be
  /// replayed after a 401. Same approach as rider_app's proof upload.
  Future<dynamic> sendFile(
    String method,
    String path, {
    Map<String, String> fields = const {},
    String? field,
    String? filePath,
  }) {
    return _withAuthRetry((headers) async {
      final request = http.MultipartRequest(method, ApiConfig.uri(path))
        ..headers.addAll(headers)
        ..fields.addAll(fields);

      if (field != null && filePath != null) {
        request.files.add(await http.MultipartFile.fromPath(field, filePath));
      }

      final streamed = await _client
          .send(request)
          .timeout(ApiConfig.uploadTimeout);
      return http.Response.fromStream(streamed);
    });
  }

  Future<dynamic> _sendJson(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) {
    final encoded = body == null ? null : jsonEncode(body);

    return _withAuthRetry(
      (headers) async {
        final request = http.Request(method, ApiConfig.uri(path, query))
          ..headers.addAll(headers);
        if (encoded != null) {
          request.headers['Content-Type'] = 'application/json';
          request.body = encoded;
        }

        final streamed = await _client.send(request).timeout(ApiConfig.timeout);
        return http.Response.fromStream(streamed);
      },
      authenticated: authenticated,
    );
  }

  /// Runs [attempt], and on a 401 refreshes the access token once and runs it
  /// again. [attempt] receives the headers to use, so a retry gets the new
  /// token rather than the stale one.
  Future<dynamic> _withAuthRetry(
    Future<http.Response> Function(Map<String, String> headers) attempt, {
    bool authenticated = true,
  }) async {
    final headers = await _headers(authenticated);
    var response = await _guarded(() => attempt(headers));

    if (response.statusCode == 401 && authenticated) {
      final refreshed = await _refreshAccessToken();
      if (refreshed == null) {
        await _tokens.clear();
        onSessionExpired?.call();
        throw SessionExpiredException();
      }
      // Re-read the headers so the replay carries the refreshed token.
      final retryHeaders = await _headers(authenticated);
      response = await _guarded(() => attempt(retryHeaders));
    }

    return _decode(response);
  }

  /// Turns transport failures into [ApiException] with a message that names
  /// the base URL — the single most useful thing to know when the tunnel
  /// address has changed.
  Future<http.Response> _guarded(Future<http.Response> Function() run) async {
    try {
      return await run();
    } on TimeoutException {
      throw ApiException(
        'The server at ${ApiConfig.baseUrl} did not respond in time.',
      );
    } on SocketException {
      throw ApiException(
        'Cannot reach the server at ${ApiConfig.baseUrl}. Check that Django is '
        'running and that the API_BASE_URL is current.',
      );
    } on http.ClientException catch (e) {
      throw ApiException('Network error: ${e.message}');
    }
  }

  Future<Map<String, String>> _headers(bool authenticated) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (authenticated) {
      final access = await _tokens.readAccessToken();
      if (access != null && access.isNotEmpty) {
        headers['Authorization'] = 'Bearer $access';
      }
    }
    return headers;
  }

  /// Exchanges the refresh token for a fresh access token.
  ///
  /// Returns the new access token, or null when the refresh token is absent
  /// or rejected — meaning the session is genuinely over.
  Future<String?> _refreshAccessToken() {
    // Collapse concurrent refreshes into one request.
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<String?> _doRefresh() async {
    final refresh = await _tokens.readRefreshToken();
    if (refresh == null || refresh.isEmpty) return null;

    late final http.Response response;
    try {
      // Deliberately not through _withAuthRetry: a refresh must never trigger
      // another refresh, and it carries no Authorization header.
      response = await _guarded(() async {
        final request = http.Request('POST', ApiConfig.uri('/api/auth/refresh/'))
          ..headers.addAll({
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode({'refresh': refresh});

        final streamed = await _client.send(request).timeout(ApiConfig.timeout);
        return http.Response.fromStream(streamed);
      });
    } on ApiException {
      // Transport failure is not proof the session died — surface it as a
      // failed refresh but leave the stored tokens alone for the next try.
      return null;
    }

    if (response.statusCode != 200) return null;

    try {
      final data = jsonDecode(response.body);
      final access = data is Map ? data['access'] as String? : null;
      if (access == null || access.isEmpty) return null;
      await _tokens.saveAccessToken(access);
      return access;
    } on FormatException {
      return null;
    }
  }

  dynamic _decode(http.Response response) {
    final status = response.statusCode;
    // Django sends UTF-8; http defaults to latin-1 when the charset is not
    // spelled out, which would mangle the peso sign in error messages.
    final body = response.bodyBytes.isEmpty
        ? ''
        : utf8.decode(response.bodyBytes, allowMalformed: true);

    // 204 is the success shape for DELETE /api/menu/{id}/ and for logout.
    if (status == 204 || body.isEmpty) {
      if (status >= 400) throw _errorFor(status, null);
      return null;
    }

    dynamic parsed;
    try {
      parsed = jsonDecode(body);
    } on FormatException {
      // A tunnel that is down, or a Django 500 with DEBUG on, answers with
      // HTML. Do not show the admin a wall of markup.
      if (status >= 400) throw _errorFor(status, null);
      throw ApiException(
        'The server returned an unexpected response (HTTP $status).',
        statusCode: status,
      );
    }

    if (status >= 400) {
      throw _errorFor(status, parsed is Map<String, dynamic> ? parsed : null);
    }

    return parsed;
  }

  ApiException _errorFor(int status, Map<String, dynamic>? payload) {
    final message = payload?['error'];
    if (message is String && message.isNotEmpty) {
      return ApiException(
        message,
        statusCode: status,
        fields: payload?['fields'] is Map<String, dynamic>
            ? payload!['fields'] as Map<String, dynamic>
            : null,
      );
    }
    return ApiException(_genericMessage(status), statusCode: status);
  }

  String _genericMessage(int status) {
    switch (status) {
      case 401:
        return 'Your session has expired. Please log in again.';
      case 403:
        return 'You do not have permission to do that.';
      case 404:
        return 'That was not found.';
      case 409:
        return 'That conflicts with existing data.';
      case 502:
      case 503:
        return 'The server is unavailable. Please try again shortly.';
      default:
        return status >= 500
            ? 'The server ran into a problem (HTTP $status).'
            : 'Request failed (HTTP $status).';
    }
  }
}
