import 'package:flutter/material.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> orders = [
      {
        "id": "#1001",
        "customer": "Juan Dela Cruz",
        "total": "₱650",
        "status": "Pending",
        "color": Colors.orange,
      },
      {
        "id": "#1002",
        "customer": "Maria Santos",
        "total": "₱980",
        "status": "Preparing",
        "color": Colors.blue,
      },
      {
        "id": "#1003",
        "customer": "Carlo Reyes",
        "total": "₱430",
        "status": "Delivered",
        "color": Colors.green,
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Orders"),
        centerTitle: true,
        backgroundColor: Colors.amber,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(15),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];

          return Card(
            elevation: 4,
            margin: const EdgeInsets.only(bottom: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        order["id"],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: order["color"],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          order["status"],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    ],
                  ),

                  const SizedBox(height: 15),

                  Text(
                    "Customer: ${order["customer"]}",
                    style: const TextStyle(fontSize: 16),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "Total: ${order["total"]}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () {},
                      icon: const Icon(Icons.visibility),
                      label: const Text("View Details"),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.amber,
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}