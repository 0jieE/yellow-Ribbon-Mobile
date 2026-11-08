import 'package:flutter/material.dart';

import '../models/order_model.dart';
import '../services/api_client.dart';
import '../services/menu_service.dart';
import '../services/order_service.dart';
import 'order_detail_screen.dart';
import 'order_status.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

/// The orders list plus the menu photos needed to illustrate it.
class _OrdersData {
  const _OrdersData(this.orders, this.photos);

  final List<AppOrder> orders;

  /// Menu id → photo URL. Empty when the menu could not be loaded; the list
  /// still renders, just with placeholder tiles.
  final Map<int, String> photos;
}

/// `GET /api/orders/` — the customer's own orders, newest first.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _orders = OrderService();
  final _menu = MenuService();

  late Future<_OrdersData> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_OrdersData> _fetch() async {
    final orders = await _orders.fetchOrders();

    // Order lines carry the menu id but not the photo, so the pictures are
    // resolved from the menu. Decoration only — a failure here must not cost
    // the customer their order list.
    var photos = <int, String>{};
    try {
      final menu = await _menu.fetchMenu();
      photos = {
        for (final item in menu)
          if (item.photo != null) item.id: item.photo!,
      };
    } on ApiException {
      // Fall through with no photos.
    }

    return _OrdersData(orders, photos);
  }

  Future<void> _reload() async {
    final future = _fetch();
    setState(() => _future = future);
    try {
      await future;
    } on ApiException {
      // Rendered by the FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "My Orders",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: _amber,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: FutureBuilder<_OrdersData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _EmptyOrError(
              icon: Icons.cloud_off,
              message: snapshot.error is ApiException
                  ? (snapshot.error as ApiException).message
                  : "Could not load your orders.",
              onRetry: _reload,
            );
          }

          final data = snapshot.data!;

          if (data.orders.isEmpty) {
            return _EmptyOrError(
              icon: Icons.receipt_long_outlined,
              message: "You have not placed any orders yet.",
              onRetry: _reload,
              // Nothing failed, so there is nothing to retry. Pull to
              // refresh still works.
              showRetry: false,
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: data.orders.length,
              separatorBuilder: (_, _) => const Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
              ),
              itemBuilder: (context, index) => _OrderRow(
                order: data.orders[index],
                photos: data.photos,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          OrderDetailScreen(orderId: data.orders[index].id),
                    ),
                  );
                  // The detail screen can cancel an order, so the list is
                  // refetched rather than trusted on the way back.
                  await _reload();
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One order, laid out after the reference: stacked artwork on the left, then
/// title, a subtitle line, a progress bar with its count, and a pill button
/// beside a short status note.
class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.photos,
    required this.onTap,
  });

  final AppOrder order;
  final Map<int, String> photos;
  final VoidCallback onTap;

  /// What was ordered, for the row's title — "Pepperoni Pizza, Hawaiian, …".
  ///
  /// `order_items` is unique on (order, menu) server-side, so repeat lines
  /// are already merged and no name appears twice. Falls back to the order
  /// number if a payload ever arrives with no lines.
  String get _itemNames {
    if (order.items.isEmpty) return order.orderNumber;
    return order.items.map((item) => item.menuName).join(', ');
  }

  /// The short grey note to the right of the pill.
  ///
  /// The ETA only appears once the rider is in transit — that is the moment
  /// the backend computes one, and before it there is no number to show.
  String get _note {
    if (order.status == 'delivered') return 'completed';
    if (order.status == 'cancelled') return 'cancelled';
    if (order.hasEta) return '~${order.etaMinutes} min';

    final done = OrderProgress.completed(
          order.status,
          deliveryStatus: order.deliveryStatus,
        ) ??
        0;
    final left = OrderProgress.total - done;
    return left <= 0 ? 'almost there' : '$left left';
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = order.items.fold<int>(0, (sum, i) => sum + i.quantity);
    final done = OrderProgress.completed(
      order.status,
      deliveryStatus: order.deliveryStatus,
    );
    // `displayStatus` promotes an out-for-delivery order to "In transit"
    // once the rider is actually moving.
    final style = OrderStatusStyle.of(order.displayStatus);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StackedPhotos(items: order.items, photos: photos),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // What was ordered leads, since that is what a customer
                  // recognises their own order by. Two lines, then ellipsis.
                  Text(
                    _itemNames,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),

                  const SizedBox(height: 5),

                  // The status carries its own colour so the queue can be
                  // read at a glance; the rest of the line stays quiet.
                  Row(
                    children: [
                      StatusBadge(status: order.displayStatus, compact: true),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          // The order number still has to be here — it is
                          // what the customer quotes to the store — and the
                          // count survives the title being truncated.
                          "${order.orderNumber} • $itemCount "
                          "item${itemCount == 1 ? '' : 's'} "
                          "• ₱${order.total.toStringAsFixed(2)}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // PROGRESS — named, not just a fraction. "4/7" alone does
                  // not tell anyone what is happening to their food.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          OrderProgress.labelFor(
                            order.status,
                            deliveryStatus: order.deliveryStatus,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: done == null ? Colors.grey : style.colour,
                          ),
                        ),
                      ),
                      Text(
                        done == null ? '—' : '$done of ${OrderProgress.total}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 5),

                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: done == null ? 0 : done / OrderProgress.total,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade300,
                      // Tinted to the status too, so the bar says the same
                      // thing as the label above it.
                      valueColor: AlwaysStoppedAnimation(
                        order.status == 'cancelled'
                            ? Colors.grey.shade400
                            : style.colour,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // PILL + NOTE
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: onTap,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          side: BorderSide(color: Colors.grey.shade400),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          minimumSize: const Size(0, 34),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: const Text("Order info"),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _note,
                        style: TextStyle(
                          fontSize: 12.5,
                          // Finished states carry their colour; anything
                          // still in flight stays quiet so it does not
                          // compete with the badge.
                          fontWeight: order.isTerminal
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: order.isTerminal
                              ? style.colour
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Up to three item photos fanned out, front-most first.
///
/// A single-item order shows one tile; more items stack behind it, which is
/// what signals "this order has several things in it" at a glance.
class _StackedPhotos extends StatelessWidget {
  const _StackedPhotos({required this.items, required this.photos});

  final List<OrderItem> items;
  final Map<int, String> photos;

  static const _tileWidth = 62.0;
  static const _tileHeight = 88.0;
  static const _offset = 7.0;

  @override
  Widget build(BuildContext context) {
    final shown = items.take(3).toList();
    final depth = shown.isEmpty ? 1 : shown.length;

    return SizedBox(
      width: _tileWidth + (depth - 1) * _offset,
      height: _tileHeight + (depth - 1) * (_offset * 0.6),
      child: Stack(
        children: [
          // Painted back to front so the first item ends up on top.
          for (var i = depth - 1; i >= 0; i--)
            Positioned(
              left: i * _offset,
              top: i * (_offset * 0.6),
              child: _PhotoTile(
                url: i < shown.length ? photos[shown[i].menuId] : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _StackedPhotos._tileWidth,
      height: _StackedPhotos._tileHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        // A white edge keeps the tiles readable as separate cards where they
        // overlap.
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? Container(
              color: _ink,
              child: const Icon(
                Icons.local_pizza,
                color: _amber,
                size: 26,
              ),
            )
          : Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: _ink,
                child: const Icon(
                  Icons.local_pizza,
                  color: _amber,
                  size: 26,
                ),
              ),
            ),
    );
  }
}

class _EmptyOrError extends StatelessWidget {
  const _EmptyOrError({
    required this.icon,
    required this.message,
    required this.onRetry,
    this.showRetry = true,
  });

  final IconData icon;
  final String message;
  final Future<void> Function() onRetry;
  final bool showRetry;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 90),
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
