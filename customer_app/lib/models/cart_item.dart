class CartItem {
  final String id;
  final String name;
  final double price;
  int quantity;

  CartItem({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 1,
  });

  double get total => price * quantity;

  // ✅ ADD THIS (VERY IMPORTANT FOR FIRESTORE)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'quantity': quantity,
      'total': total,
    };
  }

  // (Optional but useful later)
  factory CartItem.fromMap(Map<String, dynamic> map) {
    return CartItem(
      id: map['id'],
      name: map['name'],
      price: (map['price'] as num).toDouble(),
      quantity: map['quantity'],
    );
  }
}