import 'package:flutter/material.dart';

/// Presentation for the `ORDER_STATUS` values defined in
/// `orders/constants.py`. Kept in one place so the list, the detail header
/// and the timeline never disagree about what a status is called.
class OrderStatusStyle {
  const OrderStatusStyle(this.label, this.colour, this.icon);

  final String label;
  final Color colour;
  final IconData icon;

  static const _styles = <String, OrderStatusStyle>{
    // One colour per status, so a glance down the list separates them. Same
    // palette as admin_app, so staff and customer describe an order the same
    // way.
    'pending_payment': OrderStatusStyle(
      'Awaiting payment',
      Color(0xFF8D6E63),
      Icons.hourglass_empty,
    ),
    'pending': OrderStatusStyle(
      'Pending',
      Color(0xFFB26A00),
      Icons.receipt_long,
    ),
    'confirmed': OrderStatusStyle(
      'Confirmed',
      Color(0xFF1565C0),
      Icons.check_circle_outline,
    ),
    'preparing': OrderStatusStyle(
      'Preparing',
      Color(0xFF6A1B9A),
      Icons.local_fire_department_outlined,
    ),
    'ready': OrderStatusStyle(
      'Ready',
      Color(0xFF00838F),
      Icons.inventory_2_outlined,
    ),
    'out_for_delivery': OrderStatusStyle(
      'Out for delivery',
      Color(0xFF00796B),
      Icons.delivery_dining,
    ),
    // A delivery status rather than an order status, surfaced to the
    // customer because "in transit" is what they actually care about.
    'in_transit': OrderStatusStyle(
      'In transit',
      Color(0xFF00695C),
      Icons.two_wheeler,
    ),
    'delivered': OrderStatusStyle(
      'Delivered',
      Color(0xFF2E7D32),
      Icons.task_alt,
    ),
    'cancelled': OrderStatusStyle(
      'Cancelled',
      Color(0xFFC62828),
      Icons.cancel_outlined,
    ),
  };

  /// Falls back to a readable version of an unknown value rather than
  /// showing nothing, in case the backend adds a status before the app knows
  /// about it.
  static OrderStatusStyle of(String status) {
    return _styles[status] ??
        OrderStatusStyle(
          status.replaceAll('_', ' '),
          const Color(0xFF616161),
          Icons.info_outline,
        );
  }
}

/// How far along the happy path an order is, for the progress bar on the
/// orders list.
///
/// The sequence is the one `ORDER_STATUS_TRANSITIONS` walks. `pending_payment`
/// sits before it — nothing has started until the money arrives — and
/// `cancelled` leaves the path entirely rather than being a step on it.
class OrderProgress {
  const OrderProgress._();

  /// `in_transit` sits between pickup and arrival. It is not an order status
  /// — the order stays `out_for_delivery` the whole time — but it is a real
  /// stage the customer feels, and the one at which the ETA appears.
  static const steps = <String>[
    'pending',
    'confirmed',
    'preparing',
    'ready',
    'out_for_delivery',
    'in_transit',
    'delivered',
  ];

  static const stepLabels = <String>[
    'Order placed',
    'Confirmed',
    'Preparing',
    'Ready for pickup',
    'Picked up',
    'On the way',
    'Delivered',
  ];

  static int get total => steps.length;

  /// Steps completed, or null for a cancelled order, which has no progress
  /// to show.
  ///
  /// [deliveryStatus] comes from `rider_location`, which the backend withholds
  /// until the rider has reported a position. While it is unknown an order
  /// that is out for delivery reads as picked up rather than on the way —
  /// understating progress rather than claiming a stage that may not have
  /// started.
  static int? completed(String status, {String? deliveryStatus}) {
    if (status == 'cancelled') return null;
    if (status == 'pending_payment') return 0;
    if (status == 'delivered') return total;

    if (status == 'out_for_delivery') {
      return deliveryStatus == 'in_transit' ? 6 : 5;
    }

    final index = steps.indexOf(status);
    return index == -1 ? 0 : index + 1;
  }

  /// The name of the stage the order is at, for showing beside the bar.
  static String labelFor(String status, {String? deliveryStatus}) {
    if (status == 'cancelled') return 'Cancelled';
    if (status == 'pending_payment') return 'Awaiting payment';

    final done = completed(status, deliveryStatus: deliveryStatus);
    if (done == null || done == 0) return OrderStatusStyle.of(status).label;
    return stepLabels[done - 1];
  }
}

/// Small pill showing an order's current status.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.compact = false});

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = OrderStatusStyle.of(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: style.colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: compact ? 13 : 15, color: style.colour),
          const SizedBox(width: 5),
          Text(
            style.label,
            style: TextStyle(
              color: style.colour,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact local-time formatting.
///
/// Written by hand rather than pulling in `intl` for two format strings.
/// Django sends UTC; `toLocal()` puts it in the handset's zone.
class Dates {
  const Dates._();

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "7 Aug 2026, 2:05 PM"
  static String full(DateTime? value) {
    if (value == null) return '—';
    final d = value.toLocal();
    return '${d.day} ${_months[d.month - 1]} ${d.year}, ${time(d)}';
  }

  /// "2:05 PM"
  static String time(DateTime? value) {
    if (value == null) return '—';
    final d = value.toLocal();
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "just now" / "3 min ago" — for how fresh the rider's position is.
  static String since(DateTime? value) {
    if (value == null) return 'unknown';
    final seconds = DateTime.now().difference(value.toLocal()).inSeconds;
    if (seconds < 20) return 'just now';
    if (seconds < 60) return '${seconds}s ago';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes min ago';
    return time(value);
  }
}
