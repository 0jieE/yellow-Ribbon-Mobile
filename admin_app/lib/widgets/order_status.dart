import 'package:flutter/material.dart';

/// Presentation for the `ORDER_STATUS` values in `orders/constants.py`,
/// defined once so the queue, the detail screen and the timeline agree.
class OrderStatusStyle {
  const OrderStatusStyle(this.label, this.colour, this.icon);

  final String label;
  final Color colour;
  final IconData icon;

  /// In the order the backend lists them, which is also the happy path.
  static const order = <String>[
    'pending_payment',
    'pending',
    'confirmed',
    'preparing',
    'ready',
    'out_for_delivery',
    'delivered',
    'cancelled',
  ];

  static const _styles = <String, OrderStatusStyle>{
    'pending_payment': OrderStatusStyle(
      'Awaiting payment',
      Color(0xFF8D6E63),
      Icons.hourglass_empty,
    ),
    'pending': OrderStatusStyle(
      'Pending',
      Color(0xFFB26A00),
      Icons.pending_actions,
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

  static OrderStatusStyle of(String status) {
    return _styles[status] ??
        OrderStatusStyle(
          status.replaceAll('_', ' '),
          const Color(0xFF616161),
          Icons.info_outline,
        );
  }

  /// Button wording for moving *to* a status.
  static String actionLabel(String status) {
    switch (status) {
      case 'confirmed':
        return 'Accept order';
      case 'preparing':
        return 'Start preparing';
      case 'ready':
        return 'Mark ready';
      case 'out_for_delivery':
        return 'Send out for delivery';
      case 'delivered':
        return 'Mark delivered';
      case 'cancelled':
        return 'Cancel order';
      default:
        return 'Move to ${status.replaceAll('_', ' ')}';
    }
  }
}

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

/// Compact local-time formatting, matching the other two apps.
class Dates {
  const Dates._();

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String full(DateTime? value) {
    if (value == null) return '—';
    final d = value.toLocal();
    return '${d.day} ${_months[d.month - 1]} ${d.year}, ${time(d)}';
  }

  static String time(DateTime? value) {
    if (value == null) return '—';
    final d = value.toLocal();
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
  }
}
