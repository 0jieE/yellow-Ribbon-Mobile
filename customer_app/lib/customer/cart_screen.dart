import 'package:flutter/material.dart';

import '../controllers/cart_controller.dart';
import '../models/cart_item.dart';
import 'checkout_screen.dart';
import 'menu_item_detail_screen.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

/// The cart. This is the only screen where quantities change — the menu adds
/// one at a time and everything else just reads the totals.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  List<CartItem> get cart => CartController.cart;

  double get subtotal => CartController.getTotal();

  int get itemCount => cart.fold<int>(0, (sum, item) => sum + item.quantity);

  void increaseQty(int id) {
    setState(() => cart.firstWhere((e) => e.id == id).quantity += 1);
  }

  void decreaseQty(int id) {
    final item = cart.firstWhere((e) => e.id == id);
    setState(() {
      if (item.quantity > 1) {
        item.quantity -= 1;
      } else {
        // Stepping below one removes the line rather than leaving a zero.
        CartController.removeItem(id);
      }
    });
  }

  /// Opens the full item view so the customer can re-read what they picked.
  ///
  /// The cart only keeps id, name, price and photo, so the detail screen
  /// fetches the row by id for the description — and reports it if the store
  /// has taken the item off the menu since it was added.
  Future<void> _review(CartItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MenuItemDetailScreen(menuId: item.id)),
    );
    // Reviewing can add another of the same item.
    if (mounted) setState(() {});
  }

  void remove(CartItem item) {
    setState(() => CartController.removeItem(item.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("${item.name} removed"),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          itemCount == 0 ? "My Cart" : "My Cart ($itemCount)",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: _amber,
        foregroundColor: Colors.black,
        elevation: 0,
      ),

      body: cart.isEmpty
          ? const _EmptyCart()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: cart.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) => _CartRow(
                item: cart[index],
                onIncrease: () => increaseQty(cart[index].id),
                onDecrease: () => decreaseQty(cart[index].id),
                onRemove: () => remove(cart[index]),
                onReview: () => _review(cart[index]),
              ),
            ),

      bottomNavigationBar: cart.isEmpty ? null : _Summary(subtotal: subtotal),
    );
  }
}

/// One cart line, matching the orders list: photo on the left, details right.
class _CartRow extends StatelessWidget {
  const _CartRow({
    required this.item,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    required this.onReview,
  });

  final CartItem item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    // Tapping the row opens the item; the stepper and bin sit above this in
    // the tree, so they keep their own taps.
    return InkWell(
      onTap: onReview,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PhotoTile(url: item.photo),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            height: 1.15,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 21),
                        color: Colors.grey,
                        visualDensity: VisualDensity.compact,
                        tooltip: "Remove",
                        onPressed: onRemove,
                      ),
                    ],
                  ),

                  Text(
                    "₱${item.price.toStringAsFixed(2)} each",
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "₱${item.total.toStringAsFixed(2)}",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ),
                      _Stepper(
                        quantity: item.quantity,
                        onIncrease: onIncrease,
                        onDecrease: onDecrease,
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

/// Compact − / count / + control.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.onIncrease,
    required this.onDecrease,
  });

  final int quantity;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            // At one, the minus removes the line — the icon says so.
            icon: quantity > 1 ? Icons.remove : Icons.delete_outline,
            onTap: onDecrease,
          ),
          SizedBox(
            width: 30,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          _StepButton(icon: Icons.add, onTap: onIncrease),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(icon, size: 17, color: _amber),
      ),
    );
  }
}

/// Totals and the checkout button.
class _Summary extends StatelessWidget {
  const _Summary({required this.subtotal});

  final double subtotal;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Subtotal", style: TextStyle(fontSize: 15)),
                  Text(
                    "₱${subtotal.toStringAsFixed(2)}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              // The fee comes from /api/constants/ and the server recomputes
              // every figure at placement, so it is not guessed at here.
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Delivery fee added at checkout",
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ),

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: _amber,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CheckoutScreen(total: subtotal),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text(
                    "CHECKOUT",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
      width: 62,
      height: 88,
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? const Icon(Icons.local_pizza, color: _amber, size: 26)
          : Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.local_pizza, color: _amber, size: 26),
            ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 60,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 14),
            const Text(
              "Your cart is empty",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              "Add something from the menu to get started.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
