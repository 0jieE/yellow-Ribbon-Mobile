/// One line in the local cart.
///
/// [id] is the Django `menu.id`, which is what `POST /api/orders/` expects as
/// `menu_id`. [price] is kept only to show a running total while the customer
/// shops — the server recomputes every total from its own prices when the
/// order is placed.
class CartItem {
  CartItem({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.photo,
  });

  final int id;
  final String name;
  final double price;
  int quantity;

  /// Carried over from the menu item so the cart can show a picture without
  /// re-fetching the menu. Display only — it is never sent to the server.
  final String? photo;

  double get total => price * quantity;

  /// The shape `POST /api/orders/` wants for each line: what to buy and how
  /// many, never a price.
  Map<String, dynamic> toOrderItemJson() => {
        'menu_id': id,
        'quantity': quantity,
      };
}
