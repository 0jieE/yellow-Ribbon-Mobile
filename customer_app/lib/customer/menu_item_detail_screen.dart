import 'package:flutter/material.dart';

import '../controllers/cart_controller.dart';
import '../models/cart_item.dart';
import '../models/menu_item.dart';
import '../services/api_client.dart';
import '../services/menu_service.dart';
import 'cart_screen.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

/// Full detail for one menu item.
///
/// The photo fills the whole content area — portrait phone photos suit this,
/// since `BoxFit.cover` crops them least — and the name, price, description
/// and Add to Cart button float on top of it.
///
/// The menu's amber bar stays put above, so the screen reads as a continuation
/// of the menu rather than a different place.
///
/// Everything shown comes from the `Menu` row: name, description, price and
/// photo. Quantity is deliberately not adjustable here; the cart is the one
/// place where amounts change.
class MenuItemDetailScreen extends StatefulWidget {
  const MenuItemDetailScreen({super.key, required this.menuId, this.item});

  /// Which menu row to show.
  final int menuId;

  /// Supplied when the caller already has the row — the menu grid does, so it
  /// renders with no round trip. The cart only stores id, name, price and
  /// photo, so it passes null and the description is fetched.
  final MenuItem? item;

  @override
  State<MenuItemDetailScreen> createState() => _MenuItemDetailScreenState();
}

class _MenuItemDetailScreenState extends State<MenuItemDetailScreen> {
  final _menu = MenuService();

  MenuItem? _item;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    if (_item == null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final item = await _menu.fetchOne(widget.menuId);
      if (!mounted) return;
      setState(() {
        _item = item;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // A 404 here is meaningful rather than broken: the store has taken
        // the item off the menu, and an order containing it would be refused.
        _error = e.statusCode == 404
            ? "This item is no longer on the menu. Remove it from your cart "
                "before checking out."
            : e.message;
      });
    }
  }

  MenuItem get item => _item!;

  void _addToCart() {
    CartController.addItem(
      CartItem(
        id: item.id,
        name: item.name,
        price: item.price,
        photo: item.photo,
      ),
    );
    setState(() {}); // refresh the app bar cart count

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("${item.name} added to cart"),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(label: "VIEW CART", onPressed: _openCart),
      ),
    );
  }

  Future<void> _openCart() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CartScreen()),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = CartController.cart.fold<int>(
      0,
      (sum, line) => sum + line.quantity,
    );

    return Scaffold(
      backgroundColor: Colors.black,

      // Identical to the menu's bar, so it looks like it simply stayed.
      appBar: AppBar(
        backgroundColor: _amber,
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          "Yellow Ribbon Pizza",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: "Cart",
            icon: Badge(
              isLabelVisible: cartCount > 0,
              label: Text('$cartCount'),
              backgroundColor: _ink,
              child: const Icon(Icons.shopping_cart_outlined),
            ),
            onPressed: _openCart,
          ),
        ],
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _amber))
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. The photo, filling everything under the bar.
        _Photo(url: item.photo),

        // 2. A scrim, so white text stays readable whatever the photo
        //    happens to look like. Clear at the top where the food is,
        //    dark at the bottom where the text sits.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Color(0x66000000),
                Color(0xE6000000),
              ],
              stops: [0.28, 0.55, 1.0],
            ),
          ),
        ),

        // 3. The content, sitting on top of the photo. Anchored to the
        //    bottom, and scrollable in place if a long description would
        //    otherwise run off the top.
        SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    "₱${item.price.toStringAsFixed(2)}",
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      color: _amber,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      // Slightly translucent so it reads as floating on the
                      // photo rather than a panel stuck over it.
                      color: _ink.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "DESCRIPTION",
                          style: TextStyle(
                            color: _amber,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.description.isEmpty
                              ? "Freshly baked, made to order."
                              : item.description,
                          style: const TextStyle(
                            color: Colors.white,
                            height: 1.5,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Amber fill here rather than the menu's dark button —
                  // a dark button would disappear into the scrim.
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _amber,
                        foregroundColor: Colors.black,
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _addToCart,
                      icon: const Icon(Icons.shopping_cart_outlined),
                      label: const Text(
                        "ADD TO CART",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Center(
                    child: Text(
                      "Adjust the quantity in your cart.",
                      style: TextStyle(fontSize: 11.5, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown when the item could not be loaded — most usefully when the store has
/// taken it off the menu since it was added to the cart.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_meals, size: 52, color: Colors.white38),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _amber,
                foregroundColor: Colors.black,
              ),
              onPressed: onRetry,
              child: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null) return const _PhotoPlaceholder();

    return Image.network(
      url!,
      // Portrait photos fill the frame with the least cropping this way.
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _PhotoPlaceholder(),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _amber,
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 70),
      child: const Icon(Icons.local_pizza, size: 110, color: Colors.black26),
    );
  }
}
