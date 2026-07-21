import 'package:flutter/material.dart';

import '../data/dummy_orders.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final assignedOrders =
        dummyOrders.where((o) => o.status == "Assigned").length;

    final completedOrders =
        dummyOrders.where((o) => o.status == "Completed").length;

    final totalEarnings = dummyOrders
        .where((o) => o.status == "Completed")
        .fold<double>(
          0,
          (sum, order) => sum + order.totalAmount,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Rider Dashboard"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.amber,
                      child: Icon(
                        Icons.delivery_dining,
                        color: Colors.black,
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 15),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Welcome Rider!",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            "Ready for today's deliveries?",
                            style: TextStyle(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: _statCard(
                    title: "Assigned",
                    value: assignedOrders.toString(),
                    icon: Icons.assignment,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    title: "Completed",
                    value: completedOrders.toString(),
                    icon: Icons.check_circle,
                    color: Colors.green,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            _earningsCard(totalEarnings),

            const SizedBox(height: 30),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Quick Actions",
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),

            const SizedBox(height: 15),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.delivery_dining),
                label: const Text(
                  "Assigned Deliveries",
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.history),
                label: const Text(
                  "Completed Deliveries",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 22,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: color,
              size: 34,
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(title),
          ],
        ),
      ),
    );
  }

  static Widget _earningsCard(double total) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.green,
          child: Icon(
            Icons.payments,
            color: Colors.white,
          ),
        ),
        title: const Text("Completed Delivery Earnings"),
        subtitle: Text(
          "₱${total.toStringAsFixed(2)}",
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}