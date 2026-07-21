class OrderModel {
  final String id;
  final String customerName;
  final String phoneNumber;
  final String address;
  final List<String> items;
  final double totalAmount;
  final String paymentMethod;
  final String status;

  const OrderModel({
    required this.id,
    required this.customerName,
    required this.phoneNumber,
    required this.address,
    required this.items,
    required this.totalAmount,
    required this.paymentMethod,
    required this.status,
  });
}