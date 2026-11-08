/// One line on a placed order, as returned by `OrderItemSerializer`.
class OrderItem {
  OrderItem({
    required this.menuName,
    required this.quantity,
    required this.unitPrice,
    required this.lineSubtotal,
    this.menuId,
  });

  final String menuName;
  final int quantity;
  final double unitPrice;
  final double lineSubtotal;

  /// The `Menu` row this line was ordered from.
  ///
  /// The serializer sends the id but not the photo, so a thumbnail has to be
  /// looked up against `GET /api/menu/` by this id. Null when the item has
  /// since been deleted from the menu.
  final int? menuId;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        menuName: (json['menu_name'] ?? '') as String,
        quantity: (json['quantity'] ?? 0) as int,
        unitPrice: _toDouble(json['unit_price']),
        lineSubtotal: _toDouble(json['line_subtotal']),
        menuId: json['menu'] as int?,
      );
}

/// A row from `status_logs` — the audit trail the detail screen renders as a
/// timeline. The backend orders these oldest first.
class OrderStatusLog {
  OrderStatusLog({
    required this.status,
    required this.changedAt,
    this.changedByUsername,
  });

  final String status;
  final DateTime? changedAt;
  final String? changedByUsername;

  factory OrderStatusLog.fromJson(Map<String, dynamic> json) => OrderStatusLog(
        status: (json['status'] ?? '') as String,
        changedAt: DateTime.tryParse('${json['changed_at']}'),
        changedByUsername: json['changed_by_username'] as String?,
      );
}

/// Where the rider is right now.
///
/// The serializer returns this only while the delivery is actually in
/// progress — null before assignment and after it finishes — and only once
/// the rider app has reported at least one position.
class RiderLocation {
  RiderLocation({
    required this.latitude,
    required this.longitude,
    required this.deliveryStatus,
    required this.riderName,
    required this.vehicleType,
    this.updatedAt,
  });

  final double latitude;
  final double longitude;
  final String deliveryStatus;
  final String riderName;
  final String vehicleType;
  final DateTime? updatedAt;

  /// Returns null rather than throwing when the payload is absent or
  /// malformed — a missing rider position is an expected state, not an error.
  static RiderLocation? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;

    final lat = double.tryParse('${json['latitude']}');
    final lng = double.tryParse('${json['longitude']}');
    if (lat == null || lng == null) return null;

    return RiderLocation(
      latitude: lat,
      longitude: lng,
      deliveryStatus: (json['delivery_status'] ?? '') as String,
      riderName: (json['rider_name'] ?? 'Your rider') as String,
      vehicleType: (json['vehicle_type'] ?? '') as String,
      updatedAt: DateTime.tryParse('${json['updated_at']}'),
    );
  }
}

/// Money going back to the customer after a paid order was cancelled.
class RefundInfo {
  RefundInfo({
    required this.status,
    required this.amount,
    this.refundedAt,
    this.reference,
  });

  /// `pending` (asked, gateway not done yet), `refunded`, or `failed` — a
  /// failed one stays with the store to retry.
  final String status;
  final double amount;
  final DateTime? refundedAt;
  final String? reference;

  static RefundInfo? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    return RefundInfo(
      status: (json['status'] ?? '') as String,
      amount: _toDouble(json['amount']),
      refundedAt: DateTime.tryParse('${json['refunded_at']}'),
      reference: json['reference'] as String?,
    );
  }
}

/// The invoice behind an order — the receipt the gateway settled.
///
/// Null on the order until an invoice exists: a GCash or Maya checkout
/// issues one, a COD order only gets one when the rider hands the food over.
class PaymentInfo {
  PaymentInfo({
    required this.invoiceNumber,
    required this.paymongoReference,
    required this.amountPaid,
    required this.testMode,
    this.provider,
    this.payer,
    this.paidAt,
    this.refund,
  });

  final String invoiceNumber;

  /// The gateway's reference, whichever gateway it is (the name is
  /// historical). PayMongo: `src_...` while the checkout is open, `pay_...`
  /// once settled. Maya: the checkout id, then the payment id. Empty for COD.
  final String paymongoReference;

  /// `paymongo`, `maya` or `cod`.
  final String? provider;

  /// Whose wallet paid, as the gateway reported it — e.g.
  /// "Maya wallet ••••0900". Null when the gateway did not say.
  final String? payer;

  final double amountPaid;
  final DateTime? paidAt;

  /// The backend is on gateway test keys — a sandbox payment, no real money.
  final bool testMode;

  final RefundInfo? refund;

  bool get isPaid => paidAt != null;

  static PaymentInfo? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    return PaymentInfo(
      invoiceNumber: (json['invoice_number'] ?? '') as String,
      paymongoReference: (json['paymongo_reference'] ?? '') as String,
      provider: json['provider'] as String?,
      payer: json['payer'] as String?,
      amountPaid: _toDouble(json['amount_paid']),
      paidAt: DateTime.tryParse('${json['paid_at']}'),
      testMode: (json['test_mode'] ?? false) as bool,
      refund: RefundInfo.fromJson(json['refund']),
    );
  }
}

/// An order as returned by `POST /api/orders/` and `GET /api/orders/{id}/`.
///
/// Totals are the server's — the client never computes what is owed.
class AppOrder {
  AppOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentType,
    required this.paymentStatus,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.deliveryAddress,
    required this.deliveryNotes,
    required this.canCancel,
    required this.items,
    required this.statusLogs,
    this.routePolyline = '',
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.riderLocation,
    this.payment,
    this.etaMinutes,
    this.etaAt,
    this.placedAt,
    this.deliveredAt,
    this.cancelledAt,
    this.cancelReason,
  });

  final int id;
  final String orderNumber;
  final String status;
  final String paymentType;
  final String paymentStatus;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final String deliveryAddress;
  final String deliveryNotes;

  /// True while the order may still be cancelled by the customer.
  ///
  /// Sourced from `is_cancellable_by_customer`, which is narrower than the
  /// general status-transition table: only `pending_payment` and `pending`
  /// qualify. Once the store accepts the order the customer must phone in.
  final bool canCancel;

  final List<OrderItem> items;
  final List<OrderStatusLog> statusLogs;

  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final RiderLocation? riderLocation;
  final PaymentInfo? payment;

  final int? etaMinutes;
  final DateTime? etaAt;

  /// Google's encoded polyline for the leg the rider is driving.
  ///
  /// Written when the delivery goes `in_transit`; empty for the whole of the
  /// order's life before that. The model stores it as `TextField(default="")`,
  /// so absent arrives as an empty string rather than null.
  final String routePolyline;

  final DateTime? placedAt;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;
  final String? cancelReason;

  /// A GCash or Maya order sits in `pending_payment` until the gateway
  /// confirms the money arrived. Until then it has not reached the kitchen.
  bool get awaitingPayment => status == 'pending_payment';

  bool get isMaya => paymentType == 'maya';

  /// Paid through a gateway rather than in cash at the door.
  bool get isOnlinePayment => paymentType == 'gcash' || isMaya;

  /// What the customer sees the order being paid with.
  String get paymentMethodLabel => switch (paymentType) {
        'gcash' => 'GCash',
        'maya' => 'Maya',
        _ => 'Cash on delivery',
      };

  /// Nothing further will happen to the order, so polling can stop.
  bool get isTerminal => status == 'delivered' || status == 'cancelled';

  /// The rider is on the road with this order.
  bool get isOutForDelivery => status == 'out_for_delivery';

  /// The delivery's own status, which is finer-grained than the order's.
  ///
  /// Only reaches the customer through `rider_location`, and that block is
  /// withheld until the rider has reported a position — so this is null both
  /// before assignment and in the gap between pickup and the first ping.
  String? get deliveryStatus => riderLocation?.deliveryStatus;

  /// The rider has actually set off. The backend computes the ETA at exactly
  /// this moment and not before, so it gates the ETA display too.
  bool get isInTransit => deliveryStatus == 'in_transit';

  /// True only once there is a real, server-computed arrival estimate.
  bool get hasEta => isInTransit && etaMinutes != null;

  /// What to badge the order as.
  ///
  /// `in_transit` is a delivery status rather than an order status — the
  /// order stays `out_for_delivery` throughout — but "In transit" is the
  /// more truthful thing to show a customer once the rider is moving.
  String get displayStatus => isInTransit ? 'in_transit' : status;

  bool get hasDestination =>
      deliveryLatitude != null && deliveryLongitude != null;

  /// A road path exists to draw. Only true once the rider is in transit.
  bool get hasRoute => routePolyline.trim().isNotEmpty;

  factory AppOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawLogs = json['status_logs'];

    return AppOrder(
      id: (json['id'] ?? 0) as int,
      orderNumber: (json['order_number'] ?? '') as String,
      status: (json['status'] ?? '') as String,
      paymentType: (json['payment_type'] ?? '') as String,
      paymentStatus: (json['payment_status'] ?? '') as String,
      subtotal: _toDouble(json['subtotal']),
      deliveryFee: _toDouble(json['delivery_fee']),
      total: _toDouble(json['total']),
      deliveryAddress: (json['delivery_address'] ?? '') as String,
      deliveryNotes: (json['delivery_notes'] ?? '') as String,
      canCancel: (json['can_cancel'] ?? false) as bool,
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(OrderItem.fromJson)
              .toList()
          : const [],
      statusLogs: rawLogs is List
          ? rawLogs
              .whereType<Map<String, dynamic>>()
              .map(OrderStatusLog.fromJson)
              .toList()
          : const [],
      deliveryLatitude: _toNullableDouble(json['delivery_latitude']),
      deliveryLongitude: _toNullableDouble(json['delivery_longitude']),
      riderLocation: RiderLocation.fromJson(json['rider_location']),
      payment: PaymentInfo.fromJson(json['payment']),
      routePolyline: (json['route_polyline'] ?? '') as String,
      etaMinutes: json['eta_minutes'] as int?,
      etaAt: DateTime.tryParse('${json['eta_at']}'),
      placedAt: DateTime.tryParse('${json['placed_at']}'),
      deliveredAt: DateTime.tryParse('${json['delivered_at']}'),
      cancelledAt: DateTime.tryParse('${json['cancelled_at']}'),
      cancelReason: json['cancel_reason'] as String?,
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

double? _toNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}
