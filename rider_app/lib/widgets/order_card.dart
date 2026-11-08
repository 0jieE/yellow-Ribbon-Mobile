import 'package:flutter/material.dart';

import '../models/delivery_model.dart';
import 'delivery_status.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

/// One assigned delivery.
///
/// Leads with the order number and status, then who and where, and closes on
/// the amount to collect — the number a rider must not get wrong.
class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.delivery,
    this.onTap,
  });

  final Delivery delivery;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final order = delivery.order;
    final style = DeliveryStatusStyle.of(delivery.status);
    final itemCount = order.items.fold<int>(0, (sum, i) => sum + i.quantity);

    // Assigned but the kitchen has not finished: the server refuses a pickup
    // in this state, so the rider is told before they set off.
    final waitingOnKitchen =
        delivery.status == 'assigned' && !order.isReadyForPickup;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status colour as a spine down the card, readable at a
                // glance while scrolling a stack of them.
                Container(width: 5, color: style.colour),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                order.orderNumber,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  height: 1.1,
                                ),
                              ),
                            ),
                            StatusBadge(
                              status: delivery.status,
                              compact: true,
                            ),
                          ],
                        ),

                        const SizedBox(height: 3),

                        Text(
                          "$itemCount item${itemCount == 1 ? '' : 's'} • "
                          "assigned ${Dates.full(delivery.assignedAt)}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade600,
                          ),
                        ),

                        const SizedBox(height: 14),

                        _line(Icons.person_outline, order.customerName),
                        const SizedBox(height: 8),
                        _line(
                          Icons.location_on_outlined,
                          order.deliveryAddress,
                          maxLines: 2,
                        ),

                        if (order.etaMinutes != null) ...[
                          const SizedBox(height: 8),
                          _line(
                            Icons.schedule,
                            "About ${order.etaMinutes} min away",
                          ),
                        ],

                        if (waitingOnKitchen) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _amber.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Not ready for pickup yet — the order is "
                                    "${order.status.replaceAll('_', ' ')}.",
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),

                        Row(
                          children: [
                            Expanded(child: _CollectChip(order: order)),
                            const SizedBox(width: 8),
                            Text(
                              "Details",
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: Colors.grey.shade400,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text, {int maxLines = 1}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: Colors.grey.shade600),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, height: 1.3),
          ),
        ),
      ],
    );
  }
}

/// What the rider hands over or collects at the door.
class _CollectChip extends StatelessWidget {
  const _CollectChip({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context) {
    if (!order.collectsCash) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 15, color: Color(0xFF2E7D32)),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                "Already paid",
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2E7D32),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.payments, size: 15, color: _amber),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              "Collect ₱${order.amountToCollect.toStringAsFixed(2)}",
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
