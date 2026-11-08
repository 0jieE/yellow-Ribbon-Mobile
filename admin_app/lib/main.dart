import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';
import 'models/user_model.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/order_detail_screen.dart';
import 'screens/orders_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/push_service.dart';
import 'theme.dart';

/// Lets the API client return to the login screen from anywhere when the
/// refresh token stops working, without every screen having to handle it.
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Must be registered before runApp, and must point at a top-level function.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  ApiClient.instance.onSessionExpired = () {
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
  };

  PushService.instance.onNotificationTap = _openFromPush;

  await PushService.instance.initialize();

  runApp(const AdminApp());
}

/// Opens the order queue for a push, and the order itself when the payload
/// identifies one.
///
/// The admin receives `new_order` and `delivered`; both carry `order_id`, so
/// the queue is pushed first and the detail on top of it. That way backing
/// out of the order lands on the list rather than wherever the admin was.
void _openFromPush(PushPayload payload) {
  final navigator = navigatorKey.currentState;
  if (navigator == null) return;

  navigator.push(MaterialPageRoute(builder: (_) => const OrdersScreen()));

  final orderId = payload.orderId;
  if (orderId != null) {
    navigator.push(
      MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId)),
    );
  }
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Yellow Ribbon Admin',
      debugShowCheckedModeBanner: false,

      theme: AdminTheme.data,

      home: const SessionGate(),
    );
  }
}

/// Chooses the landing screen from the stored session.
///
/// A JWT in secure storage means the admin is still signed in, so a cold
/// start goes straight to the dashboard. The cached `user` carries the role
/// flags, so no network round trip is needed before the first frame.
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
    // Needs a navigator, so it waits for the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushService.instance.handleLaunchNotification();
    });
  }

  Future<AppUser?> _resolveSession() async {
    if (!await _auth.hasSession()) return null;

    final user = await _auth.cachedUser();
    // A stored non-admin session should never have been saved, but if one
    // somehow exists it is discarded rather than shown an app where every
    // screen would 403.
    if (user != null && !user.isAdmin) {
      await _auth.logout();
      return null;
    }

    // Register for pushes here too, not only on the login screen. The JWT
    // survives a restart, so a returning admin never sees the login screen
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
        return snapshot.data == null ? const LoginScreen() : const HomeScreen();
      },
    );
  }
}
