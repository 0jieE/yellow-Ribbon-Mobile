import 'package:flutter/material.dart';

import '../models/order_model.dart';

class OrderDetailsScreen extends StatelessWidget {
  final OrderModel order;

  const OrderDetailsScreen({
    super.key,
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Order ${order.id}"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer Information
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Customer Information",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),

                    ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(order.customerName),
                    ),

                    ListTile(
                      leading: const Icon(Icons.phone),
                      title: Text(order.phoneNumber),
                    ),

                    ListTile(
                      leading: const Icon(Icons.location_on),
                      title: Text(order.address),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Order Items
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Ordered Items",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    ...order.items.map(
                      (item) => ListTile(
                        leading: const Icon(Icons.local_pizza),
                        title: Text(item),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Payment Details
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.payments),
                      title: const Text("Payment Method"),
                      subtitle: Text(order.paymentMethod),
                    ),
                    ListTile(
                      leading: const Icon(Icons.attach_money),
                      title: const Text("Total Amount"),
                      subtitle: Text(
                        "₱${order.totalAmount.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Delivery Status
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.assignment_turned_in,
                  color: Colors.orange,
                ),
                title: const Text("Delivery Status"),
                subtitle: Text(order.status),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  // Camera/Gallery will be implemented later.
                },
                icon: const Icon(Icons.camera_alt),
                label: const Text("Upload Proof of Delivery"),
              ),
            ),

            const SizedBox(height: 15),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Backend update will be implemented later.
                },
                icon: const Icon(Icons.check_circle),
                label: const Text("Mark as Delivered"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}