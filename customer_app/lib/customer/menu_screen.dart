import 'package:flutter/material.dart';

import '../controllers/cart_controller.dart';
import '../models/cart_item.dart';
import '../models/menu_item.dart';
import '../services/api_client.dart';
import '../services/menu_service.dart';
import 'cart_screen.dart';
import 'menu_item_detail_screen.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final _menuService = MenuService();

  late Future<List<MenuItem>> _menu;

  @override
  void initState() {
    super.initState();
    _menu = _menuService.fetchMenu();
  }

  Future<void> _reload() async {
    final future = _menuService.fetchMenu();
    setState(() => _menu = future);
    // Let RefreshIndicator spin until the new list has actually landed.
    await future.catchError((_) => <MenuItem>[]);
  }

  /// The ORDER button adds a single unit. Quantities are changed in the cart,
  /// which is the only screen with steppers.
  void _addToCart(MenuItem item) {
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
        duration: const Duration(seconds: 1),
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

  Future<void> _openDetail(MenuItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        // The row is already loaded, so no round trip is needed.
        builder: (_) => MenuItemDetailScreen(menuId: item.id, item: item),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = CartController.cart.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),

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

      body: FutureBuilder<List<MenuItem>>(
        future: _menu,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _MenuMessage(
              message: snapshot.error is ApiException
                  ? (snapshot.error as ApiException).message
                  : "Could not load the menu.",
              onRetry: _reload,
            );
          }

          final items = snapshot.data ?? const <MenuItem>[];

          if (items.isEmpty) {
            return _MenuMessage(
              message: "No items are on the menu right now.",
              onRetry: _reload,
              isError: false,
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 13,
                mainAxisSpacing: 13,
                // A fixed height is steadier than an aspect ratio here: card
                // content varies with the description length.
                mainAxisExtent: 280,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => _MenuCard(
                item: items[index],
                onTap: () => _openDetail(items[index]),
                onOrder: () => _addToCart(items[index]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One item on the menu grid.
///
/// Laid out after the reference design: a dark information block beside the
/// photo, the name across the middle, then price and an ORDER button. The
/// reference also carries a VEG/NON-VEG tag and a discount pill; the `Menu`
/// model has neither a category nor a discount field, so those are left out
/// rather than faked. The dark block shows the item's description, which is
/// the closest real equivalent to its ingredients list.
class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.item,
    required this.onTap,
    required this.onOrder,
  });

  final MenuItem item;
  final VoidCallback onTap;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _amber,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // PHOTO, with the description floating over its top-left.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: item.photo == null
                                ? const _PhotoPlaceholder()
                                : Image.network(
                                    item.photo!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const _PhotoPlaceholder(),
                                  ),
                          ),
                        ),

                        // Sized to its own content rather than stretched, so
                        // a short description stays a small floating chip and
                        // leaves as much of the photo visible as possible.
                        Positioned(
                          top: 7,
                          left: 7,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * 0.64,
                            ),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                              decoration: BoxDecoration(
                                color: _ink,
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black38,
                                    blurRadius: 7,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "DESCRIPTION",
                                    style: TextStyle(
                                      color: _amber,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.9,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.description.isEmpty
                                        ? "Freshly baked, made to order."
                                        : item.description,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 9.5,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 10),

              // NAME
              Text(
                item.name.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.black,
                  letterSpacing: 0.3,
                ),
              ),

              const SizedBox(height: 8),

              // PRICE + ORDER
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "₱${item.price.toStringAsFixed(2)}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 30,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _ink,
                        foregroundColor: _amber,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
                      onPressed: onOrder,
                      child: const Text("ORDER"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fills the whole photo area when an item has no picture, or its URL fails
/// to load. Kept light so the dark description chip still reads over it.
class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      alignment: Alignment.bottomRight,
      padding: const EdgeInsets.all(10),
      child: const Icon(
        Icons.local_pizza,
        color: Color(0xFFFFE082),
        size: 54,
      ),
    );
  }
}

class _MenuMessage extends StatelessWidget {
  const _MenuMessage({
    required this.message,
    required this.onRetry,
    this.isError = true,
  });

  final String message;
  final Future<void> Function() onRetry;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    // Inside a scroll view so RefreshIndicator still works on an empty list.
    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
        children: [
          Icon(
            isError ? Icons.cloud_off : Icons.local_pizza_outlined,
            size: 48,
            color: Colors.grey,
          ),
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
