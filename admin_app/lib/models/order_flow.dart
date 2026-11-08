import 'admin_order_model.dart';

/// Who moves an order forward, step by step:
///
///   customer   places it (pending_payment for GCash/Maya, pending for COD)
///   gateway    confirms payment            pending_payment -> pending
///   store      accepts                     pending -> confirmed
///   store      starts preparing            confirmed -> preparing
///   store      marks it ready              preparing -> ready
///   store      assigns a rider             any time from confirmed to ready
///   rider      picks it up                 ready -> out_for_delivery
///   rider      starts the trip             (order stays out_for_delivery)
///   rider      hands it over               out_for_delivery -> delivered
///
/// The store may cancel at any step before delivery; the customer only
/// until the store accepts. The store never sets "out for delivery" or
/// "delivered" itself — those follow from what the rider does.

String deliveryStatusLabel(String status) => switch (status) {
      'assigned' => 'Assigned',
      'picked_up' => 'Picked up',
      'in_transit' => 'On the way',
      'delivered' => 'Delivered',
      'failed' => 'Failed',
      _ => status.replaceAll('_', ' '),
    };

/// What the store should do next, or is waiting on, in one sentence.
/// Null for a finished order, which has its own message.
String? nextStepHint(AdminOrder order) {
  final rider = order.rider;
  final riderName = rider?.name ?? 'The rider';

  switch (order.status) {
    case 'pending_payment':
      return "Waiting for the customer's payment. Nothing to do until it is "
          "confirmed.";
    case 'pending':
      return "New order. Accept it to send it to the kitchen, or cancel it.";
    case 'confirmed':
      return rider == null
          ? "Start preparing when the kitchen begins. You can assign a rider "
              "now or later."
          : "Start preparing when the kitchen begins.";
    case 'preparing':
      return rider == null
          ? "Mark it ready when the food is done, and assign a rider so "
              "someone can collect it."
          : "Mark it ready when the food is done. $riderName is notified to "
              "pick it up.";
    case 'ready':
      if (rider == null) {
        return "The food is ready but no rider has it. Assign one so it can "
            "be picked up.";
      }
      return "Waiting for $riderName to pick it up. The order goes out for "
          "delivery when they do.";
    case 'out_for_delivery':
      if (rider == null) return "This order is out for delivery.";
      if (rider.deliveryFailed) {
        return "$riderName could not deliver this order. Contact the "
            "customer, then cancel the order to close it — a paid order is "
            "refunded automatically.";
      }
      return rider.deliveryStatus == 'in_transit'
          ? "$riderName is on the way to the customer and marks it delivered "
              "on arrival."
          : "$riderName has the order and is about to set off.";
    default:
      return null;
  }
}
