import 'dart:async';

import 'package:flutter/material.dart';

import '../models/delivery_model.dart';
import '../services/api_client.dart';
import '../services/delivery_service.dart';
import '../services/location_pinger.dart';
import '../widgets/order_card.dart';
import 'order_details_screen.dart';

/// How often the list re-reads itself.
///
/// The admin moves an order through preparing → ready from their own app, and
/// the rider cannot pick up until it is ready. Without this the rider would
/// sit on a stale "not ready yet" until they thought to pull down.
const _pollInterval = Duration(seconds: 20);

/// `GET /api/rider/deliveries/` — assigned and in-progress work.
///
/// This screen also decides whether the location pinger runs: every fetch
/// hands the result to [LocationPinger.syncWith], so tracking starts when
/// there is work and stops when there is none.
class AssignedOrdersScreen extends StatefulWidget {
  const AssignedOrdersScreen({super.key});

  @override
  State<AssignedOrdersScreen> createState() => _AssignedOrdersScreenState();
}

class _AssignedOrdersScreenState extends State<AssignedOrdersScreen>
    with WidgetsBindingObserver {
  final _deliveries = DeliveryService();
  final _search = TextEditingController();

  List<Delivery> _all = [];
  String? _error;
  bool _loading = true;

  /// Guards against a slow poll overlapping the next tick.
  bool _refreshing = false;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _silentRefresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is exactly when a rider wants the current
    // picture — they have usually just been handed something.
    if (state == AppLifecycleState.resumed) _silentRefresh();
  }

  Future<List<Delivery>> _fetch() async {
    final deliveries = await _deliveries.fetchActive();
    LocationPinger.instance.syncWith(deliveries);
    return deliveries;
  }

  /// First load and pull-to-refresh: shows the spinner and surfaces errors.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final deliveries = await _fetch();
      if (!mounted) return;
      setState(() {
        _all = deliveries;
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

  /// Background poll: no spinner, and a dropped request keeps the last good
  /// list rather than replacing it with an error.
  Future<void> _silentRefresh() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;

    try {
      final deliveries = await _fetch();
      if (!mounted) return;
      setState(() {
        _all = deliveries;
        // A poll that succeeds clears a stale error banner.
        _error = null;
        _loading = false;
      });
    } on ApiException {
      // Keep showing what we have; the next tick tries again.
    } finally {
      _refreshing = false;
    }
  }

  /// Matches on order number, customer and item names. The list is a single
  /// rider's active work, so filtering in place beats a round trip.
  List<Delivery> get _visible {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _all;

    return _all.where((delivery) {
      final order = delivery.order;
      if (order.orderNumber.toLowerCase().contains(query)) return true;
      if (order.customerName.toLowerCase().contains(query)) return true;
      if (order.deliveryAddress.toLowerCase().contains(query)) return true;
      return order.items
          .any((item) => item.menuName.toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        title: const Text(
          "Assigned Orders",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: Column(
        children: [
          // SEARCH — for finding the order just handed over at the counter.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: "Search order number, customer or item",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),

          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _Placeholder(
        icon: Icons.cloud_off,
        message: _error!,
        onRetry: _load,
      );
    }

    if (_all.isEmpty) {
      return _Placeholder(
        icon: Icons.inbox_outlined,
        message: "No deliveries assigned to you right now.\n"
            "Pull down to refresh.",
        onRetry: _load,
        showRetry: false,
      );
    }

    final visible = _visible;

    if (visible.isEmpty) {
      return _Placeholder(
        icon: Icons.search_off,
        message: "Nothing matches \"${_search.text.trim()}\".",
        onRetry: _load,
        showRetry: false,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        // One extra row for the count header.
        itemCount: visible.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            final searching = _search.text.trim().isNotEmpty;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                searching
                    ? "${visible.length} of ${_all.length} match"
                    : _all.length == 1
                        ? "1 delivery in hand"
                        : "${_all.length} deliveries in hand",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            );
          }

          final delivery = visible[index - 1];
          return OrderCard(
            delivery: delivery,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderDetailsScreen(deliveryId: delivery.id),
                ),
              );
              // The detail screen advances status, so the list — and the
              // pinger's view of the workload — is refetched on return.
              await _silentRefresh();
            },
          );
        },
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.message,
    required this.onRetry,
    this.showRetry = true,
  });

  final IconData icon;
  final String message;
  final Future<void> Function() onRetry;

  /// Only a failed load gets a button. An empty list is not an error — new
  /// assignments arrive by push and pull-to-refresh is still there.
  final bool showRetry;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 70),
        children: [
          Icon(icon, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          if (showRetry) ...[
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                onPressed: onRetry,
                child: const Text("Retry"),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
