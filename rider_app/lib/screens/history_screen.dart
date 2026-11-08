import 'package:flutter/material.dart';

import '../models/delivery_model.dart';
import '../services/api_client.dart';
import '../services/delivery_service.dart';
import '../widgets/delivery_status.dart';
import 'order_details_screen.dart';

/// `GET /api/rider/deliveries/history/` — completed and failed deliveries.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _deliveries = DeliveryService();

  late Future<List<Delivery>> _future;

  @override
  void initState() {
    super.initState();
    _future = _deliveries.fetchHistory();
  }

  Future<void> _reload() async {
    final future = _deliveries.fetchHistory();
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
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        title: const Text(
          "Delivery History",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: FutureBuilder<List<Delivery>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _Placeholder(
              icon: Icons.cloud_off,
              message: snapshot.error is ApiException
                  ? (snapshot.error as ApiException).message
                  : "Could not load your history.",
              onRetry: _reload,
            );
          }

          final deliveries = snapshot.data ?? const <Delivery>[];

          if (deliveries.isEmpty) {
            return _Placeholder(
              icon: Icons.history,
              message: "You have not completed any deliveries yet.",
              onRetry: _reload,
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: deliveries.length,
              itemBuilder: (context, index) {
                final delivery = deliveries[index];
                final style = DeliveryStatusStyle.of(delivery.status);
                final delivered = delivery.status == 'delivered';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              OrderDetailsScreen(deliveryId: delivery.id),
                        ),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Delivered or failed, readable while scrolling.
                            Container(width: 5, color: style.colour),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    Icon(
                                      style.icon,
                                      color: style.colour,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            delivery.order.orderNumber,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            delivery.order.deliveryAddress,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            Dates.full(
                                              delivery.deliveredAt ??
                                                  delivery.assignedAt,
                                            ),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          style.label,
                                          style: TextStyle(
                                            color: style.colour,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (delivered) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            "+₱${delivery.riderEarnings.toStringAsFixed(2)}",
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String message;
  final Future<void> Function() onRetry;

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
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton(
              onPressed: onRetry,
              child: const Text("Retry"),
            ),
          ),
        ],
      ),
    );
  }
}
