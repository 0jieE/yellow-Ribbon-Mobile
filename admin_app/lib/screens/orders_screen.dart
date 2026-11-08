import 'package:flutter/material.dart';

import '../models/admin_order_model.dart';
import '../services/admin_order_service.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/assign_rider_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/order_status.dart';
import '../widgets/section_card.dart';
import 'order_detail_screen.dart';

/// `GET /api/admin/orders/` — the order queue.
///
/// This is the only paginated endpoint in the system (25 per page), so this
/// screen accumulates pages behind a "Load more" rather than assuming the
/// first response is everything.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.initialStatus});

  /// Opens pre-filtered. The dashboard's queue tiles use this so tapping
  /// "In the kitchen" lands on the preparing orders rather than on all of
  /// them, leaving the admin to find the filter themselves.
  final String? initialStatus;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _orders = AdminOrderService();

  final List<AdminOrder> _loaded = [];

  /// Null means no filter — the server returns every status.
  String? _statusFilter;

  int _page = 1;
  int _total = 0;
  bool _hasMore = false;

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _statusFilter = widget.initialStatus;
    _load();
  }

  @override
  void didUpdateWidget(OrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Arriving from a different dashboard tile while this screen is already
    // mounted has to re-filter, not show the previous tile's list.
    if (widget.initialStatus != oldWidget.initialStatus) {
      _statusFilter = widget.initialStatus;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final page = await _orders.fetchOrders(
        statuses: _statusFilter == null ? const [] : [_statusFilter!],
      );
      if (!mounted) return;
      setState(() {
        _loaded
          ..clear()
          ..addAll(page.results);
        _total = page.count;
        _hasMore = page.hasMore;
        _page = 1;
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);

    try {
      final page = await _orders.fetchOrders(
        statuses: _statusFilter == null ? const [] : [_statusFilter!],
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _loaded.addAll(page.results);
        _page += 1;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _snack(e.message);
    }
  }

  void _setFilter(String? status) {
    setState(() => _statusFilter = status);
    _load();
  }

  Future<void> _assignRider(AdminOrder order) async {
    final riderId = await showAssignRiderSheet(
      context,
      orderNumber: order.orderNumber,
    );
    if (riderId == null || !mounted) return;

    try {
      final updated = await _orders.assignRider(order.id, riderId);
      if (!mounted) return;
      _replace(updated);
      _snack("${updated.orderNumber} assigned to ${updated.rider?.name ?? 'rider'}.");
    } on ApiException catch (e) {
      if (!mounted) return;
      // The server refuses an unpaid pending_payment order, an already
      // assigned one, and a deactivated rider — each with its own sentence.
      // It no longer refuses a rider who already holds deliveries: they
      // collect a batch at the store, and the one-leg-at-a-time rule is
      // enforced when the rider starts a leg, not here.
      _showRefusal(e.message);
    }
  }

  void _replace(AdminOrder updated) {
    final index = _loaded.indexWhere((o) => o.id == updated.id);
    if (index == -1) return;
    setState(() => _loaded[index] = updated);
  }

  void _showRefusal(String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.block, color: Colors.red, size: 32),
        title: const Text("Cannot assign"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("OK"),
          ),
        ],
      ),
    );
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
      appBar: AppBar(
        title: const Text("Orders"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh",
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(selected: _statusFilter, onChanged: _setFilter),
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
      return EmptyState(
        icon: Icons.cloud_off,
        title: "Could not load the queue",
        message: _error!,
        onRetry: _load,
      );
    }

    if (_loaded.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: _statusFilter == null ? "No orders yet" : "Nothing here",
        message: _statusFilter == null
            ? "New orders land here the moment a customer places one."
            : "No orders are ${OrderStatusStyle.of(_statusFilter!).label.toLowerCase()} right now.",
        onRetry: _load,
      );
    }

    return RefreshIndicator(
      color: kAmber,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        // One extra row for the footer.
        itemCount: _loaded.length + 1,
        itemBuilder: (context, index) {
          if (index == _loaded.length) return _buildFooter();

          final order = _loaded[index];
          return _OrderCard(
            order: order,
            onViewDetails: () async {
              final updated = await Navigator.push<AdminOrder>(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderDetailScreen(orderId: order.id),
                ),
              );
              if (updated != null) {
                _replace(updated);
              } else {
                await _load();
              }
            },
            onAssignRider: () => _assignRider(order),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, top: 4),
      child: Column(
        children: [
          Text(
            "Showing ${_loaded.length} of $_total",
            style: const TextStyle(color: kMuted, fontSize: 11.5),
          ),
          if (_hasMore) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: 190,
              child: OutlinedButton(
                onPressed: _loadingMore ? null : _loadMore,
                child: _loadingMore
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Load more"),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Horizontal status filter, driving the `?status=` query parameter.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onChanged});

  final String? selected;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        children: [
          _chip(
            label: "All",
            colour: kInk,
            isSelected: selected == null,
            onTap: () => onChanged(null),
          ),
          ...OrderStatusStyle.order.map((status) {
            final style = OrderStatusStyle.of(status);
            return _chip(
              label: style.label,
              icon: style.icon,
              colour: style.colour,
              isSelected: selected == status,
              onTap: () => onChanged(status),
            );
          }),
        ],
      ),
    );
  }

  /// Hand-rolled rather than a ChoiceChip: the selected state needed to carry
  /// the status colour, and Material's chip theming fights that.
  Widget _chip({
    required String label,
    required Color colour,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: isSelected ? colour : Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 15,
                    color: isSelected ? Colors.white : colour,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : kInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onViewDetails,
    required this.onAssignRider,
  });

  final AdminOrder order;
  final VoidCallback onViewDetails;
  final VoidCallback onAssignRider;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // The whole card opens the order; the buttons below are for the
          // two things worth doing without opening it.
          onTap: onViewDetails,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.orderNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16.5,
                          color: kInk,
                        ),
                      ),
                    ),
                    StatusBadge(status: order.status, compact: true),
                  ],
                ),

                const SizedBox(height: 3),

                Text(
                  Dates.full(order.placedAt),
                  style: const TextStyle(fontSize: 11, color: kMuted),
                ),

                const SizedBox(height: 12),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Customer",
                            style: TextStyle(fontSize: 10.5, color: kMuted),
                          ),
                          Text(
                            order.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: kInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      "₱${order.total.toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: kInk,
                      ),
                    ),
                  ],
                ),

                // Once assigned, the rider's name replaces the assign button.
                if (order.isAssigned) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: kCanvas,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.delivery_dining,
                          size: 16,
                          color: kInk,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            order.rider!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: kInk,
                            ),
                          ),
                        ),
                        TagPill(
                          label: order.rider!.deliveryStatus
                              .replaceAll('_', ' '),
                          colour: const Color(0xFF00695C),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 13),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onViewDetails,
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text("Details"),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                      ),
                    ),
                    if (order.canAssignRider) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onAssignRider,
                          icon: const Icon(Icons.person_add_alt, size: 18),
                          label: const Text("Assign"),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
