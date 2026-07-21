import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../controllers/cart_controller.dart';
import '../models/cart_item.dart';
import 'cart_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  Map<String, int> qty = {};

  int getQty(String id) => qty[id] ?? 1;

  void inc(String id) {
    setState(() {
      qty[id] = getQty(id) + 1;
    });
  }

  void dec(String id) {
    setState(() {
      if (getQty(id) > 1) {
        qty[id] = getQty(id) - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),

      appBar: AppBar(
        title: const Text("Welcome!"),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CartScreen()),
              ).then((_) => setState(() {}));
            },
          )
        ],
      ),

      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection("menu").snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final id = docs[index].id;

              final name = data["name"];
              final price = (data["price"] as num).toDouble();

              // ✅ SAFE IMAGE (prevents 404 crash)
              final image = data["image"] ??
                  "https://images.unsplash.com/photo-1601924582970-9238bcb495d9";

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    )
                  ],
                ),

                child: Row(
                  children: [
                    // 🍕 IMAGE (SAFE)
                    Container(
                      width: 75,
                      height: 75,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        image: DecorationImage(
                          image: NetworkImage(image),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Container(), // prevents layout crash
                    ),

                    const SizedBox(width: 12),

                    // DETAILS
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 4),

                          const Text(
                            "Freshly baked pizza",
                            style: TextStyle(color: Colors.grey),
                          ),

                          const SizedBox(height: 6),

                          Text(
                            "₱${price.toStringAsFixed(2)}",
                            style: const TextStyle(
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // QUANTITY + ADD
                    Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => dec(id),
                            ),
                            Text(
                              "${getQty(id)}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => inc(id),
                            ),
                          ],
                        ),

                        SizedBox(
                          width: 100,
                          child: ElevatedButton(
                            onPressed: () {
                              CartController.addItem(
                                CartItem(
                                  id: id,
                                  name: name,
                                  price: price,
                                  quantity: getQty(id),
                                ),
                              );

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("$name added to cart"),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                            child: const Text("Add"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}