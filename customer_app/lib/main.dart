import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'customer/order_detail_screen.dart';
import 'customer_home.dart';
import 'firebase_options.dart';
import 'home_router.dart';
import 'services/api_client.dart';
import 'services/pending_payment.dart';
import 'services/push_service.dart';
import 'widgets/app_update.dart';

/// Lets the API client and the push/deep-link handlers reach the navigator
/// from outside the widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Must be registered before runApp, and must point at a top-level function.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  ApiClient.instance.onSessionExpired = () {
    // HomeRouter re-reads the (now cleared) session and lands on login.
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
  };

  // Tapping any order notification opens that order.
  PushService.instance.onNotificationTap = (payload) {
    final orderId = payload.orderId;
    if (orderId != null) openOrderDetail(orderId);
  };

  await PushService.instance.initialize();

  runApp(const MyApp());

  // Quietly looks for a newer build once the first frame is up.
  UpdatePrompter.instance.start(navigatorKey);
}

/// Pushes an order's detail screen from outside the widget tree.
void openOrderDetail(int orderId, {String? message}) {
  final navigator = navigatorKey.currentState;
  if (navigator == null) return;

  navigator.push(
    MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId)),
  );

  if (message != null) {
    final messengerContext = navigatorKey.currentContext;
    if (messengerContext != null) {
      ScaffoldMessenger.of(messengerContext).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();

    // Both of these need a navigator, so they wait for the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushService.instance.handleLaunchNotification();
      _listenForDeepLinks();
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  /// Handles the return from PayMongo.
  ///
  /// The backend's return page redirects to `yellowribbon://payment/success`
  /// or `.../failed`. Neither carries an order id — PayMongo only knows the
  /// redirect URL it was given — so the order is recovered from
  /// [PendingPayment], which checkout wrote before opening the browser.
  Future<void> _listenForDeepLinks() async {
    // A link that launched the app from cold, if any.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) await _handleLink(initial);
    } on Exception {
      // No initial link is the normal case.
    }

    _linkSub = _appLinks.uriLinkStream.listen(
      _handleLink,
      onError: (_) {},
    );
  }

  Future<void> _handleLink(Uri uri) async {
    if (uri.scheme != 'yellowribbon') return;

    // yellowribbon://payment/success  ->  host "payment", path "/success"
    final isPayment = uri.host == 'payment';
    if (!isPayment) return;

    final outcome = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    final orderId = await PendingPayment.instance.take();

    if (orderId == null) {
      // Nothing to open — the app was probably reinstalled, or this is a
      // stray link. Land on the orders list instead of doing nothing.
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const CustomerHome(initialTab: CustomerHome.ordersTab),
        ),
        (route) => false,
      );
      return;
    }

    // The webhook is what actually settles the payment, not this redirect, so
    // the wording stays cautious either way.
    openOrderDetail(
      orderId,
      message: outcome == 'success'
          ? "Payment received. Confirming your order…"
          : "Payment was not completed. You can try again or cancel.",
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: const HomeRouter(),
    );
  }
}
