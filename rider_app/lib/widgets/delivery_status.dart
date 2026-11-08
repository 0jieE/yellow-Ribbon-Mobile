import 'package:flutter/material.dart';

/// Presentation for `DELIVERY_STATUS` and the status transitions the rider
/// can trigger. Defined once so the list, the card and the detail screen
/// never disagree.
class DeliveryStatusStyle {
  const DeliveryStatusStyle(this.label, this.colour, this.icon);

  final String label;
  final Color colour;
  final IconData icon;

  static const _styles = <String, DeliveryStatusStyle>{
    'assigned': DeliveryStatusStyle(
      'Assigned',
      Color(0xFFB26A00),
      Icons.assignment_outlined,
    ),
    'picked_up': DeliveryStatusStyle(
      'Picked up',
      Color(0xFF1565C0),
      Icons.shopping_bag_outlined,
    ),
    'in_transit': DeliveryStatusStyle(
      'In transit',
      Color(0xFF00796B),
      Icons.delivery_dining,
    ),
    'delivered': DeliveryStatusStyle(
      'Delivered',
      Color(0xFF2E7D32),
      Icons.task_alt,
    ),
    'failed': DeliveryStatusStyle(
      'Failed',
      Color(0xFFC62828),
      Icons.error_outline,
    ),
  };

  static DeliveryStatusStyle of(String status) {
    return _styles[status] ??
        DeliveryStatusStyle(
          status.replaceAll('_', ' '),
          const Color(0xFF616161),
          Icons.info_outline,
        );
  }

  /// The button wording for moving *to* a status.
  static String actionLabel(String status) {
    switch (status) {
      case 'picked_up':
        return 'Mark picked up';
      case 'in_transit':
        return 'Start delivery';
      case 'delivered':
        return 'Mark delivered';
      case 'failed':
        return 'Report failed';
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
    final style = DeliveryStatusStyle.of(status);

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

/// Compact local-time formatting, matching customer_app's approach: written
/// by hand rather than pulling in `intl` for two format strings.
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
