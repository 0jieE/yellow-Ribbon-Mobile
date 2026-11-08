/// One line of the order the rider is carrying.
class DeliveryItem {
  DeliveryItem({
    required this.menuName,
    required this.quantity,
    required this.unitPrice,
    required this.lineSubtotal,
  });

  final String menuName;
  final int quantity;
  final double unitPrice;
  final double lineSubtotal;

  factory DeliveryItem.fromJson(Map<String, dynamic> json) => DeliveryItem(
        menuName: (json['menu_name'] ?? '') as String,
        quantity: (json['quantity'] ?? 0) as int,
        unitPrice: _toDouble(json['unit_price']),
        lineSubtotal: _toDouble(json['line_subtotal']),
      );
}

/// The order as `DeliveryOrderSerializer` presents it: where to go, what to
/// hand over, and whether to collect cash.
class DeliveryOrder {
  DeliveryOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentType,
    required this.paymentStatus,
    required this.total,
    required this.amountToCollect,
    required this.deliveryAddress,
    required this.deliveryNotes,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    this.routePolyline = '',
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.etaMinutes,
    this.etaAt,
    this.placedAt,
  });

  final int id;
  final String orderNumber;
  final String status;
  final String paymentType;
  final String paymentStatus;
  final double total;

  /// What the rider collects at the door: the full total for an unpaid COD
  /// order, and 0.00 for anything already paid through GCash. Computed
  /// server-side — the rider app never works this out itself.
  final double amountToCollect;

  final String deliveryAddress;
  final String deliveryNotes;
  final String customerName;
  final String customerPhone;
  final List<DeliveryItem> items;

  /// Google's encoded polyline for this leg.
  ///
  /// Written when the delivery goes `in_transit`; empty while it is merely
  /// assigned or picked up. Stored as `TextField(default="")`, so absent
  /// arrives as an empty string rather than null.
  final String routePolyline;

  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final int? etaMinutes;
  final DateTime? etaAt;
  final DateTime? placedAt;

  bool get hasDestination =>
      deliveryLatitude != null && deliveryLongitude != null;

  /// A road path exists to draw. Only true once the rider is in transit.
  bool get hasRoute => routePolyline.trim().isNotEmpty;

  bool get collectsCash => amountToCollect > 0;

  /// The kitchen must mark the order `ready` before a rider may pick it up —
  /// the backend rejects an early `picked_up` with a 400.
  bool get isReadyForPickup => status == 'ready';

  factory DeliveryOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return DeliveryOrder(
      id: (json['id'] ?? 0) as int,
      orderNumber: (json['order_number'] ?? '') as String,
      status: (json['status'] ?? '') as String,
      paymentType: (json['payment_type'] ?? '') as String,
      paymentStatus: (json['payment_status'] ?? '') as String,
      total: _toDouble(json['total']),
      amountToCollect: _toDouble(json['amount_to_collect']),
      deliveryAddress: (json['delivery_address'] ?? '') as String,
      deliveryNotes: (json['delivery_notes'] ?? '') as String,
      customerName: (json['customer_name'] ?? '') as String,
      customerPhone: (json['customer_phone'] ?? '') as String,
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(DeliveryItem.fromJson)
              .toList()
          : const [],
      routePolyline: (json['route_polyline'] ?? '') as String,
      deliveryLatitude: _toNullableDouble(json['delivery_latitude']),
      deliveryLongitude: _toNullableDouble(json['delivery_longitude']),
      etaMinutes: json['eta_minutes'] as int?,
      etaAt: DateTime.tryParse('${json['eta_at']}'),
      placedAt: DateTime.tryParse('${json['placed_at']}'),
    );
  }
}

/// A row from `GET /api/rider/deliveries/`.
class Delivery {
  Delivery({
    required this.id,
    required this.status,
    required this.riderEarnings,
    required this.nextStatuses,
    required this.order,
    this.proofOfDelivery,
    this.assignedAt,
    this.pickedUpAt,
    this.deliveredAt,
  });

  final int id;
  final String status;
  final double riderEarnings;

  /// The statuses this delivery may legally move to, straight from
  /// `allowed_delivery_transitions`. The action buttons are built from this
  /// rather than from a copy of the transition table, so the app cannot offer
  /// a move the server will refuse.
  final List<String> nextStatuses;

  final DeliveryOrder order;

  /// Absolute URL of the uploaded photo, or null when none has been sent.
  final String? proofOfDelivery;

  final DateTime? assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;

  /// Still being worked. Matches `ACTIVE_DELIVERY_STATUSES` server-side, and
  /// is what decides whether the location pinger runs.
  bool get isActive =>
      status == 'assigned' || status == 'picked_up' || status == 'in_transit';

  bool get isTerminal => status == 'delivered' || status == 'failed';

  /// The backend refuses a proof upload while the delivery is still merely
  /// assigned — the rider has to have collected the food first.
  bool get canUploadProof => status != 'assigned';

  bool get hasProof => (proofOfDelivery?.isNotEmpty ?? false);

  factory Delivery.fromJson(Map<String, dynamic> json) {
    final rawNext = json['next_statuses'];
    final rawOrder = json['order'];

    return Delivery(
      id: (json['id'] ?? 0) as int,
      status: (json['status'] ?? '') as String,
      riderEarnings: _toDouble(json['rider_earnings']),
      nextStatuses:
          rawNext is List ? rawNext.map((s) => '$s').toList() : const [],
      order: DeliveryOrder.fromJson(
        rawOrder is Map<String, dynamic> ? rawOrder : const {},
      ),
      proofOfDelivery: json['proof_of_delivery'] as String?,
      assignedAt: DateTime.tryParse('${json['assigned_at']}'),
      pickedUpAt: DateTime.tryParse('${json['picked_up_at']}'),
      deliveredAt: DateTime.tryParse('${json['delivered_at']}'),
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
