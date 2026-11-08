import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'models/delivery_model.dart';
import 'models/user_model.dart';
import 'rider_home.dart';
import 'screens/login_screen.dart';
import 'screens/order_details_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/delivery_service.dart';
import 'services/location_pinger.dart';
import 'services/osrm_service.dart';
import 'services/push_service.dart';

/// Lets the API client and the push handlers reach the navigator from
/// outside the widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Must be registered before runApp, and must point at a top-level function.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  ApiClient.instance.onSessionExpired = () {
    // Stop reporting a position for a rider who is no longer signed in.
    LocationPinger.instance.reset();
    OsrmService.instance.clear();
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
  };

  PushService.instance.onNotificationTap = _openAssignedDelivery;

  await PushService.instance.initialize();

  runApp(const RiderApp());
}

/// Opens the delivery a push refers to.
///
/// The backend's payload carries `order_id` — the Order primary key — but
/// this app's detail screen is keyed on the Delivery id, and there is no
/// endpoint to look one up from the other. The active list is fetched and
/// matched on `order.id`, which is the cheapest correct route with the
/// endpoints that exist. Falls back to the shell if no match is found, which
/// is what happens when the delivery has already been completed.
Future<void> _openAssignedDelivery(PushPayload payload) async {
  final navigator = navigatorKey.currentState;
  final orderId = payload.orderId;
  if (navigator == null || orderId == null) return;

  try {
    final deliveries = await DeliveryService().fetchActive();

    Delivery? match;
    for (final delivery in deliveries) {
      if (delivery.order.id == orderId) {
        match = delivery;
        break;
      }
    }

    if (match != null) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => OrderDetailsScreen(deliveryId: match!.id),
        ),
      );
      return;
    }
  } on ApiException {
    // Fall through to the shell rather than showing an error for a tap.
  }

  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const RiderHome()),
    (route) => false,
  );
}

class RiderApp extends StatefulWidget {
  const RiderApp({super.key});

  @override
  State<RiderApp> createState() => _RiderAppState();
}

class _RiderAppState extends State<RiderApp> {
  @override
  void initState() {
    super.initState();
    // Needs a navigator, so it waits for the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushService.instance.handleLaunchNotification();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Yellow Ribbon Rider',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey.shade100,

        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          primary: Colors.amber,
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.amber,
          foregroundColor: Colors.black,
          centerTitle: true,
          elevation: 0,
        ),

        cardTheme: CardThemeData(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const SessionGate(),
    );
  }
}

/// Chooses the landing screen from the stored session.
///
/// A JWT in secure storage means the rider is still signed in, so a cold
/// start goes straight to the dashboard. The cached `user` object carries the
/// role flags, so no network round trip is needed before the first frame.
class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  final _auth = AuthService();
  late Future<AppUser?> _session;

  @override
  void initState() {
    super.initState();
    _session = _resolveSession();
  }

  Future<AppUser?> _resolveSession() async {
    if (!await _auth.hasSession()) return null;
    final user = await _auth.cachedUser();
    // A stored non-rider session should never have been saved, but if one
    // somehow exists it is discarded rather than shown a broken app.
    if (user != null && !user.isRider) {
      await _auth.logout();
      return null;
    }

    // Register for pushes here too, not only on the login screen. The JWT
    // survives a restart, so a returning rider never sees the login screen
    // again — and before this, that meant their device was never registered.
    if (user != null) {
      unawaited(PushService.instance.registerToken(reason: 'session-restore'));
    }

    return user;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: _session,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data == null ? const LoginScreen() : const RiderHome();
      },
    );
  }
}
