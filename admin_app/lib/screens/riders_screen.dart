import 'package:flutter/material.dart';

import '../models/rider_model.dart';
import '../services/api_client.dart';
import '../services/rider_admin_service.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';
import 'add_rider_screen.dart';
import 'rider_detail_screen.dart';

/// `GET /api/admin/riders/` — the rider roster, and where accounts are made.
class RidersScreen extends StatefulWidget {
  const RidersScreen({super.key});

  @override
  State<RidersScreen> createState() => _RidersScreenState();
}

class _RidersScreenState extends State<RidersScreen> {
  final _riders = RiderAdminService();

  late Future<List<Rider>> _future;

  @override
  void initState() {
    super.initState();
    _future = _riders.fetchAll();
  }

  Future<void> _reload() async {
    final future = _riders.fetchAll();
    setState(() => _future = future);
    try {
      await future;
    } on ApiException {
      // Rendered by the FutureBuilder.
    }
  }

  Future<void> _openRider(Rider rider) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RiderDetailScreen(rider: rider)),
    );
    // Only refetch when something actually moved — the roster is a cheap
    // call, but a pointless spinner on every back-tap is still noise.
    if (changed == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Riders"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh",
            onPressed: _reload,
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const AddRiderScreen()),
          );
          if (created == true) await _reload();
        },
        icon: const Icon(Icons.person_add_alt),
        label: const Text(
          "Add rider",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: FutureBuilder<List<Rider>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.cloud_off,
              title: "Could not load riders",
              message: snapshot.error is ApiException
                  ? (snapshot.error as ApiException).message
                  : "Something went wrong.",
              onRetry: _reload,
            );
          }

          final riders = snapshot.data ?? const <Rider>[];

          if (riders.isEmpty) {
            return EmptyState(
              icon: Icons.delivery_dining_outlined,
              title: "No riders yet",
              message:
                  "Riders cannot sign themselves up — create the first "
                  "account with the button below.",
              onRetry: _reload,
            );
          }

          final onDuty = riders.where((r) => r.isAvailable).length;
          // Two different numbers now, and the difference is the point: a
          // rider loading three bags at the counter is holding work but is
          // still assignable, while one who has set off is not.
          final driving = riders.where((r) => r.isDriving).length;
          final free = riders.where((r) => r.isAssignable).length;

          return RefreshIndicator(
            color: kAmber,
            onRefresh: _reload,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: riders.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _Summary(
                            value: "$onDuty",
                            label: "On duty",
                            colour: const Color(0xFF2E7D32),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Summary(
                            value: "$free",
                            label: "Assignable",
                            colour: const Color(0xFF1565C0),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Summary(
                            value: "$driving",
                            label: "On the road",
                            colour: const Color(0xFF00695C),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final rider = riders[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RiderCard(
                    rider: rider,
                    onTap: () => _openRider(rider),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.value,
    required this.label,
    required this.colour,
  });

  final String value;
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              color: colour,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11.5, color: kMuted)),
        ],
      ),
    );
  }
}

class _RiderCard extends StatelessWidget {
  const _RiderCard({required this.rider, required this.onTap});

  final Rider rider;
  final VoidCallback onTap;

  /// Four states worth telling apart, in order of what stops an assignment.
  (Color, String, IconData) get _state {
    if (!rider.isActive) {
      return (kMuted, "Deactivated", Icons.person_off_outlined);
    }
    if (rider.isDriving) {
      return (const Color(0xFF00695C), "On the road", Icons.two_wheeler);
    }
    if (!rider.isAvailable) {
      return (const Color(0xFF78909C), "Off duty", Icons.bedtime_outlined);
    }
    // On duty and not driving — assignable, whether or not they are already
    // holding orders. This is the case that used to be reported wrong.
    if (rider.isHolding) {
      return (
        const Color(0xFFB26A00),
        "Loading up",
        Icons.inventory_2_outlined,
      );
    }
    return (const Color(0xFF2E7D32), "Available", Icons.check_circle_outline);
  }

  @override
  Widget build(BuildContext context) {
    final (colour, label, icon) = _state;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colour.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(Icons.delivery_dining, color: colour, size: 23),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rider.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15.5,
                            color: kInk,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          "@${rider.username}",
                          style: const TextStyle(fontSize: 11.5, color: kMuted),
                        ),
                      ],
                    ),
                  ),
                  TagPill(label: label, colour: colour, icon: icon),
                ],
              ),

              // WORKLOAD — "3 orders · on YR-0028". Before the backend change
              // this card could only say "carrying X" or nothing, and it read
              // every rider as free because the field it looked for was gone.
              if (rider.isHolding) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: kAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 16,
                        color: kInk,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          rider.workloadLabel,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: kInk,
                          ),
                        ),
                      ),
                      if (!rider.isDriving)
                        const Text(
                          "can take more",
                          style: TextStyle(fontSize: 10.5, color: kMuted),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              if (rider.phone.isNotEmpty) ...[
                IconLine(Icons.phone_outlined, rider.phone),
                const SizedBox(height: 7),
              ],
              if (rider.vehicleType.isNotEmpty || rider.plateNumber.isNotEmpty)
                IconLine(
                  Icons.motorcycle,
                  [
                    if (rider.vehicleType.isNotEmpty) rider.vehicleType,
                    if (rider.plateNumber.isNotEmpty) rider.plateNumber,
                  ].join(' · '),
                ),

              const SizedBox(height: 10),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: const [
                  Text(
                    "Manage account",
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: kMuted,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 17, color: kMuted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
