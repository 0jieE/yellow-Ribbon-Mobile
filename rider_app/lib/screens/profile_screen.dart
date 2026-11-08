import 'package:flutter/material.dart';

import '../main.dart' show navigatorKey;
import '../models/user_model.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/location_pinger.dart';
import '../services/osrm_service.dart';
import '../services/push_service.dart';
import '../services/rider_service.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthService();
  final _riders = RiderService();

  AppUser? _user;
  String? _error;
  bool _loading = true;

  /// Local mirror of `Rider.is_available`, updated optimistically and rolled
  /// back if the PATCH fails.
  bool _available = false;
  bool _savingAvailability = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = await _auth.me();
      if (!mounted) return;
      setState(() {
        _user = user;
        _available = user.isAvailable ?? false;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  /// `PATCH /api/rider/availability/`
  Future<void> _setAvailability(bool value) async {
    final previous = _available;

    setState(() {
      _available = value;
      _savingAvailability = true;
    });

    try {
      final stored = await _riders.setAvailability(value);
      if (!mounted) return;
      setState(() {
        // Trust the server's echo over the optimistic value.
        _available = stored;
        _savingAvailability = false;
      });
      _snack(stored ? "You are now on duty." : "You are now off duty.");
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _available = previous;
        _savingAvailability = false;
      });
      _snack(e.message);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Log out?"),
        content: const Text(
          "You will stop receiving delivery assignments on this device.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Log out"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Stop reporting a position before the session goes away.
    LocationPinger.instance.reset();
    // Cached route previews name real customers' streets — they must not
    // survive into the next rider's session on a shared handset.
    OsrmService.instance.clear();
    // Drop this device's push registration first — the DELETE needs the JWT
    // that logout is about to discard.
    final token = await PushService.instance.unregisterToken();
    await _auth.logout(fcmToken: token);

    navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        title: const Text(
          "Rider Profile",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _buildBody(_user!),
    );
  }

  Widget _buildBody(AppUser user) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // HEADER
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: _ink,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 40,
                  backgroundColor: _amber,
                  child: Icon(
                    Icons.delivery_dining,
                    size: 44,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  user.displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  "@${user.username}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // AVAILABILITY — the one thing on this screen the rider controls.
          _Section(
            title: "Availability",
            child: SwitchListTile(
              value: _available,
              onChanged: _savingAvailability ? null : _setAvailability,
              activeThumbColor: const Color(0xFF2E7D32),
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                _available ? Icons.work : Icons.work_off,
                color: _available ? const Color(0xFF2E7D32) : Colors.grey,
              ),
              title: const Text(
                "Available for deliveries",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
              ),
              subtitle: Text(
                _savingAvailability
                    ? "Saving…"
                    : _available
                        ? "On duty — the store can assign you orders."
                        : "Off duty — you will not be assigned new orders.",
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ),

          const SizedBox(height: 14),

          _Section(
            title: "Contact",
            child: Column(
              children: [
                _Row(
                  icon: Icons.phone_outlined,
                  label: "Phone",
                  value: user.phone.isEmpty ? "Not set" : user.phone,
                  muted: user.phone.isEmpty,
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          _Section(
            title: "Vehicle",
            child: Column(
              children: [
                _Row(
                  icon: Icons.motorcycle,
                  label: "Type",
                  value: (user.vehicleType?.isNotEmpty ?? false)
                      ? user.vehicleType!
                      : "Not recorded",
                  muted: !(user.vehicleType?.isNotEmpty ?? false),
                ),
                const Divider(height: 22),
                _Row(
                  icon: Icons.confirmation_number_outlined,
                  label: "Plate number",
                  value: (user.plateNumber?.isNotEmpty ?? false)
                      ? user.plateNumber!
                      : "Not recorded",
                  muted: !(user.plateNumber?.isNotEmpty ?? false),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          _Section(
            title: "Account",
            child: _Row(
              icon: Icons.badge_outlined,
              label: "Username",
              value: user.username,
            ),
          ),

          const SizedBox(height: 22),

          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text(
                "LOG OUT",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          const Text(
            "Your details are managed by the store admin.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: Colors.grey.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: muted ? FontWeight.normal : FontWeight.w500,
                  color: muted ? Colors.grey : Colors.black,
                  fontStyle: muted ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// White card with the amber-accented header used across the apps.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 15,
                decoration: BoxDecoration(
                  color: _amber,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text("Retry")),
          ],
        ),
      ),
    );
  }
}
