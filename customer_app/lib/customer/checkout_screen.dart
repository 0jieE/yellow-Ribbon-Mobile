import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../controllers/cart_controller.dart';

class CheckoutScreen extends StatefulWidget {
  final double total;

  const CheckoutScreen({super.key, required this.total});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final addressController = TextEditingController();

  bool loading = false;

  final double deliveryFee = 30.0;

  String phone = "";
  String name = "";

  String paymentMethod = "Cash on Delivery";

  double get grandTotal => widget.total + deliveryFee;

  @override
  void initState() {
    super.initState();
    loadUserData();
  }

  Future<void> loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();

    if (doc.exists) {
      setState(() {
        phone = doc.data()?["phone"] ?? "";
        name = doc.data()?["name"] ?? "";
      });
    }
  }

  Future<void> placeOrder() async {
    if (addressController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter delivery address")),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      await FirebaseFirestore.instance.collection('orders').add({
        // 👤 USER INFO
        'userId': user?.uid,
        'name': name,
        'phone': phone,

        // 📍 DELIVERY INFO
        'deliveryAddress': addressController.text.trim(),

        // 💳 PAYMENT
        'paymentMethod': paymentMethod,

        // 📦 ORDER STATUS
        'status': 'pending',
        'createdAt': Timestamp.now(),

        // 🍕 ITEMS
        'items': CartController.cart.map((item) {
          return {
            'id': item.id,
            'name': item.name,
            'price': item.price,
            'quantity': item.quantity,
            'subtotal': item.price * item.quantity,
          };
        }).toList(),

        // 💰 PRICING
        'subtotal': widget.total,
        'deliveryFee': deliveryFee,
        'total': grandTotal,
      });

      // CLEAR CART AFTER ORDER
      CartController.cart.clear();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Order placed successfully!")),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    const primaryYellow = Color(0xFFFFC107);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Checkout"),
        centerTitle: true,
        backgroundColor: primaryYellow,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // CUSTOMER INFO
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Customer Info",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text("Name: $name"),
                  Text("Phone: $phone"),
                ],
              ),
            ),

            const SizedBox(height: 15),

            // ADDRESS
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Delivery Address",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: addressController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: "Enter your full address",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 15),

            // PAYMENT METHOD
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Payment Method",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  RadioListTile(
                    title: const Text("Cash on Delivery"),
                    value: "Cash on Delivery",
                    groupValue: paymentMethod,
                    onChanged: (value) {
                      setState(() {
                        paymentMethod = value.toString();
                      });
                    },
                  ),
                  RadioListTile(
                    title: const Text("GCash"),
                    value: "GCash",
                    groupValue: paymentMethod,
                    onChanged: (value) {
                      setState(() {
                        paymentMethod = value.toString();
                      });
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // SUMMARY
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _row("Subtotal", widget.total),
                  _row("Delivery Fee", deliveryFee),
                  const Divider(),
                  _row("Total", grandTotal, isBold: true),
                ],
              ),
            ),

            const Spacer(),

            // PLACE ORDER BUTTON
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : placeOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryYellow,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.all(14),
                ),
                child: loading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text(
                        "Place Order",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, double value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          "₱${value.toStringAsFixed(2)}",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isBold ? Colors.red : Colors.black,
          ),
        ),
      ],
    );
  }
}