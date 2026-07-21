import 'package:flutter/material.dart';

import '../data/dummy_orders.dart';
import '../widgets/order_card.dart';
import 'order_details_screen.dart';

class AssignedOrdersScreen extends StatelessWidget {
  const AssignedOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final assignedOrders = dummyOrders
        .where((order) => order.status == "Assigned")
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Assigned Orders"),
      ),
      body: assignedOrders.isEmpty
          ? const Center(
              child: Text(
                "No assigned orders.",
                style: TextStyle(fontSize: 18),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: assignedOrders.length,
              itemBuilder: (context, index) {
                final order = assignedOrders[index];

                return OrderCard(
                  order: order,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderDetailsScreen(order: order),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}