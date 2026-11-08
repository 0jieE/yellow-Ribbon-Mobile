import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/delivery_model.dart';
import 'api_client.dart';
import 'rider_service.dart';

/// Reports the rider's position to `POST /api/rider/location/` while they are
/// carrying a delivery.
///
/// The customer's tracking map is fed entirely by this, so it runs on a fixed
/// cadence rather than on movement: a stationary rider stuck in traffic
/// should still look alive on the customer's screen.
///
/// Scope note: this is an in-app timer. It keeps running while the app is
/// alive, including when it is merely backgrounded for a while, but Android
/// will eventually suspend the process and the pings stop. Surviving that
/// properly needs a foreground service with an ongoing notification, which is
/// a larger piece of work than this — see the handover notes.
class LocationPinger {
  LocationPinger({RiderService? riders})
      : _riders = riders ?? RiderService();

  static final LocationPinger instance = LocationPinger();

  final RiderService _riders;

  /// Matches the 10–15s cadence the backend's location endpoint is designed
  /// around. Faster would burn the rider's battery and data for coordinates
  /// the customer's 12s poll would not even see.
  static const Duration interval = Duration(seconds: 12);

  Timer? _timer;
  bool _sending = false;

  /// True while the pinger is scheduled. Surfaced on the dashboard so the
  /// rider can see that tracking is live.
  final ValueNotifier<bool> isRunning = ValueNotifier(false);

  /// Last problem worth telling the rider about — usually a denied location
  /// permission. Null when everything is fine.
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  /// Starts or stops the pinger to match the current workload.
  ///
  /// Called after every deliveries fetch, so the timer's lifetime follows the
  /// rider's actual work without any screen having to remember to stop it.
  void syncWith(List<Delivery> deliveries) {
    if (deliveries.any((d) => d.isActive)) {
      start();
    } else {
      stop();
    }
  }

  void start() {
    if (_timer != null) return;

    _timer = Timer.periodic(interval, (_) => _tick());
    isRunning.value = true;

    // Send one immediately so the customer sees the rider straight away
    // rather than after the first full interval.
    unawaited(_tick());
  }

  void stop() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    isRunning.value = false;
  }

  Future<void> _tick() async {
    // A slow ping must not stack up behind the next tick.
    if (_sending) return;
    _sending = true;

    try {
      final position = await _currentPosition();
      if (position == null) return;

      await _riders.pingLocation(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      lastError.value = null;
    } on SessionExpiredException {
      // No point pinging without a session; the app is about to bounce to
      // the login screen anyway.
      stop();
    } on ApiException catch (e) {
      // A dropped ping is not worth interrupting the rider over — the next
      // tick will try again. Recorded so the dashboard can show it.
      lastError.value = e.message;
    } finally {
      _sending = false;
    }
  }

  /// Resolves the device position, or null when location is unavailable.
  ///
  /// Permission is requested here rather than at app start so the rider is
  /// asked at the moment it matters, on their first active delivery.
  Future<Position?> _currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        lastError.value =
            'Location is turned off. The customer cannot see your position.';
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Time-boxed for the same reason as the notification permission:
        // Android allows one runtime permission dialog at a time, and a
        // request made while another is showing is dropped with no callback.
        // Left unbounded that would hang here forever, and because `_sending`
        // is only cleared in the `finally` below, the pinger would never tick
        // again for the rest of the session. Timing out lets the next tick
        // ask again, by which point the other dialog is gone.
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 20));
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        lastError.value =
            'Location permission denied. The customer cannot track this '
            'delivery.';
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      // Not surfaced as an error: the next tick retries in a few seconds.
      return null;
    } on Exception {
      lastError.value = 'Could not read your location.';
      return null;
    }
  }

  /// Called on logout so a signed-out app stops reporting a position.
  void reset() {
    stop();
    lastError.value = null;
  }
}
