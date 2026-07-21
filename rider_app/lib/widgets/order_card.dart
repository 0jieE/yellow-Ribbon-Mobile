import 'package:flutter/material.dart';

import '../models/order_model.dart';

class OrderCard extends StatelessWidget {
  final OrderModel order;
  final VoidCallback? onTap;

  const OrderCard({
    super.key,
    required this.order,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor =
        order.status == "Completed"
            ? Colors.green
            : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Row(
                children: [

                  const CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.amber,
                    child: Icon(
                      Icons.local_pizza,
                      color: Colors.black,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Text(
                      order.id,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  Chip(
                    backgroundColor: statusColor,
                    label: Text(
                      order.status,
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  const Icon(Icons.person),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      order.customerName,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(order.address),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  const Icon(Icons.payments),
                  const SizedBox(width: 10),
                  Text(order.paymentMethod),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  const Icon(Icons.attach_money),
                  const SizedBox(width: 10),
                  Text(
                    "₱${order.totalAmount.toStringAsFixed(2)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),

              const Divider(height: 30),

              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [

                  Icon(
                    Icons.arrow_forward_ios,
                    size: 18,
                    color: Colors.grey,
                  ),

                  SizedBox(width: 5),

                  Text(
                    "Tap to View Details",
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}