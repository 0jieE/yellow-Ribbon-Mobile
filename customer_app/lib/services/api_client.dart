import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'token_storage.dart';

/// A failed API call, carrying the message Django sent.
///
/// The backend answers every error as `{"error": "..."}` with field detail
/// under `fields`, so [message] is always something showable to the customer.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.fields});

  final String message;
  final int? statusCode;
  final Map<String, dynamic>? fields;

  @override
  String toString() => message;
}

/// The refresh token was missing, expired or rejected. The caller should
/// send the customer back to the login screen.
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
  /// Without this, a screen firing three parallel calls would send three
  /// refreshes and two of them would race.
  Future<String?>? _refreshInFlight;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body, bool authenticated = true}) =>
      _send('POST', path, body: body, authenticated: authenticated);

  Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path, {Object? body}) =>
      _send('DELETE', path, body: body);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool authenticated = true,
    bool isRetry = false,
  }) async {
    final response = await _dispatch(
      method,
      path,
      body: body,
      query: query,
      authenticated: authenticated,
    );

    // 401 on an authenticated call means the access token has aged out.
    // Refresh once, then replay. `isRetry` stops this recursing.
    if (response.statusCode == 401 && authenticated && !isRetry) {
      final refreshed = await _refreshAccessToken();
      if (refreshed == null) {
        await _tokens.clear();
        onSessionExpired?.call();
        throw SessionExpiredException();
      }
      return _send(
        method,
        path,
        body: body,
        query: query,
        authenticated: authenticated,
        isRetry: true,
      );
    }

    return _decode(response);
  }

  Future<http.Response> _dispatch(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    required bool authenticated,
  }) async {
    final uri = ApiConfig.uri(path, query);

    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';

    if (authenticated) {
      final access = await _tokens.readAccessToken();
      if (access != null && access.isNotEmpty) {
        headers['Authorization'] = 'Bearer $access';
      }
    }

    final encoded = body == null ? null : jsonEncode(body);

    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (encoded != null) request.body = encoded;

      final streamed = await _client.send(request).timeout(ApiConfig.timeout);
      return await http.Response.fromStream(streamed);
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
      // Deliberately not through _send: a refresh must never trigger another
      // refresh, and it carries no Authorization header.
      response = await _dispatch(
        'POST',
        '/api/auth/refresh/',
        body: {'refresh': refresh},
        authenticated: false,
      );
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
    final body = response.body;

    if (status == 204 || body.isEmpty) {
      return status >= 400 ? throw _errorFor(status, null, body) : null;
    }

    dynamic parsed;
    try {
      parsed = jsonDecode(body);
    } on FormatException {
      // A tunnel that is down, or a Django 500 with DEBUG on, answers with
      // HTML. Do not show the customer a wall of markup.
      if (status >= 400) throw _errorFor(status, null, body);
      throw ApiException(
        'The server returned an unexpected response (HTTP $status).',
        statusCode: status,
      );
    }

    if (status >= 400) {
      throw _errorFor(status, parsed is Map<String, dynamic> ? parsed : null, body);
    }

    return parsed;
  }

  ApiException _errorFor(int status, Map<String, dynamic>? payload, String body) {
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
