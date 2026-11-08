import 'package:flutter/material.dart';

import '../main.dart' show navigatorKey;
import '../models/user_model.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/push_service.dart';
import '../theme.dart';
import '../widgets/app_update.dart';
import '../widgets/section_card.dart';
import 'store_settings_screen.dart';

/// The signed-in admin, and the way out.
///
/// Still deliberately thin — there is no admin profile-edit endpoint, so
/// there is nothing here to change. What it is not is a placeholder: logout
/// used to hang off the dashboard's app bar, and moving the dashboard to a
/// tab had to put it somewhere findable.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthService();

  AppUser? _user;
  bool _loading = true;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // The cached copy renders immediately; the network read only corrects it.
    final cached = await _auth.cachedUser();
    if (!mounted) return;
    setState(() {
      _user = cached;
      _loading = cached == null;
    });

    try {
      final fresh = await _auth.me();
      if (!mounted) return;
      setState(() {
        _user = fresh;
        _loading = false;
      });
    } on ApiException {
      // The cached profile is good enough for a name and an email.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Log out?"),
        content: const Text("You will need to sign in again on this device."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Log out"),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _loggingOut = true);

    // Drop this device's push registration first — the DELETE needs the JWT
    // that logout is about to discard.
    final token = await PushService.instance.unregisterToken();
    await _auth.logout(fcmToken: token);

    navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                // IDENTITY
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: kInk,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 66,
                        height: 66,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: kAmber,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings,
                          size: 33,
                          color: kInk,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        user?.displayName ?? "Administrator",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user == null ? "" : "@${user.username}",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                SectionCard(
                  title: "Account",
                  icon: Icons.badge_outlined,
                  child: Column(
                    children: [
                      DetailRow("Username", user?.username ?? "—"),
                      const Divider(height: 1),
                      DetailRow(
                        "Phone",
                        (user?.phone.isNotEmpty ?? false) ? user!.phone : "—",
                      ),
                      const Divider(height: 1),
                      DetailRow("Role", "Administrator"),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                SectionCard(
                  title: "Store",
                  icon: Icons.storefront_outlined,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.tune),
                    title: const Text("Store settings"),
                    subtitle: const Text(
                      "Delivery fee, service area, gateway fees",
                      style: TextStyle(fontSize: 12, color: kMuted),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StoreSettingsScreen(),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                const SectionCard(
                  title: "App",
                  icon: Icons.phone_android,
                  child: AppUpdateTile(),
                ),

                const SizedBox(height: 14),

                SectionCard(
                  title: "Editing your details",
                  icon: Icons.info_outline,
                  child: const Text(
                    "The backend has no admin profile-update endpoint, so "
                    "these are read-only here. Change them in Django admin.",
                    style: TextStyle(fontSize: 12.5, color: kMuted),
                  ),
                ),

                const SizedBox(height: 22),

                OutlinedButton.icon(
                  onPressed: _loggingOut ? null : _logout,
                  icon: _loggingOut
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.logout, size: 19),
                  label: const Text("Log out"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFC62828),
                    side: const BorderSide(color: Color(0xFFC62828)),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
              ],
            ),
    );
  }
}
