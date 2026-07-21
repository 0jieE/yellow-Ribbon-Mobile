import '../models/order_model.dart';

const List<OrderModel> dummyOrders = [
  OrderModel(
    id: "YR001",
    customerName: "Juan Dela Cruz",
    phoneNumber: "09123456789",
    address: "Poblacion, Kidapawan City",
    items: [
      "Hawaiian Pizza x1",
      "Pepperoni Pizza x2",
    ],
    totalAmount: 850,
    paymentMethod: "Cash on Delivery",
    status: "Assigned",
  ),

  OrderModel(
    id: "YR002",
    customerName: "Maria Santos",
    phoneNumber: "09987654321",
    address: "Magsaysay, Kidapawan City",
    items: [
      "Cheese Pizza x1",
    ],
    totalAmount: 420,
    paymentMethod: "GCash",
    status: "Assigned",
  ),

  OrderModel(
    id: "YR003",
    customerName: "Pedro Reyes",
    phoneNumber: "09112223344",
    address: "Lanao, Kidapawan City",
    items: [
      "Supreme Pizza x1",
      "Ham & Cheese Pizza x1",
    ],
    totalAmount: 780,
    paymentMethod: "Cash on Delivery",
    status: "Completed",
  ),

  OrderModel(
    id: "YR004",
    customerName: "Ana Lopez",
    phoneNumber: "09175556666",
    address: "Sudapin, Kidapawan City",
    items: [
      "Pepperoni Pizza x1",
    ],
    totalAmount: 350,
    paymentMethod: "GCash",
    status: "Completed",
  ),
];