import 'package:flutter/material.dart';

import '../models/dashboard_model.dart';
import '../rider_home.dart';
import '../services/api_client.dart';
import '../services/location_pinger.dart';
import '../services/rider_service.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onOpenTab});

  /// Switches the shell's tab. Lets the counters act as links to the list
  /// behind them, keeping the bottom bar in step rather than stacking a
  /// duplicate screen on top.
  final void Function(int index)? onOpenTab;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _riders = RiderService();

  late Future<RiderDashboard> _future;

  @override
  void initState() {
    super.initState();
    _future = _riders.fetchDashboard();
  }

  Future<void> _reload() async {
    final future = _riders.fetchDashboard();
    setState(() => _future = future);
    // Keep the refresh spinner up until the fetch settles. A failure is
    // rendered by the FutureBuilder, so it is swallowed here.
    try {
      await future;
    } on ApiException {
      // Shown by the builder.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        title: const Text(
          "Rider Dashboard",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: _amber,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: FutureBuilder<RiderDashboard>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(
              message: snapshot.error is ApiException
                  ? (snapshot.error as ApiException).message
                  : "Could not load your dashboard.",
              onRetry: _reload,
            );
          }

          final data = snapshot.data!;

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _RiderHeader(data: data),

                const SizedBox(height: 10),

                // Whether the customer can see this rider right now.
                const _TrackingIndicator(),

                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: "Assigned",
                        value: "${data.assigned}",
                        caption: data.assigned == 0
                            ? "Nothing to deliver"
                            : "Tap to open",
                        icon: Icons.assignment_outlined,
                        colour: const Color(0xFFB26A00),
                        onTap: () =>
                            widget.onOpenTab?.call(RiderHome.ordersTab),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        title: "Completed",
                        value: "${data.completed}",
                        caption: data.completed == 0
                            ? "None yet"
                            : "Tap to open",
                        icon: Icons.task_alt,
                        colour: const Color(0xFF2E7D32),
                        onTap: () =>
                            widget.onOpenTab?.call(RiderHome.historyTab),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                _Section(
                  title: "Earnings",
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E7D32)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.payments,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Total earned",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  "₱${data.earningsTotal.toStringAsFixed(2)}",
                                  style: const TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 26),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Today · ${data.completedToday} delivered",
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          Text(
                            "₱${data.earningsToday.toStringAsFixed(2)}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (data.failed > 0) ...[
                  const SizedBox(height: 14),
                  _FailedCard(
                    count: data.failed,
                    onTap: () => widget.onOpenTab?.call(RiderHome.historyTab),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Who is on shift, and whether they are on duty.
class _RiderHeader extends StatelessWidget {
  const _RiderHeader({required this.data});

  final RiderDashboard data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: _amber,
            child: Icon(
              Icons.delivery_dining,
              color: Colors.black,
              size: 32,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: data.isAvailable
                            ? const Color(0xFF4CAF50)
                            : Colors.white38,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        data.isAvailable
                            ? "On duty"
                            : "Off duty — you will not be assigned work",
                        style: TextStyle(
                          fontSize: 12.5,
                          color: data.isAvailable
                              ? const Color(0xFF9CCC65)
                              : Colors.white60,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A counter that doubles as a link to the list behind it.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.caption,
    required this.icon,
    required this.colour,
    required this.onTap,
  });

  final String title;
  final String value;
  final String caption;
  final IconData icon;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colour.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: colour, size: 21),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Text(
                value,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),

              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FailedCard extends StatelessWidget {
  const _FailedCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "$count failed ${count == 1 ? 'delivery' : 'deliveries'}",
                  style: TextStyle(
                    color: Colors.red.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                "History",
                style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
              ),
              Icon(Icons.chevron_right, size: 20, color: Colors.red.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows whether location pings are going out, so the rider knows the
/// customer can see them — and hears about a denied permission rather than
/// silently going dark on the tracking map.
class _TrackingIndicator extends StatelessWidget {
  const _TrackingIndicator();

  @override
  Widget build(BuildContext context) {
    final pinger = LocationPinger.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: pinger.isRunning,
      builder: (context, running, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: pinger.lastError,
          builder: (context, error, _) {
            if (!running && error == null) return const SizedBox.shrink();

            final isProblem = error != null;
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isProblem ? Colors.red.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isProblem
                        ? Colors.red.shade200
                        : Colors.green.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isProblem ? Icons.location_off : Icons.my_location,
                      size: 20,
                      color: isProblem ? Colors.red : Colors.green,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error ??
                            "Sharing your location — the customer can track "
                                "this delivery.",
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: isProblem
                              ? Colors.red.shade900
                              : Colors.green.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
