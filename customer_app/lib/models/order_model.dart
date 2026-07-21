class OrderModel {
  final String userId;
  final List items;
  final double total;
  final String status;
  final DateTime createdAt;

  OrderModel({
    required this.userId,
    required this.items,
    required this.total,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      "userId": userId,
      "items": items,
      "total": total,
      "status": status,
      "createdAt": createdAt.toIso8601String(),
    };
  }
}