import 'package:flutter/material.dart';

import '../models/dashboard_model.dart';
import '../services/admin_order_service.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';
import 'home_screen.dart';
import 'reports_screen.dart';

/// `GET /api/admin/dashboard/` — today's counts, revenue and rider load.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onOpenTab, this.onOpenOrders});

  /// Lets the tiles switch tabs rather than pushing a second copy of a screen
  /// that is already one tap away on the bar.
  final void Function(int index)? onOpenTab;

  /// Opens the Orders tab filtered to one status, or to everything when null.
  final void Function(String? status)? onOpenOrders;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _orders = AdminOrderService();

  late Future<AdminDashboard> _future;

  @override
  void initState() {
    super.initState();
    _future = _orders.fetchDashboard();
  }

  Future<void> _reload() async {
    final future = _orders.fetchDashboard();
    setState(() => _future = future);
    // Keep the refresh spinner up until the fetch settles; a failure is
    // rendered by the FutureBuilder.
    try {
      await future;
    } on ApiException {
      // Shown by the builder.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Yellow Ribbon"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh",
            onPressed: _reload,
          ),
        ],
      ),

      body: FutureBuilder<AdminDashboard>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.cloud_off,
              title: "Could not load the dashboard",
              message: snapshot.error is ApiException
                  ? (snapshot.error as ApiException).message
                  : "Something went wrong.",
              onRetry: _reload,
            );
          }

          final data = snapshot.data!;

          return RefreshIndicator(
            color: kAmber,
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Text(
                  "Today · ${data.date}",
                  style: const TextStyle(
                    color: kMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 14),

                // HEADLINE — revenue is the one number worth a whole card.
                _RevenueCard(data: data),

                const SizedBox(height: 14),

                // TODAY — two counts that are genuinely about today, from the
                // `today` block. Both open the whole queue: filtering by
                // `delivered` would show every delivered order ever, not
                // today's, so a filter here would contradict the number.
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        icon: Icons.receipt_long,
                        value: "${data.ordersPlaced}",
                        label: "Placed today",
                        colour: const Color(0xFF1565C0),
                        onTap: () => widget.onOpenOrders?.call(null),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.task_alt,
                        value: "${data.ordersDelivered}",
                        label: "Delivered today",
                        colour: const Color(0xFF2E7D32),
                        onTap: () => widget.onOpenOrders?.call(null),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // LIVE QUEUE — the stages an order actually sits in, each
                // opening the queue filtered to exactly that status.
                //
                // These come from `status_counts`, which is all-time rather
                // than today. For a live stage that is the same thing: an
                // order is only `preparing` right now.
                _QueueCard(
                  data: data,
                  onOpenStatus: (status) => widget.onOpenOrders?.call(status),
                ),

                const SizedBox(height: 14),

                // Revenue is recognised on delivery, so the split is worth
                // showing — it is not the same as what has been ordered.
                SectionCard(
                  title: "Today's takings",
                  icon: Icons.payments_outlined,
                  child: Column(
                    children: [
                      DetailRow(
                        "Food sales",
                        "₱${data.foodSales.toStringAsFixed(2)}",
                      ),
                      const Divider(height: 1),
                      DetailRow(
                        "Delivery fees",
                        "₱${data.deliveryFees.toStringAsFixed(2)}",
                      ),
                      const Divider(height: 1),
                      DetailRow(
                        "Cancelled today",
                        "${data.ordersCancelled}",
                        valueColour: data.ordersCancelled > 0
                            ? const Color(0xFFC62828)
                            : null,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                SectionCard(
                  title: "Riders",
                  icon: Icons.delivery_dining,
                  trailing: TextButton(
                    onPressed: () =>
                        widget.onOpenTab?.call(HomeScreen.ridersTab),
                    style: TextButton.styleFrom(
                      foregroundColor: kInk,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text("Manage"),
                  ),
                  child: Column(
                    children: [
                      DetailRow("Registered", "${data.ridersTotal}"),
                      const Divider(height: 1),
                      DetailRow("On duty", "${data.ridersOnDuty}"),
                      const Divider(height: 1),
                      // Renamed from "On a delivery": the backend counts
                      // riders with any active delivery, and since riders now
                      // batch several orders at the store, holding work is no
                      // longer the same as being out on the road.
                      DetailRow("Carrying orders", "${data.ridersOnDelivery}"),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                SectionCard(
                  title: "Reports",
                  icon: Icons.bar_chart,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "Everything above is today. Sales over a date range, "
                        "rider performance and best sellers live in reports.",
                        style: TextStyle(fontSize: 12.5, color: kMuted),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ReportsScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.bar_chart, size: 18),
                        label: const Text("Open reports"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The stages an order passes through while it is still live.
///
/// Every row filters the queue to exactly its own status. The old dashboard
/// sent all four tiles to an unfiltered list and labelled one of them "In the
/// kitchen" while counting *every* unfinished order — so it read high and
/// then showed the wrong list.
class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.data, required this.onOpenStatus});

  final AdminDashboard data;
  final void Function(String status) onOpenStatus;

  /// In the order an order moves through them.
  static const _stages = <(String, String, IconData, Color)>[
    ('pending', 'New — needs accepting', Icons.pending_actions,
        Color(0xFFB26A00)),
    ('confirmed', 'Accepted', Icons.check_circle_outline, Color(0xFF1565C0)),
    ('preparing', 'In the kitchen', Icons.local_fire_department_outlined,
        Color(0xFF6A1B9A)),
    ('ready', 'Ready for pickup', Icons.inventory_2_outlined,
        Color(0xFF00838F)),
    ('out_for_delivery', 'Out for delivery', Icons.delivery_dining,
        Color(0xFF00796B)),
  ];

  @override
  Widget build(BuildContext context) {
    final waiting = _stages.fold<int>(
      0,
      (sum, stage) => sum + data.countFor(stage.$1),
    );

    return SectionCard(
      title: "Live queue",
      icon: Icons.playlist_play,
      trailing: Text(
        waiting == 0 ? "All clear" : "$waiting open",
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: waiting == 0 ? const Color(0xFF2E7D32) : kMuted,
        ),
      ),
      child: Column(
        children: [
          for (final (status, label, icon, colour) in _stages)
            _StageRow(
              label: label,
              icon: icon,
              colour: colour,
              count: data.countFor(status),
              onTap: () => onOpenStatus(status),
            ),
        ],
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.icon,
    required this.colour,
    required this.count,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color colour;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isEmpty = count == 0;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isEmpty ? kMuted : colour),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  color: isEmpty ? kMuted : kInk,
                  fontWeight: isEmpty ? FontWeight.normal : FontWeight.w600,
                ),
              ),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 30),
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: isEmpty
                    ? const Color(0xFFF0F0F0)
                    : colour.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "$count",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isEmpty ? kMuted : colour,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: kMuted),
          ],
        ),
      ),
    );
  }
}

/// The day's money, on ink so it reads as the headline rather than one tile
/// among six.
class _RevenueCard extends StatelessWidget {
  const _RevenueCard({required this.data});

  final AdminDashboard data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: kInk,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, color: kAmber, size: 18),
              const SizedBox(width: 8),
              Text(
                "Revenue today",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              "₱${data.revenue.toStringAsFixed(2)}",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Counted when an order is delivered, so pending orders are not "
            "in this figure.",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.colour,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color colour;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
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
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: colour, size: 20),
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                    color: kInk,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(color: kMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
