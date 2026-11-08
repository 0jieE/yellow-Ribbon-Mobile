import 'package:flutter/material.dart';

import 'dart:async';

import 'customer_home.dart';
import 'login.dart';
import 'models/user_model.dart';
import 'services/auth_service.dart';
import 'services/push_service.dart';

/// Decides the landing screen from the stored session.
///
/// A JWT in secure storage means the customer is still logged in, so a cold
/// start goes straight to the menu. The cached `user` object carries the role
/// flags the login response returned, which is what picks the destination —
/// no network round trip needed before the first frame.
class HomeRouter extends StatefulWidget {
  const HomeRouter({super.key});

  @override
  State<HomeRouter> createState() => _HomeRouterState();
}

class _HomeRouterState extends State<HomeRouter> {
  final _auth = AuthService();
  late Future<AppUser?> _session;

  @override
  void initState() {
    super.initState();
    _session = _resolveSession();
  }

  /// Returns the signed-in user, or null when there is no usable session.
  Future<AppUser?> _resolveSession() async {
    if (!await _auth.hasSession()) return null;

    final user = await _auth.cachedUser();

    // Register for pushes here too, not only on the login screen. The JWT
    // survives a restart, so a returning customer never sees the login screen
    // again — and before this, that meant their device was never registered.
    if (user != null && user.isCustomer) {
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

        final user = snapshot.data;

        // No token, or a token with no cached profile to trust.
        if (user == null) {
          return const LoginPage();
        }

        if (user.isCustomer) {
          return const CustomerHome();
        }

        // A rider or admin token in this build: every customer endpoint would
        // reject it, so say so plainly rather than showing an empty menu.
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "This is a ${user.role} account.\n"
                    "Please use the ${user.role} app.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      await _auth.logout();
                      if (!context.mounted) return;
                      setState(() => _session = _resolveSession());
                    },
                    child: const Text("Log out"),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
