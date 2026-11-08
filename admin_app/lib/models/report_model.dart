/// An inclusive local-date window. Both reports and the picker speak this.
///
/// Dates only — the backend works in Asia/Manila local dates, so a delivery at
/// 07:30 Manila on the 3rd belongs to the 3rd. Sending a timestamp would
/// invite a timezone slip.
class DateRange {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  /// The backend's default when no parameters are sent.
  factory DateRange.lastDays(int days, {DateTime? today}) {
    final end = _dateOnly(today ?? DateTime.now());
    return DateRange(end.subtract(Duration(days: days - 1)), end);
  }

  int get days => end.difference(start).inDays + 1;

  String get startParam => isoDate(start);
  String get endParam => isoDate(end);

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String isoDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  @override
  bool operator ==(Object other) =>
      other is DateRange &&
      isoDate(other.start) == isoDate(start) &&
      isoDate(other.end) == isoDate(end);

  @override
  int get hashCode => Object.hash(startParam, endParam);
}

// ---------------------------------------------------------------------------
// Sales
// ---------------------------------------------------------------------------

class SalesTotals {
  SalesTotals({
    required this.revenue,
    required this.foodSales,
    required this.deliveryFees,
    required this.ordersPlaced,
    required this.ordersDelivered,
    required this.ordersCancelled,
    required this.averageOrderValue,
  });

  final double revenue;
  final double foodSales;
  final double deliveryFees;
  final int ordersPlaced;
  final int ordersDelivered;
  final int ordersCancelled;

  /// Revenue divided by deliveries, computed server-side so it agrees with
  /// the rounding on every other figure.
  final double averageOrderValue;

  /// Placed but neither delivered nor cancelled in the window. Not a
  /// server field — a range boundary means an order placed on the last day
  /// and delivered the next legitimately shows here.
  int get unresolved =>
      (ordersPlaced - ordersDelivered - ordersCancelled).clamp(0, 1 << 30);

  factory SalesTotals.fromJson(Map<String, dynamic> json) => SalesTotals(
        revenue: _toDouble(json['revenue']),
        foodSales: _toDouble(json['food_sales']),
        deliveryFees: _toDouble(json['delivery_fees']),
        ordersPlaced: _toInt(json['orders_placed']),
        ordersDelivered: _toInt(json['orders_delivered']),
        ordersCancelled: _toInt(json['orders_cancelled']),
        averageOrderValue: _toDouble(json['average_order_value']),
      );

  static SalesTotals get empty => SalesTotals(
        revenue: 0,
        foodSales: 0,
        deliveryFees: 0,
        ordersPlaced: 0,
        ordersDelivered: 0,
        ordersCancelled: 0,
        averageOrderValue: 0,
      );
}

/// One day of the series. The backend emits every day in the range, zeroes
/// included, so a chart never has to fill gaps.
class SalesDay {
  SalesDay({
    required this.date,
    required this.revenue,
    required this.foodSales,
    required this.deliveryFees,
    required this.ordersPlaced,
    required this.ordersDelivered,
    required this.ordersCancelled,
  });

  final DateTime date;
  final double revenue;
  final double foodSales;
  final double deliveryFees;
  final int ordersPlaced;
  final int ordersDelivered;
  final int ordersCancelled;

  bool get isQuiet => revenue == 0 && ordersPlaced == 0;

  factory SalesDay.fromJson(Map<String, dynamic> json) => SalesDay(
        date: DateTime.tryParse('${json['date']}') ?? DateTime(1970),
        revenue: _toDouble(json['revenue']),
        foodSales: _toDouble(json['food_sales']),
        deliveryFees: _toDouble(json['delivery_fees']),
        ordersPlaced: _toInt(json['orders_placed']),
        ordersDelivered: _toInt(json['orders_delivered']),
        ordersCancelled: _toInt(json['orders_cancelled']),
      );
}

class SalesReport {
  SalesReport({
    required this.start,
    required this.end,
    required this.days,
    required this.totals,
    required this.daily,
  });

  final String start;
  final String end;
  final int days;
  final SalesTotals totals;
  final List<SalesDay> daily;

  /// Tallest bar, for scaling the chart. Zero when nothing sold, which the
  /// chart has to handle rather than divide by.
  double get peakRevenue =>
      daily.fold(0, (best, day) => day.revenue > best ? day.revenue : best);

  /// The single best day, or null when the window is empty or all zeroes.
  SalesDay? get bestDay {
    SalesDay? best;
    for (final day in daily) {
      if (day.revenue > 0 && (best == null || day.revenue > best.revenue)) {
        best = day;
      }
    }
    return best;
  }

  int get tradingDays => daily.where((d) => d.revenue > 0).length;

  factory SalesReport.fromJson(Map<String, dynamic> json) {
    final rows = json['daily'];
    final totals = json['totals'];

    return SalesReport(
      start: (json['start'] ?? '') as String,
      end: (json['end'] ?? '') as String,
      days: _toInt(json['days']),
      totals: totals is Map<String, dynamic>
          ? SalesTotals.fromJson(totals)
          : SalesTotals.empty,
      daily: rows is List
          ? rows
              .whereType<Map<String, dynamic>>()
              .map(SalesDay.fromJson)
              .toList()
          : const [],
    );
  }
}

// ---------------------------------------------------------------------------
// Riders
// ---------------------------------------------------------------------------

class RiderReportRow {
  RiderReportRow({
    required this.riderId,
    required this.username,
    required this.name,
    required this.isActive,
    required this.deliveriesCompleted,
    required this.deliveriesFailed,
    required this.earnings,
  });

  final int riderId;
  final String username;
  final String name;
  final bool isActive;
  final int deliveriesCompleted;
  final int deliveriesFailed;
  final double earnings;

  int get attempted => deliveriesCompleted + deliveriesFailed;

  /// Share of attempts that landed, or null when they attempted nothing —
  /// which is not the same as a 0% success rate.
  double? get successRate =>
      attempted == 0 ? null : deliveriesCompleted / attempted;

  bool get didNothing => attempted == 0;

  factory RiderReportRow.fromJson(Map<String, dynamic> json) => RiderReportRow(
        riderId: _toInt(json['rider_id']),
        username: (json['username'] ?? '') as String,
        name: (json['name'] ?? '') as String,
        isActive: (json['is_active'] ?? true) as bool,
        deliveriesCompleted: _toInt(json['deliveries_completed']),
        deliveriesFailed: _toInt(json['deliveries_failed']),
        earnings: _toDouble(json['earnings']),
      );
}

class RiderReport {
  RiderReport({
    required this.start,
    required this.end,
    required this.completed,
    required this.failed,
    required this.earnings,
    required this.riders,
  });

  final String start;
  final String end;
  final int completed;
  final int failed;
  final double earnings;

  /// Every rider, best first. Ones who did nothing in the window are
  /// included on purpose — an idle rider is worth seeing.
  final List<RiderReportRow> riders;

  int get activeRiders => riders.where((r) => !r.didNothing).length;

  factory RiderReport.fromJson(Map<String, dynamic> json) {
    final rows = json['riders'];
    final totals = json['totals'];
    final totalsMap = totals is Map<String, dynamic> ? totals : const {};

    return RiderReport(
      start: (json['start'] ?? '') as String,
      end: (json['end'] ?? '') as String,
      completed: _toInt(totalsMap['deliveries_completed']),
      failed: _toInt(totalsMap['deliveries_failed']),
      earnings: _toDouble(totalsMap['earnings']),
      riders: rows is List
          ? rows
              .whereType<Map<String, dynamic>>()
              .map(RiderReportRow.fromJson)
              .toList()
          : const [],
    );
  }
}

// ---------------------------------------------------------------------------
// Menu
// ---------------------------------------------------------------------------

class MenuReportRow {
  MenuReportRow({
    required this.menuId,
    required this.name,
    required this.price,
    required this.isAvailable,
    required this.quantitySold,
    required this.revenue,
  });

  final int menuId;
  final String name;
  final double price;
  final bool isAvailable;
  final int quantitySold;
  final double revenue;

  bool get soldNothing => quantitySold == 0;

  factory MenuReportRow.fromJson(Map<String, dynamic> json) => MenuReportRow(
        menuId: _toInt(json['menu_id']),
        name: (json['name'] ?? '') as String,
        price: _toDouble(json['price']),
        isAvailable: (json['is_available'] ?? true) as bool,
        quantitySold: _toInt(json['quantity_sold']),
        revenue: _toDouble(json['revenue']),
      );
}

class MenuReport {
  MenuReport({
    required this.start,
    required this.end,
    required this.itemCount,
    required this.quantitySold,
    required this.revenue,
    required this.items,
  });

  final String start;
  final String end;
  final int itemCount;
  final int quantitySold;

  /// Food only — delivery fees are not attributable to an item, so this is
  /// deliberately less than the sales report's revenue.
  final double revenue;

  /// Best seller first, unsold items last with zeroes.
  final List<MenuReportRow> items;

  int get topSellerQuantity => items.isEmpty ? 0 : items.first.quantitySold;

  List<MenuReportRow> get unsold =>
      items.where((item) => item.soldNothing).toList();

  factory MenuReport.fromJson(Map<String, dynamic> json) {
    final rows = json['items'];
    final totals = json['totals'];
    final totalsMap = totals is Map<String, dynamic> ? totals : const {};

    return MenuReport(
      start: (json['start'] ?? '') as String,
      end: (json['end'] ?? '') as String,
      itemCount: _toInt(totalsMap['items']),
      quantitySold: _toInt(totalsMap['quantity_sold']),
      revenue: _toDouble(totalsMap['revenue']),
      items: rows is List
          ? rows
              .whereType<Map<String, dynamic>>()
              .map(MenuReportRow.fromJson)
              .toList()
          : const [],
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
