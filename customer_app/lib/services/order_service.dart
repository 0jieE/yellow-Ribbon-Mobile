import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/order_model.dart';

class OrderService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> createOrder(OrderModel order) async {
    await _db.collection("orders").add(order.toMap());
  }
}