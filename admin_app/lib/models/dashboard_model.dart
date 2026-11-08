/// `GET /api/admin/dashboard/` — counts and revenue for today.
class AdminDashboard {
  AdminDashboard({
    required this.date,
    required this.ordersPlaced,
    required this.ordersDelivered,
    required this.ordersCancelled,
    required this.revenue,
    required this.foodSales,
    required this.deliveryFees,
    required this.statusCounts,
    required this.activeOrders,
    required this.ridersTotal,
    required this.ridersOnDuty,
    required this.ridersOnDelivery,
  });

  final String date;

  // Today, in Asia/Manila local dates rather than UTC.
  final int ordersPlaced;
  final int ordersDelivered;
  final int ordersCancelled;

  /// Recognised on delivery, not on placement, so pending orders do not
  /// inflate the day's takings.
  final double revenue;
  final double foodSales;
  final double deliveryFees;

  /// Every `ORDER_STATUS` value mapped to its all-time count.
  final Map<String, int> statusCounts;

  /// Everything not delivered or cancelled.
  final int activeOrders;

  final int ridersTotal;
  final int ridersOnDuty;
  final int ridersOnDelivery;

  int countFor(String status) => statusCounts[status] ?? 0;

  /// What the queue actually needs attention on right now.
  int get pending => countFor('pending');

  factory AdminDashboard.fromJson(Map<String, dynamic> json) {
    final today = json['today'];
    final todayMap = today is Map<String, dynamic> ? today : const {};
    final riders = json['riders'];
    final ridersMap = riders is Map<String, dynamic> ? riders : const {};
    final counts = json['status_counts'];

    return AdminDashboard(
      date: (json['date'] ?? '') as String,
      ordersPlaced: (todayMap['orders_placed'] ?? 0) as int,
      ordersDelivered: (todayMap['orders_delivered'] ?? 0) as int,
      ordersCancelled: (todayMap['orders_cancelled'] ?? 0) as int,
      revenue: _toDouble(todayMap['revenue']),
      foodSales: _toDouble(todayMap['food_sales']),
      deliveryFees: _toDouble(todayMap['delivery_fees']),
      statusCounts: counts is Map
          ? counts.map((key, value) => MapEntry('$key', (value ?? 0) as int))
          : const {},
      activeOrders: (json['active_orders'] ?? 0) as int,
      ridersTotal: (ridersMap['total'] ?? 0) as int,
      ridersOnDuty: (ridersMap['on_duty'] ?? 0) as int,
      ridersOnDelivery: (ridersMap['on_delivery'] ?? 0) as int,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}
