import '../models/cart_item.dart';

class CartController {
  static final List<CartItem> _cart = [];

  static List<CartItem> get cart => _cart;

  static void addItem(CartItem item) {
    final index = _cart.indexWhere((e) => e.id == item.id);

    if (index != -1) {
      _cart[index].quantity += item.quantity;
    } else {
      _cart.add(item);
    }
  }

  static void removeItem(String id) {
    _cart.removeWhere((item) => item.id == id);
  }

  static void clearCart() {
    _cart.clear();
  }

  static double getTotal() {
    return _cart.fold(
      0,
      (sum, item) => sum + (item.price * item.quantity),
    );
  }
}