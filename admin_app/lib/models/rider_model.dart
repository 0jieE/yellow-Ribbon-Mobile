/// The one leg a rider is driving right now.
///
/// Replaces the old `active_delivery`. The distinction matters: a rider
/// collects a batch at the store and works through it, so "has deliveries" and
/// "is out on the road" stopped being the same thing. Only one delivery may be
/// `in_transit` per rider — the database enforces it — so this is unambiguous.
class CurrentDelivery {
  CurrentDelivery({
    required this.deliveryId,
    required this.orderNumber,
    required this.status,
  });

  final int deliveryId;
  final String orderNumber;
  final String status;

  /// Null when the rider is still loading up rather than driving.
  static CurrentDelivery? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    return CurrentDelivery(
      deliveryId: (json['delivery_id'] ?? 0) as int,
      orderNumber: (json['order_number'] ?? '') as String,
      status: (json['status'] ?? '') as String,
    );
  }
}

/// A row from `GET /api/admin/riders/`.
class Rider {
  Rider({
    required this.id,
    required this.username,
    required this.email,
    required this.name,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.isActive,
    required this.isAvailable,
    required this.vehicleType,
    required this.plateNumber,
    required this.deliveriesHeld,
    this.currentDelivery,
  });

  /// The Rider profile id — this is what `POST .../assign/` wants as
  /// `rider_id`, not the user id.
  final int id;

  final String username;
  final String email;

  /// Full name, or the username when neither part is set.
  final String name;

  /// The editable halves behind [name]. Kept separate because the update
  /// endpoint takes them separately, and splitting [name] on a space would
  /// mangle anyone with two given names.
  final String firstName;
  final String lastName;

  final String phone;

  /// The underlying user account; a deactivated one cannot be assigned.
  final bool isActive;

  /// The rider's own on-duty toggle, set from the rider app.
  final bool isAvailable;

  final String vehicleType;
  final String plateNumber;

  /// How many orders this rider is carrying, at any active stage — assigned,
  /// picked up, or in transit.
  final int deliveriesHeld;

  /// Non-null only while the rider is actually driving a leg.
  final CurrentDelivery? currentDelivery;

  /// Out on the road. This — not [isHolding] — is what blocks an assignment.
  bool get isDriving => currentDelivery != null;

  /// Has work in hand. Still assignable: riders batch orders at the store.
  bool get isHolding => deliveriesHeld > 0;

  /// Mirrors the filter behind `GET /api/admin/riders/available/`.
  ///
  /// Deliberately not `!isHolding`. The backend was widened so a rider
  /// holding two orders at the counter can still be given a third; only
  /// someone already `in_transit` has left and cannot collect more.
  bool get isAssignable => isActive && isAvailable && !isDriving;

  /// "3 orders · on YR-0028", or just the count, or empty when idle.
  String get workloadLabel {
    if (deliveriesHeld == 0) return '';

    final held = deliveriesHeld == 1 ? "1 order" : "$deliveriesHeld orders";
    final driving = currentDelivery;
    return driving == null
        ? "$held in hand"
        : "$held · on ${driving.orderNumber}";
  }

  factory Rider.fromJson(Map<String, dynamic> json) => Rider(
        id: (json['id'] ?? 0) as int,
        username: (json['username'] ?? '') as String,
        email: (json['email'] ?? '') as String,
        name: (json['name'] ?? '') as String,
        firstName: (json['first_name'] ?? '') as String,
        lastName: (json['last_name'] ?? '') as String,
        phone: (json['phone'] ?? '') as String,
        isActive: (json['is_active'] ?? true) as bool,
        isAvailable: (json['is_available'] ?? false) as bool,
        vehicleType: (json['vehicle_type'] ?? '') as String,
        plateNumber: (json['plate_number'] ?? '') as String,
        deliveriesHeld: (json['deliveries_held'] ?? 0) as int,
        currentDelivery: CurrentDelivery.fromJson(json['current_delivery']),
      );
}
