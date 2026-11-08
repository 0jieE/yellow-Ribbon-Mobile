import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';
import 'device_token_service.dart';

/// Handles a push that arrives while the app is terminated or backgrounded.
///
/// Must be a top-level (or static) function annotated for AOT retention —
/// the plugin runs it in a separate isolate with no access to the app's
/// state. Android draws the tray notification itself from the `notification`
/// block the server sends, so there is deliberately nothing to do here; the
/// handler exists because the plugin requires one to be registered for
/// background delivery to work at all.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally empty. Do not touch app singletons from this isolate.
}

/// The `data` payload the Django side attaches to every push
/// (see `core/notifications.py`). FCM stringifies every value.
class PushPayload {
  const PushPayload(this.data);

  final Map<String, String> data;

  /// "new_order" | "assigned" | "status_change" | "delivered"
  String get event => data['event'] ?? '';

  String get type => data['type'] ?? '';

  int? get orderId => int.tryParse(data['order_id'] ?? '');

  String get orderNumber => data['order_number'] ?? '';

  String get status => data['status'] ?? '';
}

/// FCM wiring: permission, token registration, and turning a push into a
/// screen.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  final _local = FlutterLocalNotificationsPlugin();
  final _tokens = DeviceTokenService();

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  bool _initialised = false;

  /// Stops two entry points (login and session restore) racing each other.
  bool _registrationInFlight = false;

  /// The token currently registered with the backend, kept so logout can
  /// delete exactly this device rather than all of them.
  String? _registeredToken;

  /// Last outcome of a registration attempt, so it can be surfaced in the UI
  /// or read from a debug screen rather than only existing in logcat.
  final ValueNotifier<String> lastRegistrationStatus =
      ValueNotifier('not attempted');

  /// Invoked when the customer taps a notification, from any app state.
  void Function(PushPayload payload)? onNotificationTap;

  /// Android suppresses the system tray notification while the app is in the
  /// foreground, so foreground pushes are drawn by flutter_local_notifications
  /// through this channel.
  static const _channel = AndroidNotificationChannel(
    'yellowribbon_orders',
    'Order updates',
    description: 'Updates about your Yellow Ribbon Pizza orders.',
    importance: Importance.high,
  );

  /// Everything on the registration path logs through here, prefixed so it
  /// can be isolated with `flutter logs | grep FCM` or
  /// `adb logcat | grep FCM`.
  void _log(String message) {
    debugPrint('[FCM] $message');
  }

  /// Tokens are ~160 characters and are credentials of a sort; log enough to
  /// correlate with the DeviceToken row, not the whole thing.
  String _mask(String token) =>
      token.length <= 16 ? token : '${token.substring(0, 12)}…(${token.length})';

  /// Sets up the plugin and the listeners. Safe to call more than once.
  Future<void> initialize() async {
    if (_initialised) return;
    _initialised = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _local.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Foreground: draw it ourselves.
    _foregroundSub = FirebaseMessaging.onMessage.listen(_showLocal);

    // Backgrounded, then tapped in the tray.
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _route(message.data),
    );

    _log('initialised (channel ${_channel.id})');
  }

  /// Checks whether the app was launched by tapping a notification.
  ///
  /// Call once the navigator exists, otherwise there is nowhere to route to.
  Future<void> handleLaunchNotification() async {
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _route(initial.data);
  }

  /// Requests notification permission, obtains the FCM token, and POSTs it to
  /// `/api/device-tokens/`.
  ///
  /// Call from every authenticated entry point — the login screen *and* a
  /// restored session on cold start. Registration is idempotent server-side
  /// (`update_or_create` keyed on the token), so calling it more than once
  /// costs one request and changes nothing.
  ///
  /// Fire-and-forget by design, so every failure is logged rather than
  /// thrown: a dead push registration must not break signing in.
  Future<void> registerToken({String reason = 'login'}) async {
    if (_registrationInFlight) {
      _log('register($reason): skipped, another attempt is in flight');
      return;
    }
    _registrationInFlight = true;

    try {
      _log('register($reason): starting');

      // Stage 0 — the POST is authenticated, so a JWT has to be stored
      // already. Logging in awaits saveTokens() before calling this, but a
      // caller that got the order wrong would otherwise 401 invisibly.
      final hasSession = await ApiClient.instance.tokens.hasSession();
      if (!hasSession) {
        _fail('no access token stored yet — POST would be unauthenticated');
        return;
      }
      _log('register($reason): access token present');

      // Stage 1 — the token, obtained BEFORE any permission prompt.
      //
      // Ordering matters here. Android permits one runtime permission dialog
      // at a time; a request made while another is on screen is dropped by
      // the system with no callback, leaving firebase_messaging waiting on an
      // onRequestPermissionsResult that never arrives. Asking first therefore
      // made registration depend on a dialog that can silently never resolve.
      //
      // Nothing is lost by asking later: on Android FCM issues a token
      // regardless of POST_NOTIFICATIONS, which only governs whether a
      // notification may be *displayed*. (The usual reason to ask first is
      // iOS, where APNS withholds the token until notifications are
      // authorised — but every Firebase app in this project is Android-only,
      // and DefaultFirebaseOptions has no iOS entry at all.)
      final token = await _obtainToken(reason);
      if (token == null) {
        _fail('could not obtain an FCM token after 3 attempts — $_tokenHint');
        return;
      }

      // Stage 2 — the POST.
      _log('register($reason): POST /api/device-tokens/');
      final created = await _tokens.register(token);
      _registeredToken = token;

      final id = created is Map ? created['id'] : null;
      _succeed('registered${id == null ? '' : ' (DeviceToken id $id)'}');

      _listenForTokenRefresh();

      // Stage 3 — permission, now that the row exists. Deliberately not
      // awaited and allowed to fail: it only decides whether notifications
      // may be shown, and it must never be able to hold up registration.
      unawaited(_requestDisplayPermission(reason));
    } on ApiException catch (e) {
      // Stage 3 failure with the server's own words — a 400 from the
      // serializer or a 401 from a missing/expired JWT lands here.
      _fail('POST failed: HTTP ${e.statusCode ?? '?'} — ${e.message}'
          '${e.fields == null ? '' : ' fields=${e.fields}'}');
    } catch (e, stack) {
      // Deliberately a bare catch: an Error (not just an Exception) from the
      // plugin layer would otherwise vanish into an unawaited future.
      _fail('unexpected ${e.runtimeType}: $e');
      debugPrintStack(stackTrace: stack, label: '[FCM] register($reason)');
    } finally {
      _registrationInFlight = false;
    }
  }

  /// Set from the last `getToken()` failure so the summary line names the
  /// real cause instead of guessing.
  String _tokenHint = 'see the attempt logs above.';

  /// Turns a `getToken()` failure into something actionable.
  ///
  /// The common one is not a device problem at all: FCM cannot issue a token
  /// until Firebase Installations has registered the app, and that call is
  /// authenticated with the Android API key from google-services.json. If
  /// that key is restricted to specific package names and SHA-1 fingerprints
  /// — as the Google Maps setup encourages — every app not on the list gets
  /// FIS_AUTH_ERROR here while the listed one keeps working.
  String _hintFor(Object error) {
    final text = error.toString();

    if (text.contains('FIS_AUTH_ERROR') ||
        text.contains('Installations') ||
        text.contains('AUTHENTICATION_FAILED')) {
      return 'Firebase Installations rejected this app. The Android API key '
          'in google-services.json is almost certainly restricted to other '
          'package names / SHA-1 fingerprints, or its API restrictions do '
          'not include the Firebase Installations API. This is a Google '
          'Cloud console setting, not a device or code fault.';
    }
    if (text.contains('SERVICE_NOT_AVAILABLE') || text.contains('TIMEOUT')) {
      return 'FCM could not be reached — usually a transient network problem. '
          'It will be retried on the next login or app start.';
    }
    if (text.contains('MISSING_INSTANCEID_SERVICE') ||
        text.contains('PlayServices') ||
        text.contains('play services')) {
      return 'Google Play services is missing or out of date on this device.';
    }
    return 'see the attempt logs above.';
  }

  /// Fetches the FCM token, retrying a few times.
  ///
  /// `getToken()` talks to Google Play services over the network, so a cold
  /// start on mobile data can fail transiently with SERVICE_NOT_AVAILABLE and
  /// succeed moments later. Each attempt logs its own outcome so a persistent
  /// failure names its cause rather than collapsing into "returned null".
  Future<String?> _obtainToken(String reason) async {
    const attempts = 3;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final token = await FirebaseMessaging.instance
            .getToken()
            .timeout(const Duration(seconds: 20));

        if (token != null && token.isNotEmpty) {
          _log('register($reason): getToken() ok on attempt $attempt '
              '${_mask(token)}');
          return token;
        }
        _log('register($reason): getToken() returned null on attempt '
            '$attempt/$attempts');
      } on TimeoutException {
        _log('register($reason): getToken() timed out on attempt '
            '$attempt/$attempts');
      } on FirebaseException catch (e) {
        _tokenHint = _hintFor(e);
        _log('register($reason): getToken() failed on attempt $attempt/'
            '$attempts — FirebaseException(${e.code}): ${e.message}');
      } catch (e) {
        _tokenHint = _hintFor(e);
        _log('register($reason): getToken() failed on attempt $attempt/'
            '$attempts — ${e.runtimeType}: $e');
      }

      if (attempt < attempts) {
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
    return null;
  }

  /// Asks for POST_NOTIFICATIONS so notifications can actually be shown.
  ///
  /// Runs after registration and never blocks it. Time-boxed because a
  /// request issued while another plugin's dialog is on screen is dropped by
  /// Android and its result callback never arrives.
  Future<void> _requestDisplayPermission(String reason) async {
    try {
      final settings = await FirebaseMessaging.instance
          .requestPermission()
          .timeout(const Duration(seconds: 30));
      _log('register($reason): permission = '
          '${settings.authorizationStatus.name}');
    } on TimeoutException {
      _log('register($reason): permission request never returned — another '
          'permission dialog probably owns the screen. The token is already '
          'registered; notifications may not display until permission is '
          'granted in system settings.');
    } catch (e) {
      _log('register($reason): permission request failed ($e). The token is '
          'already registered.');
    }
  }

  void _listenForTokenRefresh() {
    // Firebase rotates tokens; a stale one silently stops delivering.
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub =
        FirebaseMessaging.instance.onTokenRefresh.listen((refreshed) async {
      _log('token refreshed by Firebase: ${_mask(refreshed)}');
      try {
        await _tokens.register(refreshed);
        _registeredToken = refreshed;
        _succeed('re-registered after refresh');
      } on ApiException catch (e) {
        _fail('re-register failed: HTTP ${e.statusCode ?? '?'} — ${e.message}');
      } catch (e) {
        _fail('re-register failed: $e');
      }
    });
  }

  void _succeed(String message) {
    lastRegistrationStatus.value = 'ok: $message';
    _log('SUCCESS — $message');
  }

  void _fail(String message) {
    lastRegistrationStatus.value = 'failed: $message';
    _log('FAILED — $message');
  }

  /// Drops this device's registration. Called on logout, before the JWT is
  /// discarded — the DELETE needs it.
  ///
  /// Returns the token it removed (null when there was none), so logout
  /// can name this device rather than letting the server drop them all.
  Future<String?> unregisterToken() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;

    var token = _registeredToken;
    if (token == null) {
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        _log('unregister: getToken() failed ($e)');
      }
    }

    if (token == null || token.isEmpty) {
      _log('unregister: no token to remove');
      return null;
    }

    try {
      await _tokens.unregister(token);
      _log('unregister: removed ${_mask(token)}');
    } on ApiException catch (e) {
      // Logging out must work even if the call fails.
      _log('unregister failed: HTTP ${e.statusCode ?? '?'} — ${e.message}');
    } catch (e) {
      _log('unregister failed: $e');
    }

    _registeredToken = null;
    lastRegistrationStatus.value = 'not attempted';
    return token;
  }

  Future<void> _showLocal(RemoteMessage message) async {
    _log('foreground message: ${message.data}');

    final notification = message.notification;
    if (notification == null) return;

    await _local.show(
      // A per-order id means a second update replaces the first rather than
      // stacking up a column of near-identical notifications.
      id: message.data['order_id']?.hashCode ?? notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _onLocalTap(NotificationResponse response) {
    final raw = response.payload;
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) _route(decoded);
    } on FormatException {
      // A payload we cannot read is not worth crashing the tap over.
    }
  }

  void _route(Map<dynamic, dynamic> data) {
    final payload = PushPayload(
      data.map((key, value) => MapEntry('$key', '$value')),
    );
    _log('routing tap: ${payload.data}');
    onNotificationTap?.call(payload);
  }

  /// Tears the listeners down. Only used in tests today.
  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _foregroundSub = null;
    _openedSub = null;
    _tokenRefreshSub = null;
    _initialised = false;
  }
}
