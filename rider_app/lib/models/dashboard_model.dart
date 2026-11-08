/// `GET /api/rider/dashboard/`.
class RiderDashboard {
  RiderDashboard({
    required this.name,
    required this.isAvailable,
    required this.assigned,
    required this.completed,
    required this.failed,
    required this.earningsTotal,
    required this.earningsToday,
    required this.completedToday,
  });

  final String name;
  final bool isAvailable;

  /// Deliveries currently in an active state.
  final int assigned;
  final int completed;
  final int failed;

  /// Sums of the `rider_earnings` snapshots taken at assignment, so past pay
  /// never moves when the delivery fee changes.
  final double earningsTotal;
  final double earningsToday;

  final int completedToday;

  factory RiderDashboard.fromJson(Map<String, dynamic> json) {
    final earnings = json['earnings'];
    final earningsMap = earnings is Map<String, dynamic> ? earnings : const {};
    final today = json['today'];
    final todayMap = today is Map<String, dynamic> ? today : const {};

    return RiderDashboard(
      name: (json['name'] ?? 'Rider') as String,
      isAvailable: (json['is_available'] ?? false) as bool,
      assigned: (json['assigned'] ?? 0) as int,
      completed: (json['completed'] ?? 0) as int,
      failed: (json['failed'] ?? 0) as int,
      earningsTotal: _toDouble(earningsMap['total']),
      earningsToday: _toDouble(earningsMap['today']),
      completedToday: (todayMap['completed'] ?? 0) as int,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}
