// Unit tests for the cart logic.
//
// A full-app widget test is not possible here without mocking Firebase:
// main() calls Firebase.initializeApp() before runApp. These tests cover the
// pure-Dart cart logic instead.

import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/controllers/cart_controller.dart';
import 'package:customer_app/models/cart_item.dart';

void main() {
  // CartController keeps its state in a static list, so it must be reset
  // between tests.
  setUp(CartController.clearCart);

  test('addItem adds a new item to the cart', () {
    CartController.addItem(
      CartItem(id: 1, name: 'Pepperoni', price: 250),
    );

    expect(CartController.cart, hasLength(1));
    expect(CartController.cart.first.name, 'Pepperoni');
    expect(CartController.cart.first.quantity, 1);
  });

  test('addItem merges quantity when the same id is added again', () {
    CartController.addItem(
      CartItem(id: 1, name: 'Pepperoni', price: 250),
    );
    CartController.addItem(
      CartItem(id: 1, name: 'Pepperoni', price: 250, quantity: 2),
    );

    expect(CartController.cart, hasLength(1));
    expect(CartController.cart.first.quantity, 3);
  });

  test('getTotal sums price times quantity across items', () {
    CartController.addItem(
      CartItem(id: 1, name: 'Pepperoni', price: 250, quantity: 2),
    );
    CartController.addItem(
      CartItem(id: 2, name: 'Hawaiian', price: 300),
    );

    expect(CartController.getTotal(), 800);
  });

  test('removeItem drops only the matching item', () {
    CartController.addItem(CartItem(id: 1, name: 'Pepperoni', price: 250));
    CartController.addItem(CartItem(id: 2, name: 'Hawaiian', price: 300));

    CartController.removeItem(1);

    expect(CartController.cart, hasLength(1));
    expect(CartController.cart.single.id, 2);
  });

  test('clearCart empties the cart', () {
    CartController.addItem(CartItem(id: 1, name: 'Pepperoni', price: 250));

    CartController.clearCart();

    expect(CartController.cart, isEmpty);
    expect(CartController.getTotal(), 0);
  });

  test('toOrderItemJson sends the menu id and quantity, never a price', () {
    final item = CartItem(id: 7, name: 'Pepperoni', price: 250, quantity: 2);

    expect(item.toOrderItemJson(), {'menu_id': 7, 'quantity': 2});
    expect(item.total, 500);
  });
}
