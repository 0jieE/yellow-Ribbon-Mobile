/// One line on an order.
class OrderItem {
  OrderItem({
    required this.menuName,
    required this.quantity,
    required this.unitPrice,
    required this.lineSubtotal,
  });

  final String menuName;
  final int quantity;
  final double unitPrice;
  final double lineSubtotal;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        menuName: (json['menu_name'] ?? '') as String,
        quantity: (json['quantity'] ?? 0) as int,
        unitPrice: _toDouble(json['unit_price']),
        lineSubtotal: _toDouble(json['line_subtotal']),
      );
}

/// A row from `status_logs`, oldest first as the backend orders them.
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

/// The `rider` block on an order, present only once a Delivery exists.
class AssignedRider {
  AssignedRider({
    required this.riderId,
    required this.name,
    required this.username,
    required this.phone,
    required this.deliveryStatus,
    required this.riderEarnings,
    this.failureReason,
  });

  final int riderId;
  final String name;
  final String username;
  final String phone;
  final String deliveryStatus;
  final double riderEarnings;

  /// What the rider gave as the reason when the delivery failed.
  final String? failureReason;

  bool get hasPickedUp =>
      deliveryStatus == 'picked_up' ||
      deliveryStatus == 'in_transit' ||
      deliveryStatus == 'delivered';

  bool get deliveryFailed => deliveryStatus == 'failed';

  /// Null when no rider has been assigned yet — which is what decides
  /// whether the Assign Rider button shows.
  static AssignedRider? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    return AssignedRider(
      riderId: (json['rider_id'] ?? 0) as int,
      name: (json['name'] ?? '') as String,
      username: (json['username'] ?? '') as String,
      phone: (json['phone'] ?? '') as String,
      deliveryStatus: (json['delivery_status'] ?? '') as String,
      riderEarnings: _toDouble(json['rider_earnings']),
      failureReason: json['failure_reason'] as String?,
    );
  }
}

/// Money going back after a paid order was cancelled.
class RefundInfo {
  RefundInfo({
    required this.status,
    required this.amount,
    this.refundedAt,
    this.reference,
    this.error,
  });

  /// `pending` (gateway has not finished), `refunded`, or `failed`.
  final String status;
  final double amount;
  final DateTime? refundedAt;
  final String? reference;

  /// Why the gateway refused, when it did.
  final String? error;

  bool get isDone => status == 'refunded';

  static RefundInfo? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    return RefundInfo(
      status: (json['status'] ?? '') as String,
      amount: _toDouble(json['amount']),
      refundedAt: DateTime.tryParse('${json['refunded_at']}'),
      reference: json['reference'] as String?,
      error: json['error'] as String?,
    );
  }
}

/// The `payment` block: the invoice the gateway (or the rider, for COD)
/// settled. Null until an invoice exists.
class PaymentInfo {
  PaymentInfo({
    required this.invoiceNumber,
    required this.paymongoReference,
    required this.amountPaid,
    required this.testMode,
    this.provider,
    this.payer,
    this.fee,
    this.netAmount,
    this.paidAt,
    this.refund,
  });

  final String invoiceNumber;

  /// The gateway's reference, whichever gateway it is (the name is
  /// historical) — the id to look up in that gateway's dashboard. PayMongo:
  /// `src_...` then `pay_...`. Maya: checkout id, then payment id. Empty
  /// for COD.
  final String paymongoReference;

  /// `paymongo`, `maya` or `cod`.
  final String? provider;

  /// Whose wallet paid, as the gateway reported it.
  final String? payer;

  final double amountPaid;

  /// What the gateway kept, and what reaches the store — snapshotted at
  /// settlement from the rates in Store settings.
  final double? fee;
  final double? netAmount;

  final DateTime? paidAt;

  /// The backend is on gateway test keys.
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
      fee: json['fee'] == null ? null : _toDouble(json['fee']),
      netAmount:
          json['net_amount'] == null ? null : _toDouble(json['net_amount']),
      paidAt: DateTime.tryParse('${json['paid_at']}'),
      testMode: (json['test_mode'] ?? false) as bool,
      refund: RefundInfo.fromJson(json['refund']),
    );
  }
}

/// An order as `AdminOrderSerializer` returns it.
class AdminOrder {
  AdminOrder({
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
    required this.customerName,
    required this.customerPhone,
    required this.nextStatuses,
    required this.items,
    required this.statusLogs,
    this.rider,
    this.payment,
    this.etaMinutes,
    this.placedAt,
    this.deliveredAt,
    this.cancelledAt,
    this.cancelReason,
    this.serverCanAssignRider,
    this.serverCanChangeRider,
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
  final String customerName;
  final String customerPhone;

  /// The statuses this order may legally move to, straight from
  /// `allowed_transitions`. Action buttons are built from this rather than a
  /// client-side copy of the transition table.
  final List<String> nextStatuses;

  final List<OrderItem> items;
  final List<OrderStatusLog> statusLogs;

  /// Null until a rider is assigned.
  final AssignedRider? rider;

  /// Null until an invoice exists.
  final PaymentInfo? payment;

  final int? etaMinutes;
  final DateTime? placedAt;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;
  final String? cancelReason;

  /// The server's own answers, when it sends them. Null from an older
  /// backend, in which case the same rule is applied locally.
  final bool? serverCanAssignRider;
  final bool? serverCanChangeRider;

  bool get isAssigned => rider != null;

  bool get isTerminal => status == 'delivered' || status == 'cancelled';

  /// A rider is only handed an order the store has accepted: from
  /// `confirmed` until the food is ready. Before that the kitchen may still
  /// turn it down; after it, the order is already with a rider.
  static const assignableStatuses = {'confirmed', 'preparing', 'ready'};

  bool get canAssignRider =>
      serverCanAssignRider ??
      (!isAssigned && assignableStatuses.contains(status));

  /// The rider can be swapped until they collect the food.
  bool get canChangeRider =>
      serverCanChangeRider ??
      (isAssigned &&
          rider!.deliveryStatus == 'assigned' &&
          assignableStatuses.contains(status));

  /// Out for delivery and delivered are the rider's steps — they follow from
  /// the rider collecting and handing over the food — so the store never
  /// sets them itself, even if an older server still offers them.
  static const riderOnlyStatuses = {'out_for_delivery', 'delivered'};

  List<String> get adminNextStatuses =>
      nextStatuses.where((s) => !riderOnlyStatuses.contains(s)).toList();

  factory AdminOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawLogs = json['status_logs'];
    final rawNext = json['next_statuses'];

    return AdminOrder(
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
      customerName: (json['customer_name'] ?? '') as String,
      customerPhone: (json['customer_phone'] ?? '') as String,
      nextStatuses:
          rawNext is List ? rawNext.map((s) => '$s').toList() : const [],
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
      rider: AssignedRider.fromJson(json['rider']),
      payment: PaymentInfo.fromJson(json['payment']),
      etaMinutes: json['eta_minutes'] as int?,
      placedAt: DateTime.tryParse('${json['placed_at']}'),
      deliveredAt: DateTime.tryParse('${json['delivered_at']}'),
      cancelledAt: DateTime.tryParse('${json['cancelled_at']}'),
      cancelReason: json['cancel_reason'] as String?,
      serverCanAssignRider: json['can_assign_rider'] as bool?,
      serverCanChangeRider: json['can_change_rider'] as bool?,
    );
  }
}

/// One page of `GET /api/admin/orders/`.
///
/// This is the only paginated endpoint the three apps consume — the customer,
/// menu and rider lists all return a bare array — so the envelope is unwrapped
/// here rather than in the shared client.
class OrderPage {
  OrderPage({
    required this.count,
    required this.results,
    this.next,
    this.previous,
  });

  final int count;
  final List<AdminOrder> results;

  /// Absolute URL of the next page, or null on the last one.
  final String? next;
  final String? previous;

  bool get hasMore => next != null && next!.isNotEmpty;

  factory OrderPage.fromJson(dynamic json) {
    // Tolerate a bare list in case pagination is ever turned off.
    if (json is List) {
      return OrderPage(
        count: json.length,
        results: json
            .whereType<Map<String, dynamic>>()
            .map(AdminOrder.fromJson)
            .toList(),
      );
    }

    final map = json is Map<String, dynamic> ? json : const {};
    final rows = map['results'];

    return OrderPage(
      count: (map['count'] ?? 0) as int,
      next: map['next'] as String?,
      previous: map['previous'] as String?,
      results: rows is List
          ? rows
              .whereType<Map<String, dynamic>>()
              .map(AdminOrder.fromJson)
              .toList()
          : const [],
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}
